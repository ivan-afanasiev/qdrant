import Foundation

/// Latest-value broadcast for app-owned state. Each subscriber immediately receives the
/// current value, then later values; a slow subscriber only sees the newest one.
/// Ending a subscription never affects the producer.
public final class StatusBroadcast<Value: Sendable>: @unchecked Sendable {
    // Termination may remove a subscriber while a continuation is being yielded.
    private let lock = NSRecursiveLock()
    private var current: Value
    private var continuations: [UUID: AsyncStream<Value>.Continuation] = [:]

    public init(_ initial: Value) {
        current = initial
    }

    public var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public var subscriberCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return continuations.count
    }

    public func stream() -> AsyncStream<Value> {
        let (stream, continuation) = AsyncStream<Value>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            self?.remove(id)
        }
        lock.lock()
        defer { lock.unlock() }
        continuations[id] = continuation
        // Register and replay atomically so an older replay cannot replace a newer send.
        continuation.yield(current)
        return stream
    }

    public func send(_ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        current = value
        // Publish under the same lock as state updates to preserve concurrent send order.
        let active = Array(continuations.values)
        for continuation in active {
            continuation.yield(value)
        }
    }

    private func remove(_ id: UUID) {
        lock.lock()
        continuations[id] = nil
        lock.unlock()
    }
}

import Foundation

/// Latest-value broadcast for app-owned state. Each subscriber immediately receives the
/// current value, then later values; a slow subscriber only sees the newest one.
/// Ending a subscription never affects the producer.
public final class StatusBroadcast<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
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
        continuations[id] = continuation
        let value = current
        lock.unlock()
        continuation.yield(value)
        return stream
    }

    public func send(_ value: Value) {
        lock.lock()
        current = value
        let active = Array(continuations.values)
        lock.unlock()
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

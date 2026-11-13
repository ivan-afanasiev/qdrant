import Foundation
import SweepDomain

/// Records requested delays and returns immediately; honors task cancellation.
public actor RecordingSleeper: Sleeper {
    public private(set) var sleeps: [Duration] = []

    public init() {}

    public func sleep(for duration: Duration) async throws {
        sleeps.append(duration)
        try Task.checkCancellation()
    }
}

/// Produces predictable UUIDs: 00000000-0000-0000-0000-000000000001, …0002, and so on.
public final class SequentialIDGenerator: IDGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var next: UInt64

    public init(startingAt first: UInt64 = 1) {
        next = first
    }

    public func makeUUID() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        let value = next
        next += 1
        return Self.uuid(value)
    }

    /// The UUID this generator returns for `value`.
    public static func uuid(_ value: UInt64) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[15 - index] = UInt8(truncatingIfNeeded: value >> (8 * UInt64(index)))
        }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

/// Explicit suspension point for race tests, replacing sleep-based timing.
public actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public var waiterCount: Int { waiters.count }

    /// Suspends until `open()` is called. Returns immediately once open.
    public func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    public func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }

    /// Waits until at least `count` callers are suspended in `wait()`.
    public func waitForWaiters(_ count: Int) async {
        while waiters.count < count {
            await Task.yield()
        }
    }
}

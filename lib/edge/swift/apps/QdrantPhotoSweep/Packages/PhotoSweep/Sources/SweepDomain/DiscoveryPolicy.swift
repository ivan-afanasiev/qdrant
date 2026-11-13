import Foundation

/// User-visible discovery state; separate from vectorization status.
public enum DiscoveryStatus: Equatable, Sendable {
    case waitingForInitialPass
    case searching
    case bufferReady
    case suspended
    /// No eligible seeds or frontier remain. An empty buffer alone never means this.
    case exhausted
    case failed(String)
}

/// Revision-tagged discovery event delivered to observers.
public struct DiscoveryUpdate: Equatable, Sendable {
    public let revision: DiscoveryRevision
    public let status: DiscoveryStatus

    public init(revision: DiscoveryRevision, status: DiscoveryStatus) {
        self.revision = revision
        self.status = status
    }
}

public enum AppPresence: Equatable, Sendable {
    case foreground
    case background
}

/// Number of unreviewed ready groups to keep, counting the current card.
public struct ReviewBufferPolicy: Equatable, Sendable {
    public static let allowedCapacity: ClosedRange<Int> = 2...3
    public static let `default` = ReviewBufferPolicy(uncheckedCapacity: 3)

    public let capacity: Int

    public init?(capacity: Int) {
        guard Self.allowedCapacity.contains(capacity) else { return nil }
        self.capacity = capacity
    }

    private init(uncheckedCapacity: Int) {
        capacity = uncheckedCapacity
    }

    public func isFull(readyCount: Int) -> Bool {
        readyCount >= capacity
    }
}

public struct DiscoveryInputs: Equatable, Sendable {
    public let isInitialGateOpen: Bool
    public let presence: AppPresence
    /// Unreviewed fresh groups including the current card; deferred groups are not counted.
    public let readyCount: Int
    /// The seed cursor is at its end and no component frontier is pending.
    public let isSeedCursorExhausted: Bool
    public let failure: String?

    public init(
        isInitialGateOpen: Bool,
        presence: AppPresence,
        readyCount: Int,
        isSeedCursorExhausted: Bool,
        failure: String? = nil
    ) {
        self.isInitialGateOpen = isInitialGateOpen
        self.presence = presence
        self.readyCount = readyCount
        self.isSeedCursorExhausted = isSeedCursorExhausted
        self.failure = failure
    }
}

/// Decides whether foreground discovery should search. Discovery never runs in the
/// background, waits for the initial pass, and stops when the buffer is full.
/// It never pauses vectorization.
public enum DiscoveryPolicy {
    public static func status(_ inputs: DiscoveryInputs, buffer: ReviewBufferPolicy) -> DiscoveryStatus {
        if let failure = inputs.failure { return .failed(failure) }
        guard inputs.isInitialGateOpen else { return .waitingForInitialPass }
        guard inputs.presence == .foreground else { return .suspended }
        if buffer.isFull(readyCount: inputs.readyCount) { return .bufferReady }
        if inputs.isSeedCursorExhausted { return .exhausted }
        return .searching
    }

    public static func shouldSearch(_ inputs: DiscoveryInputs, buffer: ReviewBufferPolicy) -> Bool {
        status(inputs, buffer: buffer) == .searching
    }
}

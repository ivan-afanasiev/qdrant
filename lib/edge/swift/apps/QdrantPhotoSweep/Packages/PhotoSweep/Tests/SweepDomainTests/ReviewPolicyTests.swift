import Testing
import SweepDomain

private let group = ReviewGroupSnapshot(
    id: groupID(1),
    revision: MembershipRevision(1),
    discoveryRevision: DiscoveryRevision(1),
    members: [asset("a"), asset("b"), asset("c")]
)

@Suite struct KeepSelectionPolicyTests {
    @Test func emptySelectionNeverDeletes() {
        #expect(throws: ReviewError.emptySelection) {
            try KeepSelectionPolicy.validate(.keep([]), for: group)
        }
    }

    @Test func explicitDeleteAllDeletesEveryMember() throws {
        let decision = try KeepSelectionPolicy.validate(.deleteAll, for: group)
        #expect(decision == .delete(keep: [], delete: [asset("a"), asset("b"), asset("c")]))
    }

    @Test func keepingEveryPhotoCompletesWithoutDeletion() throws {
        let decision = try KeepSelectionPolicy.validate(.keep([asset("a"), asset("b"), asset("c")]), for: group)
        #expect(decision == .keepAll)
    }

    @Test func partialSelectionDeletesTheRest() throws {
        let decision = try KeepSelectionPolicy.validate(.keep([asset("b")]), for: group)
        #expect(decision == .delete(keep: [asset("b")], delete: [asset("a"), asset("c")]))
    }

    @Test func selectionOutsideGroupIsRejected() {
        #expect(throws: ReviewError.selectionOutsideGroup([asset("z")])) {
            try KeepSelectionPolicy.validate(.keep([asset("a"), asset("z")]), for: group)
        }
    }
}

@Suite struct ReviewCommitPolicyTests {
    @Test func currentRevisionWithAvailableAssetsCommits() throws {
        try ReviewCommitPolicy.validateCurrent(group, currentRevision: MembershipRevision(1), unavailable: [asset("other")])
    }

    @Test func missingGroupIsConflict() {
        #expect(throws: ReviewError.conflict(group.id)) {
            try ReviewCommitPolicy.validateCurrent(group, currentRevision: nil, unavailable: [])
        }
    }

    @Test func sameCountMembershipChangeIsConflict() {
        #expect(throws: ReviewError.conflict(group.id)) {
            try ReviewCommitPolicy.validateCurrent(group, currentRevision: MembershipRevision(2), unavailable: [])
        }
    }

    @Test func unavailableMemberIsConflict() {
        #expect(throws: ReviewError.conflict(group.id)) {
            try ReviewCommitPolicy.validateCurrent(group, currentRevision: MembershipRevision(1), unavailable: [asset("b")])
        }
    }
}

@Suite struct ReviewQueueTests {
    @Test func freshGroupsAreReviewedInDiscoveryOrder() {
        var queue = ReviewQueue()
        queue.enqueueDiscovered(groupID(1))
        queue.enqueueDiscovered(groupID(2))
        #expect(queue.current(isDiscoveryExhausted: false) == groupID(1))
        queue.complete(groupID(1))
        #expect(queue.current(isDiscoveryExhausted: false) == groupID(2))
    }

    @Test func skippedGroupWaitsForUndiscoveredGroups() {
        var queue = ReviewQueue(fresh: [groupID(1)])
        queue.skip(groupID(1))
        // Buffer is empty but discovery is not exhausted: more groups may still be found.
        #expect(queue.current(isDiscoveryExhausted: false) == nil)
        queue.enqueueDiscovered(groupID(2))
        #expect(queue.current(isDiscoveryExhausted: false) == groupID(2))
        queue.complete(groupID(2))
        #expect(queue.current(isDiscoveryExhausted: true) == groupID(1))
    }

    @Test func deferredGroupsCycleInDurableOrder() {
        var queue = ReviewQueue(fresh: [groupID(1), groupID(2), groupID(3)])
        queue.skip(groupID(1))
        queue.skip(groupID(2))
        queue.skip(groupID(3))
        var seen: [GroupID] = []
        for _ in 0..<6 {
            guard let current = queue.current(isDiscoveryExhausted: true) else { break }
            seen.append(current)
            queue.skip(current)
        }
        #expect(seen == [groupID(1), groupID(2), groupID(3), groupID(1), groupID(2), groupID(3)])
        #expect(queue.deferred.count == 3)
    }

    @Test func requeuingKnownGroupCreatesNoDuplicate() {
        var queue = ReviewQueue(fresh: [groupID(1)])
        queue.skip(groupID(1))
        let firstAttempt = queue.enqueueDiscovered(groupID(1))
        let secondAttempt = queue.enqueueDiscovered(groupID(1))
        #expect(!firstAttempt)
        #expect(!secondAttempt)
        #expect(queue.fresh.isEmpty)
        #expect(queue.deferred == [groupID(1)])
    }

    @Test func readyCountIncludesCurrentAndExcludesDeferred() {
        var queue = ReviewQueue(fresh: [groupID(1), groupID(2)])
        queue.skip(groupID(1))
        #expect(queue.readyCount == 1)
    }

    @Test func resetClearsOrderAndDeferrals() {
        var queue = ReviewQueue(fresh: [groupID(1)], deferred: [groupID(2)])
        queue.reset()
        #expect(queue == ReviewQueue())
    }

    @Test func skippingUnknownGroupChangesNothing() {
        var queue = ReviewQueue(fresh: [groupID(1)])
        queue.skip(groupID(9))
        #expect(queue == ReviewQueue(fresh: [groupID(1)]))
    }
}

import Foundation
import Testing
import SweepDomain
import SweepPersistence
import SweepTestSupport

@Suite struct LargeAssetRegistrationTests {
    @Test func largeBatchGetsUniquePointIDs() async throws {
        let store = try TemporaryStore().open()
        let records = try await store.register((0..<1_200).map { discovered("p\($0)") })
        #expect(records.count == 1_200)
        #expect(Set(records.map(\.pointID)).count == 1_200)
    }

    @Test func pointIDsStayUniqueWhenTheGeneratorRepeatsAfterRelaunch() async throws {
        let file = try TemporaryStore()
        let first = try await file.open(ids: SequentialIDGenerator(startingAt: 1)).register((0..<50).map { discovered("a\($0)") })
        // A relaunch with the same deterministic generator proposes the same IDs again.
        let second = try await file.open(ids: SequentialIDGenerator(startingAt: 1)).register((0..<50).map { discovered("b\($0)") })
        #expect(Set((first + second).map(\.pointID)).count == 100)
    }

    @Test func reRegisteringKeepsPointIDs() async throws {
        let store = try TemporaryStore().open()
        let first = try await store.register([discovered("a"), discovered("b")])
        let again = try await store.register([discovered("a"), discovered("b"), discovered("c")])
        #expect(Array(again.prefix(2)).map(\.pointID) == first.map(\.pointID))
        #expect(Set(again.map(\.pointID)).count == 3)
    }
}

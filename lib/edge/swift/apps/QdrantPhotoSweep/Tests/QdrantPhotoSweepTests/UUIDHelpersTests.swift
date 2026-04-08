import XCTest
@testable import QdrantPhotoSweep

final class UUIDHelpersTests: XCTestCase {
    func testDeterministicUUIDIsStable() {
        let first = deterministicUUID(from: "asset-123")
        let second = deterministicUUID(from: "asset-123")

        XCTAssertEqual(first, second)
        XCTAssertEqual(UUID(uuidString: first)?.uuidString.lowercased(), first)
    }

    func testDeterministicUUIDChangesForDifferentAssets() {
        let first = deterministicUUID(from: "asset-123")
        let second = deterministicUUID(from: "asset-456")

        XCTAssertNotEqual(first, second)
    }

    func testSimilarityEdgeRecordNormalizesOrder() {
        let sessionId = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let forward = SimilarityEdgeRecord(
            sourceVectorUUID: "z-vector",
            targetVectorUUID: "a-vector",
            score: 0.98
        )
        let reversed = SimilarityEdgeRecord(
            sourceVectorUUID: "a-vector",
            targetVectorUUID: "z-vector",
            score: 0.91
        )

        XCTAssertEqual(forward.normalizedSource, "a-vector")
        XCTAssertEqual(forward.normalizedTarget, "z-vector")
        XCTAssertEqual(forward.pairKey(sessionId: sessionId), reversed.pairKey(sessionId: sessionId))
    }
}

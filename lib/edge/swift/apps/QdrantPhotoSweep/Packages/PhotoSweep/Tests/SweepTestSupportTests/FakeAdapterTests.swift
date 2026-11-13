import CoreGraphics
import Foundation
import Testing
import SweepDomain
import SweepTestSupport

private func photo(_ id: String, day: Int?) -> PhotoAsset {
    PhotoAsset(
        id: id, localIdentifier: id,
        creationDate: day.map { Date(timeIntervalSince1970: TimeInterval($0) * 86_400) },
        pixelWidth: 4032, pixelHeight: 3024, fileSize: nil
    )
}

@Suite struct FakePhotoLibraryTests {
    @Test func recordsThumbnailAndFullResolutionRequestsSeparately() async throws {
        let library = FakePhotoLibrary(assets: [photo("a", day: 1)])
        let asset = photo("a", day: 1)
        _ = try await library.loadThumbnail(for: asset, size: CGSize(width: 224, height: 224))
        #expect(await library.fullResolutionRequestCount == 0)
        _ = try await library.loadFullImage(for: asset)
        #expect(await library.imageRequests == [
            .thumbnail(assetID: "a", size: CGSize(width: 224, height: 224)),
            .fullResolution(assetID: "a"),
        ])
    }

    @Test func fetchAppliesInclusiveScopeAndExcludesUndatedAssets() async throws {
        let library = FakePhotoLibrary(assets: [photo("in", day: 5), photo("edge", day: 10), photo("out", day: 11), photo("undated", day: nil)])
        let scope = DateRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 10 * 86_400))
        let ids = try await library.fetchAssets(in: scope).map(\.id)
        #expect(ids == ["in", "edge"])
    }

    @Test func unavailableAssetFailsImageLoad() async {
        let library = FakePhotoLibrary(assets: [photo("a", day: 1)])
        await library.setUnavailable(["a"])
        await #expect(throws: AdapterError.photoLibrary("Asset a is unavailable")) {
            _ = try await library.loadThumbnail(for: photo("a", day: 1), size: CGSize(width: 10, height: 10))
        }
    }

    @Test func declinedDeletionLeavesAssets() async {
        let library = FakePhotoLibrary(assets: [photo("a", day: 1)])
        await library.setDeletionError(.deletion("declined"))
        await #expect(throws: AdapterError.deletion("declined")) {
            try await library.deleteAssets(["a"])
        }
        #expect(await library.assets.count == 1)
        #expect(await library.deletedIdentifiers.isEmpty)
    }

    @Test func authorizationFailureIsReported() async {
        let library = FakePhotoLibrary()
        await library.setAuthorizationError(.authorization("denied"))
        await #expect(throws: AdapterError.authorization("denied")) {
            try await library.requestAuthorization()
        }
    }
}

@Suite struct FakeVectorStoreTests {
    @Test func searchUsesCosineThresholdOrderAndLimit() async throws {
        let store = FakeVectorStore()
        try await store.upsert(points: [
            VectorPoint(id: "same", vector: [1, 0], payloadJson: "{}"),
            VectorPoint(id: "close", vector: [0.9, 0.1], payloadJson: "{}"),
            VectorPoint(id: "orthogonal", vector: [0, 1], payloadJson: "{}"),
        ])
        let results = try await store.search(vector: [1, 0], limit: 10, threshold: 0.5)
        #expect(results.map(\.id) == ["same", "close"])
        let limited = try await store.search(vector: [1, 0], limit: 1, threshold: 0)
        #expect(limited.map(\.id) == ["same"])
    }

    @Test func scrollPagesThroughAllPoints() async throws {
        let store = FakeVectorStore()
        try await store.upsert(points: (0..<5).map { VectorPoint(id: "p\($0)", vector: [1], payloadJson: "{}") })
        var ids: [String] = []
        var offset: String?
        repeat {
            let page = try await store.scroll(offset: offset, limit: 2)
            ids += page.records.map(\.id)
            offset = page.nextOffset
        } while offset != nil
        #expect(ids == ["p0", "p1", "p2", "p3", "p4"])
    }

    @Test func injectedFailureAndClosedStoreThrow() async throws {
        let store = FakeVectorStore()
        await store.setFailure(.vectorStore("busy"))
        await #expect(throws: AdapterError.vectorStore("busy")) {
            _ = try await store.count()
        }
        await store.setFailure(nil)
        #expect(try await store.count() == 0)
        await store.close()
        await #expect(throws: AdapterError.vectorStore("Store is closed")) {
            _ = try await store.count()
        }
    }
}

@Suite struct DeterminismHelperTests {
    @Test func scriptedEmbeddingsAreReturnedInOrder() async throws {
        let image = try #require(FakeImages.onePixel())
        let provider = FakeEmbeddingProvider(scripted: [.success([0, 1]), .failure(.embedding("model"))], defaultVector: [1, 1])
        #expect(try await provider.embed(image: image) == [0, 1])
        await #expect(throws: AdapterError.embedding("model")) {
            _ = try await provider.embed(image: image)
        }
        #expect(try await provider.embed(image: image) == [1, 1])
        #expect(await provider.embedCount == 3)
    }

    @Test func sequentialIDsArePredictable() {
        let generator = SequentialIDGenerator()
        #expect(generator.makeUUID().uuidString == "00000000-0000-0000-0000-000000000001")
        #expect(generator.makeUUID() == SequentialIDGenerator.uuid(2))
    }

    @Test func gateReleasesAllWaiters() async {
        let gate = AsyncGate()
        async let first: Void = gate.wait()
        async let second: Void = gate.wait()
        await gate.waitForWaiters(2)
        await gate.open()
        _ = await (first, second)
        await gate.wait()
        #expect(await gate.waiterCount == 0)
    }
}

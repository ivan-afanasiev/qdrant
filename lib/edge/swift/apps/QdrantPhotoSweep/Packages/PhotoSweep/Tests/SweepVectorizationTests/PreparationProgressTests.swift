import Foundation
import Testing
import SweepDomain
import SweepTestSupport
import SweepUseCases

private actor ProgressLog {
    private(set) var entries: [[Int]] = []

    func append(_ done: Int, _ total: Int) {
        entries.append([done, total])
    }
}

@Suite struct PreparationProgressTests {
    @Test func reconcileReportsProgressAfterFetchAndEveryChunk() async throws {
        let photos = (1...1_200).map { index in
            PhotoAsset(
                id: "p\(index)", localIdentifier: "p\(index)",
                creationDate: Date(timeIntervalSince1970: Double(index) * 60),
                pixelWidth: 10, pixelHeight: 10, fileSize: nil,
                modificationDate: Date(timeIntervalSince1970: 0)
            )
        }
        let harness = try Harness(photos: photos)
        let log = ProgressLog()
        let result = try await ReconcilePhotoLibrary(library: harness.library, assets: try harness.openStore())
            .execute(scope: DateRange(start: .distantPast, end: .distantFuture)) { done, total in
                await log.append(done, total)
            }
        #expect(result.records.count == 1_200)
        #expect(await log.entries == [[0, 1_200], [500, 1_200], [1_000, 1_200], [1_200, 1_200]])
    }
}

private actor StatusLog {
    private(set) var statuses: [VectorizationStatus] = []

    func append(_ status: VectorizationStatus) {
        statuses.append(status)
    }
}

@Suite struct RoutineCheckTests {
    @Test func launchCheckAfterAFinishedScanIsQuiet() async throws {
        let harness = try Harness(photos: [photo("a"), photo("b"), photo("c")])
        let (first, _) = try harness.launch(embedder: FakeEmbeddingProvider())
        await harness.run(first, .userResume)
        #expect(first.status == .completed(deferredCount: 0))

        // Relaunch: the same library is checked again without any visible phase.
        let (relaunched, _) = try harness.launch(embedder: FakeEmbeddingProvider())
        let log = StatusLog()
        let updates = relaunched.statusUpdates()
        let observer = Task {
            for await status in updates {
                await log.append(status)
                if case .completed = status { return }
            }
        }
        await harness.run(relaunched, .appActivation)
        await observer.value
        let statuses = await log.statuses
        #expect(!statuses.contains { if case .preparing = $0 { true } else { false } })
        #expect(!statuses.contains { if case .running = $0 { true } else { false } })
        #expect(statuses.last == .completed(deferredCount: 0))
    }

    @Test func launchCheckWithNewPhotosStillAnalyzesThem() async throws {
        let harness = try Harness(photos: [photo("a"), photo("b")])
        let (first, _) = try harness.launch(embedder: FakeEmbeddingProvider())
        await harness.run(first, .userResume)

        await harness.library.setAssets([photo("a"), photo("b"), photo("c", day: 2)])
        let (relaunched, _) = try harness.launch(embedder: FakeEmbeddingProvider())
        await harness.run(relaunched, .appActivation)
        #expect(relaunched.status == .completed(deferredCount: 0))
        #expect(try await harness.vectors().count() == 3)
    }
}

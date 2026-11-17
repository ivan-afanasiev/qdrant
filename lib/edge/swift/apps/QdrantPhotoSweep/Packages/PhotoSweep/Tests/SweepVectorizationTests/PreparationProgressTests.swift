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

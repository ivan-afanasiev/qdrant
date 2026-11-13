#if os(iOS)
import CoreGraphics
import Testing
@testable import SweepPhotos

struct PhotoImageRequestTests {
    @Test func cancellationBeforeInstallationCompletesContinuation() async {
        let request = PhotoImageRequest()
        request.cancel()
        await #expect(throws: CancellationError.self) {
            let _: CGImage = try await withCheckedThrowingContinuation { continuation in
                #expect(!request.install(continuation))
            }
        }
    }

    @Test func repeatedCancellationCompletesInstalledContinuationOnlyOnce() async {
        let request = PhotoImageRequest()
        await #expect(throws: CancellationError.self) {
            let _: CGImage = try await withCheckedThrowingContinuation { continuation in
                #expect(request.install(continuation))
                request.cancel()
                request.cancel()
                request.finish(.failure(CancellationError()))
            }
        }
    }
}
#endif

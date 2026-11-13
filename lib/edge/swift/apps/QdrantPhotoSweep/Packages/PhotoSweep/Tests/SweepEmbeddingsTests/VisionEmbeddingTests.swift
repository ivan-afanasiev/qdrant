#if os(iOS)
import CoreGraphics
import Testing
import SweepEmbeddings

struct VisionEmbeddingTests {
    @Test func syntheticThumbnailProducesConsistentDimensions() async throws {
        let context = try #require(CGContext(data: nil, width: 224, height: 224,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 224, height: 224))
        let image = try #require(context.makeImage())
        let service = VisionEmbeddingService()
        let vector = try await service.embed(image: image)
        #expect(!vector.isEmpty)
        #expect(vector.allSatisfy(\.isFinite))
        #expect(await service.dimensions == vector.count)
    }
}
#endif

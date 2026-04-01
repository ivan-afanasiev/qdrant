import CoreGraphics
import Vision

final class VisionEmbeddingService: EmbeddingProviding, @unchecked Sendable {
    private var _probedDimensions: Int?

    var dimensions: Int {
        guard let probed = _probedDimensions else {
            fatalError("Must call probeDimensions() before accessing dimensions")
        }
        return probed
    }

    func probeDimensions() throws(AppError) {
        guard _probedDimensions == nil else { return }

        let size = 64
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let probeImage = ctx.makeImage() else {
            throw .embedding("Failed to create probe image for dimension detection")
        }

        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: probeImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw .embedding("Dimension probe failed: \(error.localizedDescription)")
        }

        guard let observation = request.results?.first else {
            throw .embedding("No feature print from dimension probe")
        }

        _probedDimensions = observation.elementCount
    }

    func embed(image: CGImage) async throws(AppError) -> [Float] {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw .embedding("Vision request failed: \(error.localizedDescription)")
        }

        guard let observation = request.results?.first else {
            throw .embedding("No feature print observation returned")
        }

        let elementCount = observation.elementCount
        guard observation.elementType == .float else {
            throw .embedding("Unexpected element type: \(observation.elementType)")
        }

        var floats = [Float](repeating: 0, count: elementCount)
        let data = observation.data
        data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            let typedPointer = baseAddress.assumingMemoryBound(to: Float.self)
            for i in 0..<elementCount {
                floats[i] = typedPointer[i]
            }
        }

        return floats
    }
}

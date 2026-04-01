import CoreGraphics
import Vision

struct VisionEmbeddingService: EmbeddingProviding {
    let dimensions: Int = 768

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

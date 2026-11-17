#if os(iOS)
import SweepDomain
import CoreGraphics
import CoreML
import Vision
import UIKit

public actor VisionEmbeddingService: EmbeddingProviding, EmbeddingModelDescribing {
    public init() {}
    private var _detectedDimensions: Int?
    private var descriptor: EmbeddingModelDescriptor?

    /// Model identity for vector compatibility. Dimensions are measured once by embedding
    /// a small synthetic image, because Vision does not publish them up front.
    public func modelDescriptor() async throws(AdapterError) -> EmbeddingModelDescriptor {
        if let descriptor { return descriptor }
        guard let probe = Self.probeImage() else {
            throw .embedding("Could not create the model probe image")
        }
        let dimensions = try await embed(image: probe).count
        let descriptor = EmbeddingModelDescriptor(
            model: "VNGenerateImageFeaturePrintRequest",
            revision: VNGenerateImageFeaturePrintRequest.currentRevision,
            dimensions: dimensions
        )
        self.descriptor = descriptor
        return descriptor
    }

    private static func probeImage() -> CGImage? {
        let context = CGContext(
            data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
        context?.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        return context?.makeImage()
    }

    /// Neural Engine first (cool and allowed in the background), then CPU; never the GPU.
    private static func backgroundDevice(from devices: [MLComputeDevice]) -> MLComputeDevice? {
        devices.first { if case .neuralEngine = $0 { return true } else { return false } }
            ?? devices.first { if case .cpu = $0 { return true } else { return false } }
    }

    public var dimensions: Int {
        _detectedDimensions ?? 0
    }

    public var hasDeterminedDimensions: Bool {
        _detectedDimensions != nil
    }

    public func embed(image: CGImage) async throws(AdapterError) -> [Float] {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            // Let Vision select its normal devices while active. Background requests must
            // avoid the GPU without a background GPU entitlement, so each stage uses the
            // Neural Engine when available and the CPU otherwise. CPU-only is not enough:
            // on device the CPU variant of the feature-print model can be missing
            // ("Missing weights path SceneNet…", ESPRESSO_STATUS_ERROR_IO), which failed
            // every background embedding.
            let isBackground = await MainActor.run {
                UIApplication.shared.applicationState == .background
            }
            if isBackground {
                for (stage, devices) in try request.supportedComputeStageDevices {
                    guard let device = Self.backgroundDevice(from: devices) else {
                        throw AdapterError.embedding("No Neural Engine or CPU device is available for this Vision request")
                    }
                    request.setComputeDevice(device, for: stage)
                }
            }
            try handler.perform([request])
        } catch {
            let underlying = error as NSError
            throw .embedding("Vision request failed (\(underlying.domain), \(underlying.code)): \(underlying.localizedDescription)")
        }

        guard let observation = request.results?.first else {
            throw .embedding("No feature print observation returned")
        }

        let elementCount = observation.elementCount
        guard observation.elementType == .float else {
            throw .embedding("Unexpected element type: \(observation.elementType)")
        }

        if _detectedDimensions == nil {
            _detectedDimensions = elementCount
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

#endif

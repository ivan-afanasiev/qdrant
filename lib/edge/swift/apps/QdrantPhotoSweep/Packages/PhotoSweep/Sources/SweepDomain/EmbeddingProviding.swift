import CoreGraphics
import Foundation

public protocol EmbeddingProviding: Sendable {
    func embed(image: CGImage) async throws(AdapterError) -> [Float]
}

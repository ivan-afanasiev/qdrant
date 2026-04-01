import CoreGraphics
import Foundation

protocol EmbeddingProviding: Sendable {
    func embed(image: CGImage) async throws(AppError) -> [Float]
}

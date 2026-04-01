import CoreGraphics
import Foundation

protocol EmbeddingProviding: Sendable {
    var dimensions: Int { get }
    func embed(image: CGImage) async throws(AppError) -> [Float]
}

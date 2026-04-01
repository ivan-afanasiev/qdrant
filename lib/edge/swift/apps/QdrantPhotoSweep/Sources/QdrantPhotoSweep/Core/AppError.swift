import Foundation

enum AppError: LocalizedError, Equatable {
    case authorization(String)
    case embedding(String)
    case vectorStore(String)
    case photoLibrary(String)
    case deletion(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .authorization(let detail): "Authorization failed: \(detail)"
        case .embedding(let detail): "Embedding failed: \(detail)"
        case .vectorStore(let detail): "Vector store error: \(detail)"
        case .photoLibrary(let detail): "Photo library error: \(detail)"
        case .deletion(let detail): "Deletion failed: \(detail)"
        case .unknown(let detail): "Unexpected error: \(detail)"
        }
    }
}

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
        case .authorization(let detail): L10n.authorizationError(detail)
        case .embedding(let detail): L10n.embeddingError(detail)
        case .vectorStore(let detail): L10n.vectorStoreError(detail)
        case .photoLibrary(let detail): L10n.photoLibraryError(detail)
        case .deletion(let detail): L10n.deletionError(detail)
        case .unknown(let detail): L10n.unexpectedError(detail)
        }
    }
}

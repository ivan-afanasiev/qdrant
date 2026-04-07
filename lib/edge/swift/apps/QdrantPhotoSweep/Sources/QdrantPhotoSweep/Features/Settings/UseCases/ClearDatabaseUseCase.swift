import Foundation

struct ClearDatabaseUseCase: UseCase {
    let vectorStore: any VectorStoring

    func execute(_ input: Void) async throws -> Void {
        var offset: String? = nil
        while true {
            let page = try await vectorStore.scroll(offset: offset, limit: 100)
            guard !page.records.isEmpty else { break }
            let ids = page.records.map(\.id)
            try await vectorStore.delete(ids: ids)
            offset = page.nextOffset
            guard offset != nil else { break }
        }
    }
}

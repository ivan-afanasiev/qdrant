import Foundation

@Observable
@MainActor
final class DuplicateDetectionState {
    enum Status: Equatable {
        case idle
        case analyzing(progress: Double)
        case complete(groups: [DuplicateGroup])
        case failed(AppError)
    }

    enum Action {
        case didStartAnalysis
        case progressUpdated(Double)
        case didFinishAnalysis(groups: [DuplicateGroup])
        case didFail(AppError)
    }

    private(set) var status: Status = .idle

    func reduce(_ action: Action) {
        switch action {
        case .didStartAnalysis:
            status = .analyzing(progress: 0)
        case .progressUpdated(let progress):
            status = .analyzing(progress: progress)
        case .didFinishAnalysis(let groups):
            status = .complete(groups: groups)
        case .didFail(let error):
            status = .failed(error)
        }
    }

    func findDuplicates(vectorStore: any VectorStoring, threshold: Float, scanStore: (any ScanSessionStoring)? = nil) async {
        reduce(.didStartAnalysis)

        do {
            let allData = try await scrollAllPoints(vectorStore: vectorStore)

            guard allData.ids.count > 1 else {
                reduce(.didFinishAnalysis(groups: []))
                return
            }

            let groups = try await runAnalysis(
                ids: allData.ids,
                vectors: allData.vectors,
                payloads: allData.payloads,
                vectorStore: vectorStore,
                threshold: threshold
            )

            if let store = scanStore, !groups.isEmpty {
                if let session = try? await store.latestCompletedSession() {
                    try? await store.deleteAllPendingGroups()
                    try? await store.saveDuplicateGroups(groups, sessionId: session.id)
                }
            }

            reduce(.didFinishAnalysis(groups: groups))
        } catch let appError as AppError {
            reduce(.didFail(appError))
        } catch {
            reduce(.didFail(.unknown(error.localizedDescription)))
        }
    }

    private struct ScrollData {
        var ids: [String] = []
        var payloads: [String: String?] = [:]
        var vectors: [String: [Float]] = [:]
    }

    private func scrollAllPoints(vectorStore: any VectorStoring) async throws(AppError) -> ScrollData {
        var data = ScrollData()
        var offset: String? = nil

        while true {
            let page = try await vectorStore.scroll(offset: offset, limit: 100)
            guard !page.records.isEmpty else { break }

            for record in page.records {
                data.payloads[record.id] = record.payloadJson
                if let vectorJson = record.vectorJson {
                    let vector = parseVectorJson(vectorJson)
                    data.vectors[record.id] = vector
                    data.ids.append(record.id)
                }
            }

            offset = page.nextOffset
            guard offset != nil else { break }
        }

        return data
    }

    nonisolated private func runAnalysis(
        ids: [String],
        vectors: [String: [Float]],
        payloads: [String: String?],
        vectorStore: any VectorStoring,
        threshold: Float
    ) async throws -> [DuplicateGroup] {
        var unionFind = UnionFind<String>()
        var allScores: [String: Float] = [:]

        for (index, pointId) in ids.enumerated() {
            guard let vector = vectors[pointId] else { continue }

            let results = try await vectorStore.search(
                vector: vector,
                limit: 10,
                threshold: threshold
            )

            for result in results where result.id != pointId {
                _ = unionFind.find(pointId)
                _ = unionFind.find(result.id)
                unionFind.union(pointId, result.id)
                allScores[result.id] = max(allScores[result.id, default: 0], result.score)
            }

            let progress = Double(index + 1) / Double(ids.count)
            await MainActor.run { [self] in
                self.reduce(.progressUpdated(progress))
            }
        }

        let components = unionFind.components()
        return components.compactMap { component in
            DuplicateGroup.from(
                photoIds: component,
                payloads: payloads,
                scores: allScores
            )
        }.sorted(by: { $0.count > $1.count })
    }
}

private func parseVectorJson(_ json: String) -> [Float] {
    guard let data = json.data(using: .utf8) else { return [] }

    if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let values = dict[""] as? [Any] {
        return values.compactMap { ($0 as? NSNumber)?.floatValue }
    }

    if let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
        return array.compactMap { ($0 as? NSNumber)?.floatValue }
    }

    return []
}

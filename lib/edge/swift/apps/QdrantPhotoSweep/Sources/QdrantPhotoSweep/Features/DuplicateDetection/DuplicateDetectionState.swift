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

    var status: Status = .idle

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

    func findDuplicates(vectorStore: any VectorStoring, threshold: Float) async {
        reduce(.didStartAnalysis)

        do {
            var unionFind = UnionFind<String>()
            var allPayloads: [String: String?] = [:]
            var allScores: [String: Float] = [:]
            var allVectors: [String: [Float]] = [:]
            var offset: String? = nil
            var totalRecords = 0

            // Scroll all points
            while true {
                let page = try await vectorStore.scroll(offset: offset, limit: 100)
                guard !page.records.isEmpty else { break }
                totalRecords += page.records.count

                for record in page.records {
                    allPayloads[record.id] = record.payloadJson
                    if let vectorJson = record.vectorJson {
                        let vector = parseVectorJson(vectorJson)
                        allVectors[record.id] = vector
                    }
                }

                offset = page.nextOffset
                guard offset != nil else { break }
            }

            guard totalRecords > 1 else {
                reduce(.didFinishAnalysis(groups: []))
                return
            }

            // Search neighbors for each point
            let ids = Array(allVectors.keys)
            for (index, pointId) in ids.enumerated() {
                guard let vector = allVectors[pointId] else { continue }

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
                reduce(.progressUpdated(progress))
            }

            let components = unionFind.components()
            let groups = components.compactMap { component in
                DuplicateGroup.from(
                    photoIds: component,
                    payloads: allPayloads,
                    scores: allScores
                )
            }.sorted(by: { $0.count > $1.count })

            reduce(.didFinishAnalysis(groups: groups))
        } catch {
            reduce(.didFail(error))
        }
    }
}

private func parseVectorJson(_ json: String) -> [Float] {
    guard let data = json.data(using: .utf8) else { return [] }

    // The vector JSON from Qdrant Edge comes as {"": [1.0, 2.0, ...]}
    if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let values = dict[""] as? [Any] {
        return values.compactMap { ($0 as? NSNumber)?.floatValue }
    }

    // Or it may be a flat array
    if let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
        return array.compactMap { ($0 as? NSNumber)?.floatValue }
    }

    return []
}

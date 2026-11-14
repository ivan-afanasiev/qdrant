import Foundation
import SwiftData
import SweepDomain

/// SwiftData implementation of every metadata contract. Each public operation that
/// changes several records does so in a single save, so a crash leaves either the
/// old or the new state. Only value types cross the actor boundary.
public actor SwiftDataMetadataStore: ModelActor {
    public nonisolated let modelExecutor: any ModelExecutor
    public nonisolated let modelContainer: ModelContainer
    let ids: any IDGenerating

    public init(container: ModelContainer, ids: any IDGenerating = SystemIDGenerator()) {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        self.modelContainer = container
        self.ids = ids
    }

    // MARK: - Helpers

    /// Runs store work, mapping framework errors and discarding unsaved changes on failure.
    func perform<T>(_ body: () throws -> T) throws(PersistenceError) -> T {
        do {
            return try body()
        } catch let error as PersistenceError {
            modelContext.rollback()
            throw error
        } catch {
            modelContext.rollback()
            throw .storeUnavailable(String(describing: error))
        }
    }

    func save() throws {
        do {
            try modelContext.save()
        } catch {
            throw PersistenceError.saveFailed(String(describing: error))
        }
    }

    func fetchAssetEntities(_ ids: [String]) throws -> [String: AssetEntity] {
        let descriptor = FetchDescriptor<AssetEntity>(predicate: #Predicate { ids.contains($0.assetID) })
        let entities = try modelContext.fetch(descriptor)
        return Dictionary(entities.map { ($0.assetID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func newPointID() throws -> UUID {
        while true {
            let candidate = ids.makeUUID()
            let count = try modelContext.fetchCount(FetchDescriptor<AssetEntity>(predicate: #Predicate { $0.pointID == candidate }))
            if count == 0 { return candidate }
        }
    }

    func nextJournalSequence() throws -> Int {
        var descriptor = FetchDescriptor<JournalEntity>(sortBy: [SortDescriptor(\.sequence, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try modelContext.fetch(descriptor).first?.sequence ?? 0) + 1
    }

    func journalEntity(_ operation: OperationID) throws -> JournalEntity? {
        let id = operation.rawValue
        var descriptor = FetchDescriptor<JournalEntity>(predicate: #Predicate { $0.operationID == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func intents(of operation: UUID) throws -> [JournalIntentEntity] {
        try modelContext.fetch(FetchDescriptor<JournalIntentEntity>(
            predicate: #Predicate { $0.operationID == operation },
            sortBy: [SortDescriptor(\.position)]
        ))
    }

    static func clearVector(_ entity: AssetEntity) {
        entity.embeddingModel = nil
        entity.modelRevision = nil
        entity.preprocessing = nil
        entity.dimensions = nil
        entity.generation = nil
        entity.vectorContentRevision = nil
    }

    static func record(from entity: AssetEntity) -> AssetRecord {
        AssetRecord(
            id: AssetID(entity.assetID),
            creationDate: entity.creationDate,
            contentRevision: AssetContentRevision(entity.contentRevision),
            pointID: VectorPointID(entity.pointID),
            state: state(of: entity)
        )
    }

    /// Incomplete vector metadata is never reported as vectorized.
    static func state(of entity: AssetEntity) -> AssetVectorState {
        switch entity.state {
        case "vectorized":
            guard let model = entity.embeddingModel, let modelRevision = entity.modelRevision,
                  let preprocessing = entity.preprocessing, let dimensions = entity.dimensions,
                  let generation = entity.generation, let revision = entity.vectorContentRevision else {
                return .pending
            }
            return .vectorized(
                compatibility: EmbeddingCompatibility(model: model, modelRevision: modelRevision, preprocessing: preprocessing, dimensions: dimensions),
                generation: IndexGeneration(generation),
                contentRevision: AssetContentRevision(revision)
            )
        case "deferred":
            return .deferred(.unavailable(entity.deferralDetail ?? ""))
        default:
            return .pending
        }
    }
}

// MARK: - AssetRepository

extension SwiftDataMetadataStore: AssetRepository {
    public func register(_ assets: [DiscoveredAsset]) async throws(PersistenceError) -> [AssetRecord] {
        try perform {
            var entities = try fetchAssetEntities(assets.map(\.id.rawValue))
            for asset in assets {
                if let entity = entities[asset.id.rawValue] {
                    entity.creationDate = asset.creationDate
                    entity.seedDate = asset.creationDate ?? .distantPast
                    entity.isDated = asset.creationDate != nil
                    if entity.contentRevision != asset.contentRevision.rawValue {
                        // Edited content: the stored vector no longer describes the photo,
                        // and the photo must be examined again by discovery.
                        entity.contentRevision = asset.contentRevision.rawValue
                        entity.state = "pending"
                        entity.deferralDetail = nil
                        entity.examinedRevision = 0
                        Self.clearVector(entity)
                    }
                } else {
                    let entity = AssetEntity(
                        assetID: asset.id.rawValue,
                        creationDate: asset.creationDate,
                        contentRevision: asset.contentRevision.rawValue,
                        pointID: try newPointID()
                    )
                    modelContext.insert(entity)
                    entities[asset.id.rawValue] = entity
                }
            }
            try save()
            return assets.compactMap { entities[$0.id.rawValue].map(Self.record(from:)) }
        }
    }

    public func assets(_ ids: [AssetID]) async throws(PersistenceError) -> [AssetID: AssetRecord] {
        try perform {
            let entities = try fetchAssetEntities(ids.map(\.rawValue))
            return Dictionary(uniqueKeysWithValues: entities.values.map { (AssetID($0.assetID), Self.record(from: $0)) })
        }
    }

    public func removeAssets(_ ids: [AssetID]) async throws(PersistenceError) {
        try perform {
            for entity in try fetchAssetEntities(ids.map(\.rawValue)).values {
                modelContext.delete(entity)
            }
            try save()
        }
    }
}

// MARK: - VectorWriteJournaling

extension SwiftDataMetadataStore: VectorWriteJournaling {
    public func beginVectorWrite(_ operation: OperationID, intents: [VectorWriteIntent]) async throws(PersistenceError) {
        try perform {
            guard try journalEntity(operation) == nil else {
                throw PersistenceError.invalidState("Journal entry \(operation.rawValue) already exists")
            }
            let journal = JournalEntity(operationID: operation.rawValue, kind: "vectorWrite", sequence: try nextJournalSequence())
            journal.assetIDs = intents.map(\.assetID.rawValue)
            modelContext.insert(journal)
            for (position, intent) in intents.enumerated() {
                modelContext.insert(JournalIntentEntity(operationID: operation.rawValue, position: position, intent: VectorWriteIntentFields(
                    assetID: intent.assetID.rawValue,
                    pointID: intent.pointID.rawValue,
                    contentRevision: intent.contentRevision.rawValue,
                    embeddingModel: intent.compatibility.model,
                    modelRevision: intent.compatibility.modelRevision,
                    preprocessing: intent.compatibility.preprocessing,
                    dimensions: intent.compatibility.dimensions,
                    generation: intent.generation.rawValue
                )))
            }
            try save()
        }
    }

    public func commitVectorWrite(_ operation: OperationID, pass: VectorizationPassID?) async throws(PersistenceError) {
        try perform {
            guard let journal = try journalEntity(operation), journal.kind == "vectorWrite" else {
                throw PersistenceError.notFound("Vector write \(operation.rawValue)")
            }
            let intents = try intents(of: operation.rawValue)
            let assets = try fetchAssetEntities(intents.map(\.assetID))
            var committed: [String] = []
            for intent in intents {
                // An asset edited after the intent keeps its pending state: the vector describes old content.
                guard let asset = assets[intent.assetID], asset.contentRevision == intent.contentRevision,
                      asset.pointID == intent.pointID else { continue }
                asset.state = "vectorized"
                asset.deferralDetail = nil
                asset.embeddingModel = intent.embeddingModel
                asset.modelRevision = intent.modelRevision
                asset.preprocessing = intent.preprocessing
                asset.dimensions = intent.dimensions
                asset.generation = intent.generation
                asset.vectorContentRevision = intent.contentRevision
                committed.append(intent.assetID)
            }
            if let pass {
                try applyPassOutcome("vectorized", detail: nil, assets: committed, pass: pass.rawValue)
            }
            intents.forEach(modelContext.delete)
            modelContext.delete(journal)
            try save()
        }
    }

    public func abandonVectorWrite(_ operation: OperationID) async throws(PersistenceError) {
        try perform {
            guard let journal = try journalEntity(operation), journal.kind == "vectorWrite" else {
                throw PersistenceError.notFound("Vector write \(operation.rawValue)")
            }
            let intents = try intents(of: operation.rawValue)
            let assets = try fetchAssetEntities(intents.map(\.assetID))
            for intent in intents {
                guard let asset = assets[intent.assetID], asset.pointID == intent.pointID else { continue }
                // The point was removed during rollback, so any older vector is gone too.
                asset.state = "pending"
                asset.deferralDetail = nil
                Self.clearVector(asset)
            }
            intents.forEach(modelContext.delete)
            modelContext.delete(journal)
            try save()
        }
    }
}

// MARK: - VectorizationPassRepository

extension SwiftDataMetadataStore: VectorizationPassRepository {
    public func beginPass(_ pass: VectorizationPass) async throws(PersistenceError) {
        try perform {
            try deleteAllPasses()
            modelContext.insert(PassEntity(
                passID: pass.id.rawValue,
                kind: pass.kind == .initial ? "initial" : "incremental",
                scopeStart: pass.scope.start,
                scopeEnd: pass.scope.end
            ))
            for (asset, outcome) in pass.outcomes {
                let (name, detail) = Self.encode(outcome)
                modelContext.insert(PassItemEntity(passID: pass.id.rawValue, assetID: asset.rawValue, outcome: name, deferralDetail: detail))
            }
            try save()
        }
    }

    public func activePass() async throws(PersistenceError) -> VectorizationPass? {
        try perform {
            guard let pass = try modelContext.fetch(FetchDescriptor<PassEntity>()).first else { return nil }
            let passID = pass.passID
            let items = try modelContext.fetch(FetchDescriptor<PassItemEntity>(predicate: #Predicate { $0.passID == passID }))
            var outcomes: [AssetID: AssetOutcome] = [:]
            for item in items {
                outcomes[AssetID(item.assetID)] = Self.decodeOutcome(item.outcome, detail: item.deferralDetail)
            }
            return VectorizationPass(
                id: VectorizationPassID(passID),
                kind: pass.kind == "initial" ? .initial : .incremental,
                scope: DateRange(start: pass.scopeStart, end: pass.scopeEnd),
                outcomes: outcomes
            )
        }
    }

    public func recordDeferred(_ deferrals: [AssetID: DeferralReason], pass: VectorizationPassID) async throws(PersistenceError) {
        try perform {
            let assets = try fetchAssetEntities(deferrals.keys.map(\.rawValue))
            for (id, reason) in deferrals {
                guard let asset = assets[id.rawValue] else { continue }
                asset.state = "deferred"
                asset.deferralDetail = Self.detail(of: reason)
                Self.clearVector(asset)
                try applyPassOutcome("deferred", detail: Self.detail(of: reason), assets: [id.rawValue], pass: pass.rawValue)
            }
            try save()
        }
    }

    public func finishPass(_ id: VectorizationPassID) async throws(PersistenceError) {
        try perform {
            let passID = id.rawValue
            let passes = try modelContext.fetch(FetchDescriptor<PassEntity>(predicate: #Predicate { $0.passID == passID }))
            guard !passes.isEmpty else { return }
            try deleteAllPasses()
            try save()
        }
    }

    func deleteAllPasses() throws {
        try modelContext.fetch(FetchDescriptor<PassItemEntity>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<PassEntity>()).forEach(modelContext.delete)
    }

    func applyPassOutcome(_ outcome: String, detail: String?, assets: [String], pass: UUID) throws {
        let keys = assets.map { "\(pass.uuidString)|\($0)" }
        let items = try modelContext.fetch(FetchDescriptor<PassItemEntity>(predicate: #Predicate { keys.contains($0.key) }))
        for item in items {
            item.outcome = outcome
            item.deferralDetail = detail
        }
    }

    static func encode(_ outcome: AssetOutcome) -> (String, String?) {
        switch outcome {
        case .pending: ("pending", nil)
        case .vectorized: ("vectorized", nil)
        case .deferred(let reason): ("deferred", detail(of: reason))
        }
    }

    static func decodeOutcome(_ name: String, detail: String?) -> AssetOutcome {
        switch name {
        case "vectorized": .vectorized
        case "deferred": .deferred(.unavailable(detail ?? ""))
        default: .pending
        }
    }

    static func detail(of reason: DeferralReason) -> String {
        switch reason {
        case .unavailable(let detail): detail
        }
    }
}

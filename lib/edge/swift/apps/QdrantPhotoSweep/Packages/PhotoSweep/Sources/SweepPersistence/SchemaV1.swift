import Foundation
import SwiftData

/// First schema of the rewrite. Enum-like values are stored as strings so that
/// future migrations do not depend on Swift enum layout.
enum PhotoSweepSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            AssetEntity.self, PassEntity.self, PassItemEntity.self, WorkflowStateEntity.self,
            DiscoveryProgressEntity.self, FrontierEntryEntity.self, GroupEntity.self,
            GroupMemberEntity.self, JournalEntity.self, JournalIntentEntity.self, StatisticsEventEntity.self,
        ]
    }

    @Model
    final class AssetEntity {
        @Attribute(.unique) var assetID: String
        var creationDate: Date?
        var contentRevision: String
        @Attribute(.unique) var pointID: UUID
        /// "pending", "vectorized" or "deferred".
        var state: String
        var embeddingModel: String?
        var modelRevision: Int?
        var preprocessing: String?
        var dimensions: Int?
        var generation: Int?
        var vectorContentRevision: String?
        var deferralDetail: String?
        /// Non-optional sort/filter key for newest-first seeding; undated assets have `isDated == false`.
        var seedDate: Date
        var isDated: Bool
        /// Discovery revision in which this asset was last examined (0 = never).
        var examinedRevision: Int

        init(assetID: String, creationDate: Date?, contentRevision: String, pointID: UUID) {
            self.assetID = assetID
            self.creationDate = creationDate
            self.contentRevision = contentRevision
            self.pointID = pointID
            self.state = "pending"
            self.seedDate = creationDate ?? .distantPast
            self.isDated = creationDate != nil
            self.examinedRevision = 0
        }
    }

    @Model
    final class PassEntity {
        @Attribute(.unique) var passID: UUID
        /// "initial" or "incremental".
        var kind: String
        var scopeStart: Date
        var scopeEnd: Date

        init(passID: UUID, kind: String, scopeStart: Date, scopeEnd: Date) {
            self.passID = passID
            self.kind = kind
            self.scopeStart = scopeStart
            self.scopeEnd = scopeEnd
        }
    }

    @Model
    final class PassItemEntity {
        /// "<passID>|<assetID>".
        @Attribute(.unique) var key: String
        var passID: UUID
        var assetID: String
        /// "pending", "vectorized" or "deferred".
        var outcome: String
        var deferralDetail: String?

        init(passID: UUID, assetID: String, outcome: String, deferralDetail: String?) {
            self.key = "\(passID.uuidString)|\(assetID)"
            self.passID = passID
            self.assetID = assetID
            self.outcome = outcome
            self.deferralDetail = deferralDetail
        }
    }

    @Model
    final class WorkflowStateEntity {
        @Attribute(.unique) var key: String
        var scopeStart: Date
        var scopeEnd: Date
        var threshold: Float
        var isPausedByUser: Bool
        var gateIsOpen: Bool
        var gatePassID: UUID?
        var gateDeferredCount: Int
        var discoveryRevision: Int
        var indexGeneration: Int
        var indexModel: String?
        var indexModelRevision: Int?
        var indexPreprocessing: String?
        var indexDimensions: Int?
        var notifiedPassID: UUID?
        var datePreset: String = "last3Years"
        var isOnboardingCompleted: Bool = false

        init(key: String) {
            self.key = key
            self.scopeStart = .distantPast
            self.scopeEnd = .distantPast
            self.threshold = 0
            self.isPausedByUser = false
            self.gateIsOpen = false
            self.gateDeferredCount = 0
            self.discoveryRevision = 0
            self.indexGeneration = 0
        }
    }

    @Model
    final class DiscoveryProgressEntity {
        @Attribute(.unique) var revision: Int
        var seedCursor: String?
        var isSeedCursorExhausted: Bool
        var expansionSeed: String?
        var expansionScopeStart: Date?
        var expansionScopeEnd: Date?
        var expansionThreshold: Float?
        var expansionGeneration: Int?
        var queriedCount: Int

        init(revision: Int) {
            self.revision = revision
            self.isSeedCursorExhausted = false
            self.queriedCount = 0
        }
    }

    /// Spilled component frontier: one row per visited member, so large components are not
    /// rewritten as a single blob on every checkpoint.
    @Model
    final class FrontierEntryEntity {
        /// "<revision>|<order>".
        @Attribute(.unique) var key: String
        var revision: Int
        var order: Int
        var assetID: String

        init(revision: Int, order: Int, assetID: String) {
            self.key = "\(revision)|\(order)"
            self.revision = revision
            self.order = order
            self.assetID = assetID
        }
    }

    @Model
    final class GroupEntity {
        @Attribute(.unique) var groupID: UUID
        var discoveryRevision: Int
        var membershipRevision: Int
        /// "fresh", "deferred", "completed" or "retired".
        var state: String
        var freshOrder: Int
        var deferredOrder: Int?
        var derivedFrom: [UUID]
        var completionOperation: UUID?

        init(groupID: UUID, discoveryRevision: Int, membershipRevision: Int, freshOrder: Int, derivedFrom: [UUID]) {
            self.groupID = groupID
            self.discoveryRevision = discoveryRevision
            self.membershipRevision = membershipRevision
            self.state = "fresh"
            self.freshOrder = freshOrder
            self.derivedFrom = derivedFrom
        }
    }

    @Model
    final class GroupMemberEntity {
        /// "<groupID>|<assetID>".
        @Attribute(.unique) var key: String
        var groupID: UUID
        var assetID: String
        var position: Int

        init(groupID: UUID, assetID: String, position: Int) {
            self.key = "\(groupID.uuidString)|\(assetID)"
            self.groupID = groupID
            self.assetID = assetID
            self.position = position
        }
    }

    @Model
    final class JournalEntity {
        @Attribute(.unique) var operationID: UUID
        /// "vectorWrite", "deletion" or "reset".
        var kind: String
        /// "intended" or "externalConfirmed".
        var phase: String
        var sequence: Int
        var groupID: UUID?
        var membershipRevision: Int?
        var assetIDs: [String]
        var estimatedBytes: Int64?

        init(operationID: UUID, kind: String, sequence: Int) {
            self.operationID = operationID
            self.kind = kind
            self.phase = "intended"
            self.sequence = sequence
            self.assetIDs = []
        }
    }

    @Model
    final class JournalIntentEntity {
        /// "<operationID>|<assetID>".
        @Attribute(.unique) var key: String
        var operationID: UUID
        var position: Int
        var assetID: String
        var pointID: UUID
        var contentRevision: String
        var embeddingModel: String
        var modelRevision: Int
        var preprocessing: String
        var dimensions: Int
        var generation: Int

        init(operationID: UUID, position: Int, intent: VectorWriteIntentFields) {
            self.key = "\(operationID.uuidString)|\(intent.assetID)"
            self.operationID = operationID
            self.position = position
            self.assetID = intent.assetID
            self.pointID = intent.pointID
            self.contentRevision = intent.contentRevision
            self.embeddingModel = intent.embeddingModel
            self.modelRevision = intent.modelRevision
            self.preprocessing = intent.preprocessing
            self.dimensions = intent.dimensions
            self.generation = intent.generation
        }
    }

    @Model
    final class StatisticsEventEntity {
        /// "<kind>|<operationID>" so one operation can record each kind once.
        @Attribute(.unique) var key: String
        /// "groupReviewed" or "photosDeleted".
        var kind: String
        var operationID: UUID
        var photoCount: Int
        var estimatedBytes: Int64?
        var discoveryRevision: Int

        init(kind: String, operationID: UUID, photoCount: Int, estimatedBytes: Int64?, discoveryRevision: Int) {
            self.key = "\(kind)|\(operationID.uuidString)"
            self.kind = kind
            self.operationID = operationID
            self.photoCount = photoCount
            self.estimatedBytes = estimatedBytes
            self.discoveryRevision = discoveryRevision
        }
    }
}

/// Flat storage form of a vector write intent.
struct VectorWriteIntentFields {
    let assetID: String
    let pointID: UUID
    let contentRevision: String
    let embeddingModel: String
    let modelRevision: Int
    let preprocessing: String
    let dimensions: Int
    let generation: Int
}

enum PhotoSweepMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [PhotoSweepSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

typealias AssetEntity = PhotoSweepSchemaV1.AssetEntity
typealias PassEntity = PhotoSweepSchemaV1.PassEntity
typealias PassItemEntity = PhotoSweepSchemaV1.PassItemEntity
typealias WorkflowStateEntity = PhotoSweepSchemaV1.WorkflowStateEntity
typealias DiscoveryProgressEntity = PhotoSweepSchemaV1.DiscoveryProgressEntity
typealias FrontierEntryEntity = PhotoSweepSchemaV1.FrontierEntryEntity
typealias GroupEntity = PhotoSweepSchemaV1.GroupEntity
typealias GroupMemberEntity = PhotoSweepSchemaV1.GroupMemberEntity
typealias JournalEntity = PhotoSweepSchemaV1.JournalEntity
typealias JournalIntentEntity = PhotoSweepSchemaV1.JournalIntentEntity
typealias StatisticsEventEntity = PhotoSweepSchemaV1.StatisticsEventEntity

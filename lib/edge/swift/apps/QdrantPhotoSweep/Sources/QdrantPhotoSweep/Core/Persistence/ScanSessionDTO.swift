import Foundation
import SwiftData

struct ScanSessionDTO: Identifiable, Sendable {
    let id: UUID
    let rangeStart: Date
    let rangeEnd: Date
    let scannedAt: Date
    let status: ScanSessionStatus
    let totalPhotos: Int
    let indexedPhotos: Int
}

extension ScanSessionEntity {
    func toDTO() -> ScanSessionDTO {
        ScanSessionDTO(
            id: id,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            scannedAt: scannedAt,
            status: ScanSessionStatus(rawValue: status) ?? .scanning,
            totalPhotos: totalPhotos,
            indexedPhotos: indexedPhotos
        )
    }
}

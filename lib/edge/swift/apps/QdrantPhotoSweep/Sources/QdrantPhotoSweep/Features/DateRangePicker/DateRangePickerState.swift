import Foundation
import SwiftUI

enum DatePreset: String, CaseIterable, Identifiable {
    case lastWeek
    case lastMonth
    case last3Months
    case last6Months
    case lastYear
    case allTime

    var id: String { rawValue }

    var localizedName: LocalizedStringKey {
        switch self {
        case .lastWeek: L10n.lastWeek
        case .lastMonth: L10n.lastMonth
        case .last3Months: L10n.last3Months
        case .last6Months: L10n.last6Months
        case .lastYear: L10n.lastYear
        case .allTime: L10n.allTime
        }
    }

    var dateRange: DateRange {
        let now = Date.now
        let calendar = Calendar.current
        switch self {
        case .lastWeek:
            let start = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
            return DateRange(start: start, end: now)
        case .lastMonth:
            let start = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return DateRange(start: start, end: now)
        case .last3Months:
            let start = calendar.date(byAdding: .month, value: -3, to: now) ?? now
            return DateRange(start: start, end: now)
        case .last6Months:
            let start = calendar.date(byAdding: .month, value: -6, to: now) ?? now
            return DateRange(start: start, end: now)
        case .lastYear:
            let start = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return DateRange(start: start, end: now)
        case .allTime:
            return .allTime
        }
    }
}

@Observable
@MainActor
final class DateRangePickerState {
    enum Status: Equatable {
        case idle
        case counting
        case ready(photoCount: Int)
        case failed(AppError)
    }

    enum Action {
        case presetSelected(DatePreset)
        case customRangeChanged(start: Date, end: Date)
        case didStartCounting
        case countLoaded(Int)
        case countFailed(AppError)
    }

    var status: Status = .idle
    var selectedPreset: DatePreset? = .lastMonth
    var customStart: Date = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    var customEnd: Date = .now
    var isCustomRange: Bool = false

    var newPhotoCount: Int = 0
    var lastSession: ScanSessionDTO?
    var pendingGroupCount: Int = 0
    var interruptedSession: ScanSessionDTO?

    var currentDateRange: DateRange {
        switch isCustomRange {
        case true:
            DateRange(start: customStart, end: customEnd)
        case false:
            selectedPreset?.dateRange ?? .allTime
        }
    }

    func reduce(_ action: Action) {
        switch action {
        case .presetSelected(let preset):
            isCustomRange = false
            selectedPreset = preset
            status = .counting

        case .customRangeChanged(let start, let end):
            isCustomRange = true
            selectedPreset = nil
            customStart = start
            customEnd = end
            status = .counting

        case .didStartCounting:
            status = .counting

        case .countLoaded(let count):
            status = .ready(photoCount: count)

        case .countFailed(let error):
            status = .failed(error)
        }
    }

    func loadCount(using photoLibrary: any PhotoLibraryProviding) async {
        reduce(.presetSelected(selectedPreset ?? .lastMonth))
        do {
            let count = try await photoLibrary.countAssets(in: currentDateRange)
            reduce(.countLoaded(count))
        } catch {
            reduce(.countFailed(error))
        }
    }

    func recount(using photoLibrary: any PhotoLibraryProviding) async {
        reduce(.didStartCounting)
        do {
            let count = try await photoLibrary.countAssets(in: currentDateRange)
            reduce(.countLoaded(count))
        } catch {
            reduce(.countFailed(error))
        }
    }

    func checkForNewPhotos(scanStore: any ScanSessionStoring, photoLibrary: any PhotoLibraryProviding) async {
        do {
            if let session = try await scanStore.latestCompletedSession() {
                lastSession = session
                let range = DateRange(start: session.rangeStart, end: session.rangeEnd)
                newPhotoCount = try await scanStore.countNewPhotosSince(
                    date: session.scannedAt,
                    in: range,
                    using: photoLibrary
                )
            }
            interruptedSession = try await scanStore.latestInterruptedSession()
            let pending = try await scanStore.loadPendingGroups()
            pendingGroupCount = pending.count
        } catch {
            newPhotoCount = 0
            pendingGroupCount = 0
            interruptedSession = nil
        }
    }
}

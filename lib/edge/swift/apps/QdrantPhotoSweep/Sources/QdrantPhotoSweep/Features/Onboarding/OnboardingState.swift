import Foundation

enum OnboardingFeature {
    struct UseCases: Sendable {
        let requestPhotoAccess: RequestPhotoAccessUseCase
    }
}

@Observable
@MainActor
final class OnboardingState {
    enum Step: Int, CaseIterable {
        case welcome = 0
        case permission = 1
        case scanPeriod = 2
    }

    enum PermissionStatus: Equatable, Sendable {
        case notRequested
        case requesting
        case granted
        case denied
    }

    enum Action {
        case didTapNext
        case didTapBack
        case didRequestPermission
        case permissionResult(PermissionStatus)
        case didSelectPreset(DatePreset)
        case didSetCustomRange(start: Date, end: Date)
        case didApplyToSettings
    }

    var currentStep: Step = .welcome
    var permissionStatus: PermissionStatus = .notRequested
    var selectedPreset: DatePreset? = .allTime
    var customRangeStart: Date = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    var customRangeEnd: Date = .now
    var isCustomRange: Bool = false
    private(set) var isComplete: Bool = false

    var canAdvance: Bool {
        switch currentStep {
        case .welcome:
            true
        case .permission:
            permissionStatus == .granted
        case .scanPeriod:
            true
        }
    }

    var isLastStep: Bool {
        currentStep == Step.allCases.last
    }

    func reduce(_ action: Action) {
        switch action {
        case .didTapNext:
            guard let nextIndex = Step(rawValue: currentStep.rawValue + 1) else { return }
            currentStep = nextIndex

        case .didTapBack:
            guard let prevIndex = Step(rawValue: currentStep.rawValue - 1) else { return }
            currentStep = prevIndex

        case .didRequestPermission:
            permissionStatus = .requesting

        case .permissionResult(let status):
            permissionStatus = status

        case .didSelectPreset(let preset):
            isCustomRange = false
            selectedPreset = preset

        case .didSetCustomRange(let start, let end):
            isCustomRange = true
            selectedPreset = nil
            customRangeStart = start
            customRangeEnd = end

        case .didApplyToSettings:
            isComplete = true
        }
    }

    func applyToSettings(_ settings: AppSettings) {
        settings.hasCompletedOnboarding = true
        settings.isCustomRange = isCustomRange
        if isCustomRange {
            settings.customRangeStart = customRangeStart
            settings.customRangeEnd = customRangeEnd
        } else {
            settings.scanPreset = selectedPreset
        }
        reduce(.didApplyToSettings)
    }
}

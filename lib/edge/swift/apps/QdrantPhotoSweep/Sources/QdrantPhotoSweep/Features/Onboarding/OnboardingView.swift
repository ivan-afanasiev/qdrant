import SwiftUI

struct OnboardingView: View {
    @State private var state = OnboardingState()
    let settings: AppSettings
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, QSpacing.md)

            Group {
                switch state.currentStep {
                case .welcome:
                    OnboardingWelcomeStep()
                case .permission:
                    OnboardingPermissionStep(state: state)
                case .scanPeriod:
                    OnboardingScanPeriodStep(state: state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomBar
                .padding(.horizontal, QSpacing.lg)
                .padding(.bottom, QSpacing.xl)
        }
        .animation(QAnimation.smooth, value: state.currentStep)
    }

    private var stepIndicator: some View {
        HStack(spacing: QSpacing.xs) {
            ForEach(OnboardingState.Step.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(step.rawValue <= state.currentStep.rawValue ? QColors.primary : QColors.surfaceMuted)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, QSpacing.xxxl)
    }

    private var bottomBar: some View {
        HStack(spacing: QSpacing.md) {
            if state.currentStep != .welcome {
                Button {
                    state.reduce(.didTapBack)
                } label: {
                    Text(L10n.onboardingBack)
                }
                .buttonStyle(.qSecondary)
                .frame(maxWidth: .infinity)
            }

            Button {
                handleForward()
            } label: {
                Text(state.isLastStep ? L10n.onboardingGetStarted : L10n.onboardingNext)
            }
            .buttonStyle(.qPrimary)
            .frame(maxWidth: .infinity)
            .disabled(!state.canAdvance)
        }
    }

    private func handleForward() {
        if state.isLastStep {
            state.applyToSettings(settings)
            onComplete()
        } else {
            state.reduce(.didTapNext)
        }
    }
}

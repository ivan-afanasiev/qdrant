import Photos
import SwiftUI

struct OnboardingPermissionStep: View {
    var state: OnboardingState
    let useCases: OnboardingFeature.UseCases

    var body: some View {
        VStack(spacing: QSpacing.xxl) {
            Spacer()

            statusIcon

            VStack(spacing: QSpacing.sm) {
                Text(L10n.onboardingPermissionTitle)
                    .font(QTypography.titleLarge)
                    .multilineTextAlignment(.center)

                Text(L10n.onboardingPermissionSubtitle)
                    .font(QTypography.bodyMedium)
                    .foregroundStyle(QColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            actionContent

            Spacer()
            Spacer()
        }
        .padding()
        .task {
            let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            switch current {
            case .authorized, .limited:
                state.reduce(.permissionResult(.granted))
            default:
                break
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state.permissionStatus {
        case .granted:
            Image(systemName: QIcons.successFill)
                .font(.system(size: 72))
                .foregroundStyle(QColors.success)
        default:
            Image(systemName: "photo.badge.plus.fill")
                .font(.system(size: 72))
                .foregroundStyle(QColors.primary)
        }
    }

    @ViewBuilder
    private var actionContent: some View {
        switch state.permissionStatus {
        case .notRequested:
            Button {
                requestAccess()
            } label: {
                Label(L10n.onboardingGrantAccess, systemImage: "lock.open.fill")
            }
            .buttonStyle(.qPrimary)
            .padding(.horizontal, QSpacing.xl)

        case .requesting:
            ProgressView()

        case .granted:
            Label(L10n.onboardingPermissionGranted, systemImage: QIcons.successFill)
                .font(QTypography.bodyLarge)
                .foregroundStyle(QColors.success)

        case .denied:
            VStack(spacing: QSpacing.md) {
                Text(L10n.onboardingPermissionDenied)
                    .font(QTypography.bodyMedium)
                    .foregroundStyle(QColors.error)
                    .multilineTextAlignment(.center)

                Button {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                } label: {
                    Label(L10n.openSettings, systemImage: QIcons.settings)
                }
                .buttonStyle(.qSecondary)
                .padding(.horizontal, QSpacing.xl)
            }
        }
    }

    private func requestAccess() {
        state.reduce(.didRequestPermission)
        Task {
            let result = try await useCases.requestPhotoAccess.execute(())
            state.reduce(.permissionResult(result))
        }
    }
}

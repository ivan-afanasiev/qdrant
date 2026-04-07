import SwiftUI

struct ReviewDeletingView: View {
    var body: some View {
        VStack(spacing: QSpacing.md) {
            Spacer()
            ProgressView()
            Text(L10n.deletingPhotos)
                .foregroundStyle(QColors.textTertiary)
            Spacer()
        }
    }
}

struct ReviewLoadingView: View {
    var body: some View {
        VStack(spacing: QSpacing.lg) {
            Spacer()
            ProgressView()
            Text(L10n.loadingGroup)
                .font(QTypography.bodyMedium)
                .foregroundStyle(QColors.textTertiary)
            Spacer()
        }
    }
}

struct ReviewWaitingView: View {
    var body: some View {
        VStack(spacing: QSpacing.lg) {
            Spacer()
            ProgressView()
            Text(L10n.waitingForMoreGroups)
                .font(QTypography.bodyMedium)
                .foregroundStyle(QColors.textTertiary)
            Spacer()
        }
    }
}

struct ReviewAllDoneView: View {
    let stats: ReviewStats
    let onFinished: () -> Void

    var body: some View {
        VStack(spacing: QSpacing.lg) {
            Spacer()
            QStatusIcon(QIcons.successFill, size: QSize.iconXLarge, color: QColors.success)

            Text(L10n.allDone)
                .font(QTypography.titleMedium)

            VStack(spacing: QSpacing.xs) {
                statRow(label: L10n.groupsReviewed, value: "\(stats.groupsReviewed)")
                statRow(label: L10n.photosCleaned, value: "\(stats.photosDeleted)")
            }
            .padding()
            .background(QColors.surfaceSubtle)
            .clipShape(RoundedRectangle(cornerRadius: QRadius.md))

            Button(L10n.finish) {
                onFinished()
            }
            .buttonStyle(.qPrimary)
            Spacer()
        }
        .padding()
    }

    private func statRow(label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(QColors.textSecondary)
            Spacer()
            Text(value)
                .font(QTypography.numericMedium)
        }
    }
}

struct ReviewFailedView: View {
    let error: AppError
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: QSpacing.md) {
            Spacer()
            QStatusIcon(QIcons.warningFill, size: QSize.iconLarge, color: QColors.error)
            Text(L10n.error)
                .font(QTypography.titleMedium)
            Text(error.localizedDescription)
                .font(QTypography.bodyMedium)
                .foregroundStyle(QColors.textTertiary)
                .multilineTextAlignment(.center)

            Button(L10n.done) {
                onDismiss()
            }
            .buttonStyle(.qPrimary)
            Spacer()
        }
        .padding()
    }
}

struct ReviewConfirmButton: View {
    let group: DuplicateGroup?
    let keptIds: Set<String>
    let onDelete: () -> Void
    let onSkip: () -> Void

    var body: some View {
        if let group {
            let deleteCount = group.photos.count - keptIds.count

            if deleteCount > 0 {
                Button {
                    onDelete()
                } label: {
                    Label(L10n.deleteNPhotos(deleteCount), systemImage: QIcons.delete)
                }
                .buttonStyle(.qDestructive)
                .padding(.horizontal)
            } else {
                Button {
                    onSkip()
                } label: {
                    Text(L10n.skip)
                }
                .buttonStyle(.qGhost)
                .padding(.horizontal)
            }
        }
    }
}

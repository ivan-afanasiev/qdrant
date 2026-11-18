#if os(iOS) && DEBUG
import SwiftUI
import SweepDesignSystem

// Design options for the review action controls, for choosing a layout that works with long
// localized labels (German, Russian) and with widths from a narrow folded iPhone Duo to its
// wide unfolded screen. Preview-only: the chosen option replaces `ReviewControls`, and this
// file is removed afterwards.

/// Option A — primary on its own row: a full-width destructive button, with Skip and Keep All
/// sharing a second row. Labels get the full or half width, so they rarely wrap.
private struct ReviewControlsOptionA: View {
    var body: some View {
        GlassEffectContainer(spacing: QSpacing.sm) {
            VStack(spacing: QSpacing.sm) {
                Button(role: .destructive) {} label: {
                    Text(L10n.deleteAll).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(QColors.destructive)
                HStack(spacing: QSpacing.sm) {
                    Button {} label: { Text(L10n.skip).frame(maxWidth: .infinity) }
                        .buttonStyle(.glass)
                    Button {} label: { Text(L10n.keepAll).frame(maxWidth: .infinity) }
                        .buttonStyle(.glass)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
        .controlSize(.large)
    }
}

/// Option B — adaptive: one row while all labels fit on one line, otherwise Option A's
/// two-row layout. Wide screens (unfolded Duo) keep a single row.
private struct ReviewControlsOptionB: View {
    var body: some View {
        GlassEffectContainer(spacing: QSpacing.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: QSpacing.sm) {
                    secondary(L10n.skip)
                    secondary(L10n.keepAll)
                    primary
                }
                VStack(spacing: QSpacing.sm) {
                    primary
                    HStack(spacing: QSpacing.sm) {
                        secondary(L10n.skip)
                        secondary(L10n.keepAll)
                    }
                }
            }
            .lineLimit(1)
        }
        .controlSize(.large)
    }

    private var primary: some View {
        Button(role: .destructive) {} label: {
            Text(L10n.deleteAll).fixedSize().frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(QColors.destructive)
    }

    private func secondary(_ title: LocalizedStringResource) -> some View {
        Button {} label: { Text(title).fixedSize().frame(maxWidth: .infinity) }
            .buttonStyle(.glass)
    }
}

/// Option C — icon buttons for the secondary actions: Skip and Keep All become round glass
/// buttons with SF Symbols (labels for VoiceOver), leaving the row's width to the
/// destructive action's text.
private struct ReviewControlsOptionC: View {
    var body: some View {
        GlassEffectContainer(spacing: QSpacing.sm) {
            HStack(spacing: QSpacing.sm) {
                iconButton("forward.fill", label: L10n.skip)
                iconButton(QIcons.successFill, label: L10n.keepAll)
                Button(role: .destructive) {} label: {
                    Label { Text(L10n.deleteAll) } icon: { Image(systemName: QIcons.trashFill) }
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(QColors.destructive)
            }
        }
        .controlSize(.large)
    }

    private func iconButton(_ symbol: String, label: LocalizedStringResource) -> some View {
        Button {} label: { Image(systemName: symbol).font(.title3) }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text(label))
    }
}

/// Option D — vertical label buttons: icon above a short caption, three equal columns like a
/// toolbar. Captions may take two lines without changing the button height.
private struct ReviewControlsOptionD: View {
    var body: some View {
        GlassEffectContainer(spacing: QSpacing.sm) {
            HStack(spacing: QSpacing.sm) {
                tile("forward.fill", L10n.skip, prominent: false)
                tile(QIcons.successFill, L10n.keepAll, prominent: false)
                tile(QIcons.trashFill, L10n.deleteAll, prominent: true)
            }
        }
    }

    @ViewBuilder
    private func tile(_ symbol: String, _ title: LocalizedStringResource, prominent: Bool) -> some View {
        let label = VStack(spacing: QSpacing.xxs) {
            Image(systemName: symbol).font(.title3).frame(height: 24)
            Text(title)
                .font(QTypography.captionSmall)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        if prominent {
            Button(role: .destructive) {} label: { label }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: QRadius.lg))
                .tint(QColors.destructive)
        } else {
            Button {} label: { label }
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle(radius: QRadius.lg))
        }
    }
}

/// All options stacked for one locale and width, as they would sit over the photos.
private struct ReviewControlsGallery: View {
    let locale: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QSpacing.lg) {
                option("A — primary row + two halves") { ReviewControlsOptionA() }
                option("B — one row if it fits, else A") { ReviewControlsOptionB() }
                option("C — icon buttons + labeled delete") { ReviewControlsOptionC() }
                option("D — icon tiles with captions") { ReviewControlsOptionD() }
            }
            .padding()
        }
        .background(Color.gray.opacity(0.35))
        .tint(QColors.primary)
        .environment(\.locale, Locale(identifier: locale))
    }

    private func option(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: QSpacing.xs) {
            Text(verbatim: title).font(.caption.bold()).foregroundStyle(.secondary)
            content()
        }
    }
}

#Preview("Review controls · German · iPhone", traits: .fixedLayout(width: 393, height: 760)) {
    ReviewControlsGallery(locale: "de")
}

#Preview("Review controls · Russian · iPhone", traits: .fixedLayout(width: 393, height: 760)) {
    ReviewControlsGallery(locale: "ru")
}

#Preview("Review controls · German · narrow (folded Duo)", traits: .fixedLayout(width: 320, height: 760)) {
    ReviewControlsGallery(locale: "de")
}

#Preview("Review controls · Russian · wide (unfolded Duo)", traits: .fixedLayout(width: 700, height: 760)) {
    ReviewControlsGallery(locale: "ru")
}
#endif

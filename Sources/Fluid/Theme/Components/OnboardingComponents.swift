import SwiftUI

struct FluidOnboardingLandingHero<Actions: View>: View {
    @Environment(\.theme) private var theme

    let eyebrow: String
    let title: String
    let statement: String
    let systemImage: String
    let actions: Actions

    init(
        eyebrow: String,
        title: String,
        statement: String,
        systemImage: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.statement = statement
        self.systemImage = systemImage
        self.actions = actions()
    }

    var body: some View {
        let landing = self.theme.metrics.onboardingSurface.landing
        let shape = RoundedRectangle(cornerRadius: landing.heroCornerRadius, style: .continuous)

        HStack(alignment: .center, spacing: self.theme.metrics.spacing.xl) {
            ZStack {
                Circle()
                    .fill(self.theme.palette.accent.opacity(0.14))
                Image(systemName: self.systemImage)
                    .font(.system(size: landing.heroIconSize, weight: .regular))
                    .foregroundStyle(self.theme.palette.accent)
            }
            .frame(width: landing.heroIconFrame, height: landing.heroIconFrame)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: self.theme.metrics.spacing.md) {
                Text(self.eyebrow)
                    .font(self.theme.typography.captionStrong)
                    .foregroundStyle(self.theme.palette.accent)
                    .textCase(.uppercase)

                Text(self.title)
                    .font(self.theme.typography.displayTitle)
                    .foregroundStyle(self.theme.palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(self.statement)
                    .font(self.theme.typography.statement)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                self.actions
                    .padding(.top, self.theme.metrics.spacing.sm)
            }
        }
        .padding(landing.heroPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            shape
                .fill(self.theme.palette.elevatedCardBackground.opacity(0.72))
                .overlay(shape.stroke(self.theme.palette.cardBorder.opacity(0.26), lineWidth: 1))
        )
    }
}

struct FluidOnboardingValueTile: View {
    @Environment(\.theme) private var theme

    let systemImage: String
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: self.theme.metrics.spacing.sm) {
            Image(systemName: self.systemImage)
                .font(self.theme.typography.titleIcon)
                .foregroundStyle(self.theme.palette.accent)
                .accessibilityHidden(true)

            Text(self.title)
                .font(self.theme.typography.bodyStrong)
                .foregroundStyle(self.theme.palette.primaryText)

            Text(self.description)
                .font(self.theme.typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .fluidOnboardingSelectableSurface(isSelected: false)
    }
}

struct FluidOnboardingChecklistPanel<Rows: View>: View {
    @Environment(\.theme) private var theme

    let title: String
    let rows: Rows

    init(title: String, @ViewBuilder rows: () -> Rows) {
        self.title = title
        self.rows = rows()
    }

    var body: some View {
        ThemedCard(style: .subtle) {
            VStack(alignment: .leading, spacing: self.theme.metrics.spacing.md) {
                Text(self.title)
                    .font(self.theme.typography.sectionTitle)
                    .foregroundStyle(self.theme.palette.primaryText)

                self.rows
            }
            .padding(16)
        }
    }
}

struct FluidOnboardingChecklistRow: View {
    @Environment(\.theme) private var theme

    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: self.theme.metrics.spacing.sm) {
            Image(systemName: self.systemImage)
                .font(self.theme.typography.captionStrong)
                .foregroundStyle(self.theme.palette.accent)
                .frame(width: 18)
                .accessibilityHidden(true)

            Text(self.text)
                .font(self.theme.typography.bodySmall)
                .foregroundStyle(.secondary)
        }
    }
}

private struct OnboardingSelectableSurfaceModifier: ViewModifier {
    @Environment(\.theme) private var theme
    let isSelected: Bool
    let cornerRadius: CGFloat?
    let padding: CGFloat?
    let selectedBorderOpacity: Double?

    func body(content: Content) -> some View {
        let surface = self.theme.metrics.onboardingSurface
        let radius = self.cornerRadius ?? surface.optionCornerRadius
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        content
            .padding(self.padding ?? surface.optionPadding)
            .background(
                shape
                    .fill(self.theme.palette.cardBackground.opacity(
                        self.isSelected ? surface.selectedFillOpacity : surface.normalFillOpacity
                    ))
                    .overlay(
                        shape.stroke(
                            self.isSelected
                                ? self.theme.palette.accent.opacity(self.selectedBorderOpacity ?? surface.selectedBorderOpacity)
                                : self.theme.palette.cardBorder.opacity(surface.normalBorderOpacity),
                            lineWidth: 1
                        )
                    )
            )
            .contentShape(shape)
    }
}

private struct OnboardingEditorSurfaceModifier: ViewModifier {
    @Environment(\.theme) private var theme
    let cornerRadius: CGFloat?

    func body(content: Content) -> some View {
        let surface = self.theme.metrics.onboardingSurface
        let radius = self.cornerRadius ?? surface.editorCornerRadius
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        content
            .padding(surface.editorPadding)
            .background(
                shape
                    .fill(self.theme.palette.cardBackground)
                    .overlay(
                        shape.stroke(self.theme.palette.cardBorder.opacity(surface.editorBorderOpacity), lineWidth: 1)
                    )
            )
    }
}

private struct OnboardingProminentButtonModifier: ViewModifier {
    @Environment(\.theme) private var theme
    let controlSize: ControlSize?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let controlSize {
            content
                .buttonStyle(.borderedProminent)
                .controlSize(controlSize)
                .tint(self.theme.palette.accent)
        } else {
            content
                .buttonStyle(.borderedProminent)
                .tint(self.theme.palette.accent)
        }
    }
}

private struct OnboardingSecondaryButtonModifier: ViewModifier {
    let controlSize: ControlSize?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let controlSize {
            content
                .buttonStyle(.bordered)
                .controlSize(controlSize)
        } else {
            content
                .buttonStyle(.bordered)
        }
    }
}

extension View {
    func fluidOnboardingSelectableSurface(
        isSelected: Bool,
        cornerRadius: CGFloat? = nil,
        padding: CGFloat? = nil,
        selectedBorderOpacity: Double? = nil
    ) -> some View {
        self.modifier(OnboardingSelectableSurfaceModifier(
            isSelected: isSelected,
            cornerRadius: cornerRadius,
            padding: padding,
            selectedBorderOpacity: selectedBorderOpacity
        ))
    }

    func fluidOnboardingEditorSurface(cornerRadius: CGFloat? = nil) -> some View {
        self.modifier(OnboardingEditorSurfaceModifier(cornerRadius: cornerRadius))
    }

    func fluidOnboardingProminentButton(controlSize: ControlSize? = nil) -> some View {
        self.modifier(OnboardingProminentButtonModifier(controlSize: controlSize))
    }

    func fluidOnboardingSecondaryButton(controlSize: ControlSize? = nil) -> some View {
        self.modifier(OnboardingSecondaryButtonModifier(controlSize: controlSize))
    }
}

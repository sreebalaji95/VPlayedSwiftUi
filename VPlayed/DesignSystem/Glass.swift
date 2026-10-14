import SwiftUI

// Liquid Glass for every tappable element and floating chrome. Views use these helpers instead of
// checking availability themselves: iOS 26 gets real glass, iOS 17–18 get the closest standard
// styles.

enum GlassProminence {
    /// Neutral glass, for most controls.
    case regular
    /// Tinted glass. Set the colour with `.tint(_:)` on the button.
    case prominent
    /// The primary action: tinted glass in `Theme.Palette.primary` with an `onPrimary` label.
    case primary
}

extension View {
    /// Liquid Glass button style for controls (calls to action, icon buttons, retry, skip…).
    @ViewBuilder
    func glassButtonStyle(_ prominence: GlassProminence = .regular) -> some View {
        switch prominence {
        case .regular: systemGlassButtonStyle(prominent: false)
        case .prominent: systemGlassButtonStyle(prominent: true)
        case .primary: buttonStyle(PrimaryGlassButtonStyle())
        }
    }

    @ViewBuilder
    private func systemGlassButtonStyle(prominent: Bool) -> some View {
        if #available(iOS 26, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }

    /// Soft scroll-edge effect under the glass top bar, so content blurs gently into the bar
    /// instead of meeting it at a hard line.
    @ViewBuilder
    func softTopScrollEdge() -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }

    /// Non-interactive glass behind floating chrome such as badges.
    @ViewBuilder
    func glassSurface(in shape: some Shape) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }
}

/// The primary action's colours, in one place for every brand. The label is coloured on the
/// label itself (spinners included), because the prominent system styles colour it otherwise.
private struct PrimaryGlassButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
                .foregroundStyle(Theme.Palette.onPrimary)
                .tint(Theme.Palette.onPrimary)
        }
        .glassButtonStyle(.prominent)
        .tint(Theme.Palette.primary)
    }
}

/// Liquid Glass for tappable content (cards, rail titles, list rows): the label sits on
/// interactive glass in `shape`, which also gives the system press response.
struct GlassCardButtonStyle<S: Shape>: ButtonStyle {
    let shape: S
    var padding: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        GlassCard(shape: shape, padding: padding, isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

private struct GlassCard<S: Shape, Label: View>: View {
    let shape: S
    let padding: CGFloat
    let isPressed: Bool
    @ViewBuilder let label: Label

    var body: some View {
        let padded = label
            .padding(padding)
            .contentShape(shape)
        if #available(iOS 26, *) {
            padded.glassEffect(.regular.interactive(), in: shape)
        } else {
            padded
                .background(.ultraThinMaterial, in: shape)
                .scaleEffect(isPressed ? 0.97 : 1)
                .opacity(isPressed ? 0.85 : 1)
                .animation(.easeOut(duration: 0.16), value: isPressed)
        }
    }
}

/// Groups nearby glass shapes so they blend and morph together (iOS 26).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat? = nil
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

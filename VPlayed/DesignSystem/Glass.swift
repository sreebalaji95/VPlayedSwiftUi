import SwiftUI

// Liquid Glass for every tappable element and floating chrome. Views use these helpers instead of
// checking availability themselves: iOS / macOS 26 get real glass, iOS 17–18 get the closest
// standard styles, and visionOS, whose standard buttons are already glass, uses those.

enum GlassProminence {
    /// Neutral glass, for most controls.
    case regular
    /// Tinted glass for the primary action. Set the colour with `.tint(_:)` on the button.
    case prominent
}

extension View {
    /// Liquid Glass button style for controls (calls to action, icon buttons, retry, skip…).
    @ViewBuilder
    func glassButtonStyle(_ prominence: GlassProminence = .regular) -> some View {
        #if os(visionOS)
        switch prominence {
        case .regular: buttonStyle(.bordered)
        case .prominent: buttonStyle(.borderedProminent)
        }
        #else
        if #available(iOS 26, macOS 26, *) {
            switch prominence {
            case .regular: buttonStyle(.glass)
            case .prominent: buttonStyle(.glassProminent)
            }
        } else {
            switch prominence {
            case .regular: buttonStyle(.bordered)
            case .prominent: buttonStyle(.borderedProminent)
            }
        }
        #endif
    }

    /// Soft scroll-edge effect under the glass top bar, so content blurs gently into the bar
    /// instead of meeting it at a hard line.
    @ViewBuilder
    func softTopScrollEdge() -> some View {
        #if os(visionOS)
        self
        #else
        if #available(iOS 26, macOS 26, *) {
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
        #endif
    }

    /// Non-interactive glass behind floating chrome such as badges.
    @ViewBuilder
    func glassSurface(in shape: some Shape) -> some View {
        #if os(visionOS)
        background(.ultraThinMaterial, in: shape)
        #else
        if #available(iOS 26, macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
        #endif
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
        #if os(visionOS)
        padded
            .background(.regularMaterial, in: shape)
            .hoverEffect()
            .scaleEffect(isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.16), value: isPressed)
        #else
        if #available(iOS 26, macOS 26, *) {
            padded.glassEffect(.regular.interactive(), in: shape)
        } else {
            padded
                .background(.ultraThinMaterial, in: shape)
                .scaleEffect(isPressed ? 0.97 : 1)
                .opacity(isPressed ? 0.85 : 1)
                .animation(.easeOut(duration: 0.16), value: isPressed)
        }
        #endif
    }
}

/// Groups nearby glass shapes so they blend and morph together (iOS / macOS 26).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat? = nil
    @ViewBuilder let content: Content

    var body: some View {
        #if os(visionOS)
        content
        #else
        if #available(iOS 26, macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #endif
    }
}

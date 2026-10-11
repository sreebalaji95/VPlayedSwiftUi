import SwiftUI

extension View {
    /// Tracking for display text, applied only when the UI language uses Latin script. Spaced-out
    /// labels are a Latin-capitals device: tracking pulls apart joined Arabic letters and Tamil
    /// conjuncts.
    func letterSpacing(_ value: CGFloat) -> some View {
        modifier(LetterSpacing(value: value))
    }
}

private struct LetterSpacing: ViewModifier {
    let value: CGFloat

    @Environment(\.locale) private var locale

    func body(content: Content) -> some View {
        content.tracking(usesLatinScript ? value : 0)
    }

    private var usesLatinScript: Bool {
        // The maximal identifier fills in the script, e.g. "ta" → "ta-Taml-IN".
        Locale.Language(identifier: locale.language.maximalIdentifier).script == .latin
    }
}

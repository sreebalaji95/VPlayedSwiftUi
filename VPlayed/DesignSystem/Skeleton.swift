import SwiftUI

/// A placeholder bar or tile for skeleton loaders. Without a width it fills the offered width.
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    let height: CGFloat
    var cornerRadius: CGFloat = Theme.Radius.badge

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Theme.Palette.raised)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

extension View {
    /// Sweeps a soft highlight across the view's opaque shapes, the usual skeleton shimmer.
    /// Mirrors in right-to-left languages and holds still when Reduce Motion is on.
    func shimmering() -> some View {
        modifier(Shimmer())
    }
}

private struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        let band = proxy.size.width * 0.6
                        LinearGradient(
                            colors: [.clear, Theme.Palette.shimmer, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: band)
                        .offset(x: -band + phase * (proxy.size.width + band))
                    }
                    .mask { content }
                    .flipsForRightToLeftLayoutDirection(true)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

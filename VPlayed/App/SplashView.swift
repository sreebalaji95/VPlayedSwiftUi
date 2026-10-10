import SwiftUI

/// Intro shown on cold launch (prototype "VPlayed Splash"): the wordmark centered on the brand
/// background with a red glow, a loading bar and tagline, then a fade into Home after 3s.
///
/// The logo sits exactly where the system launch screen draws `SplashLogo` (centered on the full
/// screen at its natural 288pt size), so the handoff from the launch screen has no jump.
struct SplashView: View {
    let onFinish: () -> Void

    static let duration: Duration = .seconds(3)
    private static let exitDuration = 0.48
    private static let logoSize = CGSize(width: 288, height: 75.43)

    @State private var glowVisible = false
    @State private var detailsVisible = false
    @State private var barProgress: CGFloat = 0
    @State private var isLeaving = false
    @State private var didFinish = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.Palette.background

            glow

            Image(.splashLogo)
                .accessibilityLabel("VPlayed")
                .overlay(alignment: .top) {
                    VStack(spacing: 28) {
                        loadingBar
                        Text("Stream the experience")
                            .font(.system(size: 13))
                            .tracking(3.6)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.white.opacity(0.62))
                            .fixedSize()
                    }
                    .opacity(detailsVisible ? 1 : 0)
                    .offset(y: Self.logoSize.height + 28)
                }
                .scaleEffect(isLeaving ? 1.04 : 1)
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) { skipButton }
        .opacity(isLeaving ? 0 : 1)
        .task { await run() }
    }

    private var glow: some View {
        GeometryReader { proxy in
            let diameter = min(760, min(proxy.size.width, proxy.size.height) * 1.6)
            RadialGradient(
                stops: [
                    .init(color: Theme.Palette.brand.opacity(0.22), location: 0),
                    .init(color: Theme.Palette.brand.opacity(0.06), location: 0.42),
                    .init(color: .clear, location: 0.70),
                ],
                center: .center,
                startRadius: 0,
                endRadius: diameter / 2
            )
            .frame(width: diameter, height: diameter)
            .scaleEffect(glowVisible ? 1 : 0.6)
            .opacity(glowVisible ? 1 : 0)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var loadingBar: some View {
        Capsule()
            .fill(Color.white.opacity(0.14))
            .frame(width: 180, height: 3)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: [Theme.Palette.brand, Theme.Palette.accent], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 180 * barProgress, height: 3)
            }
            .accessibilityHidden(true)
    }

    private var skipButton: some View {
        Button {
            Task { await finish() }
        } label: {
            HStack(spacing: 6) {
                Text("Skip intro")
                Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold))
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.72))
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.95))
        .opacity(detailsVisible ? 1 : 0)
        .padding(.bottom, 16)
    }

    private func run() async {
        if reduceMotion {
            glowVisible = true
            detailsVisible = true
            barProgress = 1
        } else {
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 2.6)) { glowVisible = true }
            withAnimation(.easeOut(duration: 0.6).delay(1.0)) { detailsVisible = true }
            withAnimation(.timingCurve(0.5, 0, 0.2, 1, duration: 1.7).delay(1.0)) { barProgress = 1 }
        }
        do {
            try await Task.sleep(for: Self.duration)
        } catch {
            return
        }
        await finish()
    }

    private func finish() async {
        guard !didFinish else { return }
        didFinish = true
        withAnimation(.timingCurve(0.4, 0, 1, 1, duration: Self.exitDuration)) { isLeaving = true }
        try? await Task.sleep(for: .seconds(Self.exitDuration))
        onFinish()
    }
}

#Preview {
    SplashView {}
        .preferredColorScheme(.dark)
}

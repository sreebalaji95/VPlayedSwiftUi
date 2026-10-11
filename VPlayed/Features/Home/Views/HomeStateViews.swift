import SwiftUI

/// Skeleton shown during the first load: a hero block and two rails of card placeholders.
struct HomeLoadingView: View {
    @State private var dimmed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle()
                    .fill(Theme.Palette.surface)
                    .containerRelativeFrame(.vertical) { height, _ in min(max(height * 0.72, 460), 600) }
                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 14) {
                        RoundedRectangle(cornerRadius: Theme.Radius.badge)
                            .frame(width: 150, height: 18)
                        // The row is wider than a phone; a disabled scroll view takes exactly the
                        // offered width, so it can't widen the screen.
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(0..<3, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: Theme.Radius.control)
                                        .frame(width: 158, height: 89)
                                }
                            }
                        }
                        .scrollDisabled(true)
                        .scrollIndicators(.hidden)
                    }
                    .foregroundStyle(Theme.Palette.raised)
                    .padding(.leading, Theme.Spacing.gutter)
                    .padding(.top, 26)
                }
            }
            .opacity(dimmed ? 0.5 : 1)
        }
        .scrollDisabled(true)
        .scrollIndicators(.hidden)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dimmed = true }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading home")
    }
}

/// Centered message with an icon tile and one call to action (empty feed / load failure).
struct HomeMessageView: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: String
    let actionTitle: LocalizedStringKey
    let action: () async -> Void

    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 32))
                .foregroundStyle(Theme.Palette.textPrimary)
                .frame(width: 76, height: 76)
                .background(Theme.Palette.raised, in: .rect(cornerRadius: Theme.Radius.popover))
                .padding(.bottom, 20)
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            Button {
                isWorking = true
                Task {
                    await action()
                    isWorking = false
                }
            } label: {
                ZStack {
                    Text(actionTitle).opacity(isWorking ? 0 : 1)
                    if isWorking { ProgressView().tint(.white) }
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
            }
            .glassButtonStyle(.prominent)
            .tint(Theme.Palette.brand)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(isWorking)
            .padding(.top, 24)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Feed footer while more rails page in, or a retry row if the next page failed.
struct LoadMoreFooter: View {
    let failed: Bool
    let retry: () async -> Void

    var body: some View {
        Group {
            if failed {
                Button {
                    Task { await retry() }
                } label: {
                    Label("Couldn't load more. Tap to retry.", systemImage: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                .glassButtonStyle()
                .buttonBorderShape(.capsule)
                .frame(maxWidth: .infinity)
            } else {
                ProgressView()
                    .tint(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityLabel("Loading more")
            }
        }
        .padding(.vertical, 16)
    }
}

/// Short-lived message pill (prototype toast).
struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.Palette.textPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(Theme.Palette.raised, in: .capsule)
            .overlay { Capsule().strokeBorder(Theme.Palette.line2, lineWidth: 1) }
            .padding(.horizontal, 24)
    }
}

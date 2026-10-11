import SwiftUI

/// "Live now" card: 300pt wide, 16:9 artwork with a LIVE/UPCOMING badge, plus a channel footer.
struct LiveNowCard: View {
    let item: LiveItem
    let onWatch: () -> Void
    let onRemind: () -> Void

    private let width: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onWatch) {
                RemoteImage(url: item.imageURL)
                    .frame(width: width, height: width * 9 / 16)
                    .background(Theme.Palette.raised)
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: Theme.Palette.scrim.opacity(0.94), location: 0.03),
                                .init(color: Theme.Palette.scrim.opacity(0.25), location: 0.40),
                                .init(color: .clear, location: 0.64),
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    }
                    .overlay(alignment: .topLeading) { badge.padding(14) }
                    .overlay(alignment: .bottomLeading) { caption }
                    // Badge and caption sit on artwork, so they stay dark in both themes.
                    .environment(\.colorScheme, .dark)
            }
            .buttonStyle(PressableButtonStyle(scale: 0.99))

            footer
        }
        .frame(width: width)
        .background(Theme.Palette.surface)
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Palette.line, lineWidth: 1)
        }
    }

    private var badge: some View {
        HStack(spacing: 6) {
            if item.isLive {
                PulsingDot(color: Theme.Palette.onPrimary, size: 7)
            }
            item.isLive ? Text("LIVE") : Text("UPCOMING")
        }
        .font(.system(size: 11, weight: .bold))
        .letterSpacing(0.6)
        // LIVE sits on the brand colour; UPCOMING on a dark scrim.
        .foregroundStyle(item.isLive ? Theme.Palette.onPrimary : .white)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            item.isLive ? AnyShapeStyle(Theme.Palette.brand) : AnyShapeStyle(Theme.Palette.scrim.opacity(0.72)),
            in: .rect(cornerRadius: Theme.Radius.control)
        )
        .overlay {
            if !item.isLive {
                RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(Theme.Palette.line2, lineWidth: 1)
            }
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            if let startsAt = item.startsAt {
                Label {
                    Text(startsAt, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                } icon: {
                    Image(systemName: "clock").font(.system(size: 11))
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let channel = item.channelName {
                Text(Self.initials(of: channel))
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.Palette.background)
                    .frame(width: 32, height: 32)
                    .background(Theme.Palette.textPrimary, in: .rect(cornerRadius: Theme.Radius.control))
                Text(channel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Group {
                if item.isLive {
                    Button(action: onWatch) {
                        Label("Watch Live", systemImage: "play.fill")
                            .foregroundStyle(Theme.Palette.onPrimary)
                    }
                    .glassButtonStyle(.prominent)
                    .tint(Theme.Palette.brand)
                } else {
                    Button(action: onRemind) {
                        Label("Set reminder", systemImage: "bell")
                    }
                    .glassButtonStyle()
                }
            }
            .font(.system(size: 14, weight: .bold))
            .lineLimit(1)
            .buttonBorderShape(.capsule)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .overlay(alignment: .top) { Theme.Palette.line.frame(height: 1) }
    }

    private static func initials(of name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.count > 1 ? words.compactMap(\.first) : Array(name.prefix(2))
        return String(letters).uppercased()
    }
}

struct PulsingDot: View {
    let color: Color
    var size: CGFloat = 7

    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(pulsing ? 0.35 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulsing = true }
            }
    }
}

/// Channel card (Live TV style): 212pt wide, white circular logo, name and follower count.
struct ChannelCard: View {
    let item: ChannelItem

    var body: some View {
        VStack(spacing: 0) {
            RemoteImage(url: item.logoURL, contentMode: .fit)
                .padding(16)
                .frame(width: 104, height: 104)
                .background(.white, in: .circle)
                .clipShape(.circle)
                .overlay { Circle().strokeBorder(Theme.Palette.line, lineWidth: 1) }
                .padding(.bottom, 16)
            Text(item.name)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
            if let followers = item.followCount {
                // Plural forms come from the catalog (Arabic has six); the count reads compactly, e.g. 1.2K.
                Text("\(followers.formatted(.number.notation(.compactName))) followers \(followers)")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .padding(.top, 4)
            }
        }
        .padding(EdgeInsets(top: 28, leading: 20, bottom: 22, trailing: 20))
        .frame(width: 212)
        .background(Theme.Palette.surface, in: .rect(cornerRadius: Theme.Radius.panel))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.panel).strokeBorder(Theme.Palette.line, lineWidth: 1)
        }
    }
}

/// Bulk-purchase promotion card: tinted panel, icon tile, label, name, description, price, CTA.
struct BulkPlanCard: View {
    let plan: BulkPlan
    let onExplore: () -> Void

    private var tint: Color { Color(hexString: plan.accentHex) ?? Color(hex: 0x3B82F6) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "bag.fill")
                .font(.system(size: 26))
                .foregroundStyle(Theme.Palette.onLight)
                .frame(width: 60, height: 60)
                .background(tint, in: .rect(cornerRadius: Theme.Radius.panel))

            VStack(alignment: .leading, spacing: 6) {
                if let label = plan.label {
                    Text(label.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .letterSpacing(1.5)
                        .foregroundStyle(tint)
                        .lineLimit(1)
                }
                Text(plan.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(2)
                if let summary = plan.summary {
                    Text(summary)
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(2)
                }
            }

            if let price = plan.price, let amount = price.formatted {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(amount)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    if let saving = price.discountedPercentage, saving > 0 {
                        Text("· Save up to \(Int(saving))%")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
            }

            Button(action: onExplore) {
                Text("Explore bundles")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .glassButtonStyle()
            .buttonBorderShape(.capsule)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            LinearGradient(
                colors: [tint.opacity(0.32), Theme.Palette.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(.rect(cornerRadius: Theme.Radius.popover))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.popover).strokeBorder(tint.opacity(0.35), lineWidth: 1)
        }
    }
}

/// Music card: vinyl record with the album art as its label, centred title and artist.
struct AudioCard: View {
    let item: AudioItem

    private let size: CGFloat = 140

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(
                    RadialGradient(
                        colors: [Color(hex: 0x2A2B30), Color(hex: 0x0E0E10), Color(hex: 0x1C1D21), Color(hex: 0x09090A)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.47
                    )
                )
                ForEach([0.62, 0.74, 0.86], id: \.self) { ratio in
                    Circle()
                        .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                        .frame(width: size * 0.94 * ratio, height: size * 0.94 * ratio)
                }
                RemoteImage(url: item.imageURL)
                    .frame(width: size * 0.46, height: size * 0.46)
                    .clipShape(.circle)
                Circle()
                    .fill(Theme.Palette.background)
                    .frame(width: 8, height: 8)
            }
            .frame(width: size * 0.94, height: size * 0.94)
            .frame(width: size, height: size)

            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, 10)
            if let artist = item.artistName {
                Label {
                    Text(artist)
                } icon: {
                    Image(systemName: "music.note").foregroundStyle(Theme.Palette.accent)
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.textTertiary)
                .lineLimit(1)
                .padding(.top, 3)
            }
        }
        .frame(width: size)
    }
}

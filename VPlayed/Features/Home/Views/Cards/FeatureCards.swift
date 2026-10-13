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
        .font(Theme.Typography.badge)
        .letterSpacing(0.6)
        // LIVE sits on the brand colour; UPCOMING on a dark scrim.
        .foregroundStyle(item.isLive ? Theme.Palette.onPrimary : .white)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            item.isLive ? AnyShapeStyle(Theme.Palette.primary) : AnyShapeStyle(Theme.Palette.scrim.opacity(0.72)),
            in: .rect(cornerRadius: Theme.Radius.control)
        )
        .overlay {
            if !item.isLive {
                RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(Theme.Palette.lineStrong, lineWidth: 1)
            }
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(.white)
                .lineLimit(1)
            if let startsAt = item.startsAt {
                Label {
                    Text(startsAt, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                } icon: {
                    Image(systemName: "clock").font(.system(size: 11))
                }
                .font(Theme.Typography.caption)
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
                    .font(Theme.Typography.monogram)
                    .foregroundStyle(Theme.Palette.background)
                    .frame(width: 32, height: 32)
                    .background(Theme.Palette.textPrimary, in: .rect(cornerRadius: Theme.Radius.control))
                Text(channel)
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Group {
                if item.isLive {
                    Button(action: onWatch) {
                        Label("Watch Live", systemImage: "play.fill")
                    }
                    .glassButtonStyle(.primary)
                } else {
                    Button(action: onRemind) {
                        Label("Set reminder", systemImage: "bell")
                    }
                    .glassButtonStyle()
                }
            }
            .font(Theme.Typography.button)
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

/// Channel card: 300pt wide plate tinted by the channel's brand colour, with a white logo well, name,
/// followers pill and a full-width Follow button. The plate is dark in both
/// themes, so its text is fixed white.
struct ChannelCard: View {
    let item: ChannelItem
    let isFollowing: Bool
    let followers: Int?
    let isUpdating: Bool
    let onOpen: () -> Void
    let onFollow: () -> Void
    /// Called once the user confirms leaving a channel they follow.
    let onUnfollow: () -> Void

    @State private var confirmsUnfollow = false

    private var brand: Color { Color(hexString: item.brandHex) ?? Theme.Palette.primary }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 0) {
                    logo
                    Text(item.name)
                        .font(Theme.Typography.title)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.top, 16)
                    if let followers {
                        // Plural forms come from the catalog (Arabic has six); the count reads compactly, e.g. 1.2K.
                        Text("\(followers.formatted(.number.notation(.compactName))) followers \(followers)")
                            .font(Theme.Typography.captionMedium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 26)
                            .background(Theme.Palette.scrim.opacity(0.35), in: .capsule)
                            .padding(.top, 10)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .contentShape(.rect)
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.bottom, 16)

            Button {
                if isFollowing { confirmsUnfollow = true } else { onFollow() }
            } label: {
                // Followed channels get a solid white button, as in the prototype.
                Group {
                    if isFollowing { Text("Following") } else { Text("Follow") }
                }
                .font(Theme.Typography.controlLabel)
                .foregroundStyle(isFollowing ? Color.black : Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
            }
            .glassButtonStyle(isFollowing ? .prominent : .regular)
            .buttonBorderShape(.roundedRectangle(radius: Theme.Radius.control))
            .tint(.white)
            .disabled(isUpdating)
            .confirmationDialog("Unfollow \(item.name)?", isPresented: $confirmsUnfollow, titleVisibility: .visible) {
                Button("Unfollow", role: .destructive, action: onUnfollow)
            }
        }
        .padding(20)
        .frame(width: 300)
        .background(plate)
        .clipShape(.rect(cornerRadius: Theme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(brand.opacity(0.26), lineWidth: 1)
        }
        .environment(\.colorScheme, .dark)
    }

    /// The brand colour over near-black, stronger at the top leading corner.
    private var plate: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.09), Color(white: 0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: [brand.opacity(0.46), brand.opacity(0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .flipsForRightToLeftLayoutDirection(true)
    }

    private var logo: some View {
        ZStack {
            if let url = item.logoURL {
                RemoteImage(url: url, contentMode: .fit).padding(10)
            } else {
                Text(String(item.name.prefix(1)).uppercased())
                    .font(Theme.Typography.title)
                    .foregroundStyle(brand)
            }
        }
        .frame(width: 60, height: 60)
        .background(.white, in: .rect(cornerRadius: Theme.Radius.panel))
        .clipShape(.rect(cornerRadius: Theme.Radius.panel))
        .shadow(color: Theme.Palette.scrim.opacity(0.25), radius: 4, y: 2)
    }
}

/// Bulk-purchase promotion card: tinted panel, icon tile, label, name, description, price, CTA.
struct BulkPlanCard: View {
    let plan: BulkPlan
    let onExplore: () -> Void

    /// The bundle's colour from the API, else the brand colour.
    private var tint: Color { Color(hexString: plan.accentHex) ?? Theme.Palette.primary }

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
                        .font(Theme.Typography.badge)
                        .letterSpacing(1.5)
                        .foregroundStyle(tint)
                        .lineLimit(1)
                }
                Text(plan.name)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(2)
                if let summary = plan.summary {
                    Text(summary)
                        .font(Theme.Typography.bodySmall)
                        .lineSpacing(3)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(2)
                }
            }

            if let price = plan.price, let amount = price.formatted {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(amount)
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    if let saving = price.discountedPercentage, saving > 0 {
                        Text("· Save up to \(Int(saving))%")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
            }

            Button(action: onExplore) {
                Text("Explore bundles")
                    .font(Theme.Typography.button)
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
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, 10)
            if let artist = item.artistName {
                Label {
                    Text(artist)
                } icon: {
                    Image(systemName: "music.note").foregroundStyle(Theme.Palette.highlight)
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .lineLimit(1)
                .padding(.top, 3)
            }
        }
        .frame(width: size)
    }
}

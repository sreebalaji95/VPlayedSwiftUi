import SwiftUI

/// One home rail: a tappable title (opens "view all") above a horizontally snapping row of cards.
struct RailSectionView: View {
    let section: HomeSection

    @Environment(\.openRoute) private var openRoute

    var body: some View {
        if let layout = section.layout {
            VStack(alignment: .leading, spacing: 0) {
                header
                rail(layout)
            }
            .padding(.top, Theme.Spacing.railGap)
        }
    }

    @ViewBuilder
    private var header: some View {
        let title = Text(section.title)
            .font(Theme.Typography.railTitle)
            .letterSpacing(-0.2)
            .foregroundStyle(Theme.Palette.textPrimary)
            .lineLimit(1)

        Group {
            if section.showsViewAll {
                Button {
                    openRoute(.viewAll(sectionID: section.id, title: section.title))
                } label: {
                    title.contentShape(.rect)
                }
                .buttonStyle(PressableButtonStyle(scale: 0.98))
                .accessibilityHint("Shows all titles in \(section.title)")
            } else {
                title.accessibilityAddTraits(.isHeader)
            }
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.bottom, Theme.Spacing.railTitleGap)
    }

    @ViewBuilder
    private func rail(_ layout: HomeSection.Layout) -> some View {
        switch (layout, section.content) {
        case (.landscape, .titles(let items)):
            HorizontalRail(items: items) { item in
                cardButton(item) { LandscapeCard(item: item) }
            }
        case (.portrait, .titles(let items)):
            HorizontalRail(items: items) { item in
                cardButton(item) { PortraitCard(item: item) }
            }
        case (.rankedPortrait, .titles(let items)):
            HorizontalRail(items: Array(items.prefix(10)), spacing: 4) { item in
                cardButton(item) { RankedPortraitCard(item: item, rank: rank(of: item, in: items)) }
            }
        case (.rankedLandscape, .titles(let items)):
            HorizontalRail(items: Array(items.prefix(10)), spacing: 4) { item in
                cardButton(item) { RankedLandscapeCard(item: item, rank: rank(of: item, in: items)) }
            }
        case (.promos, .promos(let items)):
            HorizontalRail(items: items) { item in
                cardButton(item) { PromoCard(item: item) }
            }
        case (.audio, .audio(let items)):
            HorizontalRail(items: items, spacing: 12) { item in
                Button {
                    openRoute(.content(slug: item.slug, title: item.title, kind: .audio))
                } label: {
                    AudioCard(item: item)
                }
                .buttonStyle(PressableButtonStyle())
            }
        case (.channels, .channels(let items)):
            HorizontalRail(items: items, spacing: 12) { item in
                Button {
                    openRoute(.channel(slug: item.slug, name: item.name))
                } label: {
                    ChannelCard(item: item)
                }
                .buttonStyle(PressableButtonStyle())
            }
        case (.live, .live(let items)):
            HorizontalRail(items: items, spacing: 12) { item in
                LiveNowCard(
                    item: item,
                    onWatch: { openRoute(.content(slug: item.slug, title: item.title, kind: .live)) },
                    onRemind: { openRoute(.signInRequired(prompt: String(localized: "Sign in to set a reminder", bundle: .localized))) }
                )
            }
        case (.bulkPlans, .bulkPlans(let plans)):
            HorizontalRail(items: plans, spacing: 14) { plan in
                BulkPlanCard(plan: plan) {
                    openRoute(.bulkPlan(slug: plan.slug, name: plan.name))
                }
                .containerRelativeFrame(.horizontal) { width, _ in
                    max(width - Theme.Spacing.gutter * 2, 0)
                }
            }
        default:
            EmptyView()
        }
    }

    private func cardButton<Card: View>(_ item: ContentItem, @ViewBuilder card: () -> Card) -> some View {
        Button {
            openRoute(.content(slug: item.slug, title: item.title, kind: section.kind(for: item)))
        } label: {
            card()
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func rank(of item: ContentItem, in items: [ContentItem]) -> Int {
        (items.firstIndex(of: item) ?? 0) + 1
    }
}

/// Horizontal rail with leading-edge snapping and gutter insets that the snapping respects.
struct HorizontalRail<Item: Identifiable, Card: View>: View {
    let items: [Item]
    var spacing: CGFloat = 8
    @ViewBuilder let card: (Item) -> Card

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: spacing) {
                ForEach(items) { item in
                    card(item)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, Theme.Spacing.gutter, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
    }
}

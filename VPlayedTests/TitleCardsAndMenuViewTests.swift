import SwiftUI
import Testing
@testable import VPlayed

@MainActor
struct TitleCardsTests {
    @Test func titleCardsUsePrototypeDefaultWidths() throws {
        let item = try makeItem()

        #expect(LandscapeCard(item: item).width == 172)
        #expect(PortraitCard(item: item).width == 112)
        #expect(PromoCard(item: item).width == 172)
    }

    @Test func titleCardsPreserveCustomWidths() throws {
        let item = try makeItem()

        #expect(LandscapeCard(item: item, width: 240).width == 240)
        #expect(PortraitCard(item: item, width: 144).width == 144)
        #expect(PromoCard(item: item, width: 200).width == 200)
    }

    @Test func rankedCardsKeepTheirItemAndRank() throws {
        let item = try makeItem(id: "featured")

        let portrait = RankedPortraitCard(item: item, rank: 10)
        let landscape = RankedLandscapeCard(item: item, rank: 1)

        #expect(portrait.item.id == "featured")
        #expect(portrait.rank == 10)
        #expect(landscape.item.id == "featured")
        #expect(landscape.rank == 1)
    }
}

@MainActor
struct MenuViewTests {
    @Test func menuViewUsesItsProvidedCloseAction() {
        var didClose = false
        let view = MenuView { didClose = true }

        view.onClose()

        #expect(didClose)
    }
}

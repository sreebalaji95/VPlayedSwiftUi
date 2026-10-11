import SwiftUI

/// App root: a system tab bar (Liquid Glass on iOS 26+) with one navigation stack per tab,
/// covered by the splash on cold launch. The Home model lives here so it survives navigation
/// and tab switches, and Home doesn't reload when the user comes back. Home starts loading
/// under the splash, so content is usually ready when it fades.
///
/// It also applies the language picked in Menu → Language: the locale and layout direction,
/// plus a fresh view tree (`.id`) so strings built in code re-resolve. Navigation state lives
/// here, so the user stays on the Language screen while the app switches around them.
struct RootView: View {
    @State private var homeModel = HomeViewModel()
    @State private var languageStore = LanguageStore()
    @State private var selectedTab: AppTab = .home
    @State private var paths: [AppTab: [AppRoute]] = [:]
    @State private var showsSplash = true

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                ForEach(AppTab.allCases) { tab in
                    NavigationStack(path: path(for: tab)) {
                        root(for: tab)
                            .navigationDestination(for: AppRoute.self, destination: destination)
                    }
                    .tint(Theme.Palette.textPrimary)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
                }
            }
            // Colours the selected tab; the stacks reset it so their content stays white.
            .tint(Color(.accent))
            .id(languageStore.language)
            .environment(\.openRoute, RouteAction(open))
            .accessibilityHidden(showsSplash)

            if showsSplash {
                SplashView { showsSplash = false }
                    .zIndex(1)
            }
        }
        .tint(Theme.Palette.textPrimary)
        .environment(languageStore)
        .environment(\.locale, languageStore.language.locale)
        .environment(\.layoutDirection, languageStore.language.isRightToLeft ? .rightToLeft : .leftToRight)
        // API text (rail titles, synopses) is fetched in the chosen language, so fetch it again.
        .onChange(of: languageStore.language) {
            Task { await homeModel.refresh() }
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .menu: MenuView()
        case .language: LanguageView()
        case .movies: MoviesView()
        default: PlaceholderDestinationView(route: route)
        }
    }

    @ViewBuilder
    private func root(for tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView(model: homeModel)
        default: PlaceholderDestinationView(tab: tab)
        }
    }

    private func path(for tab: AppTab) -> Binding<[AppRoute]> {
        Binding(
            get: { paths[tab] ?? [] },
            set: { paths[tab] = $0 }
        )
    }

    /// Search has its own tab, so a search request switches to it instead of pushing a screen.
    private func open(_ route: AppRoute) {
        if case .search = route {
            selectedTab = .search
        } else {
            paths[selectedTab, default: []].append(route)
        }
    }
}

#Preview {
    RootView()
}

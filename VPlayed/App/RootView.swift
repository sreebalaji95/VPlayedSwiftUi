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
    @State private var showsMenu = false
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
            .tint(Theme.Palette.brand)
            .id(languageStore.language)
            .accessibilityHidden(showsSplash || showsMenu)

            // Above the tab bar, like a side menu.
            MenuDrawer(isPresented: $showsMenu)
                .zIndex(1)

            if showsSplash {
                SplashView { showsSplash = false }
                    .zIndex(2)
            }
        }
        .environment(\.openRoute, RouteAction(open))
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

    /// The menu is a drawer over the tabs, and Search has its own tab, so neither pushes a
    /// screen. Anything opened from the menu pushes onto the current tab as the drawer closes.
    private func open(_ route: AppRoute) {
        switch route {
        case .menu:
            withAnimation(.snappy) { showsMenu = true }
        case .search:
            showsMenu = false
            selectedTab = .search
        default:
            withAnimation(.snappy) { showsMenu = false }
            paths[selectedTab, default: []].append(route)
        }
    }
}

#Preview {
    RootView()
}

import SwiftUI
// Kotlin classes are not Sendable; only the preview builds one here.
@preconcurrency import Shared

/// App root: a system tab bar (Liquid Glass on iOS 26+) with one navigation stack per tab,
/// covered by the splash on cold launch. The Home model lives here so it survives navigation
/// and tab switches, and Home doesn't reload when the user comes back. Home starts loading
/// under the splash, so content is usually ready when it fades.
///
/// It also applies the language picked in Menu → Language: the locale and layout direction,
/// plus a fresh view tree (`.id`) so strings built in code re-resolve. Navigation state lives
/// here, so the user stays on the Language screen while the app switches around them.
///
/// It applies two rules from the launch-time common settings (`AppStartup`): drama catalogues
/// force dark mode, and the server can turn right-to-left layout off.
///
/// Login (`AppRoute.signIn`) is presented over everything; when the session changes, Home
/// reloads so its content matches the new account.
struct RootView: View {
    let startup: AppStartup
    let account: AccountStore
    @State private var homeModel: SharedHomeViewModel
    @State private var languageStore = LanguageStore()
    @State private var selectedTab: AppTab = .home
    @State private var paths: [AppTab: [AppRoute]] = [:]
    @State private var showsMenu = false
    @State private var showsSplash = true
    @State private var showsLogin = false
    /// Shown on Login when it opens because the session expired.
    @State private var loginNotice: String?

    init(startup: AppStartup, account: AccountStore) {
        self.startup = startup
        self.account = account
        // Home's first requests wait for the geo token (`X-Bearer-Token`), but no longer than the splash.
        _homeModel = State(initialValue: SharedHomeViewModel(prepare: { await startup.waitForGeoToken(upTo: SplashView.duration) }))
    }

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
            .tint(Theme.Palette.primary)
            .id(LayoutID(language: languageStore.language, isRightToLeft: languageStore.isRightToLeft))
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
        .font(Theme.Typography.standard)
        .environment(languageStore)
        .environment(startup)
        .environment(account)
        .environment(\.locale, languageStore.language.locale)
        .environment(\.layoutDirection, languageStore.isRightToLeft ? .rightToLeft : .leftToRight)
        .preferredColorScheme(startup.forcesDarkMode ? .dark : nil)
        .onChange(of: startup.isRTLAllowed, initial: true) { _, allowed in
            languageStore.isRTLAllowed = allowed
        }
        // Rails, prices and access tags depend on who is signed in (not on a refreshed token).
        .onChange(of: account.accountID) {
            Task { await homeModel.refresh() }
        }
        // As the UIKit app: "Session Expired, Please login to continue", then Login.
        .onChange(of: account.expiredSessionCount) {
            withAnimation(.snappy) { showsMenu = false }
            loginNotice = L10n.shared(.sessionExpired)
            showsLogin = true
        }
        .fullScreenCover(isPresented: $showsLogin, onDismiss: { loginNotice = nil }) {
            LoginView(account: account, verificationMethod: startup.settings?.verificationMethod, notice: loginNotice)
                .font(Theme.Typography.standard)
                .environment(startup)
                .environment(\.locale, languageStore.language.locale)
                .environment(\.layoutDirection, languageStore.isRightToLeft ? .rightToLeft : .leftToRight)
        }
        // API text (rail titles, synopses) is fetched in the chosen language, so fetch it again.
        .onChange(of: languageStore.language) {
            Task { await homeModel.refresh() }
        }
    }

    /// Rebuilds the tabs when the language or the layout direction changes.
    private struct LayoutID: Hashable {
        var language: AppLanguage
        var isRightToLeft: Bool
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
        case .signIn:
            withAnimation(.snappy) { showsMenu = false }
            showsLogin = true
        case .signInRequired where !account.isSignedIn:
            withAnimation(.snappy) { showsMenu = false }
            showsLogin = true
        default:
            withAnimation(.snappy) { showsMenu = false }
            paths[selectedTab, default: []].append(route)
        }
    }
}

#Preview {
    RootView(startup: AppStartup(), account: AccountStore(sessions: SessionManager(store: InMemorySecureStore())))
}

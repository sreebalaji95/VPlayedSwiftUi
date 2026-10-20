# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

VPlayed is a SwiftUI video app (App Store category `public.app-category.video`). Its only third-party dependencies are the sign-in SDKs, as Swift packages: FirebaseAuth (`firebase-ios-sdk`, phone sign-in codes) and GoogleSignIn (`GoogleSignIn-iOS`), the same SDKs the UIKit app uses. Add no others without asking. `MyApp.swift` (`@main`) → `App/RootView.swift` → the Home screen. Home, Menu, Language, Movies and Login are the only real screens so far; every other destination is a placeholder.

Service teams fork it to ship white-label brands; [`WHITE_LABEL.md`](WHITE_LABEL.md) lists what a rebrand edits (`Config/Brand.xcconfig`, everything in `VPlayed/Brand/` (`Brand.swift`, `Assets.xcassets` with the colorsets and `SplashLogo`, `AppIcon.icon`, `Fonts/`), brand copy keys) and what it must not. Put new brand-replaceable files in `VPlayed/Brand/` and core code elsewhere. Keep it in step when those files or tokens change.

It is a native rewrite of the existing UIKit app at `/Users/balaji/Desktop/GSVplayed/Vplayed New`. Its source (`GudSho/`) is the reference for endpoints, headers, JSON keys and business rules, but nothing there compiles standalone (Alamofire, ObjectMapper, UIKit globals). Port logic into new Swift 6 code; never modify that project.

## Commits

Do not add a `Co-Authored-By: Claude …` trailer or any other Claude attribution to commit messages.

## Build

Before the first build, set up the two local inputs that are not in git:

- `Config/Secrets.xcconfig`: copy `Config/Secrets.example.xcconfig` and fill in `VPLAYED_TRANSPORT_KEY`, plus the optional sign-in provider settings (`VPLAYED_GOOGLE_*`, `VPLAYED_FIREBASE_*`; empty hides Google sign-in and keeps email sign-in when the backend asks for phone verification). They reach the app through Info.plist keys (`AuthProviderConfig`); `FirebaseBootstrap` starts Firebase from them, without a `GoogleService-Info.plist`.
- `SharedKit/Shared.xcframework`: the Kotlin Multiplatform shared layer, built from the `kmp` repository checked out next to this one (`../kmp`). Run `scripts/build-shared.sh` (needs JDK 25, e.g. `export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"`), and run it again after pulling `kmp` changes. See "Shared layer" under Architecture.

The app target is `VPlayed`. There is one shared scheme per environment (`Dev`, `Qa`, `Stage`, `Demo`; see Environments), and each also runs the `VPlayedTests` target (Swift Testing). Use `Dev` day to day. Build:

```bash
xcodebuild -project VPlayed.xcodeproj -scheme Dev -destination 'generic/platform=iOS Simulator' build
```

Run the tests, or a single suite or test:

```bash
xcodebuild test -project VPlayed.xcodeproj -scheme Dev -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test -project VPlayed.xcodeproj -scheme Dev -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:VPlayedTests/MoviesViewModelTests
xcodebuild test -project VPlayed.xcodeproj -scheme Dev -destination 'platform=iOS Simulator,name=iPhone 17' '-only-testing:VPlayedTests/MoviesViewModelTests/pageOfDuplicatesKeepsLoading()'
```

`VPlayedTests/` is also a synchronized folder; JSON in `VPlayedTests/Fixtures/` is real dev-API output, trimmed to two items per rail and stripped of studio contact/KYC fields and live-stream credentials (`streaming_key`, `streaming_url`, `streaming_watch_url`, `streaming_id`, `streaming_arn`). People and accounts are pseudonymised: `studio_name` / `name` → "Studio A" / "Channel A"…, `artist_name`, `cast_name`, `lead_name` → "Artist A" / "Cast Member A"…, and `creator_id` / `updator_id` → `00000000000000000000c001`…; content titles and artwork paths stay. Do the same to any new capture; the app never reads the stripped fields.

## Environments

Four shared schemes, `Dev`, `Qa`, `Stage` and `Demo`, mirror the UIKit app's environments. Each uses its own `Debug<Env>` / `Release<Env>` build configurations (`DebugDev`, `ReleaseDev`, …), which set:

| Scheme | Compilation condition | Bundle ID | Home-screen name | API host | Image bucket |
|---|---|---|---|---|---|
| `Dev` | `DEV` | `com.contus.vplayed.dev` | DevVPlayed | `api-devgs.vplayed.com` | `gsvp-dev` |
| `Qa` | `QA` | `com.contus.vplayed.qa` | QaVPlayed | `api-qags.vplayed.com` | `gsvp-qa` |
| `Stage` | `STAGE` | `com.contus.vplayed.stage` | StageVPlayed | `api-stagings.vplayed.com` | `gsvp-qa` (as in the UIKit app) |
| `Demo` | `DEMO` | `com.contus.vplayed` | VPlayed | `api-demogs.vplayed.com` | `gsvp-demo` |

- The condition is set at project level (`SWIFT_ACTIVE_COMPILATION_CONDITIONS`), and `APIEnvironment.current` picks the hosts with `#if`. Demo is the UIKit app's PROD build, which points at the demo hosts.
- There are no plain `Debug` / `Release` configurations. Building without a scheme uses `ReleaseDemo`. Code built with no condition falls back to Dev.
- To add a setting per environment, set it in all eight configurations of the right target (project, `VPlayed` or `VPlayedTests`); new configurations must exist in all three configuration lists.
- Brand identity lives in `Config/Brand.xcconfig`, the base configuration of all eight project-level configurations: `BRAND_BUNDLE_ID`, `BRAND_DISPLAY_NAME`, `DEVELOPMENT_TEAM`, `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`. The project-level configurations add the environment's part, `APP_ENV_NAME_PREFIX` (`Dev`, `Qa`, `Stage`, empty for Demo) and `APP_ENV_BUNDLE_SUFFIX` (`.dev`, `.qa`, `.stage`, empty). The `VPlayed` target then sets one value, identical in all eight configurations: `PRODUCT_BUNDLE_IDENTIFIER = $(BRAND_BUNDLE_ID)$(APP_ENV_BUNDLE_SUFFIX)` and `INFOPLIST_KEY_CFBundleDisplayName = $(APP_ENV_NAME_PREFIX)$(BRAND_DISPLAY_NAME)`. The tests use `$(BRAND_BUNDLE_ID).tests`. Keep the target values identical across configurations: Xcode's General tab shows one Display Name, and if the configurations differ, merely focusing that field writes the current configuration's resolved name (`DevVPlayed`) into all of them. Don't set the brand keys in the target configurations, or they override the xcconfig.
- Stage's Home API currently returns only empty rails for a guest, so Stage's Home shows the hero and pages through ~39 empty pages.

## Project configuration that affects code

- **One iOS target** for iPhone and iPad (min 17.0; `SUPPORTED_PLATFORMS = iphoneos iphonesimulator`). Apple-silicon Macs and Apple Vision Pro run it as the iPad app ("Designed for iPad": `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD`, `SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD`; no Mac Catalyst), so there are no macOS or visionOS builds and no `#if os(...)` branches. iOS 17 is the floor, so APIs newer than iOS 17 need `if #available(iOS …, *)`.
- **Swift 6 with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency.** Every type is implicitly `@MainActor` unless marked otherwise. Heavy or background work (decoding, file I/O, networking) must be explicitly `nonisolated` or `@concurrent`.
- **`MemberImportVisibility` is enabled.** Each file must `import` every module whose members it uses; transitive imports don't count.
- **File-system-synchronized groups.** Files added under `VPlayed/` are picked up by the target automatically, so `project.pbxproj` doesn't need editing to add sources or resources.
- **The Info.plist is generated** (`GENERATE_INFOPLIST_FILE = YES`). Add keys such as usage descriptions as `INFOPLIST_KEY_*` build settings in `project.pbxproj` (in both Debug and Release target configs).
  - The only exception is the launch screen. `VPlayed/Info.plist` holds just `UILaunchScreen` (the `SplashLogo` image on the `Background` color, the same colorset as the app's page background; both have light and dark variants, the light logo being `SplashLogoLight.svg` with a dark wordmark), because there is no build setting for a launch image.
  - That plist is merged via `INFOPLIST_FILE` and excluded from the synchronized folder by a `PBXFileSystemSynchronizedBuildFileExceptionSet`. Keep that exception, or the build fails with duplicate Info.plist outputs.
- **Launch flow**:
  - The system launch screen shows the wordmark centered.
  - `App/SplashView.swift` then draws the same `SplashLogo` at the same spot (full-screen center, at the SVG's natural `width`/`height`, 288pt), adds the prototype's glow, progress bar and tagline, and fades out after 3s. Its "Skip intro" button is hidden for now (`SplashView.showsSkipButton = false`); the code stays for later. The bar and tagline hang 28pt below the logo by alignment guide, so a logo of another size needs no code change.
  - Home loads underneath meanwhile. If you change the logo size or position, change both.
- **Shapes and other SwiftUI protocol conformances used off the main actor** (e.g. `Shape`) must be declared `nonisolated struct`, or the build fails with a `ConformanceIsolation` error.

## Architecture

- **Networking (`Core/Networking`)**:
  - Every backend call goes through the shared layer's Ktor client on the Darwin engine (`SharedLayer.configureSession`: six connections per host and a URL cache). There is no Swift HTTP client. `Core/Networking` holds the hosts (`APIEnvironment`, see Environments), `APIError` (the failures the UI shows, mapped from the shared `AppError`) and `DeviceID`.
  - Endpoints, the `{statusCode, message, response}` envelope and the status rules live in `../kmp`. A non-2xx HTTP status fails; within 2xx the envelope's `statusCode` decides (decision D1).
  - The shared `VPlayedHeaders` sends the UIKit app's header set: `X-Request-Type: mobile`, `device_type: ios`, `device_id`, `app_version`, `X-Language-Code`. It adds `Authorization` and `profile_id` with a session and `X-Bearer-Token` once the geo token is known. `profile_id` is the default profile's id from the shared sign-in (`AuthCredentials.profileID`); there is no profile selection yet.
  - Home APIs work as an anonymous guest.
- **Shared layer (`Core/Shared`, `SharedKit/`)**:
  - Business logic shared with the Android app lives in a Kotlin Multiplatform library in the `kmp` repository. The plan is in `../KMP_PLANNING/`. `scripts/build-shared.sh` builds `Shared.xcframework` (iOS device, iOS simulator arm64/x86_64) into the local `SharedKit` package, which the `VPlayed` target links.
  - `SharedLayer` builds the one `SharedGraph` from `APIEnvironment`, the app version and the transport key. `IOSSharedDeviceInfo` supplies `device_id` (`DeviceID`), `deviceDetail` (`DeviceModel`) and `X-Language-Code` (`AppLanguage.current`). It and `IOSSharedLogger` are `nonisolated`, because Kotlin calls them from background threads. Import the module as `@preconcurrency import Shared`, since Kotlin classes aren't `Sendable`.
  - No Swift copy of shared logic is left (Phase 7 removed them). Put new endpoints, JSON reading and business rules in `../kmp`. Swift keeps:
    - the views and their `@Observable` models (`SharedLoginViewModel`, `SharedHomeViewModel`, `MoviesViewModel`, `AccountStore`, `AppStartup`);
    - plain view structs (`HomeSection`, `ContentItem`, `CommonSettings`, `GeoInfo`…) that `SharedHomeMapping` and the services fill from the shared models;
    - the service protocols the tests mock (`AuthServicing`, `StartupServicing`, `MoviesServicing`) with their shared implementations (`SharedAuthService`, `SharedStartupService`, `SharedMoviesService`);
    - the platform pieces the shared layer asks for: `KeychainSecureStore`, `IOSSharedDeviceInfo`, `IOSSharedLogger`, the Darwin engine and CommonCrypto (`platformCryptoPrimitives()`).
  - What runs on the shared layer:
    - Login: `LoginView` runs on `SharedLoginViewModel`, which runs the shared `EmailLoginController` and `OtpController` (the same rules AndroidJP's Login and OTP screens use), mirrors their state through `watchState` / `watchEffects`, and closes them through `KotlinSubscriptions`.
    - Logout: `AuthServices.live()` returns `SharedAuthService`.
    - Home: `HomeView` runs on `SharedHomeViewModel`, which runs the shared `HomeFeedController` (the same feed rules AndroidJP's Home uses: parallel first load, de-duplicated paging, up to five empty pages skipped, refresh that keeps content, channel follow) and maps the shared models into the Swift view structs (`SharedHomeMapping`). The shared mapper applies this app's image table (decision D12, `HomeImagePolicy.APPLE`).
    - Movies: `MoviesViewModel` pages through `SharedMoviesService` (`SharedGraph.moviesRepository`).
    - Launch: `StartupServices.live()` returns `SharedStartupService` (`SharedGraph.commonSettingsRepository` and `geoRepository`). `AppStartup` still decides when they run (decision D18).
    - Kotlin types that share a name with an app type (`HomeSection`, `ContentItem`, `CommonSettings`, `GeoInfo`, `Price`, `AccessTag`) are written `Shared.X`; unqualified names are the app's. Tests import both modules, so they qualify the app's as `VPlayed.X`.
  - Since Phase 5 the session belongs to the shared `SessionManager` (`SharedLayer.sessions`), stored by `KeychainSecureStore` in the Keychain item the app always used. Requests send its tokens and the graph `GeoStore`'s geo token.
  - Tests:
    - `SharedLayerTests` checks the shared configuration, that the app's graph uses `SharedLayer.sessions` and the shared auth service, and the exact backend headers the Darwin engine sends.
    - `SharedSessionTests` covers the upgrade (a session stored as `AuthCredentials` JSON is restored, guests too), `AccountStore` over the manager and the Keychain round trip in the app's item format; `SharedSessionExpiryTests` covers the 401 rule.
    - `SharedInteropTests` checks how Swift meets Kotlin: Darwin timeouts and offline errors arrive as typed `Timeout` / `Network` failures, a suspend call from a cancelled Swift task still completes (cancellation does not cross into Kotlin), watchers deliver on the main thread from the current value and stop when closed, and Kotlin enums and sealed types compare as expected.
    - `AuthServiceContractTests` runs scripted backend answers against `SharedAuthService`: paths, encrypted bodies (decrypted with the shared `TransportCipher`) and the outcome of each status.
    - `SharedLoginViewModelTests` runs the Login model against scripted answers.
    - The suites that script `AuthStubURLProtocol` are nested in the serialized `StubbedBackendTests`. The flow rules themselves are tested in `../kmp`.
    - The suites that script `RouteStubURLProtocol`, which answers by path because Home loads banners and rails in parallel, are nested in the serialized `RoutedBackendTests`: `HomeFixtureTests` reads the dev-API fixtures through the shared layer and `SharedHomeMapping`, `SharedHomeViewModelTests` runs the Home model, `SharedMoviesServiceTests` the Movies call, `SharedStartupServiceTests` the launch calls.
  - Kotlin `StateFlow`s are not `@Observable`. Observe them with `StateFlowWatcher.watch(onEach:)`, which delivers on the main thread, and `close()` the returned `Closeable` in `deinit`. Kotlin `suspend` functions are `async` in Swift. Shared APIs return result types and never throw.
- **Decoding**:
  - The shared layer reads all JSON. The API mixes types (`sho_type` Int or String, `video_duration` String, flags 0/1 or Bool, titles String or `{"en": …}`); the lenient helpers in `../kmp` (`core/serialization/Lenient.kt`) read them so one malformed item never fails a whole response.
  - The Swift model structs have no decoders. They are `nonisolated` so the services can build them off the main actor.
- **Launch configuration (`Core/AppConfig`)**:
  - `AppStartup` (`@Observable`) runs the UIKit app's two launch calls once per process. `MyApp` owns it and calls `start()` from its `init`, so view updates, navigation and language switches never fetch again. Don't trigger it from views.
  - The calls are independent and run concurrently:
    - `GET mediaview/api/v1/common` (from `SceneDelegate.getCommonKeys`) gives `CommonSettings`: feature flags, content library, OTP method, payment flags and the iOS `force_update_details`.
    - The geo step (`geoLookup()`) looks up the public IP at `api.ipify.org`, then calls `GET mediaview/api/v1/common/geo-data/{ip}` (from `SplashScreenViewController.getBearerToken`). The shared `GeoStore` keeps `geo_token`, so every later request sends it as `X-Bearer-Token`. `GeoInfo` (country, currency…) comes from the token's base64 JSON.
    - Both calls go through the shared layer (`SharedStartupService`).
  - Failures are logged (category `Startup`) and ignored, as in UIKit, and the defaults apply.
  - Home's first load waits for the geo step through `SharedHomeViewModel(prepare:)`, for at most `SplashView.duration`.
  - `RootView` applies two UIKit rules. A drama catalogue (`content_library` 2) forces dark mode except in `QA` builds. `rtl: false` sets `LanguageStore.isRTLAllowed = false`, which lays the chosen language out left to right; use `languageStore.isRightToLeft`, not `language.isRightToLeft`, for layout.
  - `start()` also starts the shared `GuestSessionKeeper` (`StartupServicing.startGuestSessions()`): whenever nobody is signed in and the common settings' `is_guest_user` is true, it starts a guest session (`auth/generate`), as the UIKit app's `checkIfUserLoggedIn`.
  - Not ported yet: the force/soft update prompt (the settings are stored), and re-fetching on foreground.
- **Auth (`Core/Auth`, `Features/Auth`)**:
  - Login (`LoginView` / `SharedLoginViewModel`) is the prototype's "VPlayed Sign Up" flow on the UIKit app's passwordless email sign-in. Step 1: `POST users/api/v1/auth/email-login` (200 or 203 sends a code; 202 is the device limit). Step 2: `POST users/api/v1/auth/verifyEmailOtp` (200, or 203 with a token, signs in; 203 without one means "register first"; 202 is the device limit). Then "You're all set", which closes itself after 3s. UIKit rules kept: its email regex, a 50-character cap and a 60s resend wait.
  - Status rules shared with Android (decisions in `../KMP_PLANNING/KMP_ARCHITECTURE_ANALYSIS.md` §5):
    - D1: a non-2xx HTTP status always fails. Within 2xx, the envelope's `statusCode` decides.
    - D2: a 203 at email-login also goes to the code step.
    - D4: an account without phone or social IDs signs in. These replace UIKit's "no account" and "not registered" rules.
  - Bodies are `{"data": <CryptoJS AES>}`: the shared `TransportCipher` reproduces `CryptoJS.AES.encrypt(json, passphrase)` (OpenSSL `Salted__` format, MD5 key derivation, AES-256-CBC), on CommonCrypto here. The passphrase is a build secret. `VPLAYED_TRANSPORT_KEY` comes from the git-ignored `Config/Secrets.xcconfig` (included by `Brand.xcconfig`) and reaches `SharedLayer.transportKey` (then `SharedConfig.transportKey`) through the `VPlayedTransportKey` Info.plist entry. Never put it in source. Tests use a test-only passphrase.
  - "Continue as guest" (`POST users/api/v1/auth/generate`, `{"uuid": DeviceID}`) only shows when the common API's `is_guest_user` is true. Guests still see "Sign in" in Menu.
  - Device-limit responses show a message (see the switch below). New accounts get the UIKit Register screen as a `LoginView` step (`.register`, shared `RegistrationController`; prototype "Complete your profile" copy): an email account with no phone and no Google / Apple / Facebook id adds its name and mobile number (`POST users/api/v1/auth/update-profile`, optional referral code); a `phone-login` 203 adds its name and email (`POST users/api/v1/auth/register`). The session is stored only once that succeeds; Back returns to step 1 with "Your signup was unsuccessful.".
  - Every sign-in uses the account's first profile (`GET users/api/v1/muti-profile/list`, shared `profileChooser`; PIN-locked profiles are skipped, else the login's `default_profile` stays). The UIKit profile picker isn't ported.
  - The device-limit step (`LoginView.devicesStep`: sign other devices out, then continue) is built but switched off with `AuthFeatures.deviceSignOut = false`. Its "continue" (`verifyEmailLogin`) signs in without a code, so it stays off until the backend confirms that's safe (D5). `SharedLoginViewModelTests` runs it with the switch on.
  - Shared messages are `AuthMessage`s: the server's words when safe, else an `AuthMessageKey` that `SharedLoginViewModel.text(for:)` maps to `Localizable.xcstrings`. The Arabic, Portuguese and Tamil translations added in Phase 3 and for phone / social sign-in are marked "needs review".
  - Phone sign-in: when the common settings' `otp_verfied` is `phone` / `mobile` and Firebase is configured, step 1 asks for a mobile number (`PhoneField`: the prototype's country chip, +91 by default, and the number). The shared `PhoneLoginController` validates it (+91: ten digits starting 6–9; others: 7–15) and calls `POST users/api/v1/auth/phone-login` with `is_phone_verified` "0"; the shared `OtpController` then has `FirebasePhoneOtpSender` text and check the code and signs in with "1". Without APNs, Firebase checks the app with a reCAPTCHA page that returns through `VPLAYED_FIREBASE_URL_SCHEME` (`AuthURLHandler`).
  - Google and Apple sign-in (`LiveSocialSignIn`, shared `SocialLoginController`): `POST users/api/v1/auth/login` with the UIKit app's `LoginRequestModel` keys. Google sends its OAuth access token as `id_token` (UIKit parity); Apple its identity token, with the email from the credential, the token's claim or the Keychain (`appleEmail`), since Apple shares it once. The Google button is hidden without `VPLAYED_GOOGLE_CLIENT_ID`; Apple needs the Sign in with Apple capability (`Config/VPlayed.entitlements`).
  - `AccountStore` (`@Observable`, owned by `MyApp`) holds signed out / guest / signed in.
    - The shared `SessionManager` keeps the session in the Keychain (`KeychainSecureStore` over `KeychainItem`, service `com.contus.vplayed`, account `session`) and restores it on first use. Every request waits for that, so the first request is authenticated. `AccountStore` follows the manager's status (`currentStatus`, `watchStatus`): the restored session, and signed out when a request carrying the token gets a 401 (decision D21). Sessions stored before Phase 5 (`AuthCredentials` JSON) are read as they are.
    - Tests and previews use `SessionManager(store: InMemorySecureStore())`, which is memory-only.
    - A 401 first tries one token refresh (`auth/refresh-token`) in the shared `ApiCaller` (decision D21, revised); when the session still ends, `AccountStore.expiredSessionCount` makes `RootView` open Login with "Session Expired, Please login to continue". Home reloads when `AccountStore.accountID` changes, not on a refreshed token.
  - Sign out (Menu) calls `POST users/api/v1/auth/logout` (`SharedAuthService` → `SharedGraph.logout()`, the same rule as AndroidJP's menu). It clears the session on success or 401; other failures keep it, as in UIKit. `RootView` refreshes Home whenever the account changes.
- **Images (`Core/Images`)**:
  - API image fields are relative keys joined to the CDN by `ImageURL.resolve`.
  - Image variant codes (`tv`, `tp`, `tm`…) are sizes, not shapes. Video thumbnails are 16:9 but micro-series (`sho_type` 6) ones are 3:4, so each card picks its own variant order. The shared mapper picks them with this app's table (decision D12, `HomeImagePolicy.APPLE` in `../kmp`).
  - Quality: the table prefers the `default` (JPEG/PNG) originals over `webp`, whose copies are compressed much harder. 16:9 cards (videos, series, promos, live) use `tc` first (≈1280–1567 px wide; `tl`/`to` go up to 3840). Micro-series portrait cards use `tp` first (700×922); their `tc` is only 231×307. Banners, posters and 2:3 thumbnails use `web` (= `Key`, the full size).
  - `RemoteImage` loads through `ImagePipeline`, an actor that de-duplicates requests, caches on disk and in memory, and downsamples with ImageIO.
  - Use `RemoteImage`, not `AsyncImage`.
- **Home (`Features/Home`)**:
  - Data comes from `GET mediaview/api/v1/homebanners` (hero) and `GET mediaview/api/v1/home?limit=3&inside_limit=10&page=N` (rails, paged by top-level `next`).
  - Each rail's `data` is polymorphic by `type`: 1/7 titles, 2/8 promos, 3 audio, 4/9 channels, 5 bulk plans, 6 live.
  - `HomeSection.layout` maps type + `is_top_ten` + micro-series to a prototype card style. Unknown types and empty rails are dropped.
  - The shared layer applies the UIKit card badge rules (`SeriesCollectionViewCell`, decision D14); `ContentItem` stores the resulting `AccessTag` and its image URLs, mapped by `SharedHomeMapping`.
  - Live items: the dev API sends `streaming_status` and `schedule_at` (AndroidJP's keys); the shared layer reads those first, then `publish_status` / `scheduled_at` (decision D10).
  - The bulk-plan card shows the full price and "Save up to N%" from the listed `discounted_percentage`, even when `discounted_price` is 0; AndroidJP shows the reduced price and a percentage only with a real discount (divergence D20, kept per app).
  - `SharedHomeViewModel` (`@Observable`) owns phases, refresh and de-duplicated pagination. It is held by `RootView` so Home doesn't reload after navigation.
- **Movies (`Features/Movies`)**, opened from Menu → Movies:
  - Data comes from `GET mediaview/api/v1/sho-details/media/1?page=N&limit=10&is_promo=true` (`SharedGraph.moviesRepository` through `SharedMoviesService`; the backend uses 2 for series, 6 for micro-series). It is paged by top-level `next`, and `total` feeds the "N films" subtitle.
  - Items map to `ContentItem` through `SharedHomeMapping.contentItem` (`genre` comes from `default_genre.title`). `MoviesViewModel` mirrors Home's phases, refresh and de-duplicated paging.
  - The UI is an adaptive grid (two columns on iPhone) of `CardArtwork(url:aspectRatio:)` cards with the access tag, title and "Genre • duration".
  - The prototype's Genre / Language / Access / Sort chips are intentionally omitted, because the API has no filter or sort parameters.
- **Navigation**:
  - `RootView` hosts a system `TabView` (tabs in `AppTab`: Home, Promos, Subscription, then Search on the right as in the App Store), which gets the Liquid Glass tab bar on iOS 26+. Only Home is built; the other tabs show `PlaceholderDestinationView(tab:)`.
  - Each tab has its own `NavigationStack`. Views call `@Environment(\.openRoute)` with an `AppRoute`; `RootView` pushes it onto the selected tab's stack, except `.search`, which switches to the Search tab, and `.menu`.
  - `.menu` opens `MenuDrawer` (`Features/Menu`), a side drawer drawn above the `TabView` (tab bar included). It slides in from the leading edge (left in LTR, right in Arabic) to `min(82%, 340pt)` wide over a dimmed scrim. The scrim, the close button and a swipe towards that edge close it. Any other route opened while it is showing closes it and pushes onto the current tab.
  - In RTL, SwiftUI mirrors `offset` but not `DragGesture` translations, so the drawer converts the translation (`towardsTrailing`) and offsets with it unconverted.
  - `.signIn`, and `.signInRequired` while not signed in (guests included), present `LoginView` over everything: a full-screen cover. It closes the menu first. Menu has a Sign in row, or the account and Sign out once signed in.
  - Routes without a screen resolve to `PlaceholderDestinationView`. Add real screens by switching on the route in `navigationDestination`.
- **Localization**:
  - English is the development language. Arabic (`ar`, right-to-left), Portuguese (`pt`) and Tamil (`ta`) are listed in `knownRegions`, and every string lives in `VPlayed/Localizable.xcstrings`.
  - The app language is `AppLanguage` (`Core/Localization`). Users pick it in Menu (Home's leading toolbar button) → Language (`Features/Menu`), or in iOS Settings → VPlayed → Language. Both write the app's `AppleLanguages`, so they always agree.
  - Switching is live. `RootView` owns a `LanguageStore`, sets `\.locale` and `\.layoutDirection`, gives the `TabView` an `.id` so everything re-renders, and refreshes Home so API text comes back in the new language. Navigation paths live in `RootView`, so the user stays on the Language screen.
  - Literals passed to `Text`, `Label`, `Button` and `accessibilityLabel` are localized automatically. Strings built elsewhere (enum titles, error messages, route titles) need `String(localized: "…", bundle: .localized)`. `Bundle.main` only picks its language at launch; `Bundle.localized` is the current language's `.lproj`. View parameters that take UI text should be `LocalizedStringKey`. Add every new key's `ar`, `pt` and `ta` translations to the catalog. Find the exact keys in the build's `*.stringsdata` files, or let Xcode sync the catalog.
  - UIKit bars lay out in the launch language's direction, not SwiftUI's `layoutDirection`. So `LanguageStore` forces `UIView.appearance().semanticContentAttribute` before each switch (the `TabView` rebuild then creates fresh bars), and `HomeToolbar` uses `.topBarLeading` / `.topBarTrailing` rather than `.navigation` / `.primaryAction`, which ended up together on one side after popping back to Home following a switch between LTR and RTL languages.
  - Counts that need plural forms use catalog substitutions (see the `%@ followers %lld` key; Arabic has six plural categories).
  - `AppLanguage.current` also drives the API's `X-Language-Code` header and which translation the shared mapper picks from translated titles.
  - RTL: layout mirrors automatically. Use `.forward` SF Symbols rather than `.right`, and `.flipsForRightToLeftLayoutDirection(true)` on directional gradients. Use `.letterSpacing(_:)` instead of `.tracking(_:)` for display text; it only tracks Latin-script languages, because tracking breaks Arabic joins and Tamil conjuncts.
  - Try a language with launch arguments, e.g. `xcrun simctl launch booted com.contus.vplayed -AppleLanguages "(ar)" -AppleLocale ar_SA`.
- **Liquid Glass (always)**:
  - Bars are system bars. Home's top bar is `HomeToolbar` (`HomeChrome.swift`): system toolbar items for the menu, the `SplashLogo` wordmark (`.sharedBackgroundVisibility(.hidden)`) and the bell. The feed `ScrollView` ignores the top safe area so the hero runs behind the glass bar (and the status bar), with `.softTopScrollEdge()` and a top fade in the hero scrims for legibility. The scrims are weaker in light mode (`ScrimTone`), where the near-white page colour would wash the art out.
  - Controls are glass, through `DesignSystem/Glass.swift`, never custom filled styles:
    - `glassButtonStyle()` for controls, and `glassButtonStyle(.primary)` for the primary action (it tints with `Theme.Palette.primary` and colours the label, spinners included, with `onPrimary`; don't add `.tint` or `.white`). `glassButtonStyle(.prominent)` + `.tint(_:)` is for other tinted actions;
    - `GlassCardButtonStyle(shape:padding:)` for Menu/Language rows;
    - `glassSurface(in:)` for floating chips;
    - `GlassGroup` to blend neighbouring glass.
  - The helpers hold all availability logic: iOS 26 gets `.glass` / `.glassEffect`; iOS 17–18 get bordered styles or material. Don't add `#available` checks in views.
  - Exceptions:
    - Home rail content (poster/promo/audio/channel cards, the Live card panel, rail titles) keeps its original surfaces and `PressableButtonStyle`; the user preferred it to glass. Buttons inside cards ("Watch Live", "Set reminder", "Explore bundles") are glass.
    - The hero's full-bleed background image tap stays plain, since an edge-to-edge photo has no shape for glass. "Watch now" is its glass action.
- **Design**:
  - `DesignSystem/Theme.swift` holds the tokens from the HTML prototype (`~/Downloads/VPlayed Complete Prototype (offline) (9).html`, page "VPlayed Home Mobile"): SF Pro, Material Symbols mapped to SF Symbols. The prototype is dark-only; the light values are our own.
  - Text styles are `Theme.Typography` roles (`.font(Theme.Typography.cardTitle)`), never `.font(.system(size:…))`; pick the role by meaning, not by size, and add a role rather than an inline size. SF Symbol sizes (`Image(systemName:).font(.system(size:))`) are icon metrics and stay in the views.
  - The roles use SF Pro unless `Brand.fontFamily` (`Brand/Brand.swift`) names a typeface; then they use `.custom(family, fixedSize:).weight(_:)`. `BrandFonts.registerBundledFonts()` (called from `MyApp.init`) registers every `.ttf`/`.otf`/`.ttc` in the app's resources through CoreText, so fonts need no `UIAppFonts` entries. The brand is Inter (`Brand/Fonts`, Light to Bold; `.heavy` roles use Bold). It also gives the UIKit bars the family: navigation titles through `UINavigationBar` appearance, tab labels through a `UITabBarAppearance` that sets only the font (the iOS 26 bar ignores `UITabBarItem` appearance) at an unscaled 10pt, since a Dynamic Type-scaled font renders larger than the system's. `RootView` and the Login cover set `Theme.Typography.standard` (17pt, scales like `.body`) as the default for text without a role. `BrandTests` checks that the named family is installed.
  - Colours are colorsets in `Brand/Assets.xcassets/Colors`; `Theme.Palette` refers to them through generated asset symbols (`Color(.textPrimary)`). Palette members are named by role (`primary`, `highlight`, `fillStrong`, `lineStrong`…), and so are their colorsets, so a white-label brand can recolour them without the names lying. Add a colour as a role-named asset first, and avoid names that collide with SwiftUI's own `Color` members (hence the primary colour stays in `AccentColor`, since `Primary` would clash with `Color.primary`).
  - The app follows the system Light/Dark setting. Each colorset has a light base value plus a Dark appearance; give new colours both. `AccentColor`, `OnLight` and `Scrim` are deliberately the same in both themes.
  - Chips and labels drawn on artwork (`CornerTag`, the Live card's badge and caption) apply `.environment(\.colorScheme, .dark)` so they stay dark on photos. The hero is the exception: it fades into the page background in both themes.
  - On page surfaces use `Theme.Palette.textPrimary.opacity(x)` rather than `Color.white.opacity(x)`, so it inverts in light mode.
  - The app's main accent is the red `AccentColor` asset, the only primary colour: `Theme.Palette.primary` reads it, and the selected tab, primary actions and the LIVE badge use it. Don't reference `Color(.accent)` directly. `Theme.Palette.highlight` is a secondary yellow highlight (asset `Highlight`).
  - Loading states are shimmer skeletons that mirror the real layout (`HomeLoadingView`, `MoviesLoadingView`), built from `SkeletonBlock` and `.shimmering()` in `DesignSystem/Skeleton.swift`. The hero skeleton shares `HeroCarouselView.height(inContainer:)` with the real hero.
  - To render a prototype page for comparison, open the file in headless Chrome with the page name as the URL hash, e.g. `…(9).html#VPlayed%20Home%20Mobile.html`. Chrome may not exit on its own because the page keeps animating.

## App icon

`VPlayed/Brand/AppIcon.icon` is an Icon Composer (Liquid Glass) document, referenced by `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`. It has two glass groups: `Play` (front, the yellow/green play triangle) and `V` (back, the red V with a darker fold). Both are vector SVGs in `Assets/`, all drawn on the same 1024×1024 canvas. Xcode builds flat fallback icons for iOS 17–18 automatically.

- Edit it in Icon Composer (`/Applications/Xcode.app/Contents/Applications/Icon Composer.app`) or directly via `icon.json`.
- Render a preview to check changes:
  ```bash
  "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" VPlayed/Brand/AppIcon.icon --export-image --output-file /tmp/icon.png --platform iOS --rendition Default --width 1024 --height 1024 --scale 1
  ```
  Other renditions include `Dark`, `ClearLight` and `TintedDark`.
- Icon Composer's SVG renderer ignores `clip-rule="evenodd"`. Build cut-outs by layering shapes in paint order, not with even-odd clip paths.

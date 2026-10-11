# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

VPlayed is a SwiftUI video app (App Store category `public.app-category.video`) with no third-party dependencies. `MyApp.swift` (`@main`) → `App/RootView.swift` → the Home screen. Home, Menu, Language and Movies are the only real screens so far; every other destination is a placeholder.

It is a native rewrite of the existing UIKit app at `/Users/balaji/Desktop/GSVplayed/Vplayed New`. Its source (`GudSho/`) is the reference for endpoints, headers, JSON keys and business rules, but nothing there compiles standalone (Alamofire, ObjectMapper, UIKit globals). Port logic into new Swift 6 code; never modify that project.

## Commits

Do not add a `Co-Authored-By: Claude …` trailer or any other Claude attribution to commit messages.

## Build

The app target is `VPlayed`. There is one shared scheme per environment (`Dev`, `Qa`, `Stage`, `Demo`; see Environments), and each also runs the `VPlayedTests` target (Swift Testing). Use `Dev` day to day. Build per platform:

```bash
xcodebuild -project VPlayed.xcodeproj -scheme Dev -destination 'generic/platform=iOS Simulator' build
xcodebuild -project VPlayed.xcodeproj -scheme Dev -destination 'generic/platform=macOS' build
xcodebuild -project VPlayed.xcodeproj -scheme Dev -destination 'generic/platform=visionOS Simulator' build
```

Run the tests, or a single suite or test:

```bash
xcodebuild test -project VPlayed.xcodeproj -scheme Dev -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test -project VPlayed.xcodeproj -scheme Dev -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:VPlayedTests/HomeViewModelTests
xcodebuild test -project VPlayed.xcodeproj -scheme Dev -destination 'platform=iOS Simulator,name=iPhone 17' '-only-testing:VPlayedTests/HomeViewModelTests/loadMoreAppendsDedupesAndStops()'
```

`VPlayedTests/` is also a synchronized folder; JSON in `VPlayedTests/Fixtures/` is real dev-API output, trimmed to two items per rail and stripped of studio contact/KYC fields.

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
- Stage's Home API currently returns only empty rails for a guest, so Stage's Home shows the hero and pages through ~39 empty pages.

## Project configuration that affects code

- **One multiplatform target** builds for iOS/iPadOS (min 17.0), macOS (min 26.0) and visionOS (min 26.0). iOS 17 is the floor, so APIs newer than iOS 17 need `if #available`. APIs exclusive to one platform (UIKit, AppKit, RealityKit) need `#if os(...)` guards, and changes should be built against all three destinations.
- **Swift 6 with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency.** Every type is implicitly `@MainActor` unless marked otherwise. Heavy or background work (decoding, file I/O, networking) must be explicitly `nonisolated` or `@concurrent`.
- **`MemberImportVisibility` is enabled.** Each file must `import` every module whose members it uses; transitive imports don't count.
- **File-system-synchronized groups.** Files added under `VPlayed/` are picked up by the target automatically, so `project.pbxproj` doesn't need editing to add sources or resources.
- **The Info.plist is generated** (`GENERATE_INFOPLIST_FILE = YES`). Add keys such as usage descriptions as `INFOPLIST_KEY_*` build settings in `project.pbxproj` (in both Debug and Release target configs).
  - The only exception is the launch screen. `VPlayed/Info.plist` holds just `UILaunchScreen` (the `SplashLogo` image on the `LaunchBackground` color; both have light and dark variants, the light logo being `SplashLogoLight.svg` with a dark wordmark), because there is no build setting for a launch image.
  - That plist is merged via `INFOPLIST_FILE` and excluded from the synchronized folder by a `PBXFileSystemSynchronizedBuildFileExceptionSet`. Keep that exception, or the build fails with duplicate Info.plist outputs.
- **Launch flow**:
  - The system launch screen shows the wordmark centered.
  - `App/SplashView.swift` then draws the same `SplashLogo` at the same spot (full-screen center, natural 288pt size), adds the prototype's glow, progress bar, tagline and "Skip intro", and fades out after 3s.
  - Home loads underneath meanwhile. If you change the logo size or position, change both.
- **The macOS build is sandboxed** with outgoing network access (`ENABLE_OUTGOING_NETWORK_CONNECTIONS`) and read-only access to user-selected files. Writing files or incoming connections need more entitlements.
- **Shapes and other SwiftUI protocol conformances used off the main actor** (e.g. `Shape`) must be declared `nonisolated struct`, or the build fails with a `ConformanceIsolation` error.

## Architecture

- **Networking (`Core/Networking`)**:
  - `APIClient.get(_:as:)` is a `@concurrent` URLSession GET that decodes the `{statusCode, message, response}` envelope.
  - Success means the JSON `statusCode == 200`, not the HTTP status, matching the UIKit app.
  - Endpoints live in `Endpoint.swift`; hosts in `APIEnvironment` (see Environments).
  - `RequestHeaders` sends the UIKit app's header set: `X-Request-Type: mobile`, `device_type: ios`, `device_id`, `app_version`, `X-Language-Code`. It adds `Authorization`, `profile_id` and `X-Bearer-Token` only when `SessionStore` holds them; nothing sets them yet because there is no sign-in.
  - Home APIs work as an anonymous guest.
- **Decoding**:
  - The API mixes types (`sho_type` Int or String, `video_duration` String, flags 0/1 or Bool, titles String or `{"en": …}`). Decode through the lenient helpers in `LenientDecoding.swift` (`lenientInt`, `lossyArray`, `LocalizedText`…) so one malformed item never fails a whole response.
  - Model structs are `nonisolated` so they decode off the main actor.
- **Images (`Core/Images`)**:
  - API image fields are relative keys joined to the CDN by `ImageURL.resolve`.
  - `ImageSet` variant codes (`tv`, `tp`, `tm`…) are sizes, not shapes. Video thumbnails are 16:9 but micro-series (`sho_type` 6) ones are 3:4, so each card picks its own variant order.
  - Quality: `ImageSet` prefers the `default` (JPEG/PNG) originals over `webp`, whose copies are compressed much harder. 16:9 cards (videos, series, promos, live) use `tc` first (≈1280–1567 px wide; `tl`/`to` go up to 3840). Micro-series portrait cards use `tp` first (700×922); their `tc` is only 231×307. Banners, posters and 2:3 thumbnails use `web` (= `Key`, the full size). Measured sizes are in the `ImageVariant` doc comment.
  - `RemoteImage` loads through `ImagePipeline`, an actor that de-duplicates requests, caches on disk and in memory, and downsamples with ImageIO.
  - Use `RemoteImage`, not `AsyncImage`.
- **Home (`Features/Home`)**:
  - Data comes from `GET mediaview/api/v1/homebanners` (hero) and `GET mediaview/api/v1/home?limit=3&inside_limit=10&page=N` (rails, paged by top-level `next`).
  - Each rail's `data` is polymorphic by `type`: 1/7 titles, 2/8 promos, 3 audio, 4/9 channels, 5 bulk plans, 6 live.
  - `HomeSection.layout` maps type + `is_top_ten` + micro-series to a prototype card style. Unknown types and empty rails are dropped.
  - `AccessTag` ports the UIKit card badge rules (`SeriesCollectionViewCell`).
  - `HomeViewModel` (`@Observable`) owns phases, refresh and de-duplicated pagination. It is held by `RootView` so Home doesn't reload after navigation.
- **Movies (`Features/Movies`)**, opened from Menu → Movies:
  - Data comes from `GET mediaview/api/v1/sho-details/media/1?page=N&limit=10&is_promo=true` (`Endpoint.media(shoType:page:)`; 2 is series, 6 micro-series). It is paged by top-level `next`, and `total` feeds the "N films" subtitle.
  - Items decode as `ContentItem` (`genre` comes from `default_genre.title`). `MoviesViewModel` mirrors `HomeViewModel`'s phases, refresh and de-duplicated paging.
  - The UI is an adaptive grid (two columns on iPhone) of `CardArtwork(url:aspectRatio:)` cards with the access tag, title and "Genre • duration".
  - The prototype's Genre / Language / Access / Sort chips are intentionally omitted, because the API has no filter or sort parameters.
- **Navigation**:
  - `RootView` hosts a system `TabView` (tabs in `AppTab`: Home, Promos, Subscription, then Search on the right as in the App Store), which gets the Liquid Glass tab bar on iOS 26+. Only Home is built; the other tabs show `PlaceholderDestinationView(tab:)`.
  - Each tab has its own `NavigationStack`. Views call `@Environment(\.openRoute)` with an `AppRoute`; `RootView` pushes it onto the selected tab's stack, except `.search`, which switches to the Search tab, and `.menu`.
  - `.menu` opens `MenuDrawer` (`Features/Menu`), a side drawer drawn above the `TabView` (tab bar included). It slides in from the leading edge (left in LTR, right in Arabic) to `min(82%, 340pt)` wide over a dimmed scrim. The scrim, the close button and a swipe towards that edge close it. Any other route opened while it is showing closes it and pushes onto the current tab.
  - In RTL, SwiftUI mirrors `offset` but not `DragGesture` translations, so the drawer converts the translation (`towardsTrailing`) and offsets with it unconverted.
  - Routes without a screen resolve to `PlaceholderDestinationView`. Add real screens by switching on the route in `navigationDestination`.
- **Localization**:
  - English is the development language. Arabic (`ar`, right-to-left), Portuguese (`pt`) and Tamil (`ta`) are listed in `knownRegions`, and every string lives in `VPlayed/Localizable.xcstrings`.
  - The app language is `AppLanguage` (`Core/Localization`). Users pick it in Menu (Home's leading toolbar button) → Language (`Features/Menu`), or in iOS Settings → VPlayed → Language. Both write the app's `AppleLanguages`, so they always agree.
  - Switching is live. `RootView` owns a `LanguageStore`, sets `\.locale` and `\.layoutDirection`, gives the `TabView` an `.id` so everything re-renders, and refreshes Home so API text comes back in the new language. Navigation paths live in `RootView`, so the user stays on the Language screen.
  - Literals passed to `Text`, `Label`, `Button` and `accessibilityLabel` are localized automatically. Strings built elsewhere (enum titles, error messages, route titles) need `String(localized: "…", bundle: .localized)`. `Bundle.main` only picks its language at launch; `Bundle.localized` is the current language's `.lproj`. View parameters that take UI text should be `LocalizedStringKey`. Add every new key's `ar`, `pt` and `ta` translations to the catalog. Find the exact keys in the build's `*.stringsdata` files, or let Xcode sync the catalog.
  - UIKit bars lay out in the launch language's direction, not SwiftUI's `layoutDirection`. So `LanguageStore` forces `UIView.appearance().semanticContentAttribute` before each switch (the `TabView` rebuild then creates fresh bars), and `HomeToolbar` uses `.topBarLeading` / `.topBarTrailing` rather than `.navigation` / `.primaryAction`, which ended up together on one side after popping back to Home following a switch between LTR and RTL languages.
  - Counts that need plural forms use catalog substitutions (see the `%@ followers %lld` key; Arabic has six plural categories).
  - `AppLanguage.current` also drives the API's `X-Language-Code` header and the `LocalizedText` choice.
  - RTL: layout mirrors automatically. Use `.forward` SF Symbols rather than `.right`, and `.flipsForRightToLeftLayoutDirection(true)` on directional gradients. Use `.letterSpacing(_:)` instead of `.tracking(_:)` for display text; it only tracks Latin-script languages, because tracking breaks Arabic joins and Tamil conjuncts.
  - Try a language with launch arguments, e.g. `xcrun simctl launch booted com.contus.vplayed -AppleLanguages "(ar)" -AppleLocale ar_SA`.
- **Liquid Glass (always)**:
  - Bars are system bars. Home's top bar is `HomeToolbar` (`HomeChrome.swift`): system toolbar items for the menu, the `SplashLogo` wordmark (`.sharedBackgroundVisibility(.hidden)`) and the bell. The feed `ScrollView` ignores the top safe area so the hero runs behind the glass bar (and the status bar), with `.softTopScrollEdge()` and a top fade in the hero scrims for legibility. The scrims are weaker in light mode (`ScrimTone`), where the near-white page colour would wash the art out.
  - Controls are glass, through `DesignSystem/Glass.swift`, never custom filled styles:
    - `glassButtonStyle()` for controls, and `glassButtonStyle(.prominent)` + `.tint(Theme.Palette.brand)` for the primary action;
    - `GlassCardButtonStyle(shape:padding:)` for Menu/Language rows;
    - `glassSurface(in:)` for floating chips;
    - `GlassGroup` to blend neighbouring glass.
  - The helpers hold all availability logic: iOS / macOS 26 get `.glass` / `.glassEffect`; iOS 17–18 get bordered styles or material; visionOS (no glass button styles) uses `.bordered`, which is glass there. Don't add `#available` checks in views.
  - Exceptions:
    - Home rail content (poster/promo/audio/channel cards, the Live card panel, rail titles) keeps its original surfaces and `PressableButtonStyle`; the user preferred it to glass. Buttons inside cards ("Watch Live", "Set reminder", "Explore bundles") are glass.
    - The hero's full-bleed background image tap stays plain, since an edge-to-edge photo has no shape for glass. "Watch now" is its glass action.
- **Design**:
  - `DesignSystem/Theme.swift` holds the tokens from the HTML prototype (`~/Downloads/VPlayed Complete Prototype (offline) (9).html`, page "VPlayed Home Mobile"): SF Pro, Material Symbols mapped to SF Symbols. The prototype is dark-only; the light values are our own.
  - Colours are colorsets in `Assets.xcassets/Colors`; `Theme.Palette` refers to them through generated asset symbols (`Color(.textPrimary)`). Add a colour as an asset first, and avoid names that collide with SwiftUI's own `Color` members (hence `AccentTeal`, not `Teal`).
  - The app follows the system Light/Dark setting. Each colorset has a light base value plus a Dark appearance; give new colours both. `Brand`, `BrandPressed`, `AccentColor`, `OnLight` and `Scrim` are deliberately the same in both themes.
  - Chips and labels drawn on artwork (`CornerTag`, the Live card's badge and caption) apply `.environment(\.colorScheme, .dark)` so they stay dark on photos. The hero is the exception: it fades into the page background in both themes.
  - On page surfaces use `Theme.Palette.textPrimary.opacity(x)` rather than `Color.white.opacity(x)`, so it inverts in light mode.
  - The app's main accent is the red `AccentColor` asset (the selected tab uses it). `Theme.Palette.accent` is a secondary yellow highlight (asset `AccentYellow`).
  - Loading states are shimmer skeletons that mirror the real layout (`HomeLoadingView`, `MoviesLoadingView`), built from `SkeletonBlock` and `.shimmering()` in `DesignSystem/Skeleton.swift`. The hero skeleton shares `HeroCarouselView.height(inContainer:)` with the real hero.
  - To render a prototype page for comparison, open the file in headless Chrome with the page name as the URL hash, e.g. `…(9).html#VPlayed%20Home%20Mobile.html`. Chrome may not exit on its own because the page keeps animating.

## App icon

`VPlayed/AppIcon.icon` is an Icon Composer (Liquid Glass) document, referenced by `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`. It has two glass groups: `Play` (front, the yellow/green play triangle) and `V` (back, the red V with a darker fold). Both are vector SVGs in `Assets/`, all drawn on the same 1024×1024 canvas. Xcode builds flat fallback icons for iOS 17–18 automatically.

- Edit it in Icon Composer (`/Applications/Xcode.app/Contents/Applications/Icon Composer.app`) or directly via `icon.json`.
- Render a preview to check changes:
  ```bash
  "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" VPlayed/AppIcon.icon --export-image --output-file /tmp/icon.png --platform iOS --rendition Default --width 1024 --height 1024 --scale 1
  ```
  Other renditions include `Dark`, `ClearLight` and `TintedDark`.
- Icon Composer's SVG renderer ignores `clip-rule="evenodd"`. Build cut-outs by layering shapes in paint order, not with even-odd clip paths.

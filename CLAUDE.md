# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

VPlayed is a SwiftUI video app (App Store category `public.app-category.video`) with no third-party dependencies. `MyApp.swift` (`@main`) → `App/RootView.swift` → the Home screen. Home is the only real screen so far; every other destination is a placeholder.

It is a native rewrite of the existing UIKit app at `/Users/balaji/Desktop/GSVplayed/Vplayed New`. Its source (`GudSho/`) is the reference for endpoints, headers, JSON keys and business rules, but nothing there compiles standalone (Alamofire, ObjectMapper, UIKit globals). Port logic into new Swift 6 code; never modify that project.

## Commits

Do not add a `Co-Authored-By: Claude …` trailer or any other Claude attribution to commit messages.

## Build

The app target and shared scheme are both named `VPlayed`; the `VPlayedTests` target (Swift Testing) runs from the same scheme. Build per platform:

```bash
xcodebuild -project VPlayed.xcodeproj -scheme VPlayed -destination 'generic/platform=iOS Simulator' build
xcodebuild -project VPlayed.xcodeproj -scheme VPlayed -destination 'generic/platform=macOS' build
xcodebuild -project VPlayed.xcodeproj -scheme VPlayed -destination 'generic/platform=visionOS Simulator' build
```

Run the tests, or a single suite or test:

```bash
xcodebuild test -project VPlayed.xcodeproj -scheme VPlayed -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test -project VPlayed.xcodeproj -scheme VPlayed -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:VPlayedTests/HomeViewModelTests
xcodebuild test -project VPlayed.xcodeproj -scheme VPlayed -destination 'platform=iOS Simulator,name=iPhone 17' '-only-testing:VPlayedTests/HomeViewModelTests/loadMoreAppendsDedupesAndStops()'
```

`VPlayedTests/` is also a synchronized folder; JSON in `VPlayedTests/Fixtures/` is real dev-API output, trimmed to two items per rail and stripped of studio contact/KYC fields.

## Project configuration that affects code

- **One multiplatform target** builds for iOS/iPadOS (min 17.0), macOS (min 26.0) and visionOS (min 26.0). iOS 17 is the floor, so APIs newer than iOS 17 need `if #available`. APIs exclusive to one platform (UIKit, AppKit, RealityKit) need `#if os(...)` guards, and changes should be built against all three destinations.
- **Swift 6 with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency.** Every type is implicitly `@MainActor` unless marked otherwise. Heavy or background work (decoding, file I/O, networking) must be explicitly `nonisolated` or `@concurrent`.
- **`MemberImportVisibility` is enabled.** Each file must `import` every module whose members it uses; transitive imports don't count.
- **File-system-synchronized groups.** Files added under `VPlayed/` are picked up by the target automatically, so `project.pbxproj` doesn't need editing to add sources or resources.
- **The Info.plist is generated** (`GENERATE_INFOPLIST_FILE = YES`). Add keys such as usage descriptions as `INFOPLIST_KEY_*` build settings in `project.pbxproj` (in both Debug and Release target configs).
  - The only exception is the launch screen. `VPlayed/Info.plist` holds just `UILaunchScreen` (the `SplashLogo` image on the `LaunchBackground` color), because there is no build setting for a launch image.
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
  - Endpoints live in `Endpoint.swift`; hosts in `APIEnvironment` (dev only for now).
  - `RequestHeaders` sends the UIKit app's header set: `X-Request-Type: mobile`, `device_type: ios`, `device_id`, `app_version`, `X-Language-Code`. It adds `Authorization`, `profile_id` and `X-Bearer-Token` only when `SessionStore` holds them; nothing sets them yet because there is no sign-in.
  - Home APIs work as an anonymous guest.
- **Decoding**:
  - The API mixes types (`sho_type` Int or String, `video_duration` String, flags 0/1 or Bool, titles String or `{"en": …}`). Decode through the lenient helpers in `LenientDecoding.swift` (`lenientInt`, `lossyArray`, `LocalizedText`…) so one malformed item never fails a whole response.
  - Model structs are `nonisolated` so they decode off the main actor.
- **Images (`Core/Images`)**:
  - API image fields are relative keys joined to the CDN by `ImageURL.resolve`.
  - `ImageSet` variant codes (`tv`, `tp`, `tm`…) are sizes, not shapes. Video thumbnails are 16:9 but micro-series (`sho_type` 6) ones are 3:4, so each card picks its own variant order.
  - `RemoteImage` loads through `ImagePipeline`, an actor that de-duplicates requests, caches on disk and in memory, and downsamples with ImageIO.
  - Use `RemoteImage`, not `AsyncImage`.
- **Home (`Features/Home`)**:
  - Data comes from `GET mediaview/api/v1/homebanners` (hero) and `GET mediaview/api/v1/home?limit=3&inside_limit=10&page=N` (rails, paged by top-level `next`).
  - Each rail's `data` is polymorphic by `type`: 1/7 titles, 2/8 promos, 3 audio, 4/9 channels, 5 bulk plans, 6 live.
  - `HomeSection.layout` maps type + `is_top_ten` + micro-series to a prototype card style. Unknown types and empty rails are dropped.
  - `AccessTag` ports the UIKit card badge rules (`SeriesCollectionViewCell`).
  - `HomeViewModel` (`@Observable`) owns phases, refresh and de-duplicated pagination. It is held by `RootView` so Home doesn't reload after navigation.
- **Navigation**:
  - `RootView` hosts a system `TabView` (tabs in `AppTab`: Home, Search, Promos, Subscription, Rewards), which gets the Liquid Glass tab bar on iOS 26+. Only Home is built; the other tabs show `PlaceholderDestinationView(tab:)`.
  - Each tab has its own `NavigationStack`. Views call `@Environment(\.openRoute)` with an `AppRoute`; `RootView` pushes it onto the selected tab's stack, except `.search`, which switches to the Search tab.
  - Every route currently resolves to `PlaceholderDestinationView`. Add real screens by switching on the route in `navigationDestination`.
- **Design**:
  - `DesignSystem/Theme.swift` holds the tokens from the HTML prototype (`~/Downloads/VPlayed Complete Prototype (offline) (9).html`, page "VPlayed Home Mobile"): dark theme only, SF Pro, Material Symbols mapped to SF Symbols.
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

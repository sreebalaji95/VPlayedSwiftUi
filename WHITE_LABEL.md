# White-label guide

This guide is for teams that fork VPlayed to ship it under another brand. A rebrand changes the **identity, colours, wordmark, app icon and brand copy** listed below. It does not touch networking, decoding, navigation or view models. If a branding change seems to need an edit outside the files named here, treat that as a gap: raise it with the core team rather than patching around it.

The app is SwiftUI only: no storyboards, no XIBs, no third-party dependencies. It builds for iOS/iPadOS 17+, macOS 26 and visionOS 26 from one target, with four schemes (`Dev`, `Qa`, `Stage`, `Demo`).

## Quick start

Almost everything a rebrand replaces is in one folder, [`VPlayed/Brand/`](VPlayed/Brand), plus [`Config/Brand.xcconfig`](Config/Brand.xcconfig) and a few keys in the string catalog. The `Brand` folder holds `Brand.swift`, `Assets.xcassets` (colours and wordmark), `AppIcon.icon` and, if you add a typeface, `Fonts/`.

1. Set your identity in [`Config/Brand.xcconfig`](Config/Brand.xcconfig).
2. Recolour the colorsets in [`VPlayed/Brand/Assets.xcassets`](VPlayed/Brand/Assets.xcassets).
3. Replace the wordmark SVGs in `VPlayed/Brand/Assets.xcassets/SplashLogo.imageset`.
4. Replace the app icon, [`VPlayed/Brand/AppIcon.icon`](VPlayed/Brand/AppIcon.icon), in Icon Composer.
5. Set the product name and, optionally, a typeface in [`VPlayed/Brand/Brand.swift`](VPlayed/Brand/Brand.swift). Set the tagline in the string catalog.
6. Point [`APIEnvironment.swift`](VPlayed/Core/Networking/APIEnvironment.swift) at your backend, but only if your brand has its own API tenant.
7. Validate: see [Validation](#validation).

## Editable areas

### Identity: `Config/Brand.xcconfig`

Every scheme and both targets read this file. Don't set these keys in the project's build settings, or they override it.

| Key | Today | Becomes |
|---|---|---|
| `BRAND_BUNDLE_ID` | `com.contus.vplayed` | Bundle IDs: `.dev`, `.qa`, `.stage` suffixes; Demo uses it as is; tests add `.tests` |
| `BRAND_DISPLAY_NAME` | `VPlayed` | Home-screen names: `DevVPlayed`, `QaVPlayed`, `StageVPlayed`, `VPlayed` (Demo) |
| `DEVELOPMENT_TEAM` | `G44VFA67ZG` | Signing team for all configurations |
| `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` | `1.0.0` / `1` | Version and build number |

### Colours: `VPlayed/Brand/Assets.xcassets`

Views never use raw colours. They read `Theme.Palette` ([`DesignSystem/Theme.swift`](VPlayed/DesignSystem/Theme.swift)), which reads these colorsets through Xcode's generated asset symbols. So:

- **Edit values, never names.** A renamed or deleted colorset fails the build, by design.
- **Give each colour a light value and a Dark appearance.** The ones marked *one value* are the same in both themes in VPlayed. `AccentColor` and `OnPrimary` may still get a Dark appearance if your brand needs it (see the light-primary pitfall below). `Scrim` and `OnLight` should stay single dark values.

| Colorset | Theme name | Role and where it shows |
|---|---|---|
| `AccentColor` *(one value)* | `primary` | The primary colour, both as a fill ("Watch now", "Watch Live", retry buttons, the LIVE badge) and as text and icons on the page (the selected tab, the Language checkmark), plus the splash glow and the start of the splash bar, the fallback tint of bulk-purchase cards |
| `Colors/OnPrimary` *(one value)* | `onPrimary` | Text and icons on the primary colour. White suits a dark primary. **If your primary is light, make this dark.** |
| `Colors/Highlight` | `highlight` | Secondary highlight: crown and price tags on cards, the hero's category dot and active page dot, the end of the splash bar, the music-note icon |
| `Colors/Background` | `background` | Page background, and the launch screen's; the hero artwork fades into it |
| `Colors/Surface` | `surface` | Card backgrounds (Live, channel and bulk-purchase cards) |
| `Colors/Raised` | `raised` | Image placeholders, skeleton loaders, toasts, icon tiles |
| `Colors/FillStrong` | `fillStrong` | Failed-image fill; crown tag gradient |
| `Colors/TextPrimary`, `TextSecondary`, `TextTertiary` | `text…` | Text, from most to least prominent |
| `Colors/Line`, `LineStrong` | `line`, `lineStrong` | Hairline borders; `LineStrong` is the more visible one (toast border, rank numerals) |
| `Colors/Scrim` *(one value)* | `scrim` | Dark overlay behind text on artwork, and the menu's dimming. Keep it dark. |
| `Colors/ShimmerHighlight` | `shimmer` | The sweep across skeleton loaders |
| `Colors/OnLight` *(one value)* | `onLight` | Dark icon on light fills (the bulk-purchase icon tile) |

Chips drawn on artwork (card corner tags, the Live card's badge and caption) always use the **Dark** values of their colours (`Highlight`, `Scrim`, `FillStrong`, `Background`, `TextSecondary`, `LineStrong`), even in light mode. Check those Dark values over bright artwork.

### Wordmark: `VPlayed/Brand/Assets.xcassets/SplashLogo.imageset`

One asset serves the launch screen, the animated splash, the Home toolbar and the menu header.

- `SplashLogoLight.svg` is the light-mode version (dark lettering). `SplashLogo.svg` is the dark-mode version (light lettering). Keep both vector, and keep the file names.
- **Declare `width` and `height` on the root `<svg>`.** The launch screen draws the logo at exactly that size in points, centred on the screen. Today's is 288 × 75.43. The splash re-draws it at the same size and hangs its progress bar and tagline 28pt below it, so a logo of any shape works without code changes.
- The toolbar and menu scale it to 26pt high (`Theme.Layout.headerLogoHeight`).

### App icon: `VPlayed/Brand/AppIcon.icon`

This is an Icon Composer (Liquid Glass) document with two glass groups, `Play` (front) and `V` (back). Each group is an SVG in `Assets/` drawn on the same 1024 × 1024 canvas, and `icon.json` sets the light and dark background fill. Edit it with `/Applications/Xcode.app/Contents/Applications/Icon Composer.app`. Xcode generates the flat icons for iOS 17–18 itself.

- You can also replace `Assets/V.svg` and `Assets/Play.svg` directly. Keep the file names, draw on the 1024 × 1024 canvas, and change the background `solid` colours in `icon.json`.
- Icon Composer ignores `clip-rule="evenodd"`. Build cut-outs by layering shapes in paint order.
- To preview a rendition:
  ```bash
  "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" VPlayed/Brand/AppIcon.icon --export-image --output-file /tmp/icon.png --platform iOS --rendition Default --width 1024 --height 1024 --scale 1
  ```
  Other renditions: `Dark`, `ClearLight`, `TintedDark`.

### Typeface

Text uses SF Pro unless you set a brand typeface:

1. Put the font files (`.ttf`, `.otf` or `.ttc`) in `VPlayed/Brand/Fonts/`. Use one file per weight, or a variable font. The folder is part of the app target automatically, so you don't need to edit the project or Info.plist; the app registers every bundled font at launch.
2. Set `Brand.fontFamily` to the typeface's **family name** as it appears in Font Book, for example `"Inter"`, not a file name or PostScript name.

Every text style then uses that family. Each style picks the face nearest to its weight (regular, medium, semibold, bold, heavy), so ship at least regular and bold. The sizes and weights themselves are the core team's, in `Theme.Typography`.

- **Scripts:** characters the typeface lacks fall back to the system font automatically. A Latin-only typeface therefore shows Arabic and Tamil in SF, which is usually what you want. Check those languages if your typeface covers them.
- **System bars:** the tab bar and navigation titles stay in the system font.
- **Licence:** make sure the font's licence allows embedding in an app.
- `BrandTests/brandTypefaceIsAvailable()` fails if the family named in `Brand.fontFamily` isn't installed.

### Brand name and copy

- `Brand.name` in [`VPlayed/Brand/Brand.swift`](VPlayed/Brand/Brand.swift) is the product name people see. It is the wordmark's VoiceOver label, and it fills the `%@` in the messages below. It is not translated.
- Copy in [`VPlayed/Localizable.xcstrings`](VPlayed/Localizable.xcstrings) that is about the brand. Every string needs English, Arabic (`ar`), Portuguese (`pt`) and Tamil (`ta`). **To reword the English, give the key an English (`en`) value in the catalog; don't change the key itself**, because that's what the code looks it up by. For example, setting `en` of `Stream the experience` to "Watch it together" changes the tagline with no code edit.

| Key | Where |
|---|---|
| `Stream the experience` | Splash tagline (shown in capitals in Latin scripts) |
| `We couldn't reach %@. Please try again.` | Network error message |
| `Titles and descriptions from %@ also switch when they're available in that language.` | Footnote on the Language screen |

### Backend: `VPlayed/Core/Networking/APIEnvironment.swift`

This file holds the API host and image bucket per environment. Edit it only if your brand has its own backend tenant. Dev, Qa, Stage and Demo each pick theirs at compile time.

## Shared styles: change through tokens only

These are owned by the core team. Brands get their look from the tokens above, so don't edit these files to rebrand.

- [`DesignSystem/Theme.swift`](VPlayed/DesignSystem/Theme.swift): palette, typography roles (sizes and weights), corner radii, spacing.
- [`DesignSystem/Glass.swift`](VPlayed/DesignSystem/Glass.swift): Liquid Glass buttons and surfaces, with all the iOS 17–18 and visionOS fallbacks. Primary actions use `glassButtonStyle(.primary)`, which alone sets their `primary` tint and `onPrimary` label.
- [`DesignSystem/BrandWordmark.swift`](VPlayed/DesignSystem/BrandWordmark.swift), [`Skeleton.swift`](VPlayed/DesignSystem/Skeleton.swift), [`LetterSpacing.swift`](VPlayed/DesignSystem/LetterSpacing.swift).
- Card layouts in `Features/**/Views`. Card sizes and aspect ratios match the API's image variants (`Core/Images/ImageSet.swift`), so don't change them.

## Protected areas

No branding change needs these.

| Area | Files |
|---|---|
| API and session | `Core/Networking/` (`APIClient`, `Endpoint`, `RequestHeaders`, `SessionStore`, `LenientDecoding`, `APIError`) |
| Device ID | `Core/Networking/DeviceID.swift`. Its Keychain service name must stay as it is; changing it resets every install's device ID. |
| Images | `Core/Images/` (`ImagePipeline`, `ImageSet`, `RemoteImage`) |
| Business rules and data | `Features/*/*ViewModel.swift`, `*Service.swift`, `Features/Home/Models/` (`AccessTag`, `HomeSection`, content models) |
| Navigation | `App/RootView.swift`, `App/AppRoute.swift`, `Features/Menu/MenuDrawer.swift` |
| Localization plumbing | `Core/Localization/` |
| Launch plumbing | `VPlayed/Info.plist` (launch screen keys only) and its exception in the project file |

Tab titles and symbols in `App/AppTab.swift` may be changed with care. Titles need all four languages.

## Validation

Run these after every rebrand.

1. **Build every scheme and platform.** Repeat with `-scheme Qa`, `Stage` and `Demo`:
   ```bash
   xcodebuild -project VPlayed.xcodeproj -scheme Dev -destination 'generic/platform=iOS Simulator' build
   xcodebuild -project VPlayed.xcodeproj -scheme Dev -destination 'generic/platform=macOS' build
   xcodebuild -project VPlayed.xcodeproj -scheme Dev -destination 'generic/platform=visionOS Simulator' build
   ```
2. **Run the tests:**
   ```bash
   xcodebuild test -project VPlayed.xcodeproj -scheme Dev -destination 'platform=iOS Simulator,name=iPhone 17'
   ```
3. **Check the launch screen.** **Delete the app first**, because iOS caches launch screens. On a fresh install, the wordmark must not jump when the launch screen hands over to the animated splash.
4. **Look at every screen in light and dark, in English, Arabic (right-to-left) and Tamil, on iPhone and iPad.** Screens: splash, Home (hero, then every rail: landscape, portrait, the two top-10 styles, promos, music, channels, live, bulk purchase), menu, Language, Movies, and the error and empty states (turn off the network). Try another language with launch arguments, for example:
   ```bash
   xcrun simctl launch booted com.contus.vplayed.dev -AppleLanguages "(ar)" -AppleLocale ar_SA
   ```
   Use your own bundle ID.
5. **Check contrast:** `onPrimary` on `AccentColor`, text on `Background` and `Surface`, and the corner tags over bright artwork.

## Known pitfalls

- **A light primary colour** (lime, yellow, pastel) needs a dark `OnPrimary`. It also needs a darker **light-mode** appearance on `AccentColor`, because the primary draws the selected tab and the Language checkmark directly on the page, and lime on the near-white tab bar is unreadable. Keep `OnPrimary` readable on both values. Glass buttons are tinted with the primary, so check very pale or very saturated primaries in both themes.
- **The hero's fades are tuned to `Background`.** A background with a very different lightness or hue may make the hero artwork look washed out or muddy. Raise it with the core team if so; the strengths live in `ScrimTone` in `HeroCarouselView.swift`.
- **Don't put hex colours or `.white` in views.** If a new colour is needed, add a colorset, give it a role in `Theme.Palette`, and give it a Dark appearance.

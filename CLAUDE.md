# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

VPlayed is a SwiftUI video app (App Store category `public.app-category.video`) at an early scaffold stage: `MyApp.swift` (`@main`) → `ContentView.swift`. There are no dependencies, packages, or test targets yet.

## Commits

Do not add a `Co-Authored-By: Claude …` trailer or any other Claude attribution to commit messages.

## Build

Single target and scheme, both named `VPlayed`. Build per platform:

```bash
xcodebuild -project VPlayed.xcodeproj -scheme VPlayed -destination 'generic/platform=iOS Simulator' build
xcodebuild -project VPlayed.xcodeproj -scheme VPlayed -destination 'generic/platform=macOS' build
xcodebuild -project VPlayed.xcodeproj -scheme VPlayed -destination 'generic/platform=visionOS Simulator' build
```

There is no test target, so `xcodebuild test` will not work until one is added.

## Project configuration that affects code

- **One multiplatform target** builds for iOS/iPadOS (min 17.0), macOS (min 26.0) and visionOS (min 26.0). iOS 17 is the floor, so APIs newer than iOS 17 need `if #available`. APIs exclusive to one platform (UIKit, AppKit, RealityKit) need `#if os(...)` guards, and changes should be built against all three destinations.
- **Swift 6 with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency.** Every type is implicitly `@MainActor` unless marked otherwise. Heavy or background work (decoding, file I/O, networking) must be explicitly `nonisolated` or `@concurrent`.
- **`MemberImportVisibility` is enabled.** Each file must `import` every module whose members it uses; transitive imports don't count.
- **File-system-synchronized groups.** Files added under `VPlayed/` are picked up by the target automatically, so `project.pbxproj` doesn't need editing to add sources or resources.
- **The Info.plist is generated** (`GENERATE_INFOPLIST_FILE = YES`). Add keys such as usage descriptions as `INFOPLIST_KEY_*` build settings in `project.pbxproj` (in both Debug and Release target configs), not as a plist file.
- **The macOS build is sandboxed** with read-only access to user-selected files (`ENABLE_USER_SELECTED_FILES = readonly`). Writing files, or using network access on macOS, requires changing entitlements and build settings.

## App icon

`VPlayed/AppIcon.icon` is an Icon Composer (Liquid Glass) document, referenced by `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`. It has two glass groups: `Play` (front, the yellow/green play triangle) and `V` (back, the red V with a darker fold). Both are vector SVGs in `Assets/`, all drawn on the same 1024×1024 canvas. Xcode builds flat fallback icons for iOS 17–18 automatically.

- Edit it in Icon Composer (`/Applications/Xcode.app/Contents/Applications/Icon Composer.app`) or directly via `icon.json`.
- Render a preview to check changes:
  ```bash
  "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" VPlayed/AppIcon.icon --export-image --output-file /tmp/icon.png --platform iOS --rendition Default --width 1024 --height 1024 --scale 1
  ```
  Other renditions include `Dark`, `ClearLight` and `TintedDark`.
- Icon Composer's SVG renderer ignores `clip-rule="evenodd"`. Build cut-outs by layering shapes in paint order, not with even-odd clip paths.

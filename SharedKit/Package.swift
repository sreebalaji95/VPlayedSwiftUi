// swift-tools-version: 6.0
// Local package that exposes the Kotlin Multiplatform shared layer (../kmp) to the VPlayed target.
// Shared.xcframework is a build product, not source: create it with scripts/build-shared.sh.
import PackageDescription

let package = Package(
    name: "SharedKit",
    platforms: [.iOS(.v17), .macOS(.v15)],
    products: [
        .library(name: "SharedKit", targets: ["Shared"]),
    ],
    targets: [
        // iOS device, iOS simulator and macOS (Apple silicon) slices. Kotlin/Native has no visionOS
        // target, so the app links this only for iOS and macOS (platform filter in the project).
        .binaryTarget(name: "Shared", path: "Shared.xcframework"),
    ]
)

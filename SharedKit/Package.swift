// swift-tools-version: 6.0
// Local package that exposes the Kotlin Multiplatform shared layer (../kmp) to the VPlayed target.
// Shared.xcframework is a build product, not source: create it with scripts/build-shared.sh.
import PackageDescription

let package = Package(
    name: "SharedKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "SharedKit", targets: ["Shared"]),
    ],
    targets: [
        // iOS device and simulator slices. On Mac and Apple Vision Pro the app runs as the iPad app
        // ("Designed for iPad"), which uses the device slice.
        .binaryTarget(name: "Shared", path: "Shared.xcframework"),
    ]
)

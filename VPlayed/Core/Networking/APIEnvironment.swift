import Foundation

/// Server hosts per environment, mirroring the UIKit app (`GudSho/AppDelegate.swift`,
/// `setup…Environment()`). The `Dev`, `Qa`, `Stage` and `Demo` schemes build with the matching
/// `DEV` / `QA` / `STAGE` / `DEMO` compilation condition; with none, it falls back to Dev.
nonisolated struct APIEnvironment: Sendable {
    let apiBaseURL: URL
    let imageBaseURL: URL
    /// The website, for pages the app links to (terms, privacy policy); UIKit's `BuildConfig.shareUrl`.
    let webBaseURL: URL

    static let development = APIEnvironment(
        apiBaseURL: URL(string: "https://api-devgs.vplayed.com/")!,
        imageBaseURL: URL(string: "https://gsvp-dev.s3.ap-south-1.amazonaws.com/")!,
        webBaseURL: URL(string: "https://devgs.vplayed.com/")!
    )

    static let qa = APIEnvironment(
        apiBaseURL: URL(string: "https://api-qags.vplayed.com/")!,
        imageBaseURL: URL(string: "https://gsvp-qa.s3.ap-south-1.amazonaws.com/")!,
        webBaseURL: URL(string: "https://qags.vplayed.com/")!
    )

    /// Staging serves its images from the QA bucket, as in the UIKit app.
    static let staging = APIEnvironment(
        apiBaseURL: URL(string: "https://api-stagings.vplayed.com/")!,
        imageBaseURL: URL(string: "https://gsvp-qa.s3.ap-south-1.amazonaws.com/")!,
        webBaseURL: URL(string: "https://staginggs.vplayed.com/")!
    )

    /// The UIKit app's PROD build, which points at the demo hosts.
    static let demo = APIEnvironment(
        apiBaseURL: URL(string: "https://api-demogs.vplayed.com/")!,
        imageBaseURL: URL(string: "https://gsvp-demo.s3.ap-south-1.amazonaws.com/")!,
        webBaseURL: URL(string: "https://demogs.vplayed.com/")!
    )

    #if DEMO
    static let current = demo
    #elseif STAGE
    static let current = staging
    #elseif QA
    static let current = qa
    #else
    static let current = development
    #endif
}

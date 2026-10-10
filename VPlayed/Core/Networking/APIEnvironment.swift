import Foundation

/// Server hosts per environment. Values mirror the DEV entry of the existing UIKit app
/// (`GudSho/AppDelegate.swift` environment setup).
nonisolated struct APIEnvironment: Sendable {
    let apiBaseURL: URL
    let imageBaseURL: URL

    static let development = APIEnvironment(
        apiBaseURL: URL(string: "https://api-devgs.vplayed.com/")!,
        imageBaseURL: URL(string: "https://gsvp-dev.s3.ap-south-1.amazonaws.com/")!
    )

    static let current = development
}

import Foundation
// FirebaseCore comes with the FirebaseAuth product; its types are not Sendable.
@preconcurrency import FirebaseCore

/// The sign-in providers' client settings for this build: Google's OAuth client ID and the Firebase
/// app that sends phone sign-in codes. They come from `Config/Secrets.xcconfig` through Info.plist
/// keys (like `VPlayedTransportKey`), never from source, else from a bundled
/// `GoogleService-Info.plist` (`CLIENT_ID`, read through Firebase). A missing value turns its feature
/// off: no Google button, and email sign-in when the backend asks for phone verification.
nonisolated struct AuthProviderConfig: Sendable {
    struct Firebase: Sendable {
        let apiKey: String
        let appID: String
        let senderID: String
        let projectID: String
    }

    let googleClientID: String?
    let firebase: Firebase?

    static let current = AuthProviderConfig(bundle: .main)

    /// The client ID Google Sign-In can use: the build setting, else `GoogleService-Info.plist`'s
    /// `CLIENT_ID`. Nil unless its reversed form is a registered URL scheme
    /// (`VPLAYED_GOOGLE_URL_SCHEME`), since Google Sign-In stops the app without one.
    var googleSignInClientID: String? {
        guard let clientID = googleClientID ?? FirebaseApp.app()?.options.clientID else { return nil }
        let reversed = clientID.components(separatedBy: ".").reversed().joined(separator: ".")
        return Self.isURLSchemeRegistered(reversed) ? clientID : nil
    }

    /// Whether Info.plist registers [scheme] (case-insensitive) under `CFBundleURLTypes`.
    static func isURLSchemeRegistered(_ scheme: String, bundle: Bundle = .main) -> Bool {
        let urlTypes = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        return urlTypes
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
            .contains { $0.caseInsensitiveCompare(scheme) == .orderedSame }
    }

    init(googleClientID: String?, firebase: Firebase?) {
        self.googleClientID = googleClientID
        self.firebase = firebase
    }

    init(bundle: Bundle) {
        func value(_ key: String) -> String? {
            let text = (bundle.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespaces)
            // An unset build setting arrives empty, or unexpanded when the plist is not processed.
            guard let text, !text.isEmpty, !text.hasPrefix("$(") else { return nil }
            return text
        }
        googleClientID = value("VPlayedGoogleClientID")
        if let apiKey = value("VPlayedFirebaseAPIKey"), let appID = value("VPlayedFirebaseAppID"),
           let senderID = value("VPlayedFirebaseSenderID"), let projectID = value("VPlayedFirebaseProjectID") {
            firebase = Firebase(apiKey: apiKey, appID: appID, senderID: senderID, projectID: projectID)
        } else {
            firebase = nil
        }
    }
}

/// Starts Firebase from `AuthProviderConfig` (per-environment build settings), else from a bundled
/// `GoogleService-Info.plist` when there is one. Does nothing without either.
nonisolated enum FirebaseBootstrap {
    /// True once Firebase is running.
    static var isConfigured: Bool { FirebaseApp.app() != nil }

    /// Phone sign-in can run: Firebase is running and the app registers the URL scheme its
    /// reCAPTCHA check returns through (without it Firebase stops the app with a fatal error).
    static var isPhoneSignInReady: Bool {
        guard let options = FirebaseApp.app()?.options else { return false }
        // Firebase's rule: the reversed client ID when registered, else `app-<GOOGLE_APP_ID with dashes>`.
        if let clientID = options.clientID,
           AuthProviderConfig.isURLSchemeRegistered(clientID.components(separatedBy: ".").reversed().joined(separator: ".")) {
            return true
        }
        return AuthProviderConfig.isURLSchemeRegistered("app-\(options.googleAppID.replacingOccurrences(of: ":", with: "-"))")
    }

    /// Call once, at launch, before any Firebase API (`AppDelegate`).
    static func configure(_ config: AuthProviderConfig = .current) {
        guard !isConfigured else { return }
        if let firebase = config.firebase {
            let options = FirebaseOptions(googleAppID: firebase.appID, gcmSenderID: firebase.senderID)
            options.apiKey = firebase.apiKey
            options.projectID = firebase.projectID
            if let bundleID = Bundle.main.bundleIdentifier { options.bundleID = bundleID }
            FirebaseApp.configure(options: options)
        } else if let options = FirebaseOptions.defaultOptions() {
            // A `GoogleService-Info.plist` in the app bundle.
            FirebaseApp.configure(options: options)
        }
    }
}

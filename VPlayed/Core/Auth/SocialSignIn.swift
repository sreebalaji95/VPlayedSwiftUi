import AuthenticationServices
import Foundation
import UIKit
// Firebase, Google and Kotlin types are not Sendable; everything here runs on the main actor.
@preconcurrency import FirebaseAuth
@preconcurrency import GoogleSignIn
@preconcurrency import Shared

/// What a provider's sign-in sheet ended with.
enum SocialSignInOutcome {
    case credential(SocialCredential)
    /// The user closed the sheet: nothing to report.
    case cancelled
    case failed
}

/// The platform half of Google and Apple sign-in: runs the provider's sheet and returns what the
/// shared `SocialLoginController` sends to `auth/login`. Tests pass a mock.
protocol SocialSigningIn {
    var isGoogleAvailable: Bool { get }
    func google() async -> SocialSignInOutcome
    func apple() async -> SocialSignInOutcome
}

/// Google Sign-In and Sign in with Apple, filled in as the UIKit app does
/// (`SocialLoginDelegateHelpers`): Google sends its OAuth access token as `id_token`, Apple its
/// identity token. Apple shares the email and name only on the first sign-in, so they are kept in
/// the Keychain for later ones.
final class LiveSocialSignIn: SocialSigningIn {
    private let config: AuthProviderConfig
    private var appleCoordinator: AppleSignInCoordinator?

    init(config: AuthProviderConfig = .current) {
        self.config = config
    }

    var isGoogleAvailable: Bool { config.googleSignInClientID != nil }

    func google() async -> SocialSignInOutcome {
        guard let clientID = config.googleSignInClientID, let presenter = UIApplication.shared.topViewController else { return .failed }
        let signIn = GIDSignIn.sharedInstance
        signIn.configuration = GIDConfiguration(clientID: clientID)
        do {
            let user = try await signIn.signIn(withPresenting: presenter).user
            // Only the token is needed; don't keep a Google session on the device.
            defer { signIn.signOut() }
            return .credential(SocialCredential(
                provider: .google,
                socialUserId: user.userID ?? "",
                token: user.accessToken.tokenString,
                email: user.profile?.email,
                name: user.profile?.name,
                pictureUrl: user.profile?.imageURL(withDimension: 120)?.absoluteString
            ))
        } catch {
            let error = error as NSError
            let cancelled = error.domain == kGIDSignInErrorDomain && error.code == GIDSignInError.Code.canceled.rawValue
            return cancelled ? .cancelled : .failed
        }
    }

    func apple() async -> SocialSignInOutcome {
        let coordinator = AppleSignInCoordinator()
        appleCoordinator = coordinator
        defer { appleCoordinator = nil }
        return await coordinator.run()
    }
}

/// Runs one Sign in with Apple request.
private final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    private static let emailItem = KeychainItem(account: "appleEmail")
    private static let nameItem = KeychainItem(account: "appleUserName")

    private var continuation: CheckedContinuation<SocialSignInOutcome, Never>?

    func run() async -> SocialSignInOutcome {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.foregroundKeyWindow ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            finish(.failed)
            return
        }
        let email = credential.email ?? JwtClaims.shared.string(token: token, claim: "email") ?? Self.stored(Self.emailItem)
        let given = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
        let name = given.isEmpty ? Self.stored(Self.nameItem) : given
        if let email { Self.emailItem.save(Data(email.utf8)) }
        if !given.isEmpty { Self.nameItem.save(Data(given.utf8)) }
        finish(.credential(SocialCredential(
            provider: .apple,
            socialUserId: credential.user,
            token: token,
            email: email,
            name: name,
            pictureUrl: nil
        )))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        let cancelled = (error as? ASAuthorizationError)?.code == .canceled
        finish(cancelled ? .cancelled : .failed)
    }

    private func finish(_ outcome: SocialSignInOutcome) {
        continuation?.resume(returning: outcome)
        continuation = nil
    }

    private static func stored(_ item: KeychainItem) -> String? {
        item.load().flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// URLs the sign-in providers send back to the app: Google's OAuth redirect and Firebase's
/// reCAPTCHA return for phone sign-in. `MyApp` passes every opened URL here.
enum AuthURLHandler {
    @discardableResult
    static func handle(_ url: URL) -> Bool {
        if GIDSignIn.sharedInstance.handle(url) { return true }
        return FirebaseBootstrap.isConfigured && Auth.auth().canHandle(url)
    }
}

extension UIApplication {
    /// The foreground key window, for presenting provider sheets.
    var foregroundKeyWindow: UIWindow? {
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
    }

    /// The view controller on top (Login is a full-screen cover), for providers that present from one.
    var topViewController: UIViewController? {
        var top = foregroundKeyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

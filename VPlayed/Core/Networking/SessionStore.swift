import Foundation

/// Holds per-session request credentials. Nothing populates these yet (no sign-in flow),
/// so requests go out as an anonymous guest, which the Home APIs allow.
actor SessionStore {
    static let shared = SessionStore()

    struct Snapshot: Sendable {
        var accessToken: String?
        var profileID: String?
        var geoToken: String?
    }

    private var snapshot = Snapshot()

    func current() -> Snapshot { snapshot }

    func update(_ change: @Sendable (inout Snapshot) -> Void) {
        change(&snapshot)
    }
}

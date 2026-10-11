import Foundation

/// Common headers sent with every API request, ported from the UIKit app's
/// `NetworkRequest.httpHeader` (`GudSho/Network/Network.swift`).
nonisolated struct RequestHeaders: Sendable {
    var session: SessionStore = .shared
    var deviceID: String = DeviceID.current
    var appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    var languageCode: @Sendable () -> String = { AppLanguage.current.rawValue }

    func values() async -> [String: String] {
        let credentials = await session.current()
        var headers = [
            "Accept": "application/json",
            "Content-Type": "application/json",
            "device_id": deviceID,
            "app_version": appVersion,
            "X-Request-Type": "mobile",
            "device_type": "ios",
            "X-Language-Code": languageCode(),
        ]
        if let profileID = credentials.profileID, !profileID.isEmpty {
            headers["profile_id"] = profileID
        }
        if let token = credentials.accessToken, !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
        }
        if let geoToken = credentials.geoToken, !geoToken.isEmpty {
            headers["X-Bearer-Token"] = geoToken
        }
        return headers
    }
}

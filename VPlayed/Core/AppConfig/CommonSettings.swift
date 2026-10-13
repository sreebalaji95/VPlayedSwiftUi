import Foundation

/// App-wide settings from `GET mediaview/api/v1/common`, ported from the UIKit app's
/// `CommonKeysStruct` plus the payment flags and update details it reads from the same response
/// (`SceneDelegate.getCommonKeys`, `AppUpdateConfig`). Missing or malformed keys fall back to the
/// UIKit defaults instead of failing the response.
nonisolated struct CommonSettings: Decodable, Sendable, Equatable {
    /// Which catalogue the backend serves (`AppContentType` in the UIKit app).
    enum ContentLibrary: Int, Sendable {
        case vodDrama = 0
        case vod = 1
        case drama = 2
    }

    /// How sign-up codes are verified (`LoginType` in the UIKit app).
    enum VerificationMethod: String, Sendable {
        case email
        case phone
        case mobile
    }

    /// iOS force/soft update settings from `force_update_details`. Stored only; nothing prompts yet.
    struct UpdateDetails: Decodable, Sendable, Equatable {
        var isForceUpdateEnabled: Bool
        var minimumVersion: String?
        var forceUpdateMessage: String?
        var isSoftUpdateEnabled: Bool
        var latestVersion: String?
        var softUpdateMessage: String?

        private enum CodingKeys: String, CodingKey {
            case forceUpdate = "force_update"
            case minimumVersion = "minimum_version"
            case forceUpdateMessage = "force_update_message"
            case softUpdate = "soft_update"
            case latestVersion = "latest_version"
            case softUpdateMessage = "soft_update_message"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            isForceUpdateEnabled = container.lenientBool(.forceUpdate) ?? false
            minimumVersion = container.lenientString(.minimumVersion)
            forceUpdateMessage = container.lenientString(.forceUpdateMessage)
            isSoftUpdateEnabled = container.lenientBool(.softUpdate) ?? false
            latestVersion = container.lenientString(.latestVersion)
            softUpdateMessage = container.lenientString(.softUpdateMessage)
        }
    }

    /// `nil` means the key was absent; the UIKit app only acts on an explicit `false`.
    var isRTLAllowed: Bool?
    var isPiPAllowed: Bool?
    var isCastingAllowed: Bool?
    var isScreenRecordingAllowed: Bool?
    var isGuestUser: Bool?
    var contentLibrary: ContentLibrary
    var verificationMethod: VerificationMethod
    var isIAPEnabled: Bool
    var isAppStoreCTAChange: Bool
    /// Only set when the block is the iOS configuration.
    var update: UpdateDetails?

    private enum CodingKeys: String, CodingKey {
        case rtl
        case pictureInPicture = "pic_in_pic"
        case casting
        case screenRecording = "screen_rec"
        case isGuestUser = "is_guest_user"
        case contentLibrary = "content_library"
        case verificationMethod = "otp_verfied"
        case isIAPEnabled = "is_iap_enabled"
        case isAppStoreCTAChange = "is_iosappstore_cta_change"
        case update = "force_update_details"
    }

    private struct Platform: Decodable {
        var platform: String?
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isRTLAllowed = container.lenientBool(.rtl)
        isPiPAllowed = container.lenientBool(.pictureInPicture)
        isCastingAllowed = container.lenientBool(.casting)
        isScreenRecordingAllowed = container.lenientBool(.screenRecording)
        isGuestUser = container.lenientBool(.isGuestUser)
        contentLibrary = container.lenientInt(.contentLibrary).flatMap(ContentLibrary.init) ?? .vodDrama
        verificationMethod = container.lenientString(.verificationMethod).flatMap(VerificationMethod.init) ?? .email
        isIAPEnabled = container.lenientBool(.isIAPEnabled) ?? false
        isAppStoreCTAChange = container.lenientBool(.isAppStoreCTAChange) ?? false
        let platform = container.lenient(Platform.self, .update)?.platform?.lowercased()
        update = platform == "ios" ? container.lenient(UpdateDetails.self, .update) : nil
    }
}

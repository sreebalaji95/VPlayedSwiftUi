import Foundation

/// App-wide settings from `GET mediaview/api/v1/common`, ported from the UIKit app's
/// `CommonKeysStruct` plus the payment flags and update details it reads from the same response
/// (`SceneDelegate.getCommonKeys`, `AppUpdateConfig`). Missing or malformed keys fall back to the
/// UIKit defaults instead of failing the response.
nonisolated struct CommonSettings: Sendable, Equatable {
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
    struct UpdateDetails: Sendable, Equatable {
        var isForceUpdateEnabled: Bool
        var minimumVersion: String?
        var forceUpdateMessage: String?
        var isSoftUpdateEnabled: Bool
        var latestVersion: String?
        var softUpdateMessage: String?

        init(
            isForceUpdateEnabled: Bool,
            minimumVersion: String?,
            forceUpdateMessage: String?,
            isSoftUpdateEnabled: Bool,
            latestVersion: String?,
            softUpdateMessage: String?
        ) {
            self.isForceUpdateEnabled = isForceUpdateEnabled
            self.minimumVersion = minimumVersion
            self.forceUpdateMessage = forceUpdateMessage
            self.isSoftUpdateEnabled = isSoftUpdateEnabled
            self.latestVersion = latestVersion
            self.softUpdateMessage = softUpdateMessage
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

    init(
        isRTLAllowed: Bool? = nil,
        isPiPAllowed: Bool? = nil,
        isCastingAllowed: Bool? = nil,
        isScreenRecordingAllowed: Bool? = nil,
        isGuestUser: Bool? = nil,
        contentLibrary: ContentLibrary = .vodDrama,
        verificationMethod: VerificationMethod = .email,
        isIAPEnabled: Bool = false,
        isAppStoreCTAChange: Bool = false,
        update: UpdateDetails? = nil
    ) {
        self.isRTLAllowed = isRTLAllowed
        self.isPiPAllowed = isPiPAllowed
        self.isCastingAllowed = isCastingAllowed
        self.isScreenRecordingAllowed = isScreenRecordingAllowed
        self.isGuestUser = isGuestUser
        self.contentLibrary = contentLibrary
        self.verificationMethod = verificationMethod
        self.isIAPEnabled = isIAPEnabled
        self.isAppStoreCTAChange = isAppStoreCTAChange
        self.update = update
    }

}

import CommonCrypto
import CryptoKit
import Foundation
import Security

/// `CryptoJS.AES.encrypt(message, passphrase)` with a string passphrase, which the auth
/// endpoints expect for their `data` field. The UIKit app ran crypto-js in JavaScriptCore
/// (`CryptoJS.swift` + `aes.js`); this produces the same OpenSSL-compatible format natively:
/// base64 of `"Salted__" + 8-byte salt + AES-256-CBC (PKCS#7) ciphertext`, with the key and IV
/// derived from the passphrase and salt by OpenSSL's `EVP_BytesToKey` (MD5, one iteration).
nonisolated enum CryptoJSAES {
    enum Failure: Error {
        /// The build has no passphrase (`Config/Secrets.xcconfig` missing), so nothing can be encrypted.
        case missingPassphrase
        case randomBytes
        case crypt(CCCryptorStatus)
        case malformed
    }

    /// The passphrase the UIKit app encrypts auth payloads with (`getEmailEncrypted`). It is not in
    /// source control: `VPLAYED_TRANSPORT_KEY` in the git-ignored `Config/Secrets.xcconfig` reaches the
    /// app through the `VPlayedTransportKey` Info.plist entry. Empty when the build has none.
    static let authPassphrase: String = Bundle.main.object(forInfoDictionaryKey: "VPlayedTransportKey") as? String ?? ""

    private static let magic = Data("Salted__".utf8)

    static func encrypt(_ plaintext: String, passphrase: String) throws -> String {
        guard !passphrase.isEmpty else { throw Failure.missingPassphrase }
        var salt = Data(count: 8)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 8, $0.baseAddress!) }
        guard status == errSecSuccess else { throw Failure.randomBytes }
        let (key, iv) = deriveKeyAndIV(passphrase: Data(passphrase.utf8), salt: salt)
        let ciphertext = try crypt(CCOperation(kCCEncrypt), Data(plaintext.utf8), key: key, iv: iv)
        return (magic + salt + ciphertext).base64EncodedString()
    }

    /// The inverse, for tests and debugging.
    static func decrypt(_ base64: String, passphrase: String) throws -> String {
        guard let data = Data(base64Encoded: base64), data.count > 16, data.prefix(8) == magic else {
            throw Failure.malformed
        }
        let salt = data.subdata(in: 8..<16)
        let (key, iv) = deriveKeyAndIV(passphrase: Data(passphrase.utf8), salt: salt)
        let plaintext = try crypt(CCOperation(kCCDecrypt), data.subdata(in: 16..<data.count), key: key, iv: iv)
        guard let string = String(data: plaintext, encoding: .utf8) else { throw Failure.malformed }
        return string
    }

    /// `EVP_BytesToKey(MD5, salt, passphrase, count: 1)` for a 32-byte key and a 16-byte IV.
    private static func deriveKeyAndIV(passphrase: Data, salt: Data) -> (key: Data, iv: Data) {
        var derived = Data()
        var block = Data()
        while derived.count < kCCKeySizeAES256 + kCCBlockSizeAES128 {
            block = Data(Insecure.MD5.hash(data: block + passphrase + salt))
            derived += block
        }
        return (derived.prefix(kCCKeySizeAES256), derived.subdata(in: kCCKeySizeAES256..<(kCCKeySizeAES256 + kCCBlockSizeAES128)))
    }

    private static func crypt(_ operation: CCOperation, _ input: Data, key: Data, iv: Data) throws -> Data {
        var output = Data(count: input.count + kCCBlockSizeAES128)
        var written = 0
        let capacity = output.count
        let status = output.withUnsafeMutableBytes { outputBytes in
            input.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count,
                            ivBytes.baseAddress,
                            inputBytes.baseAddress, input.count,
                            outputBytes.baseAddress, capacity,
                            &written
                        )
                    }
                }
            }
        }
        guard status == CCCryptorStatus(kCCSuccess) else { throw Failure.crypt(status) }
        return output.prefix(written)
    }
}

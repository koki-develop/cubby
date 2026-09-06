import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Everything that touches the Secure Enclave key.
enum Enclave {
    typealias PrivateKey = SecureEnclave.P256.KeyAgreement.PrivateKey

    /// Generates a new key that can only be used after Touch ID succeeds.
    ///
    /// The access control is passed explicitly: the initializer's default is an empty flag
    /// set, which yields a key that never asks for authentication.
    static func generateKey() throws -> PrivateKey {
        guard SecureEnclave.isAvailable else {
            throw CubbyError("the Secure Enclave is not available")
        }
        var error: Unmanaged<CFError>?
        guard let acl = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .biometryAny], &error)
        else {
            throw CubbyError("could not create \(Store.location): \(error!.takeRetainedValue())")
        }
        do {
            return try PrivateKey(accessControl: acl)
        } catch {
            throw CubbyError("could not create \(Store.location): \(error.localizedDescription)")
        }
    }

    /// Reads `key.blob` once and verifies that the key it holds requires user interaction.
    ///
    /// Callers must restore the key from the returned bytes rather than re-reading the file,
    /// so that the key that was verified is the key that gets used.
    static func loadVerifiedKeyBlob() throws -> Data {
        try Store.requireStore()
        guard let blob = try Store.read(Store.keyPath, what: "the store key in \(Store.display(Store.home))") else {
            throw CubbyError("the store key in \(Store.display(Store.home)) cannot be loaded")
        }
        try verifyRequiresInteraction(blob)
        return blob
    }

    /// Fails unless using the key would prompt the user.
    ///
    /// A key agreement is attempted under an `LAContext` that forbids interaction. The only
    /// acceptable outcome is `LAError.notInteractive`: the key demanded authentication and the
    /// context refused to show a prompt. Success means the key has no authentication
    /// requirement. Any other Touch ID condition is reported in plain words.
    static func verifyRequiresInteraction(_ blob: Data) throws {
        let context = LAContext()
        context.interactionNotAllowed = true
        let key = try restore(blob, context: context)

        let probeInfo = Data("cubby/verify".utf8)
        let sender = try HPKE.Sender(recipientKey: key.publicKey, ciphersuite: Record.suite, info: probeInfo)
        do {
            _ = try HPKE.Recipient(
                privateKey: key, ciphersuite: Record.suite, info: probeInfo,
                encapsulatedKey: sender.encapsulatedKey)
        } catch let error as LAError where error.code == .notInteractive {
            return
        } catch let error as LAError {
            throw CubbyError("Touch ID: \(error.localizedDescription)")
        } catch {
            throw CubbyError(
                "the store key in \(Store.display(Store.home)) cannot be used: \(error.localizedDescription)")
        }
        throw CubbyError("the store key in \(Store.display(Store.home)) does not require Touch ID")
    }

    /// Restores the key from verified bytes with a fresh `LAContext` whose reason names the
    /// operation, the secret, and the store fingerprint. The password fallback button is
    /// hidden: the key's access control accepts biometry only. No authentication happens here.
    static func restoreKey(from blob: Data, operation: String, name: String) throws -> PrivateKey {
        let context = LAContext()
        context.localizedFallbackTitle = ""
        let key = try restore(blob, context: context)
        context.localizedReason = "\(operation) \(name)\nstore: \(fingerprint(of: key.publicKey))"
        return key
    }

    /// First 8 bytes of SHA-256 over the 64-byte raw public key, as `xxxx-xxxx-xxxx-xxxx`.
    static func fingerprint(of publicKey: P256.KeyAgreement.PublicKey) -> String {
        let digest = SHA256.hash(data: publicKey.rawRepresentation)
        let hex = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return stride(from: 0, to: hex.count, by: 4)
            .map { offset -> Substring in
                let start = hex.index(hex.startIndex, offsetBy: offset)
                return hex[start..<hex.index(start, offsetBy: 4)]
            }
            .joined(separator: "-")
    }

    private static func restore(_ blob: Data, context: LAContext) throws -> PrivateKey {
        do {
            return try PrivateKey(dataRepresentation: blob, authenticationContext: context)
        } catch {
            throw CubbyError(
                "the store key in \(Store.display(Store.home)) cannot be loaded: \(error.localizedDescription)")
        }
    }
}

import CryptoKit
import Foundation
import LocalAuthentication

/// Encoding of one stored secret: `encapsulatedKey (65 bytes) ‖ ciphertext`.
///
/// Secrets are sealed with HPKE in authentication mode, with the Secure Enclave key as both
/// recipient and sender. Producing a valid record therefore requires the Secure Enclave key,
/// which is what lets `get` detect a substituted or altered record.
enum Record {
    static let suite = HPKE.Ciphersuite.P256_SHA256_AES_GCM_256
    static let encapsulatedKeySize = 65

    /// Binds a record to its name so that a record cannot be opened under another name.
    static func info(for name: SecretName) -> Data {
        Data(("cubby/v1:" + name.text).utf8)
    }

    /// Touch ID is requested while constructing the sender.
    static func seal(_ plaintext: Data, name: SecretName, key: Enclave.PrivateKey) throws -> Data {
        var sender = try authenticating {
            try HPKE.Sender(
                recipientKey: key.publicKey, ciphersuite: suite, info: info(for: name), authenticatedBy: key)
        }
        let ciphertext = try sender.seal(plaintext)
        return sender.encapsulatedKey + ciphertext
    }

    /// Touch ID is requested while constructing the recipient. Returns `nil` when the record
    /// is malformed or fails authentication.
    static func open(_ record: Data, name: SecretName, key: Enclave.PrivateKey) throws -> Data? {
        let encapsulatedKey = record.prefix(encapsulatedKeySize)
        let ciphertext = record.dropFirst(encapsulatedKeySize)
        var recipient: HPKE.Recipient
        do {
            recipient = try authenticating {
                try HPKE.Recipient(
                    privateKey: key, ciphersuite: suite, info: info(for: name),
                    encapsulatedKey: encapsulatedKey, authenticatedBy: key.publicKey)
            }
        } catch is HPKE.Errors {
            return nil
        } catch is CryptoKitError {
            return nil
        }
        return try? recipient.open(ciphertext)
    }

    /// Runs a step that may prompt for Touch ID and reports a refused or failed prompt under
    /// a `Touch ID:` prefix.
    private static func authenticating<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as LAError {
            throw CubbyError("Touch ID: \(error.localizedDescription)")
        }
    }
}

import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Everything that touches the Secure Enclave key of one store.
struct Enclave {
    typealias PrivateKey = SecureEnclave.P256.KeyAgreement.PrivateKey

    /// The store the key belongs to. Its location appears in every message here.
    let store: Store

    /// Why this Mac cannot hold a store, or `nil` when it can.
    ///
    /// A store needs two things: a Secure Enclave to keep its key in, and a biometry to gate
    /// that key on. `SecureEnclave.isAvailable` answers only the first, and a Mac can have an
    /// enclave with no Touch ID enrolled — a virtual machine is one. There the key is refused
    /// the moment it is created, under a bare `Authentication failure` that names neither what
    /// was missing nor what to do about it.
    static var unsupported: CubbyError? {
        guard SecureEnclave.isAvailable else {
            return CubbyError("the Secure Enclave is not available")
        }
        var error: NSError?
        guard LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            switch error.flatMap({ LAError.Code(rawValue: $0.code) }) {
            case .biometryNotEnrolled:
                return CubbyError("no Touch ID is enrolled; add one in System Settings first")
            case .biometryLockout:
                return CubbyError("Touch ID is locked out; enter your password to re-enable it")
            default:
                return CubbyError("Touch ID is not available")
            }
        }
        return nil
    }

    /// Generates a new key that can only be used after Touch ID succeeds.
    ///
    /// The access control is passed explicitly: the initializer's default is an empty flag
    /// set, which yields a key that never asks for authentication.
    func generateKey() throws -> PrivateKey {
        if let unsupported = Enclave.unsupported { throw unsupported }
        var error: Unmanaged<CFError>?
        guard let acl = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .biometryAny], &error)
        else {
            throw CubbyError("could not create \(store.location): \(error!.takeRetainedValue())")
        }
        do {
            return try PrivateKey(accessControl: acl)
        } catch {
            throw CubbyError("could not create \(store.location): \(error.localizedDescription)")
        }
    }

    /// Reads `key.blob`. Fails with the `cubby init` hint when there is no store.
    func loadKeyBlob() throws -> Data {
        guard let blob = try Store.read(store.keyPath, what: "the store key in \(Store.display(store.home))") else {
            throw store.noStore
        }
        return blob
    }

    /// What the key is about to be used for, in the words the Touch ID dialog shows.
    ///
    /// On macOS `localizedReason` is the dialog's *title*, so a case reads as one:
    /// capitalized, and carrying no app name — the dialog shows that itself. `save` and
    /// `replace` are separate because a replacement destroys the value already stored, and
    /// that is the part worth approving.
    enum Purpose {
        case read(SecretName)
        case save(SecretName)
        case replace(SecretName)

        var title: String {
            switch self {
            case .read(let name): "Read the secret \"\(name)\""
            case .save(let name): "Save a new secret \"\(name)\""
            case .replace(let name): "Replace the secret \"\(name)\""
            }
        }
    }

    /// Restores the key from `blob` with a fresh `LAContext` whose reason names the purpose.
    /// The password fallback button is hidden: the key's access control accepts biometry
    /// only. No authentication happens here.
    func restoreKey(from blob: Data, for purpose: Purpose) throws -> PrivateKey {
        let context = LAContext()
        context.localizedFallbackTitle = ""
        let key = try restore(blob, context: context)
        context.localizedReason = purpose.title
        return key
    }

    private func restore(_ blob: Data, context: LAContext) throws -> PrivateKey {
        do {
            return try PrivateKey(dataRepresentation: blob, authenticationContext: context)
        } catch {
            throw CubbyError(
                "the store key in \(Store.display(store.home)) cannot be loaded: \(error.localizedDescription)")
        }
    }
}

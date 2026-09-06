import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Everything that touches the Secure Enclave key of one store.
struct Enclave {
    typealias PrivateKey = SecureEnclave.P256.KeyAgreement.PrivateKey

    /// The store the key belongs to. Its location appears in every message here.
    let store: Store

    /// Generates a new key that can only be used after Touch ID succeeds.
    ///
    /// The access control is passed explicitly: the initializer's default is an empty flag
    /// set, which yields a key that never asks for authentication.
    func generateKey() throws -> PrivateKey {
        guard SecureEnclave.isAvailable else {
            throw CubbyError("the Secure Enclave is not available")
        }
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

    /// Restores the key from `blob` with a fresh `LAContext` whose reason names the operation
    /// and the secret. The password fallback button is hidden: the key's access control
    /// accepts biometry only. No authentication happens here.
    func restoreKey(from blob: Data, operation: String, name: SecretName) throws -> PrivateKey {
        let context = LAContext()
        context.localizedFallbackTitle = ""
        let key = try restore(blob, context: context)
        context.localizedReason = "\(operation) \(name)"
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

import CryptoKit
import Foundation
import Testing

@testable import cubby

@Suite struct RecordTests {
    @Test func bindsTheInfoStringToTheName() throws {
        #expect(try Record.info(for: SecretName("token")) == Data("cubby/v1:token".utf8))
    }

    @Test func givesEveryNameItsOwnInfoString() throws {
        #expect(try Record.info(for: SecretName("a")) != Record.info(for: SecretName("b")))
        #expect(try Record.info(for: SecretName("Token")) != Record.info(for: SecretName("token")))
    }

    /// The stored `encapsulatedKey ‖ ciphertext` split only lands on the right boundary while
    /// this matches what the suite's KEM actually emits.
    @Test func splitsRecordsAtTheSizeTheSuitesKemProduces() {
        #expect(P256.KeyAgreement.PrivateKey().publicKey.x963Representation.count == Record.encapsulatedKeySize)
    }
}

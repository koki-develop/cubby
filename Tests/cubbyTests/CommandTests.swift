import ArgumentParser
import CryptoKit
import Foundation
import Testing

@testable import cubby

@Suite struct ListCommandTests {
    @Test func reportsAMissingStore() throws {
        try withStore { store in
            let error = #expect(throws: CubbyError.self) {
                try ListCommand().run(in: store, to: Recorded().output)
            }
            #expect(error?.description == "no store at \(Store.display(store.home)); run cubby init first")
        }
    }

    @Test func printsNothingForAnEmptyStore() throws {
        try withInitializedStore { store in
            let recorded = Recorded()
            try ListCommand().run(in: store, to: recorded.output)
            #expect(recorded.text.isEmpty)
        }
    }

    @Test func printsOneNamePerLineInOrder() throws {
        try withInitializedStore { store in
            for text in ["token", "api"] { try plantRecord(text, in: store) }
            let recorded = Recorded()
            try ListCommand().run(in: store, to: recorded.output)
            #expect(recorded.text == "api\ntoken\n")
        }
    }

    /// What the user typed comes back, not the hex the file is named after.
    @Test func printsTheNameAndNotTheFileItIsStoredIn() throws {
        try withInitializedStore { store in
            try plantRecord("a/b", in: store)
            let recorded = Recorded()
            try ListCommand().run(in: store, to: recorded.output)
            #expect(recorded.lines == ["a/b"])
        }
    }

    @Test func leavesTheStoreAsItIs() throws {
        try withInitializedStore { store in
            try plantRecord("token", in: store)
            try ListCommand().run(in: store, to: Recorded().output)
            #expect(exists(store.recordPath(for: try SecretName("token"))))
            #expect(store.hasKey())
        }
    }
}

@Suite struct RemoveCommandTests {
    private func remove(_ name: String, in store: Store, to output: Output) throws {
        try RemoveCommand.parse([name]).run(in: store, to: output)
    }

    @Test func reportsAMissingStore() throws {
        try withStore { store in
            let error = #expect(throws: CubbyError.self) {
                try remove("token", in: store, to: Recorded().output)
            }
            #expect(error?.description == "no store at \(Store.display(store.home)); run cubby init first")
        }
    }

    /// A missing store is reported ahead of a missing secret: the hint the user needs is the
    /// one about `cubby init`.
    @Test func reportsAMissingStoreAheadOfAMissingSecret() throws {
        try withStore { store in
            try store.ensureDirectories()
            let error = #expect(throws: CubbyError.self) {
                try remove("token", in: store, to: Recorded().output)
            }
            #expect(error?.description.hasPrefix("no store at ") == true)
        }
    }

    @Test func reportsAMissingSecret() throws {
        try withInitializedStore { store in
            let error = #expect(throws: CubbyError.self) {
                try remove("token", in: store, to: Recorded().output)
            }
            #expect(error?.description == "no secret named \"token\"")
        }
    }

    @Test func deletesTheRecordAndSaysSo() throws {
        try withInitializedStore { store in
            try plantRecord("token", in: store)
            let recorded = Recorded()
            try remove("token", in: store, to: recorded.output)
            #expect(recorded.text == "Deleted \"token\"\n")
            #expect(!exists(store.recordPath(for: try SecretName("token"))))
            let names = try store.secretNames()
            #expect(names.isEmpty)
        }
    }

    @Test func deletesOnlyTheNamedRecord() throws {
        try withInitializedStore { store in
            for text in ["token", "api"] { try plantRecord(text, in: store) }
            try remove("token", in: store, to: Recorded().output)
            #expect(try store.secretNames().map(\.text) == ["api"])
            #expect(store.hasKey())
        }
    }

    @Test func deletesTheRecordOfANameThatReadsLikeAPath() throws {
        try withInitializedStore { store in
            try plantRecord("a/b", in: store)
            try remove("a/b", in: store, to: Recorded().output)
            #expect(try store.secretNames().isEmpty)
        }
    }

    @Test func refusesToDeleteTheSecondTime() throws {
        try withInitializedStore { store in
            try plantRecord("token", in: store)
            try remove("token", in: store, to: Recorded().output)
            let error = #expect(throws: CubbyError.self) {
                try remove("token", in: store, to: Recorded().output)
            }
            #expect(error?.description == "no secret named \"token\"")
        }
    }
}

@Suite struct InitCommandTests {
    @Test func refusesWhenAStoreAlreadyExists() throws {
        try withInitializedStore { store in
            let recorded = Recorded()
            let error = #expect(throws: CubbyError.self) {
                try InitCommand().run(in: store, to: recorded.output)
            }
            #expect(error?.description == "a store already exists at \(Store.display(store.home))")
            #expect(recorded.text.isEmpty)
        }
    }

    /// The existing key is what makes a store, so an untouched key blob proves nothing was
    /// overwritten.
    @Test func leavesTheExistingKeyAloneWhenItRefuses() throws {
        try withInitializedStore { store in
            let before = try Store.read(store.keyPath, what: "the key")
            #expect(throws: CubbyError.self) { try InitCommand().run(in: store, to: Recorded().output) }
            #expect(try Store.read(store.keyPath, what: "the key") == before)
        }
    }

    @Test(.enabled(if: SecureEnclave.isAvailable))
    func createsAStoreAndSaysWhere() throws {
        try withStore { store in
            let recorded = Recorded()
            try InitCommand().run(in: store, to: recorded.output)
            #expect(recorded.text == "Created a store at \(Store.display(store.home))\n")
            #expect(store.hasKey())
            #expect(try mode(of: store.home) == 0o700)
            #expect(try mode(of: store.secretsDir) == 0o700)
            #expect(try mode(of: store.keyPath) == 0o600)
            #expect(try store.secretNames().isEmpty)
        }
    }

    @Test(.enabled(if: SecureEnclave.isAvailable))
    func refusesTheSecondTime() throws {
        try withStore { store in
            try InitCommand().run(in: store, to: Recorded().output)
            let error = #expect(throws: CubbyError.self) {
                try InitCommand().run(in: store, to: Recorded().output)
            }
            #expect(error?.description == "a store already exists at \(Store.display(store.home))")
        }
    }

    @Test(.enabled(if: SecureEnclave.isAvailable))
    func writesAKeyThatCanBeLoadedBack() throws {
        try withStore { store in
            try InitCommand().run(in: store, to: Recorded().output)
            let blob = try Enclave(store: store).loadKeyBlob()
            #expect(!blob.isEmpty)
            #expect(throws: Never.self) {
                try Enclave(store: store).restoreKey(from: blob, operation: "read", name: SecretName("token"))
            }
        }
    }

    @Test(.disabled(if: SecureEnclave.isAvailable, "the Secure Enclave is available here"))
    func reportsAMissingSecureEnclave() throws {
        try withStore { store in
            let error = #expect(throws: CubbyError.self) {
                try InitCommand().run(in: store, to: Recorded().output)
            }
            #expect(error?.description == "the Secure Enclave is not available")
            #expect(!store.hasKey())
        }
    }
}

@Suite struct EnclaveTests {
    @Test func reportsAMissingStoreWhenThereIsNoKeyBlob() throws {
        try withStore { store in
            let error = #expect(throws: CubbyError.self) { try Enclave(store: store).loadKeyBlob() }
            #expect(error?.description == "no store at \(Store.display(store.home)); run cubby init first")
        }
    }

    @Test func readsTheKeyBlobItWasGiven() throws {
        try withInitializedStore { store in
            let blob = try Enclave(store: store).loadKeyBlob()
            #expect(blob == Data("stand-in".utf8))
        }
    }

    @Test func reportsAKeyBlobItCannotLoad() throws {
        try withInitializedStore { store in
            let blob = try Enclave(store: store).loadKeyBlob()
            let error = #expect(throws: CubbyError.self) {
                try Enclave(store: store).restoreKey(from: blob, operation: "read", name: SecretName("token"))
            }
            #expect(
                error?.description.hasPrefix(
                    "the store key in \(Store.display(store.home)) cannot be loaded: ") == true)
        }
    }
}

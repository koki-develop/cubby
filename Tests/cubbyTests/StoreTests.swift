import Foundation
import Testing

@testable import cubby

@Suite struct StoreEnvironmentTests {
  @Test func takesTheRootFromCubbyHome() {
    #expect(Store.fromEnvironment(["CUBBY_HOME": "/somewhere/else"]).home == "/somewhere/else")
  }

  @Test func fallsBackToTheHomeDirectoryWhenCubbyHomeIsUnset() {
    #expect(Store.fromEnvironment([:]).home == NSHomeDirectory() + "/.cubby")
  }

  @Test func fallsBackToTheHomeDirectoryWhenCubbyHomeIsEmpty() {
    #expect(Store.fromEnvironment(["CUBBY_HOME": ""]).home == NSHomeDirectory() + "/.cubby")
  }

  @Test func looksAtNoOtherVariable() {
    #expect(
      Store.fromEnvironment(["HOME": "/nowhere", "CUBBY": "/nowhere"]).home == NSHomeDirectory()
        + "/.cubby")
  }
}

@Suite struct StoreLayoutTests {
  @Test func placesTheKeyAndTheSecretsUnderTheRoot() {
    let store = Store(home: "/root")
    #expect(store.keyPath == "/root/key.blob")
    #expect(store.secretsDir == "/root/secrets")
  }

  /// The name reaches the path only as hex, so a name that reads like a path never is one.
  @Test(arguments: [("token", "746f6b656e"), ("a/b", "612f62"), ("..", "2e2e")])
  func namesRecordsByTheHexOfTheSecretName(_ text: String, _ encoded: String) throws {
    #expect(
      try Store(home: "/root").recordPath(for: SecretName(text)) == "/root/secrets/\(encoded).bin")
  }

  @Test func shortensTheUsersHomeDirectoryForMessages() {
    #expect(Store.display(NSHomeDirectory() + "/.cubby") == "~/.cubby")
    #expect(Store.display("/somewhere/else") == "/somewhere/else")
  }

  @Test func namesItsLocationForMessages() {
    #expect(Store(home: "/somewhere/else").location == "the store at /somewhere/else")
  }
}

@Suite struct StoreKeyTests {
  @Test func hasNoKeyBeforeTheStoreIsCreated() throws {
    try withStore { store in
      #expect(!store.hasKey())
    }
  }

  @Test func hasNoKeyWhenOnlyTheDirectoriesAreThere() throws {
    try withStore { store in
      try store.ensureDirectories()
      #expect(!store.hasKey())
    }
  }

  @Test func hasAKeyOnceTheBlobIsWritten() throws {
    try withInitializedStore { store in
      #expect(store.hasKey())
    }
  }

  @Test func requiringAMissingStoreReportsTheInitHint() throws {
    try withStore { store in
      let error = #expect(throws: CubbyError.self) { try store.requireStore() }
      #expect(
        error?.description == "no store at \(Store.display(store.home)); run `cubby init` first")
    }
  }

  @Test func requiringAnExistingStorePasses() throws {
    try withInitializedStore { store in
      #expect(throws: Never.self) { try store.requireStore() }
    }
  }
}

@Suite struct StoreRecordTests {
  @Test func holdsNoRecordForANameNothingWasStoredUnder() throws {
    try withInitializedStore { store in
      let token = try SecretName("token")
      #expect(!store.hasRecord(for: token))
    }
  }

  @Test func holdsARecordOnceOneIsWrittenUnderTheName() throws {
    try withInitializedStore { store in
      try plantRecord("token", in: store)
      let (token, other) = try (SecretName("token"), SecretName("other"))
      #expect(store.hasRecord(for: token))
      #expect(!store.hasRecord(for: other))
    }
  }
}

@Suite struct StoreDirectoryTests {
  @Test func createsTheRootAndTheSecretsDirectoryAtMode0700() throws {
    try withStore { store in
      try store.ensureDirectories()
      #expect(try mode(of: store.home) == 0o700)
      #expect(try mode(of: store.secretsDir) == 0o700)
    }
  }

  @Test func createsEveryMissingComponentOfTheRoot() throws {
    try withTemporaryDirectory { dir in
      let store = Store(home: dir + "/deeply/nested/root")
      try store.ensureDirectories()
      #expect(exists(store.secretsDir))
    }
  }

  @Test func leavesExistingDirectoriesAndTheirContentsAlone() throws {
    try withStore { store in
      try store.ensureDirectories()
      try plantRecord("token", in: store)
      try store.ensureDirectories()
      #expect(try store.secretNames().map(\.text) == ["token"])
    }
  }
}

@Suite struct StoreSecretNamesTests {
  @Test func listsNothingWhenTheSecretsDirectoryIsMissing() throws {
    try withStore { store in
      let names = try store.secretNames()
      #expect(names.isEmpty)
    }
  }

  @Test func listsNothingForAnEmptyStore() throws {
    try withInitializedStore { store in
      let names = try store.secretNames()
      #expect(names.isEmpty)
    }
  }

  @Test func listsStoredNamesInOrder() throws {
    try withInitializedStore { store in
      for text in ["token", "api", "Zeta", "zeta"] {
        try plantRecord(text, in: store)
      }
      #expect(try store.secretNames().map(\.text) == ["Zeta", "api", "token", "zeta"])
    }
  }

  @Test func listsNamesThatWouldReadLikePaths() throws {
    try withInitializedStore { store in
      for text in ["..", "a/b", ".hidden"] {
        try plantRecord(text, in: store)
      }
      #expect(try store.secretNames().map(\.text) == ["..", ".hidden", "a/b"])
    }
  }

  @Test(arguments: [
    "746f6b656e",  // no suffix
    "746f6b656e.txt",  // another suffix
    "746f6b656e.bin.tmp",  // the temporary sibling of a record
    "6.bin",  // an odd number of digits
    "7E.bin",  // uppercase hex
    "20.bin",  // the hex of a name that is not valid
    ".bin",  // the hex of the empty name
    "notHex.bin",
    "README",
  ])
  func ignoresEntriesNotNamedTheWayCubbyWritesThem(_ entry: String) throws {
    try withInitializedStore { store in
      try plant(entry, in: store)
      let names = try store.secretNames()
      #expect(names.isEmpty)
    }
  }

  @Test func ignoresATemporarySiblingNextToTheRecordItBelongsTo() throws {
    try withInitializedStore { store in
      try plantRecord("token", in: store)
      try plant(
        SecretName("token").encoded + Store.recordSuffix + Store.temporarySuffix + "aB3d9Z",
        in: store)
      #expect(try store.secretNames().map(\.text) == ["token"])
    }
  }

  @Test func reportsAFileWhereTheSecretsDirectoryShouldBe() throws {
    try withStore { store in
      try FileManager.default.createDirectory(atPath: store.home, withIntermediateDirectories: true)
      #expect(FileManager.default.createFile(atPath: store.secretsDir, contents: nil))
      let error = #expect(throws: CubbyError.self) { try store.secretNames() }
      #expect(error?.description.hasPrefix("could not read ") == true)
    }
  }
}

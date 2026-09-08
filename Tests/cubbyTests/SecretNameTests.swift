import Testing

@testable import cubby

@Suite struct SecretNameValidationTests {
  @Test func acceptsEveryPrintableAsciiCharacterOtherThanSpace() throws {
    for byte in UInt8(0x21)...UInt8(0x7E) {
      let text = String(UnicodeScalar(byte))
      #expect(throws: Never.self) { try SecretName(text) }
    }
  }

  @Test func rejectsTheEmptyName() {
    let error = #expect(throws: CubbyError.self) { try SecretName("") }
    #expect(error?.description == "must not be empty")
  }

  @Test(arguments: [
    " ", "a b", " token", "token ", "\t", "a\tb", "\n", "a\u{0}b", "\u{7F}", "café", "日本語", "🙂",
  ])
  func rejectsAnythingOutsidePrintableAscii(_ text: String) {
    let error = #expect(throws: CubbyError.self) { try SecretName(text) }
    #expect(error?.description == "may only contain printable ASCII characters other than space")
  }

  @Test func acceptsANameOfExactlyTheMaximumLength() throws {
    let name = try SecretName(String(repeating: "a", count: SecretName.maxLength))
    #expect(name.text.utf8.count == SecretName.maxLength)
  }

  @Test func rejectsANameOneCharacterOverTheMaximum() {
    let error = #expect(throws: CubbyError.self) {
      try SecretName(String(repeating: "a", count: SecretName.maxLength + 1))
    }
    #expect(error?.description == "must be at most \(SecretName.maxLength) characters long")
  }

  /// A name that breaks both rules is reported under the character set, so the message
  /// names the rule the user is most likely to have missed.
  @Test func reportsTheCharacterSetAheadOfTheLength() {
    let error = #expect(throws: CubbyError.self) {
      try SecretName(String(repeating: "é", count: SecretName.maxLength + 1))
    }
    #expect(error?.description == "may only contain printable ASCII characters other than space")
  }
}

@Suite struct SecretNameEncodingTests {
  @Test(arguments: [("a", "61"), ("A", "41"), ("!", "21"), ("~", "7e"), ("token", "746f6b656e")])
  func encodesTheNameAsLowercaseHexOfItsBytes(_ text: String, _ encoded: String) throws {
    #expect(try SecretName(text).encoded == encoded)
  }

  /// The characters that would be dangerous in a path are exactly the ones the encoding
  /// removes.
  @Test(arguments: ["..", ".", "/", "a/b", "../../etc/passwd", ".hidden", "-rf"])
  func encodesNamesThatWouldOtherwiseMeanSomethingToTheFileSystem(_ text: String) throws {
    let encoded = try SecretName(text).encoded
    #expect(encoded.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    #expect(SecretName(encoded: encoded)?.text == text)
  }

  @Test func encodesNamesDifferingOnlyInCaseDistinctly() throws {
    #expect(try SecretName("Token").encoded != SecretName("token").encoded)
  }

  @Test(arguments: ["a", "token", "~", "!", String(repeating: "z", count: SecretName.maxLength)])
  func restoresANameFromItsOwnEncoding(_ text: String) throws {
    let name = try SecretName(text)
    #expect(SecretName(encoded: name.encoded)?.text == text)
  }

  @Test(arguments: ["", "6", "616", "6g", "zz", "notHex"])
  func rejectsTextThatIsNotAnEvenNumberOfHexDigits(_ encoded: String) {
    #expect(SecretName(encoded: encoded) == nil)
  }

  /// Only the spelling cubby writes counts, so that exactly one file name maps to each name.
  /// Each of these decodes to a perfectly valid name in lowercase.
  @Test(arguments: [("7E", "7e"), ("6A", "6a"), ("746F6B656E", "746f6b656e")])
  func rejectsUppercaseHex(_ uppercase: String, _ lowercase: String) {
    #expect(SecretName(encoded: uppercase) == nil)
    #expect(SecretName(encoded: lowercase) != nil)
  }

  @Test(arguments: ["20", "00", "7f", "c3a9", "ff"])
  func rejectsHexThatDecodesToAnInvalidName(_ encoded: String) {
    #expect(SecretName(encoded: encoded) == nil)
  }

  @Test func rejectsHexThatDecodesToAnOverlongName() {
    #expect(SecretName(encoded: String(repeating: "61", count: SecretName.maxLength)) != nil)
    #expect(SecretName(encoded: String(repeating: "61", count: SecretName.maxLength + 1)) == nil)
  }
}

@Suite struct SecretNameOrderingTests {
  @Test func ordersByText() throws {
    let names = try ["b", "A", "a", "!", "~"].map { try SecretName($0) }
    #expect(names.sorted().map(\.text) == ["!", "A", "a", "b", "~"])
  }

  @Test func describesItselfAsItsText() throws {
    #expect(try "\(SecretName("a/b"))" == "a/b")
  }
}

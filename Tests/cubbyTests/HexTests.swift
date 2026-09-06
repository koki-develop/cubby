import Testing

@testable import cubby

@Suite struct HexTests {
    @Test func encodesEachByteAsTwoDigits() {
        #expect(Hex.encode([0x00] as [UInt8]) == "00")
        #expect(Hex.encode([0x0F] as [UInt8]) == "0f")
        #expect(Hex.encode([0xF0] as [UInt8]) == "f0")
        #expect(Hex.encode([0xFF] as [UInt8]) == "ff")
        #expect(Hex.encode([0xDE, 0xAD, 0xBE, 0xEF] as [UInt8]) == "deadbeef")
    }

    @Test func encodesNoBytesAsAnEmptyString() {
        #expect(Hex.encode([UInt8]()) == "")
    }

    @Test func encodesEveryByteInLowercase() {
        let text = Hex.encode(UInt8.min...UInt8.max)
        #expect(text.count == 512)
        #expect(text == text.lowercased())
    }

    @Test func decodesWhatEncodeProduces() {
        let bytes = Array(UInt8.min...UInt8.max)
        #expect(Hex.decode(Hex.encode(bytes)) == bytes)
    }

    @Test func decodesAnEmptyStringAsNoBytes() {
        #expect(Hex.decode("") == [])
    }

    @Test(arguments: ["0", "f", "abc", "0000f"])
    func rejectsAnOddNumberOfDigits(_ text: String) {
        #expect(Hex.decode(text) == nil)
    }

    @Test(arguments: ["AB", "0F", "dEaD", "FF"])
    func rejectsUppercaseDigits(_ text: String) {
        #expect(Hex.decode(text) == nil)
    }

    @Test(arguments: ["zz", "0x", "g0", "  ", "00 ", "-1", "００", "0\u{0}"])
    func rejectsAnythingThatIsNotAHexDigit(_ text: String) {
        #expect(Hex.decode(text) == nil)
    }
}

/// Lowercase hexadecimal encoding of bytes.
enum Hex {
    private static let digits = Array("0123456789abcdef".utf8)

    static func encode<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.underestimatedCount * 2)
        for byte in bytes {
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 0x0F)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// Bytes of `text`, or `nil` unless `text` is exactly what `encode` produces: an even
    /// number of lowercase hex digits.
    static func decode(_ text: String) -> [UInt8]? {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(text.utf8.count / 2)
        var high: UInt8?
        for digit in text.utf8 {
            let value: UInt8
            switch digit {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): value = digit - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): value = digit - UInt8(ascii: "a") + 10
            default: return nil
            }
            if let h = high {
                bytes.append(h << 4 | value)
                high = nil
            } else {
                high = value
            }
        }
        guard high == nil else { return nil }
        return bytes
    }
}

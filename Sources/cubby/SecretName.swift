/// The name of one stored secret.
///
/// A name is 1 to `maxLength` characters of printable ASCII other than space (`!` through
/// `~`). The set is deliberately small and fixed: every name is unambiguous on screen and
/// in the Touch ID prompt, and no Unicode normalization or case folding enters the picture.
///
/// On disk a name appears only through `encoded`, the lowercase hex of its bytes, so the
/// file system never interprets any character of it: no path separators, no `..`, no
/// dotfiles, no case-insensitive or normalization-insensitive collisions.
struct SecretName: Comparable, CustomStringConvertible {
  /// Two hex digits per character plus the record and temporary file suffixes stay well
  /// under `NAME_MAX` (255).
  static let maxLength = 100

  let text: String

  /// Fails with a message that names the violated rule.
  init(_ text: String) throws {
    guard !text.isEmpty else {
      throw CubbyError("must not be empty")
    }
    guard text.utf8.allSatisfy({ $0 > 0x20 && $0 < 0x7F }) else {
      throw CubbyError("may only contain printable ASCII characters other than space")
    }
    guard text.utf8.count <= Self.maxLength else {
      throw CubbyError("must be at most \(Self.maxLength) characters long")
    }
    self.text = text
  }

  /// Lowercase hex of the name's bytes: the only form the file system sees.
  var encoded: String {
    Hex.encode(text.utf8)
  }

  /// Restores a name from `encoded`. Returns `nil` unless the text is lowercase hex that
  /// decodes to a valid name, so that exactly one file name maps to each name.
  init?(encoded: String) {
    guard let bytes = Hex.decode(encoded),
      let name = try? SecretName(String(decoding: bytes, as: UTF8.self))
    else { return nil }
    self = name
  }

  var description: String { text }

  static func < (lhs: SecretName, rhs: SecretName) -> Bool {
    lhs.text < rhs.text
  }
}

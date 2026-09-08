import Darwin
import Foundation

/// Secret store layout on disk.
///
/// ```
/// ~/.cubby/                (0700)
/// ├── key.blob             wrapped Secure Enclave key   (0600)
/// └── secrets/
///     └── <hex>.bin        encapsulatedKey ‖ ciphertext (0600)
/// ```
///
/// `<hex>` is `SecretName.encoded`: the file system only ever sees hex digits, never the
/// name itself. Files are written through a temporary sibling.
///
/// A store is addressed by its root, which a command takes from the environment. The file
/// primitives at the bottom take a path and belong to no particular store.
struct Store {
  static let recordSuffix = ".bin"
  static let temporarySuffix = ".tmp."

  /// The store root.
  let home: String

  /// The store rooted at `$CUBBY_HOME`, or at `~/.cubby` when that is unset or empty.
  static func fromEnvironment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Store {
    if let override = environment["CUBBY_HOME"], !override.isEmpty {
      return Store(home: override)
    }
    return Store(home: NSHomeDirectory() + "/.cubby")
  }

  var keyPath: String { home + "/key.blob" }
  var secretsDir: String { home + "/secrets" }

  /// The store's location as shown in messages.
  var location: String { "the store at " + Store.display(home) }

  /// `path` with the user's home directory shortened to `~`, for messages.
  static func display(_ path: String) -> String {
    (path as NSString).abbreviatingWithTildeInPath
  }

  // MARK: Layout

  /// Whether the location holds a store key.
  func hasKey() -> Bool {
    FileManager.default.fileExists(atPath: keyPath)
  }

  /// Raised when there is no store.
  var noStore: CubbyError {
    CubbyError("no store at \(Store.display(home)); run `cubby init` first")
  }

  /// Raised when the location holds a store already.
  var alreadyAStore: CubbyError {
    CubbyError("a store already exists at \(Store.display(home))")
  }

  /// Fails unless the location holds a store key.
  func requireStore() throws {
    guard hasKey() else { throw noStore }
  }

  /// Creates `secrets/` and, with it, the store root, at mode 0700. Existing directories are
  /// left as they are.
  func ensureDirectories() throws {
    do {
      try FileManager.default.createDirectory(
        atPath: secretsDir, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
    } catch {
      throw CubbyError("could not create \(location): \(error.localizedDescription)")
    }
  }

  /// Entries of the directory at `dir`, or none when nothing is there.
  private static func entries(of dir: String) throws -> [String] {
    guard FileManager.default.fileExists(atPath: dir) else { return [] }
    do {
      return try FileManager.default.contentsOfDirectory(atPath: dir)
    } catch {
      throw CubbyError("could not read \(display(dir)): \(error.localizedDescription)")
    }
  }

  // MARK: Records

  /// Where the record for `name` is written.
  func recordPath(for name: SecretName) -> String {
    secretsDir + "/" + Store.recordEntry(for: name)
  }

  /// Whether the store already holds a record named `name`.
  func hasRecord(for name: SecretName) -> Bool {
    FileManager.default.fileExists(atPath: recordPath(for: name))
  }

  /// Raised when a record named `name` is there and the caller was not told to replace it.
  static func alreadyExists(_ name: SecretName) -> CubbyError {
    CubbyError("a secret named \"\(name)\" already exists; pass `--force` to replace it")
  }

  /// Names of all stored secrets, sorted. Entries not named like a record are left out.
  func secretNames() throws -> [SecretName] {
    try Store.entries(of: secretsDir).compactMap(Store.recordName(ofEntry:)).sorted()
  }

  private static func recordEntry(for name: SecretName) -> String {
    name.encoded + recordSuffix
  }

  /// The name a `secrets/` entry is named after, or `nil` when it is not named like a
  /// record: only the spelling cubby writes counts, so an entry with another spelling is
  /// not a record even where the volume matches names case-insensitively.
  private static func recordName(ofEntry entry: String) -> SecretName? {
    guard entry.hasSuffix(recordSuffix) else { return nil }
    return SecretName(encoded: String(entry.dropLast(recordSuffix.count)))
  }

  /// Opens a temporary file next to `path`. A failure is reported here rather than handed
  /// back, so that `errno` is read where the call left it.
  ///
  /// The name is `mkstemp`'s to pick: one derived from `path` alone would have two writes to
  /// the same destination truncating each other's file, and the rename would move the
  /// spliced result into place. `mkstemp` creates the file exclusively, at mode 0600, which
  /// the rename carries over to `path`.
  private static func openTemporary(besides path: String, action: String) throws -> (
    descriptor: Int32, path: String
  ) {
    var template = Array((path + temporarySuffix + "XXXXXX").utf8) + [0]
    let descriptor = template.withUnsafeMutableBufferPointer { buffer in
      buffer.withMemoryRebound(to: CChar.self) { mkstemp($0.baseAddress!) }
    }
    guard descriptor >= 0 else {
      let code = errno
      throw CubbyError("could not \(action): \(message(for: code))")
    }
    return (descriptor, String(decoding: template.dropLast(), as: UTF8.self))
  }

  // MARK: Files

  /// Contents of `path`, or `nil` when there is no such file. Any other failure is
  /// reported as `could not read <what>`.
  static func read(_ path: String, what: String) throws -> Data? {
    do {
      return try Data(contentsOf: URL(fileURLWithPath: path))
    } catch let error as NSError
      where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError
    {
      return nil
    } catch {
      throw CubbyError("could not read \(what): \(error.localizedDescription)")
    }
  }

  /// Writes `data` to `path` without ever exposing a partially written file, replacing
  /// whatever is there.
  ///
  /// The data goes to a temporary sibling, created with mode 0600, and is `fsync`ed, then
  /// `rename`d over `path`. On any failure the temporary file is removed and `path` is left
  /// untouched. Failures are reported as `could not <action>`.
  static func writeAtomically(_ data: Data, to path: String, action: String) throws {
    _ = try write(data, to: path, action: action, replacing: true)
  }

  /// Writes `data` the same way, but only where nothing is: returns `false`, having written
  /// nothing and left the file that is there untouched, when `path` is taken.
  ///
  /// What decides is the rename itself, so a caller that looked before calling cannot lose a
  /// file that appeared in between.
  static func createAtomically(_ data: Data, to path: String, action: String) throws -> Bool {
    try write(data, to: path, action: action, replacing: false)
  }

  /// The body of both writes. Returns `false` only for the one failure `createAtomically`
  /// answers rather than reports: a destination that is already taken.
  private static func write(_ data: Data, to path: String, action: String, replacing: Bool) throws
    -> Bool
  {
    let (fd, tmp) = try openTemporary(besides: path, action: action)
    var renamed = false
    defer { if !renamed { unlink(tmp) } }

    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    do {
      try handle.write(contentsOf: data)
    } catch {
      throw CubbyError("could not \(action): \(error.localizedDescription)")
    }
    guard fsync(fd) == 0 else {
      let code = errno
      throw CubbyError("could not \(action): \(message(for: code))")
    }
    do {
      try handle.close()
    } catch {
      throw CubbyError("could not \(action): \(error.localizedDescription)")
    }
    // `RENAME_EXCL` fails with `EEXIST` instead of replacing, leaving the destination as
    // it is.
    let moved = replacing ? rename(tmp, path) : renamex_np(tmp, path, UInt32(RENAME_EXCL))
    guard moved == 0 else {
      let code = errno
      if !replacing, code == EEXIST { return false }
      throw CubbyError("could not \(action): \(message(for: code))")
    }
    renamed = true
    return true
  }

  /// Unlinks one file. Returns `false` when there is no such file. A directory at `path`
  /// is an error, never removed.
  static func remove(_ path: String, what: String) throws -> Bool {
    guard unlink(path) == 0 else {
      let code = errno
      if code == ENOENT { return false }
      throw CubbyError("could not delete \(what): \(message(for: code))")
    }
    return true
  }

  // MARK: Errors

  private static func message(for code: Int32) -> String {
    String(cString: strerror(code))
  }
}

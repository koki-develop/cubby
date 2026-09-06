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
/// name itself. Files are written through a sibling `<file>.tmp`.
///
/// The root directory is `~/.cubby`, or `$CUBBY_HOME` when that is set to a non-empty value.
enum Store {
    static let home: String = {
        if let override = ProcessInfo.processInfo.environment["CUBBY_HOME"], !override.isEmpty {
            return override
        }
        return NSHomeDirectory() + "/.cubby"
    }()

    static let keyPath = home + "/key.blob"
    static let secretsDir = home + "/secrets"
    static let recordSuffix = ".bin"
    static let temporarySuffix = ".tmp"

    /// The store's location as shown in messages.
    static let location = "the store at " + display(home)

    /// `path` with the user's home directory shortened to `~`, for messages.
    static func display(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    // MARK: Layout

    /// Whether the location holds a store key.
    static func hasKey() -> Bool {
        FileManager.default.fileExists(atPath: keyPath)
    }

    /// Raised when there is no store.
    static var noStore: CubbyError {
        CubbyError("no store at \(display(home)); run cubby init first")
    }

    /// Fails unless the location holds a store key.
    static func requireStore() throws {
        guard hasKey() else { throw noStore }
    }

    /// Creates `secrets/` and, with it, the store root, at mode 0700. Existing directories are
    /// left as they are.
    static func ensureDirectories() throws {
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
    static func recordPath(for name: SecretName) -> String {
        secretsDir + "/" + recordEntry(for: name)
    }

    /// Names of all stored secrets, sorted. Entries not named like a record are left out.
    static func secretNames() throws -> [SecretName] {
        try entries(of: secretsDir).compactMap(recordName(ofEntry:)).sorted()
    }

    private static func recordEntry(for name: SecretName) -> String {
        name.encoded + recordSuffix
    }

    /// The name a `secrets/` entry is named after, or `nil` when it is not named like a
    /// record: only the spelling cubby writes counts, so an entry under another spelling is
    /// not a record even where the volume matches names case-insensitively.
    private static func recordName(ofEntry entry: String) -> SecretName? {
        guard entry.hasSuffix(recordSuffix) else { return nil }
        return SecretName(encoded: String(entry.dropLast(recordSuffix.count)))
    }

    private static func temporaryPath(for path: String) -> String {
        path + temporarySuffix
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

    /// Writes `data` to `path` without ever exposing a partially written file.
    ///
    /// The data goes to `<path>.tmp`, created fresh with mode 0600 (a stale one is replaced),
    /// and is `fsync`ed, then `rename`d over `path`. On any failure the temporary file is
    /// removed and `path` is left untouched. Failures are reported as `could not <action>`.
    static func writeAtomically(_ data: Data, to path: String, action: String) throws {
        let tmp = temporaryPath(for: path)
        unlink(tmp)
        let fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else {
            let code = errno
            throw CubbyError("could not \(action): \(message(for: code))")
        }
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
        guard rename(tmp, path) == 0 else {
            let code = errno
            throw CubbyError("could not \(action): \(message(for: code))")
        }
        renamed = true
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

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
/// Only what cubby creates is part of the store. Every command refuses a symbolic link or
/// anything but a regular file in the place of `key.blob` or a record, and anything but a
/// directory in the place of `secrets/`. The root itself is the user's to place: symbolic
/// links on the way to it are resolved once, at startup, and the store lives at the real
/// path.
///
/// The root directory is `~/.cubby`, or `$CUBBY_HOME` when that is set to a non-empty value.
enum Store {
    static let home: String = {
        if let override = ProcessInfo.processInfo.environment["CUBBY_HOME"], !override.isEmpty {
            return realPath(of: override)
        }
        return realPath(of: NSHomeDirectory() + "/.cubby")
    }()

    /// `path` made absolute, with symbolic links resolved in every component that exists.
    /// Components that do not exist yet are appended to the longest existing prefix as
    /// given, except that `.` is dropped and `..` steps back, so that nothing is ever created
    /// under a name other than the one the result shows.
    private static func realPath(of path: String) -> String {
        let absolute = path.hasPrefix("/") ? path : FileManager.default.currentDirectoryPath + "/" + path
        var resolved = [CChar](repeating: 0, count: Int(PATH_MAX))
        if realpath(absolute, &resolved) != nil {
            return resolved.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        }
        let parent = (absolute as NSString).deletingLastPathComponent
        guard parent != absolute else { return absolute }
        let base = realPath(of: parent)
        switch (absolute as NSString).lastPathComponent {
        case ".", "": return base
        case "..": return (base as NSString).deletingLastPathComponent
        case let last: return base + "/" + last
        }
    }

    static let keyPath = home + "/key.blob"
    static let secretsEntry = "secrets"
    static let secretsDir = home + "/" + secretsEntry
    static let recordSuffix = ".bin"
    static let temporarySuffix = ".tmp"

    /// The store's location as shown in messages.
    static let location = "the store at " + display(home)

    /// `path` with the user's home directory shortened to `~`, for messages.
    static func display(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    // MARK: Layout

    /// Whether the location holds a store key. Anything but a directory at `home`, or
    /// anything but a regular file in the key's place, is an error.
    static func hasKey() throws -> Bool {
        try directoryExists(at: home) && regularFileExists(at: keyPath)
    }

    /// Fails unless the location is a usable store: a store key inside a real directory,
    /// with `secrets/` either absent or a real directory too. Every command but `init`
    /// starts here.
    static func requireStore() throws {
        guard try hasKey() else {
            throw CubbyError("no store at \(display(home)); run cubby init first")
        }
        _ = try directoryExists(at: secretsDir)
    }

    /// Fails unless `home` is absent or holds nothing beyond an empty `secrets/`. Anything
    /// named like a record, whatever it holds, gets its own message: deleting it may lose a
    /// secret.
    static func requireEmptyLocation() throws {
        let inHome = try entries(of: home)
        let inSecrets = try entries(of: secretsDir)
        if inSecrets.contains(where: { recordName(ofEntry: $0) != nil }) {
            throw CubbyError(
                "\(display(home)) holds secrets but no store key; restore the key or delete \(display(secretsDir)) first")
        }
        if let entry = inSecrets.first { throw notEmpty(at: secretsDir, holding: entry) }
        if let entry = inHome.first(where: { $0 != secretsEntry }) { throw notEmpty(at: home, holding: entry) }
    }

    /// Creates the store directories, or brings existing ones to mode 0700: `createDirectory`
    /// leaves the mode of a directory that already exists untouched.
    static func createDirectories() throws {
        for dir in [home, secretsDir] {
            if try !directoryExists(at: dir) { try makeDirectory(dir) }
            guard chmod(dir, 0o700) == 0 else {
                let code = errno
                throw CubbyError("could not create \(location): \(message(for: code))")
            }
        }
    }

    /// Recreates `secrets/` if it has gone missing and fails, before any prompt, unless it is
    /// a directory this process can list and write into. Existing directories keep their mode.
    static func ensureWritableSecretsDirectory() throws {
        if try !directoryExists(at: secretsDir) { try makeDirectory(secretsDir) }
        guard access(secretsDir, R_OK | W_OK | X_OK) == 0 else {
            let code = errno
            throw CubbyError("cannot use \(display(secretsDir)): \(message(for: code))")
        }
    }

    private static func makeDirectory(_ dir: String) throws {
        do {
            try FileManager.default.createDirectory(
                atPath: dir, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        } catch {
            throw CubbyError("could not create \(location): \(error.localizedDescription)")
        }
    }

    /// Whether a directory is at `path`. Anything else there is an error.
    private static func directoryExists(at path: String) throws -> Bool {
        try exists(S_IFDIR, describedAs: "a directory", at: path)
    }

    /// Whether a regular file is at `path`. Anything else there is an error.
    private static func regularFileExists(at path: String) throws -> Bool {
        try exists(S_IFREG, describedAs: "a regular file", at: path)
    }

    /// Whether an entry of `type` is at `path`. Anything else there is an error, a symbolic
    /// link with its own message.
    private static func exists(_ type: mode_t, describedAs noun: String, at path: String) throws -> Bool {
        switch try fileType(at: path) {
        case nil: return false
        case type: return true
        case S_IFLNK: throw symbolicLink(at: path)
        default: throw CubbyError("\(display(path)) is not \(noun)")
        }
    }

    /// Entries of the directory at `dir`, or none when nothing is there.
    private static func entries(of dir: String) throws -> [String] {
        guard try directoryExists(at: dir) else { return [] }
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

    /// The path of the record for `name`, or `nil` when nothing is at its place. Anything
    /// there other than a regular file is an error. Errors name the secret.
    static func existingRecordPath(for name: SecretName) throws -> String? {
        let path = recordPath(for: name)
        return try naming(name) { () -> String? in
            try regularFileExists(at: path) ? path : nil
        }
    }

    /// Fails early, before any prompt, unless the record for `name` can be written where
    /// `existingRecordPath` will find it: on a leftover temporary file, or on anything at
    /// the record's place other than the record itself.
    static func checkWritable(recordFor name: SecretName) throws {
        let tmp = temporaryPath(for: recordPath(for: name))
        try naming(name) {
            if try fileType(at: tmp) != nil { throw obstruction(at: tmp) }
        }
        _ = try existingRecordPath(for: name)
    }

    /// Names of all stored secrets, sorted, and the errors for entries that are named like a
    /// record but are not one, each exactly as `get` would report it. Values are never read.
    /// Entries not named like a record are left out. Failing to list `secrets/` at all is
    /// thrown.
    static func secretNames() throws -> (names: [SecretName], refused: [CubbyError]) {
        var names: [SecretName] = []
        var refused: [CubbyError] = []
        for entry in try entries(of: secretsDir) {
            do {
                if let name = try secretName(ofRecordEntry: entry) { names.append(name) }
            } catch let problem as CubbyError {
                refused.append(problem)
            }
        }
        return (names.sorted(), refused.sorted { $0.description < $1.description })
    }

    private static func recordEntry(for name: SecretName) -> String {
        name.encoded + recordSuffix
    }

    /// The name of the secret whose record is the `secrets/` entry `entry`, or `nil` when
    /// the entry is not that record: not named like one, or vanished. Whatever
    /// `existingRecordPath` refuses for the name is refused here.
    private static func secretName(ofRecordEntry entry: String) throws -> SecretName? {
        guard let name = recordName(ofEntry: entry), try existingRecordPath(for: name) != nil else { return nil }
        return name
    }

    /// The name a `secrets/` entry is named after, or `nil` when it is not named like a
    /// record: only the spelling cubby writes counts, so an entry under another spelling is
    /// not a record even where the volume matches names case-insensitively. What the entry
    /// holds is not considered.
    private static func recordName(ofEntry entry: String) -> SecretName? {
        guard entry.hasSuffix(recordSuffix) else { return nil }
        return SecretName(encoded: String(entry.dropLast(recordSuffix.count)))
    }

    private static func temporaryPath(for path: String) -> String {
        path + temporarySuffix
    }

    // MARK: Files

    /// Type bits (`S_IFREG`, `S_IFDIR`, `S_IFLNK`, …) of the entry at `path`, or `nil` when
    /// nothing is there. Symbolic links are never followed: a link is reported as a link.
    /// Any failure other than absence is an error, never "nothing there".
    private static func fileType(at path: String) throws -> mode_t? {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            let code = errno
            if code == ENOENT { return nil }
            throw CubbyError("could not read \(display(path)): \(message(for: code))")
        }
        return info.st_mode & S_IFMT
    }

    /// Contents of `path`, or `nil` when there is no such file. Anything at `path` other
    /// than a regular file is refused, even one that appeared after the caller looked: a
    /// symbolic link is never followed, opening a pipe never waits for a writer, and what was
    /// opened is checked before it is read. `O_NONBLOCK` is left set, which a regular file
    /// ignores. Any other failure is reported as `could not read <what>`.
    static func read(_ path: String, what: String) throws -> Data? {
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else {
            let code = errno
            if code == ENOENT { return nil }
            if code == ELOOP { throw symbolicLink(at: path) }
            throw CubbyError("could not read \(what): \(message(for: code))")
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0 else {
            let code = errno
            throw CubbyError("could not read \(what): \(message(for: code))")
        }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw CubbyError("\(display(path)) is not a regular file") }
        do {
            return try handle.readToEnd() ?? Data()
        } catch {
            throw CubbyError("could not read \(what): \(error.localizedDescription)")
        }
    }

    /// Thrown by `writeAtomically(replacing: false)` when `path` already exists.
    struct AlreadyExists: Error {}

    /// Writes `data` to `path` without ever exposing a partially written file.
    ///
    /// The data goes to `<path>.tmp`, created with `O_CREAT | O_EXCL` and mode 0600, and is
    /// `fsync`ed. With `replacing` the temporary file is then `rename`d over `path`; without
    /// it, `path` is created with `link(2)`, which fails if `path` already exists. On any
    /// failure the temporary file is removed and `path` is left untouched. Failures are
    /// reported as `could not <action>`.
    static func writeAtomically(_ data: Data, to path: String, action: String, replacing: Bool = true) throws {
        let tmp = temporaryPath(for: path)
        let fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else {
            let code = errno
            if code == EEXIST { throw obstruction(at: tmp) }
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
        if replacing {
            guard rename(tmp, path) == 0 else {
                let code = errno
                throw CubbyError("could not \(action): \(message(for: code))")
            }
            renamed = true
        } else {
            guard link(tmp, path) == 0 else {
                let code = errno
                if code == EEXIST { throw AlreadyExists() }
                throw CubbyError("could not \(action): \(message(for: code))")
            }
        }
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

    /// Reports whatever `body` throws under `name`, which a record's path shows only as hex.
    private static func naming<T>(_ name: SecretName, _ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let problem as CubbyError {
            throw CubbyError("\"\(name)\": \(problem)")
        }
    }

    private static func obstruction(at path: String) -> CubbyError {
        CubbyError("\(display(path)) is in the way; delete it and retry")
    }

    private static func symbolicLink(at path: String) -> CubbyError {
        CubbyError("\(display(path)) is a symbolic link")
    }

    private static func notEmpty(at path: String, holding entry: String) -> CubbyError {
        CubbyError("\(display(path)) already exists and holds \(entry)")
    }

    private static func message(for code: Int32) -> String {
        String(cString: strerror(code))
    }
}

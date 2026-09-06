import Darwin
import Foundation

/// Secret store layout on disk.
///
/// ```
/// ~/.cubby/                (0700)
/// ├── key.blob             wrapped Secure Enclave key   (0600)
/// └── secrets/
///     └── <name>.bin       encapsulatedKey ‖ ciphertext (0600)
/// ```
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

    /// The store's location as shown in messages.
    static let location = "the store at " + display(home)

    static func recordPath(for name: String) -> String {
        secretsDir + "/" + name + ".bin"
    }

    /// `path` with the user's home directory shortened to `~`, for messages.
    static func display(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    /// Fails unless the location holds a store key.
    static func requireStore() throws {
        guard exists(keyPath) else {
            throw CubbyError("no store at \(display(home)); run cubby init first")
        }
    }

    /// Whether `secrets/` holds any `.bin` entry, of any kind.
    static func hasSecretEntries() throws -> Bool {
        guard exists(secretsDir) else { return false }
        do {
            return try FileManager.default.contentsOfDirectory(atPath: secretsDir).contains { $0.hasSuffix(".bin") }
        } catch {
            throw CubbyError("could not read \(location): \(error.localizedDescription)")
        }
    }

    /// Whether `home` already exists and holds anything other than `secrets/`.
    static func homeHoldsForeignEntries() throws -> Bool {
        guard exists(home) else { return false }
        do {
            return try FileManager.default.contentsOfDirectory(atPath: home).contains { $0 != "secrets" }
        } catch {
            throw CubbyError("could not read \(location): \(error.localizedDescription)")
        }
    }

    /// Creates the store directories, or brings existing ones to mode 0700: `createDirectory`
    /// leaves the mode of a directory that already exists untouched. A symbolic link in either
    /// place is refused, since `chmod` would follow it to a directory outside the store.
    static func createDirectories() throws {
        for dir in [home, secretsDir] {
            var info = stat()
            if lstat(dir, &info) == 0, (info.st_mode & S_IFMT) == S_IFLNK {
                throw CubbyError("\(display(dir)) is a symbolic link")
            }
            try makeDirectory(dir)
            guard chmod(dir, 0o700) == 0 else {
                let code = errno
                throw CubbyError("could not create \(location): \(message(for: code))")
            }
        }
    }

    /// Recreates `secrets/` if it has gone missing and fails, before any prompt, unless it is
    /// a directory this process can write into. Existing directories keep their mode.
    static func ensureWritableSecretsDirectory() throws {
        var info = stat()
        if stat(secretsDir, &info) != 0 { try makeDirectory(secretsDir) }
        guard stat(secretsDir, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else {
            throw CubbyError("\(display(secretsDir)) is not a directory")
        }
        guard access(secretsDir, W_OK | X_OK) == 0 else {
            let code = errno
            throw CubbyError("cannot write to \(display(secretsDir)): \(message(for: code))")
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

    /// Fails early, before any prompt, if writing `path` atomically would fail: on a leftover
    /// temporary file, or on something other than a regular file already sitting at `path`.
    static func checkWritable(recordAt path: String) throws {
        var info = stat()
        let tmp = path + ".tmp"
        if lstat(tmp, &info) == 0 {
            throw CubbyError("\(display(tmp)) is in the way; delete it and retry")
        }
        if lstat(path, &info) == 0, (info.st_mode & S_IFMT) != S_IFREG {
            throw CubbyError("\(display(path)) is in the way; delete it and retry")
        }
    }

    static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    /// Contents of `path`, or `nil` when there is no such file. Any other failure is reported
    /// as `could not read <what>`.
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
        let tmp = path + ".tmp"
        let fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else {
            let code = errno
            if code == EEXIST {
                throw CubbyError("\(display(tmp)) is in the way; delete it and retry")
            }
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
        try handle.close()
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

    /// Names of all stored secrets, sorted. Values are never read.
    static func secretNames() throws -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: secretsDir) else { return [] }
        let entries: [String]
        do {
            entries = try fm.contentsOfDirectory(atPath: secretsDir)
        } catch {
            throw CubbyError("could not read \(location): \(error.localizedDescription)")
        }
        return entries
            .filter { $0.hasSuffix(".bin") && isRegularFile(secretsDir + "/" + $0) }
            .map { String($0.dropLast(".bin".count)) }
            .sorted()
    }

    /// Follows symbolic links, so a linked record counts and a directory does not.
    private static func isRegularFile(_ path: String) -> Bool {
        var info = stat()
        return stat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
    }

    private static func message(for code: Int32) -> String {
        String(cString: strerror(code))
    }
}

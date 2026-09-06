import Foundation

@testable import cubby

/// Runs `body` with a directory that exists only for the call.
func withTemporaryDirectory<T>(_ body: (String) throws -> T) throws -> T {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cubby-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    return try body(dir.path)
}

/// Runs `body` with a store that does not exist yet: its root is a path inside a temporary
/// directory, and nothing has created it.
func withStore<T>(_ body: (Store) throws -> T) throws -> T {
    try withTemporaryDirectory { dir in try body(Store(home: dir + "/cubby")) }
}

/// Runs `body` with a store whose directories and key blob are in place.
///
/// The blob is a stand-in rather than a Secure Enclave key: `list` and `rm` only ever check
/// that a key is there.
func withInitializedStore<T>(_ body: (Store) throws -> T) throws -> T {
    try withStore { store in
        try store.ensureDirectories()
        try Store.writeAtomically(Data("stand-in".utf8), to: store.keyPath, action: "seed the store key")
        return try body(store)
    }
}

/// Puts one entry into the store's `secrets/` directory, under exactly the given name.
func plant(_ entry: String, in store: Store, contents: Data = Data()) throws {
    try Store.writeAtomically(contents, to: store.secretsDir + "/" + entry, action: "plant \(entry)")
}

/// Puts a record for `name` into the store.
func plantRecord(_ name: String, in store: Store) throws {
    try plant(SecretName(name).encoded + Store.recordSuffix, in: store)
}

/// The permission bits of the file or directory at `path`.
func mode(of path: String) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

func exists(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: path)
}

/// An `Output` that keeps everything written to it.
final class Recorded: @unchecked Sendable {
    private let lock = NSLock()
    private var written = Data()

    var output: Output {
        Output { [self] chunk in
            lock.lock()
            defer { lock.unlock() }
            written.append(chunk)
        }
    }

    var bytes: Data {
        lock.lock()
        defer { lock.unlock() }
        return written
    }

    var text: String { String(decoding: bytes, as: UTF8.self) }

    /// The complete lines written, without their terminators.
    var lines: [String] {
        let text = text
        guard !text.isEmpty else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
    }
}

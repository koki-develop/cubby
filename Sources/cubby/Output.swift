import Foundation

/// Where a command writes what the user asked for.
///
/// A command never reaches for standard output itself, so a caller can put the bytes
/// somewhere else.
struct Output: Sendable {
    /// Writes bytes verbatim. Fails when the destination rejects them.
    let write: @Sendable (Data) throws -> Void

    static let standardOutput = Output { data in
        try FileHandle.standardOutput.write(contentsOf: data)
    }

    /// Writes `text` and a newline, letting a failed write pass the way `print` does: a
    /// message the user was going to read is not worth failing the command over.
    func line(_ text: String) {
        try? write(Data((text + "\n").utf8))
    }
}

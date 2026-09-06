import Darwin
import Foundation

/// Interactive input from the controlling terminal.
enum Terminal {
    /// Size of the buffer handed to `readpassphrase`. The terminal's canonical mode caps a
    /// line at `MAX_INPUT` (1024 bytes on macOS) well before this buffer fills.
    private static let bufferSize = 4096

    /// Reads one line from `/dev/tty` with echo turned off. The line terminator is not part of
    /// the result. Fails when no terminal is available or the input does not fit the buffer.
    static func readSecret(prompt: String) throws -> Data {
        var buffer = [CChar](repeating: 0, count: bufferSize)
        defer { _ = buffer.withUnsafeMutableBytes { memset_s($0.baseAddress, $0.count, 0, $0.count) } }

        let result = buffer.withUnsafeMutableBufferPointer { pointer in
            readpassphrase(prompt, pointer.baseAddress, pointer.count, RPP_ECHO_OFF | RPP_REQUIRE_TTY)
        }
        guard result != nil else {
            let code = errno
            if code == ENOTTY {
                throw CubbyError("no terminal to read the value from; use --from-stdin")
            }
            throw CubbyError("could not read the value: \(String(cString: strerror(code)))")
        }

        let length = strlen(buffer)
        guard length < bufferSize - 1 else {
            throw CubbyError("value is too long to type in; use --from-stdin")
        }
        return Data(bytes: buffer, count: length)
    }
}

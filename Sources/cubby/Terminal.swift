import Darwin
import Foundation

/// Interactive input from the controlling terminal.
enum Terminal {
    /// Size of the buffer handed to `readpassphrase`. The terminal's canonical mode caps a
    /// line at `MAX_INPUT` (1024 bytes on macOS) well before this buffer fills.
    private static let bufferSize = 4096

    /// Reads one line from `/dev/tty` with echo turned off. The line terminator is not part of
    /// the result. Fails when no terminal is available.
    static func readSecret(prompt: String) throws -> Data {
        var buffer = [CChar](repeating: 0, count: bufferSize)

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
        return Data(bytes: buffer, count: length)
    }
}

import ArgumentParser
import CryptoKit
import Foundation

struct CubbyError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@main
struct Cubby: ParsableCommand {
    static let configuration = CommandConfiguration(
        subcommands: [
            InitCommand.self,
            SetCommand.self,
            GetCommand.self,
            RemoveCommand.self,
            ListCommand.self,
        ]
    )
}

struct InitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "init")

    func run() throws {
        let alreadyExists = CubbyError("a store already exists at \(Store.display(Store.home))")
        if try Store.hasKey() { throw alreadyExists }
        try Store.requireEmptyLocation()
        let key = try Enclave.generateKey()
        try Enclave.verifyRequiresInteraction(key.dataRepresentation)
        try Store.createDirectories()
        do {
            try Store.writeAtomically(
                key.dataRepresentation, to: Store.keyPath, action: "create \(Store.location)", replacing: false)
        } catch is Store.AlreadyExists {
            throw alreadyExists
        }
        print("Created a store at \(Store.display(Store.home))")
    }
}

struct SetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "set")

    @Argument(help: SecretName.argumentHelp, transform: SecretName.init) var name: SecretName

    @Flag(help: "Read the value from standard input instead of the terminal.") var fromStdin = false

    func run() throws {
        try Store.requireStore()
        let blob = try Enclave.loadVerifiedKeyBlob()
        try Store.ensureWritableSecretsDirectory()
        try Store.checkWritable(recordFor: name)
        let value: Data
        if fromStdin {
            do {
                value = try FileHandle.standardInput.readToEnd() ?? Data()
            } catch {
                throw CubbyError("could not read standard input: \(error.localizedDescription)")
            }
            guard !value.isEmpty else { throw CubbyError("no value on standard input") }
        } else {
            value = try Terminal.readSecret(prompt: "Value for \(name): ")
            guard !value.isEmpty else { throw CubbyError("no value was entered") }
        }
        let key = try Enclave.restoreKey(from: blob, operation: "write", name: name)
        let record = try Record.seal(value, name: name, key: key)
        try Store.writeAtomically(record, to: Store.recordPath(for: name), action: "save \"\(name)\"")
        print("Saved \"\(name)\"")
    }
}

struct GetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get")

    @Argument(help: SecretName.argumentHelp, transform: SecretName.init) var name: SecretName

    func run() throws {
        try Store.requireStore()
        guard let path = try Store.existingRecordPath(for: name),
            let record = try Store.read(path, what: "\"\(name)\"")
        else {
            throw CubbyError("no secret named \"\(name)\"")
        }
        let blob = try Enclave.loadVerifiedKeyBlob()
        let key = try Enclave.restoreKey(from: blob, operation: "read", name: name)
        guard let plaintext = try Record.open(record, name: name, key: key) else {
            throw CubbyError("\"\(name)\" cannot be decrypted")
        }
        do {
            try FileHandle.standardOutput.write(contentsOf: plaintext)
        } catch {
            throw CubbyError("could not write \"\(name)\": \(error.localizedDescription)")
        }
    }
}

struct RemoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "rm")

    @Argument(help: SecretName.argumentHelp, transform: SecretName.init) var name: SecretName

    func run() throws {
        try Store.requireStore()
        guard let path = try Store.existingRecordPath(for: name),
            try Store.remove(path, what: "\"\(name)\"")
        else {
            throw CubbyError("no secret named \"\(name)\"")
        }
        print("Deleted \"\(name)\"")
    }
}

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list")

    func run() throws {
        try Store.requireStore()
        let (names, refused) = try Store.secretNames()
        for name in names {
            print(name)
        }
        guard refused.isEmpty else {
            fflush(stdout)
            for problem in refused {
                FileHandle.standardError.write(Data("Error: \(problem)\n".utf8))
            }
            throw ExitCode.failure
        }
    }
}

extension SecretName {
    static var argumentHelp: ArgumentHelp {
        "The secret's name: 1 to \(maxLength) printable ASCII characters, no spaces."
    }
}

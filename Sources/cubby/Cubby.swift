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

/// A subcommand that works on one store and writes to one destination.
///
/// The environment is read in exactly one place, here, so that everything below a command
/// is handed the store it operates on rather than looking one up.
protocol StoreCommand: ParsableCommand {
    func run(in store: Store, to output: Output) throws
}

extension StoreCommand {
    func run() throws {
        try run(in: .fromEnvironment(), to: .standardOutput)
    }
}

struct InitCommand: StoreCommand {
    static let configuration = CommandConfiguration(commandName: "init")

    func run(in store: Store, to output: Output) throws {
        if store.hasKey() { throw CubbyError("a store already exists at \(Store.display(store.home))") }
        let key = try Enclave(store: store).generateKey()
        try store.ensureDirectories()
        try Store.writeAtomically(key.dataRepresentation, to: store.keyPath, action: "create \(store.location)")
        output.line("Created a store at \(Store.display(store.home))")
    }
}

struct SetCommand: StoreCommand {
    static let configuration = CommandConfiguration(commandName: "set")

    @Argument(help: SecretName.argumentHelp, transform: SecretName.init) var name: SecretName

    @Flag(help: "Read the value from standard input.") var fromStdin = false

    func run(in store: Store, to output: Output) throws {
        let enclave = Enclave(store: store)
        let blob = try enclave.loadKeyBlob()
        try store.ensureDirectories()
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
        let key = try enclave.restoreKey(from: blob, operation: "write", name: name)
        let record = try Record.seal(value, name: name, key: key)
        try Store.writeAtomically(record, to: store.recordPath(for: name), action: "save \"\(name)\"")
        output.line("Saved \"\(name)\"")
    }
}

struct GetCommand: StoreCommand {
    static let configuration = CommandConfiguration(commandName: "get")

    @Argument(help: SecretName.argumentHelp, transform: SecretName.init) var name: SecretName

    func run(in store: Store, to output: Output) throws {
        let enclave = Enclave(store: store)
        let blob = try enclave.loadKeyBlob()
        guard let record = try Store.read(store.recordPath(for: name), what: "\"\(name)\"") else {
            throw CubbyError("no secret named \"\(name)\"")
        }
        let key = try enclave.restoreKey(from: blob, operation: "read", name: name)
        guard let plaintext = try Record.open(record, name: name, key: key) else {
            throw CubbyError("\"\(name)\" cannot be decrypted")
        }
        do {
            try output.write(plaintext)
        } catch {
            throw CubbyError("could not write \"\(name)\": \(error.localizedDescription)")
        }
    }
}

struct RemoveCommand: StoreCommand {
    static let configuration = CommandConfiguration(commandName: "rm")

    @Argument(help: SecretName.argumentHelp, transform: SecretName.init) var name: SecretName

    func run(in store: Store, to output: Output) throws {
        try store.requireStore()
        guard try Store.remove(store.recordPath(for: name), what: "\"\(name)\"") else {
            throw CubbyError("no secret named \"\(name)\"")
        }
        output.line("Deleted \"\(name)\"")
    }
}

struct ListCommand: StoreCommand {
    static let configuration = CommandConfiguration(commandName: "list")

    func run(in store: Store, to output: Output) throws {
        try store.requireStore()
        for name in try store.secretNames() {
            output.line(name.text)
        }
    }
}

extension SecretName {
    static var argumentHelp: ArgumentHelp {
        "The secret's name."
    }
}

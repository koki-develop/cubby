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
        abstract: "Secret store gated by Touch ID.",
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
    static let configuration = CommandConfiguration(
        commandName: "init", abstract: "Create the store.")

    func run(in store: Store, to output: Output) throws {
        if store.hasKey() { throw store.alreadyAStore }
        let key = try Enclave(store: store).generateKey()
        try store.ensureDirectories()
        // The write is what refuses, not the check above: replacing a key that appeared in
        // between would leave every secret already sealed under it unreadable.
        guard try Store.createAtomically(
            key.dataRepresentation, to: store.keyPath, action: "create \(store.location)")
        else { throw store.alreadyAStore }
        output.line("Created a store at \(Store.display(store.home))")
    }
}

struct SetCommand: StoreCommand {
    static let configuration = CommandConfiguration(
        commandName: "set", abstract: "Save a secret.")

    @Argument(help: SecretName.argumentHelp, transform: SecretName.init) var name: SecretName

    @Flag(help: "Read the value from standard input.") var fromStdin = false

    @Flag(help: "Replace a secret that already exists.") var force = false

    func run(in store: Store, to output: Output) throws {
        let enclave = Enclave(store: store)
        let blob = try enclave.loadKeyBlob()
        let replacing = store.hasRecord(for: name)
        // Refused before the value is asked for: entering the secret and answering Touch ID
        // would otherwise be spent on a record that is thrown away.
        if replacing, !force { throw Store.alreadyExists(name) }
        try store.ensureDirectories()
        let value = try readValue()
        let key = try enclave.restoreKey(from: blob, for: replacing ? .replace(name) : .save(name))
        let record = try Record.seal(value, name: name, key: key)
        try write(record, to: store)
        output.line("Saved \"\(name)\"")
    }

    private func readValue() throws -> Data {
        if fromStdin {
            let value: Data
            do {
                value = try FileHandle.standardInput.readToEnd() ?? Data()
            } catch {
                throw CubbyError("could not read standard input: \(error.localizedDescription)")
            }
            guard !value.isEmpty else { throw CubbyError("no value on standard input") }
            return value
        }
        let value = try Terminal.readSecret(prompt: "Value for \(name): ")
        guard !value.isEmpty else { throw CubbyError("no value was entered") }
        return value
    }

    /// Writes the sealed record. Without `--force` the write is the one that refuses a taken
    /// name, so a record written since the first check is refused too rather than lost.
    private func write(_ record: Data, to store: Store) throws {
        let path = store.recordPath(for: name)
        let action = "save \"\(name)\""
        if force {
            try Store.writeAtomically(record, to: path, action: action)
        } else if try !Store.createAtomically(record, to: path, action: action) {
            throw Store.alreadyExists(name)
        }
    }
}

struct GetCommand: StoreCommand {
    static let configuration = CommandConfiguration(
        commandName: "get", abstract: "Print a secret.")

    @Argument(help: SecretName.argumentHelp, transform: SecretName.init) var name: SecretName

    func run(in store: Store, to output: Output) throws {
        let enclave = Enclave(store: store)
        let blob = try enclave.loadKeyBlob()
        guard let record = try Store.read(store.recordPath(for: name), what: "\"\(name)\"") else {
            throw CubbyError("no secret named \"\(name)\"")
        }
        let key = try enclave.restoreKey(from: blob, for: .read(name))
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
    static let configuration = CommandConfiguration(
        commandName: "rm", abstract: "Delete a secret.")

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
    static let configuration = CommandConfiguration(
        commandName: "list", abstract: "List the names of the stored secrets.")

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

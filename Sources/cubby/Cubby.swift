import ArgumentParser
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
        if Store.exists(Store.keyPath) { throw alreadyExists }
        if try Store.hasSecretEntries() {
            throw CubbyError(
                "\(Store.display(Store.home)) holds secrets but no store key; restore the key or delete \(Store.display(Store.secretsDir)) first")
        }
        if try Store.homeHoldsForeignEntries() {
            throw CubbyError("\(Store.display(Store.home)) already exists and is not empty")
        }
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

    @Argument var name: String

    @Flag var fromStdin = false

    func run() throws {
        let blob = try Enclave.loadVerifiedKeyBlob()
        try Store.ensureWritableSecretsDirectory()
        try Store.checkWritable(recordAt: Store.recordPath(for: name))
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

    @Argument var name: String

    func run() throws {
        try Store.requireStore()
        guard let record = try Store.read(Store.recordPath(for: name), what: "\"\(name)\"") else {
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

    @Argument var name: String

    func run() throws {
        try Store.requireStore()
        guard try Store.remove(Store.recordPath(for: name), what: "\"\(name)\"") else {
            throw CubbyError("no secret named \"\(name)\"")
        }
        print("Deleted \"\(name)\"")
    }
}

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list")

    func run() throws {
        try Store.requireStore()
        for name in try Store.secretNames() {
            print(name)
        }
    }
}

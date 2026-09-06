import ArgumentParser

@main
struct Thumb: ParsableCommand {
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

    // TODO: implement
    func run() throws { throw ExitCode.failure }
}

struct SetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "set")

    @Argument var name: String

    // TODO: implement
    func run() throws { throw ExitCode.failure }
}

struct GetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get")

    @Argument var name: String

    // TODO: implement
    func run() throws { throw ExitCode.failure }
}

struct RemoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "rm")

    @Argument var name: String

    // TODO: implement
    func run() throws { throw ExitCode.failure }
}

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list")

    // TODO: implement
    func run() throws { throw ExitCode.failure }
}

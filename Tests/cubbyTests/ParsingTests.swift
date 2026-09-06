import ArgumentParser
import Testing

@testable import cubby

@Suite struct ParsingTests {
    @Test func parsesEverySubcommand() throws {
        #expect(try Cubby.parseAsRoot(["init"]) is InitCommand)
        #expect(try Cubby.parseAsRoot(["set", "token"]) is SetCommand)
        #expect(try Cubby.parseAsRoot(["get", "token"]) is GetCommand)
        #expect(try Cubby.parseAsRoot(["rm", "token"]) is RemoveCommand)
        #expect(try Cubby.parseAsRoot(["list"]) is ListCommand)
    }

    @Test func rejectsAnUnknownSubcommand() {
        #expect(throws: (any Error).self) { try Cubby.parseAsRoot(["nope"]) }
    }

    @Test func turnsTheArgumentIntoASecretName() throws {
        let command = try #require(Cubby.parseAsRoot(["get", "a/b"]) as? GetCommand)
        #expect(command.name.text == "a/b")
    }

    @Test(arguments: ["a b", "", String(repeating: "a", count: SecretName.maxLength + 1)])
    func rejectsAnArgumentThatIsNotASecretName(_ text: String) {
        #expect(throws: (any Error).self) { try Cubby.parseAsRoot(["get", text]) }
    }

    @Test func requiresANameWhereOneIsExpected() {
        #expect(throws: (any Error).self) { try Cubby.parseAsRoot(["get"]) }
        #expect(throws: (any Error).self) { try Cubby.parseAsRoot(["rm"]) }
        #expect(throws: (any Error).self) { try Cubby.parseAsRoot(["set"]) }
    }

    @Test func readsTheFromStdinFlag() throws {
        #expect(try (Cubby.parseAsRoot(["set", "token"]) as? SetCommand)?.fromStdin == false)
        #expect(try (Cubby.parseAsRoot(["set", "token", "--from-stdin"]) as? SetCommand)?.fromStdin == true)
    }

    @Test func takesNoArgumentWhereNoneIsExpected() {
        #expect(throws: (any Error).self) { try Cubby.parseAsRoot(["list", "token"]) }
        #expect(throws: (any Error).self) { try Cubby.parseAsRoot(["init", "token"]) }
    }
}

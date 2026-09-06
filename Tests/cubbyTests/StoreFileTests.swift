import Foundation
import Testing

@testable import cubby

@Suite struct StoreReadTests {
    @Test func returnsNothingForAMissingFile() throws {
        try withTemporaryDirectory { dir in
            let contents = try Store.read(dir + "/absent", what: "the thing")
            #expect(contents == nil)
        }
    }

    @Test func returnsTheContents() throws {
        try withTemporaryDirectory { dir in
            let path = dir + "/file"
            try Data([0x00, 0xFF, 0x10]).write(to: URL(fileURLWithPath: path))
            #expect(try Store.read(path, what: "the thing") == Data([0x00, 0xFF, 0x10]))
        }
    }

    @Test func returnsNoBytesForAnEmptyFile() throws {
        try withTemporaryDirectory { dir in
            let path = dir + "/file"
            #expect(FileManager.default.createFile(atPath: path, contents: nil))
            let contents = try Store.read(path, what: "the thing")
            #expect(contents == Data())
        }
    }

    @Test func reportsAnythingOtherThanAMissingFileUnderWhatWasBeingRead() throws {
        try withTemporaryDirectory { dir in
            let error = #expect(throws: CubbyError.self) { try Store.read(dir, what: "the thing") }
            #expect(error?.description.hasPrefix("could not read the thing: ") == true)
        }
    }
}

@Suite struct StoreWriteTests {
    @Test func writesTheContentsAtMode0600() throws {
        try withTemporaryDirectory { dir in
            let path = dir + "/file"
            try Store.writeAtomically(Data("hello".utf8), to: path, action: "write it")
            #expect(try Store.read(path, what: "it") == Data("hello".utf8))
            #expect(try mode(of: path) == 0o600)
        }
    }

    @Test func leavesNoTemporaryFileBehind() throws {
        try withTemporaryDirectory { dir in
            let path = dir + "/file"
            try Store.writeAtomically(Data("hello".utf8), to: path, action: "write it")
            #expect(!exists(path + Store.temporarySuffix))
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir) == ["file"])
        }
    }

    /// The rename brings the temporary file's mode along, so a replaced file never keeps a
    /// wider mode than cubby writes.
    @Test func replacesAnExistingFileAndItsMode() throws {
        try withTemporaryDirectory { dir in
            let path = dir + "/file"
            #expect(
                FileManager.default.createFile(
                    atPath: path, contents: Data("old".utf8), attributes: [.posixPermissions: 0o644]))
            try Store.writeAtomically(Data("new".utf8), to: path, action: "write it")
            #expect(try Store.read(path, what: "it") == Data("new".utf8))
            #expect(try mode(of: path) == 0o600)
        }
    }

    @Test func writesNoBytesAsAnEmptyFile() throws {
        try withTemporaryDirectory { dir in
            let path = dir + "/file"
            try Store.writeAtomically(Data(), to: path, action: "write it")
            #expect(try Store.read(path, what: "it") == Data())
        }
    }

    @Test func reportsAMissingParentDirectoryUnderTheAction() throws {
        try withTemporaryDirectory { dir in
            let path = dir + "/absent/file"
            let error = #expect(throws: CubbyError.self) {
                try Store.writeAtomically(Data("hello".utf8), to: path, action: "save it")
            }
            #expect(error?.description.hasPrefix("could not save it: ") == true)
            #expect(!exists(path))
        }
    }

    /// A failed rename must leave both the destination and the directory as they were.
    @Test func keepsTheDestinationAndRemovesTheTemporaryFileWhenTheRenameFails() throws {
        try withTemporaryDirectory { dir in
            let path = dir + "/occupied"
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
            #expect(FileManager.default.createFile(atPath: path + "/child", contents: nil))

            let error = #expect(throws: CubbyError.self) {
                try Store.writeAtomically(Data("hello".utf8), to: path, action: "save it")
            }
            #expect(error?.description.hasPrefix("could not save it: ") == true)
            #expect(!exists(path + Store.temporarySuffix))
            #expect(exists(path + "/child"))
        }
    }
}

@Suite struct StoreRemoveTests {
    @Test func unlinksTheFileAndReportsThatItWasThere() throws {
        try withTemporaryDirectory { dir in
            let path = dir + "/file"
            #expect(FileManager.default.createFile(atPath: path, contents: nil))
            let removed = try Store.remove(path, what: "the thing")
            #expect(removed)
            #expect(!exists(path))
        }
    }

    @Test func reportsAMissingFileWithoutFailing() throws {
        try withTemporaryDirectory { dir in
            let removed = try Store.remove(dir + "/absent", what: "the thing")
            #expect(removed == false)
        }
    }

    @Test func refusesToRemoveADirectory() throws {
        try withTemporaryDirectory { dir in
            let path = dir + "/subdirectory"
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
            let error = #expect(throws: CubbyError.self) { try Store.remove(path, what: "the thing") }
            #expect(error?.description.hasPrefix("could not delete the thing: ") == true)
            #expect(exists(path))
        }
    }
}

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
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir) == ["file"])
        }
    }

    /// Two writes to one path must never splice: what is there afterwards is one payload or
    /// the other, whole. A temporary file named after the destination alone fails this, since
    /// the second writer truncates the first one's file before either has renamed.
    @Test func keepsConcurrentWritesToOnePathApart() throws {
        try withTemporaryDirectory { dir in
            let path = dir + "/file"
            let payloads = [
                Data(repeating: 0xAA, count: 1 << 18), Data(repeating: 0xBB, count: 1 << 18),
            ]
            for _ in 0..<20 {
                // Every writer is known to be running before any of them writes: a queue is
                // free to run them one after the other, which would pass either way.
                let running = DispatchSemaphore(value: 0)
                let start = DispatchSemaphore(value: 0)
                let finished = DispatchSemaphore(value: 0)
                for payload in payloads {
                    Thread {
                        running.signal()
                        start.wait()
                        #expect(throws: Never.self) {
                            try Store.writeAtomically(payload, to: path, action: "write it")
                        }
                        finished.signal()
                    }.start()
                }
                for _ in payloads { running.wait() }
                for _ in payloads { start.signal() }
                for _ in payloads { finished.wait() }
                let written = try Store.read(path, what: "it")
                #expect(written.map { payloads.contains($0) } == true)
            }
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
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir) == ["occupied"])
            #expect(exists(path + "/child"))
        }
    }
}

@Suite struct StoreCreateTests {
    @Test func writesTheContentsAtMode0600WhereNothingIs() throws {
        try withTemporaryDirectory { dir in
            let path = dir + "/file"
            let written = try Store.createAtomically(Data("hello".utf8), to: path, action: "write it")
            #expect(written)
            #expect(try Store.read(path, what: "it") == Data("hello".utf8))
            #expect(try mode(of: path) == 0o600)
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir) == ["file"])
        }
    }

    /// The file that is there keeps both its contents and its mode.
    @Test func writesNothingWhereAFileAlreadyIs() throws {
        try withTemporaryDirectory { dir in
            let path = dir + "/file"
            #expect(
                FileManager.default.createFile(
                    atPath: path, contents: Data("old".utf8), attributes: [.posixPermissions: 0o644]))
            let written = try Store.createAtomically(Data("new".utf8), to: path, action: "write it")
            #expect(written == false)
            #expect(try Store.read(path, what: "it") == Data("old".utf8))
            #expect(try mode(of: path) == 0o644)
        }
    }

    /// A refused write is still a temporary file that was created, and it may not be left
    /// behind: `secrets/` would collect one per refusal.
    @Test func leavesNoTemporaryFileBehindWhenItRefuses() throws {
        try withTemporaryDirectory { dir in
            let path = dir + "/file"
            #expect(FileManager.default.createFile(atPath: path, contents: Data("old".utf8)))
            let written = try Store.createAtomically(Data("new".utf8), to: path, action: "write it")
            #expect(written == false)
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir) == ["file"])
        }
    }

    /// An empty file is a file: the name is taken even where nothing was written under it.
    @Test func refusesAnEmptyFileTheSameWay() throws {
        try withTemporaryDirectory { dir in
            let path = dir + "/file"
            #expect(FileManager.default.createFile(atPath: path, contents: nil))
            let written = try Store.createAtomically(Data("new".utf8), to: path, action: "write it")
            #expect(written == false)
        }
    }

    /// Only a taken destination is answered with `false`; everything else is still reported.
    @Test func reportsAMissingParentDirectoryUnderTheAction() throws {
        try withTemporaryDirectory { dir in
            let path = dir + "/absent/file"
            let error = #expect(throws: CubbyError.self) {
                try Store.createAtomically(Data("hello".utf8), to: path, action: "save it")
            }
            #expect(error?.description.hasPrefix("could not save it: ") == true)
            #expect(!exists(path))
        }
    }

    /// A directory occupies the name as much as a file does, and is never removed to make room.
    @Test func refusesADirectoryWithoutTouchingIt() throws {
        try withTemporaryDirectory { dir in
            let path = dir + "/occupied"
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
            #expect(FileManager.default.createFile(atPath: path + "/child", contents: nil))
            let written = try Store.createAtomically(Data("hello".utf8), to: path, action: "save it")
            #expect(written == false)
            #expect(exists(path + "/child"))
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir) == ["occupied"])
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

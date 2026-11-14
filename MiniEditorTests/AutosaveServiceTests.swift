import XCTest
@testable import MiniEditor

@MainActor
final class AutosaveServiceTests: XCTestCase {
    private var dir: TemporaryDirectory!

    override func setUpWithError() throws {
        dir = try TemporaryDirectory()
    }

    override func tearDown() {
        dir.remove()
    }

    private func permissions(_ url: URL) throws -> Int {
        try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
    }

    // MARK: Ghi atomic

    func testAtomicWriteKeepsExecutablePermission() throws {
        let url = dir.url.appendingPathComponent("deploy.sh")
        try dir.makeFile("deploy.sh", contents: "echo 1\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)

        try AtomicFileWriter.write(Data("echo 2\n".utf8), to: url)

        XCTAssertEqual(try permissions(url), 0o755)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "echo 2\n")
        // Không để lại file tạm.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.url.path), ["deploy.sh"])
    }

    func testAtomicWriteThroughSymlinkKeepsSymlink() throws {
        try dir.makeFile("real.sh", contents: "a")
        let link = dir.url.appendingPathComponent("link.sh")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: dir.url.appendingPathComponent("real.sh"))

        try AtomicFileWriter.write(Data("b".utf8), to: link)

        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path).hasSuffix("real.sh"), true)
        XCTAssertEqual(try String(contentsOf: dir.url.appendingPathComponent("real.sh"), encoding: .utf8), "b")
    }

    // MARK: Kiểu xuống dòng & encoding

    func testCRLFIsDetectedNormalizedAndRestored() {
        let decoded = TextFileCodec.decode(Data("a\r\nb\r\n".utf8))
        XCTAssertEqual(decoded.lineEnding, .crlf)
        XCTAssertEqual(decoded.text, "a\nb\n")
        XCTAssertEqual(TextFileCodec.encode(decoded.text + "c\n", lineEnding: .crlf), Data("a\r\nb\r\nc\r\n".utf8))
    }

    func testPastedCRLFIsNotDoubledInCRLFFile() {
        XCTAssertEqual(TextFileCodec.encode("x\r\ny\n", lineEnding: .crlf), Data("x\r\ny\r\n".utf8))
    }

    func testLFStaysLF() {
        let decoded = TextFileCodec.decode(Data("a\nb\n".utf8))
        XCTAssertEqual(decoded.lineEnding, .lf)
        XCTAssertEqual(TextFileCodec.encode(decoded.text, lineEnding: .lf), Data("a\nb\n".utf8))
    }

    func testInvalidUTF8IsFlagged() {
        XCTAssertFalse(TextFileCodec.decode(Data([0x61, 0xFF, 0x62])).isUTF8)
        XCTAssertTrue(TextFileCodec.decode(Data("Tiếng Việt".utf8)).isUTF8)
    }

    // MARK: AutosaveService

    func testSavingCRLFFileKeepsLineEndingAndPermission() throws {
        let url = dir.url.appendingPathComponent("run.sh")
        try Data("echo a\r\necho b\r\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o744], ofItemAtPath: url.path)
        let buffer = try Buffer.load(url: url)
        let service = AutosaveService(draftStore: DraftStore(directory: dir.url.appendingPathComponent("drafts")))

        buffer.textStorage.append(NSAttributedString(string: "echo c\n"))
        service.bufferDidChange(buffer)
        XCTAssertEqual(buffer.saveState, .pending)
        service.save(buffer)

        XCTAssertEqual(try Data(contentsOf: url), Data("echo a\r\necho b\r\necho c\r\n".utf8))
        XCTAssertEqual(try permissions(url), 0o744)
        XCTAssertEqual(buffer.saveState, .saved)
        XCTAssertFalse(buffer.isDirty)
    }

    func testDebounceWritesOnceAfterDelay() async throws {
        let url = dir.url.appendingPathComponent("a.md")
        try dir.makeFile("a.md", contents: "")
        let buffer = try Buffer.load(url: url)
        let service = AutosaveService(draftStore: DraftStore(directory: dir.url))
        var writes = 0
        service.writeData = { data, target in
            writes += 1
            try AtomicFileWriter.write(data, to: target)
        }

        for char in "abc" {
            buffer.textStorage.append(NSAttributedString(string: String(char)))
            service.bufferDidChange(buffer)
        }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(writes, 0, "chưa hết 500ms thì chưa ghi")
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "abc")
    }

    func testDraftUsesShorterDelayAndDraftsFolder() async throws {
        let store = DraftStore(directory: dir.url.appendingPathComponent("drafts"))
        let id = UUID()
        try store.create(id)
        let buffer = Buffer(id: .draft(id), text: "")
        let service = AutosaveService(draftStore: store)

        buffer.textStorage.append(NSAttributedString(string: "nháp"))
        service.bufferDidChange(buffer)
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(try store.read(id), "nháp")
    }

    func testWriteFailureKeepsContentAndRetriesNextSave() throws {
        let url = dir.url.appendingPathComponent("a.sh")
        try dir.makeFile("a.sh", contents: "")
        let buffer = try Buffer.load(url: url)
        let service = AutosaveService(draftStore: DraftStore(directory: dir.url))
        var shouldFail = true
        service.writeData = { data, target in
            if shouldFail { throw CocoaError(.fileWriteOutOfSpace) }
            try AtomicFileWriter.write(data, to: target)
        }

        buffer.textStorage.append(NSAttributedString(string: "keep me"))
        service.bufferDidChange(buffer)
        service.save(buffer)
        guard case .failed = buffer.saveState else { return XCTFail("phải ở trạng thái lỗi") }
        XCTAssertTrue(buffer.isDirty)
        XCTAssertEqual(buffer.text, "keep me")

        shouldFail = false
        service.save(buffer)
        XCTAssertEqual(buffer.saveState, .saved)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "keep me")
    }

    func testReadOnlyBufferIsNeverSaved() throws {
        let url = dir.url.appendingPathComponent("latin.txt")
        try Data([0x61, 0xFF]).write(to: url)
        let buffer = try Buffer.load(url: url)
        let service = AutosaveService(draftStore: DraftStore(directory: dir.url))
        service.bufferDidChange(buffer)
        service.save(buffer)
        XCTAssertEqual(try Data(contentsOf: url), Data([0x61, 0xFF]))
    }

    func testAttributeOnlyChangesDoNotMarkEdit() {
        let buffer = Buffer(id: .draft(UUID()), text: "abc")
        var edits = 0
        buffer.onEdit = { edits += 1 }
        buffer.textStorage.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: 0, length: 3))
        XCTAssertEqual(edits, 0)
        buffer.textStorage.append(NSAttributedString(string: "d"))
        XCTAssertEqual(edits, 1)
    }
}

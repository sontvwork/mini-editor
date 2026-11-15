import XCTest
@testable import MiniEditor

@MainActor
final class SidebarFileOperationTests: XCTestCase {
    private var dir: TemporaryDirectory!
    private var state: AppState!

    override func setUp() async throws {
        dir = try TemporaryDirectory()
        try dir.makeFile("ops/a.txt", contents: "echo hi\r\n")
        state = AppState(draftStore: DraftStore(directory: dir.url.appendingPathComponent("drafts")))
    }

    override func tearDown() async throws {
        dir.remove()
    }

    private func url(_ path: String) -> URL { dir.url.appendingPathComponent(path) }

    func testCreateFileMakesEmptyFileAndOpensIt() throws {
        let ops = state.addWorkspace(url: url("ops"))
        let created = try state.createFile(named: " new.sh ", in: ops)
        XCTAssertEqual(created.lastPathComponent, "new.sh")
        XCTAssertEqual(try Data(contentsOf: created), Data())
        XCTAssertEqual(state.activeBuffer?.id, .file(path: created))
    }

    func testCreateFileRejectsExistingAndInvalidNames() {
        let ops = state.addWorkspace(url: url("ops"))
        XCTAssertThrowsError(try state.createFile(named: "a.txt", in: ops))
        XCTAssertThrowsError(try state.createFile(named: "x/y", in: ops))
        XCTAssertThrowsError(try state.createFile(named: "  ", in: ops))
        XCTAssertEqual(try String(contentsOf: url("ops/a.txt"), encoding: .utf8), "echo hi\r\n")
    }

    func testRenameOpenFileKeepsTabContentAndRedetectsLanguage() throws {
        state.addWorkspace(url: url("ops"))
        try state.openFile(url("ops/a.txt"))
        let buffer = try XCTUnwrap(state.activeBuffer)
        buffer.textStorage.append(NSAttributedString(string: "chưa lưu"))

        try state.renameFile(url("ops/a.txt"), to: "b.sh")

        XCTAssertFalse(FileManager.default.fileExists(atPath: url("ops/a.txt").path))
        XCTAssertEqual(try String(contentsOf: url("ops/b.sh"), encoding: .utf8), "echo hi\r\nchưa lưu")
        XCTAssertTrue(state.activeBuffer === buffer)
        XCTAssertEqual(buffer.id, .file(path: url("ops/b.sh")))
        XCTAssertEqual(buffer.language, .bash)
        XCTAssertNil(state.buffers[.file(path: url("ops/a.txt"))])
    }

    func testRenameRefusesToOverwrite() throws {
        try dir.makeFile("ops/b.txt", contents: "b")
        XCTAssertThrowsError(try state.renameFile(url("ops/a.txt"), to: "b.txt"))
        XCTAssertEqual(try String(contentsOf: url("ops/b.txt"), encoding: .utf8), "b")
    }
}

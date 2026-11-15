import XCTest
@testable import MiniEditor

/// SPEC §3.6: file bị sửa từ bên ngoài.
@MainActor
final class ExternalChangeTests: XCTestCase {
    private var dir: TemporaryDirectory!
    private var state: AppState!
    private var fileURL: URL!

    override func setUp() async throws {
        dir = try TemporaryDirectory()
        try dir.makeFile("ops/run.sh", contents: "echo 1\necho 2\n")
        fileURL = dir.url.appendingPathComponent("ops/run.sh")
        state = AppState(draftStore: DraftStore(directory: dir.url.appendingPathComponent("drafts")))
        state.addWorkspace(url: dir.url.appendingPathComponent("ops"))
        try state.openFile(fileURL)
    }

    override func tearDown() async throws {
        dir.remove()
    }

    private var buffer: Buffer { state.buffers[.file(path: fileURL)]! }

    private func writeExternally(_ text: String) throws {
        try Data(text.utf8).write(to: fileURL)
    }

    private func disk() throws -> String {
        try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func type(_ text: String) {
        buffer.textStorage.append(NSAttributedString(string: text))
    }

    func testOwnWriteIsIgnored() throws {
        type("echo 3\n")
        state.saveNow(buffer)
        state.checkExternalChanges(paths: nil)
        XCTAssertNil(buffer.externalChange)
        XCTAssertEqual(buffer.text, "echo 1\necho 2\necho 3\n")
    }

    func testCleanBufferReloadsAndKeepsCursor() throws {
        buffer.selection = NSRange(location: 9, length: 2) // trong "echo 2"
        try writeExternally("# mới\necho 1\necho 2\n")
        var reloaded = 0
        state.onBufferReload = { _ in reloaded += 1 }

        state.checkExternalChanges(paths: nil)

        XCTAssertEqual(buffer.text, "# mới\necho 1\necho 2\n")
        XCTAssertEqual(buffer.selection, NSRange(location: 15, length: 2), "con trỏ dời theo dòng chèn phía trên")
        XCTAssertNil(buffer.externalChange)
        XCTAssertFalse(buffer.isDirty)
        XCTAssertEqual(reloaded, 1)
        // Nạp lại không bị coi là gõ → không ghi ngược ra đĩa.
        XCTAssertEqual(buffer.saveState, .saved)
    }

    func testOnlyMatchingPathsAreChecked() throws {
        try writeExternally("khác\n")
        state.checkExternalChanges(paths: ["/không/liên/quan.sh"])
        XCTAssertEqual(buffer.text, "echo 1\necho 2\n")
        state.checkExternalChanges(paths: [DirectoryWatcher.realPath(fileURL.path)])
        XCTAssertEqual(buffer.text, "khác\n")
    }

    func testDirtyBufferPausesAutosaveAndShowsConflict() throws {
        type("của tôi\n")
        try writeExternally("bên ngoài\n")
        state.checkExternalChanges(paths: nil)

        XCTAssertEqual(buffer.externalChange, .modified)
        XCTAssertEqual(buffer.text, "echo 1\necho 2\ncủa tôi\n")
        state.saveAllBuffers()
        XCTAssertEqual(try disk(), "bên ngoài\n", "không tự lưu đè khi đang xung đột")

        // Đóng tab bằng × không làm mất nội dung đang xung đột.
        state.closeTab(buffer.id)
        XCTAssertNotNil(state.buffers[.file(path: fileURL)])
    }

    func testKeepMineOverwritesDisk() throws {
        type("của tôi\n")
        try writeExternally("bên ngoài\n")
        state.checkExternalChanges(paths: nil)

        state.keepMine(buffer)

        XCTAssertNil(buffer.externalChange)
        XCTAssertEqual(buffer.saveState, .saved)
        XCTAssertEqual(try disk(), "echo 1\necho 2\ncủa tôi\n")
    }

    func testReloadFromDiskDropsMine() throws {
        type("của tôi\n")
        try writeExternally("bên ngoài\n")
        state.checkExternalChanges(paths: nil)

        state.reloadFromDisk(buffer)

        XCTAssertNil(buffer.externalChange)
        XCTAssertFalse(buffer.isDirty)
        XCTAssertEqual(buffer.text, "bên ngoài\n")
        XCTAssertFalse(buffer.undoManager.canUndo)
    }

    func testAutosaveDoesNotClobberExternalEditBeforeWatcherFires() throws {
        type("của tôi\n")
        try writeExternally("bên ngoài\n") // watcher chưa kịp báo
        state.saveNow(buffer)
        XCTAssertEqual(try disk(), "bên ngoài\n")
        XCTAssertEqual(buffer.externalChange, .modified)
    }

    func testDeletedFileKeepsContentAndCanBeSavedAgain() throws {
        try FileManager.default.removeItem(at: fileURL)
        state.checkExternalChanges(paths: nil)
        XCTAssertEqual(buffer.externalChange, .deleted)
        XCTAssertEqual(buffer.text, "echo 1\necho 2\n")

        type("thêm\n")
        state.saveAllBuffers()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "không tự tạo lại file")

        state.keepMine(buffer) // [Lưu lại]
        XCTAssertNil(buffer.externalChange)
        XCTAssertEqual(try disk(), "echo 1\necho 2\nthêm\n")
    }

    func testDeletedFileCloseTabDiscards() throws {
        type("thêm\n")
        try FileManager.default.removeItem(at: fileURL)
        state.checkExternalChanges(paths: nil)

        state.closeTab(buffer.id, discardingChanges: true)

        XCTAssertTrue(state.buffers.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testFileRecreatedIdenticallyClearsDeletedState() throws {
        try FileManager.default.removeItem(at: fileURL)
        state.checkExternalChanges(paths: nil)
        try writeExternally("echo 1\necho 2\n")
        state.checkExternalChanges(paths: nil)
        XCTAssertNil(buffer.externalChange)
    }

    func testRenamedFileIsReportedAsDeleted() throws {
        try FileManager.default.moveItem(at: fileURL, to: dir.url.appendingPathComponent("ops/new.sh"))
        state.checkExternalChanges(paths: nil)
        XCTAssertEqual(buffer.externalChange, .deleted)
    }

    func testWatchedDirectoriesAreRealParentDirectories() {
        XCTAssertEqual(state.watchedDirectories, [DirectoryWatcher.realPath(dir.url.appendingPathComponent("ops").path)])
    }

    func testFileWatcherReportsChangedFilePath() async throws {
        let realFile = DirectoryWatcher.realPath(fileURL.path)
        let changed = expectation(description: "file đổi được báo")
        changed.assertForOverFulfill = false
        let watcher = DirectoryWatcher(debounce: .milliseconds(100), fileEvents: true) { changes in
            if changes.paths.contains(realFile) { changed.fulfill() }
        }
        watcher.watch(paths: Array(state.watchedDirectories))
        try await Task.sleep(for: .milliseconds(300))
        try writeExternally("echo đổi\n")
        await fulfillment(of: [changed], timeout: 5)
        watcher.stop()
    }
}

final class TextDiffTests: XCTestCase {
    private func change(_ old: String, _ new: String) -> TextDiff.Change {
        TextDiff.change(from: old as NSString, to: new as NSString)
    }

    func testFindsMiddleChange() {
        XCTAssertEqual(change("abcXdef", "abcYYdef"),
                       .init(oldRange: NSRange(location: 3, length: 1), newRange: NSRange(location: 3, length: 2)))
    }

    func testIdenticalHasEmptyChange() {
        XCTAssertEqual(change("abc", "abc").oldRange.length, 0)
        XCTAssertEqual(change("abc", "abc").newRange.length, 0)
    }

    func testRepeatedCharactersDoNotOverlap() {
        let c = change("aa", "aaa")
        XCTAssertEqual(c.oldRange.length, 0)
        XCTAssertEqual(c.newRange.length, 1)
    }

    func testDoesNotSplitSurrogatePair() {
        // 😀 = D83D DE00, 😁 = D83D DE01: chung nửa đầu.
        let c = change("x😀y", "x😁y")
        XCTAssertEqual(c.oldRange, NSRange(location: 1, length: 2))
        XCTAssertEqual(c.newRange, NSRange(location: 1, length: 2))
    }

    func testAdjustSelection() {
        let c = TextDiff.Change(oldRange: NSRange(location: 5, length: 2), newRange: NSRange(location: 5, length: 4))
        XCTAssertEqual(TextDiff.adjust(NSRange(location: 2, length: 1), for: c), NSRange(location: 2, length: 1))
        XCTAssertEqual(TextDiff.adjust(NSRange(location: 10, length: 0), for: c), NSRange(location: 12, length: 0))
        XCTAssertEqual(TextDiff.adjust(NSRange(location: 6, length: 0), for: c), NSRange(location: 6, length: 0))
    }
}

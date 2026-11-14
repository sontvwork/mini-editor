import XCTest
@testable import MiniEditor

@MainActor
final class DraftFlowTests: XCTestCase {
    private var dir: TemporaryDirectory!
    private var state: AppState!

    override func setUpWithError() throws {
        dir = try TemporaryDirectory()
        try dir.makeFile("ops/a.sh", contents: "a")
        try dir.makeFile("web/b.md", contents: "b")
        state = AppState(draftStore: DraftStore(directory: dir.url.appendingPathComponent("drafts")))
    }

    override func tearDown() {
        dir.remove()
    }

    private func url(_ path: String) -> URL { dir.url.appendingPathComponent(path) }

    func testNewDraftGoesToFocusedColumnWithIncrementingTitle() throws {
        state.addWorkspace(url: url("ops"))
        try state.openFile(url("ops/a.sh"))
        let first = try state.newDraft()
        let second = try state.newDraft()
        XCTAssertEqual(state.drafts.map(\.title), ["Chưa đặt tên-1", "Chưa đặt tên-2"])
        XCTAssertEqual(state.layout.columns.count, 1)
        XCTAssertEqual(state.layout.focusedColumn.activeTab?.buffer, .draft(second))
        XCTAssertTrue(state.draftStore.exists(first))
        XCTAssertEqual(state.buffers[.draft(first)]?.language, .markdown)
    }

    func testClosingDraftTabKeepsDraftAndContent() throws {
        let id = try state.newDraft()
        state.buffers[.draft(id)]?.textStorage.append(NSAttributedString(string: "giữ lại"))
        state.closeTab(.draft(id))
        XCTAssertEqual(state.drafts.map(\.id), [id])
        XCTAssertEqual(try state.draftStore.read(id), "giữ lại")

        try state.openDraft(id)
        XCTAssertEqual(state.activeBuffer?.text, "giữ lại")
    }

    func testSaveDraftIntoWorkspaceMovesTabToThatColumn() throws {
        let ops = state.addWorkspace(url: url("ops"))
        let web = state.addWorkspace(url: url("web"))
        try state.openFile(url("ops/a.sh"))
        try state.openFile(url("web/b.md")) // focus cột web
        let id = try state.newDraft()       // nháp ở cột web
        state.buffers[.draft(id)]?.textStorage.append(NSAttributedString(string: "#!/bin/bash\necho hi\n"))

        try state.saveDraft(id, to: url("ops/new.sh"))

        let fileID = BufferID.file(path: url("ops/new.sh"))
        XCTAssertEqual(try String(contentsOf: url("ops/new.sh"), encoding: .utf8), "#!/bin/bash\necho hi\n")
        XCTAssertTrue(state.drafts.isEmpty)
        XCTAssertFalse(state.draftStore.exists(id))
        XCTAssertEqual(state.layout.columns.map(\.workspaceID), [ops, web])
        XCTAssertEqual(state.layout.columns[0].tabs.map(\.buffer).last, fileID)
        XCTAssertEqual(state.layout.focusedIndex, 0)
        XCTAssertEqual(state.activeBuffer?.language, .bash)
        XCTAssertNil(state.buffers[.draft(id)])
    }

    func testSaveDraftOutsideWorkspaceStaysInPlace() throws {
        let id = try state.newDraft()
        try state.saveDraft(id, to: url("elsewhere.md"))
        XCTAssertEqual(state.layout.columns.count, 1)
        XCTAssertEqual(state.layout.columns[0].tabs.map(\.buffer), [.file(path: url("elsewhere.md"))])
    }

    func testEditsAfterSaveAsGoToNewFile() throws {
        let id = try state.newDraft()
        try state.saveDraft(id, to: url("x.md"))
        let buffer = try XCTUnwrap(state.activeBuffer)
        buffer.textStorage.append(NSAttributedString(string: "more"))
        state.saveNow(buffer)
        XCTAssertEqual(try String(contentsOf: url("x.md"), encoding: .utf8), "more")
    }
}

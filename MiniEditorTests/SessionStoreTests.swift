import XCTest
@testable import MiniEditor

@MainActor
final class SessionStoreTests: XCTestCase {
    private var dir: TemporaryDirectory!

    override func setUpWithError() throws {
        dir = try TemporaryDirectory()
        try dir.makeFile("ops/deploy/prod.sh", contents: "echo prod\n")
        try dir.makeFile("ops/notes.md", contents: "line1\nline2\n")
        try dir.makeFile("web/index.md", contents: "# web\n")
    }

    override func tearDown() {
        dir.remove()
    }

    private func url(_ path: String) -> URL { dir.url.appendingPathComponent(path) }

    private func makeState() -> AppState {
        AppState(draftStore: DraftStore(directory: url("support/drafts")))
    }

    private let windowState = AppState.WindowLayoutState(
        window: Session.WindowState(frame: "{{100, 100}, {1400, 860}}"),
        sidebar: Session.SidebarState(visible: true, width: 240),
        columnWidthRatios: [0.6, 0.4]
    )

    func testJSONMatchesSpecShape() throws {
        let session = Session(
            fontSize: 13,
            window: Session.WindowState(frame: "{{100, 100}, {1400, 860}}"),
            sidebar: Session.SidebarState(visible: true, width: 240),
            workspaces: [Session.WorkspaceState(id: UUID(), path: "/tmp/ops", expandedDirs: ["deploy"], collapsed: false)],
            drafts: [DraftInfo(id: UUID(), title: "Chưa đặt tên-1", language: .markdown,
                               createdAt: Date(timeIntervalSince1970: 1_794_000_000))],
            columns: [Session.ColumnState(workspaceId: nil, widthRatio: 1, activeIndex: 0,
                                          tabs: [.file(path: "/tmp/ops/a.sh"), .draft(id: UUID())])],
            focusedColumn: 0,
            bufferState: ["/tmp/ops/a.sh": Session.BufferState(selection: [120, 0], scrollY: 0, language: .bash)]
        )
        let data = try SessionStore.encode(session)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 1)
        let tabs = try XCTUnwrap(((json["columns"] as? [[String: Any]])?.first?["tabs"]) as? [[String: Any]])
        XCTAssertEqual(tabs[0]["kind"] as? String, "file")
        XCTAssertEqual(tabs[1]["kind"] as? String, "draft")
        let draft = try XCTUnwrap((json["drafts"] as? [[String: Any]])?.first)
        XCTAssertTrue((draft["createdAt"] as? String)?.hasSuffix("Z") == true)
        XCTAssertEqual(try SessionStore.decode(data), session)
    }

    func testCorruptSessionLoadsAsNil() throws {
        try Data("{not json".utf8).write(to: url("session.json"))
        XCTAssertNil(SessionStore(fileURL: url("session.json")).load())
        XCTAssertNil(SessionStore(fileURL: url("missing.json")).load())
    }

    func testRoundTripRestoresWorkspacesColumnsTabsAndCursor() throws {
        let state = makeState()
        let ops = state.addWorkspace(url: url("ops"))
        let web = state.addWorkspace(url: url("web"))
        state.setDirectory("deploy", expanded: true, in: ops)
        state.setFontSize(15)
        try state.openFile(url("ops/deploy/prod.sh"))
        try state.openFile(url("ops/notes.md"))
        state.buffers[.file(path: url("ops/notes.md"))]?.selection = NSRange(location: 7, length: 2)
        try state.openFile(url("web/index.md"))
        let draftID = try state.newDraft() // vào cột web (đang focus)
        state.buffers[.draft(draftID)]?.textStorage.append(NSAttributedString(string: "prompt"))
        state.saveAllBuffers()

        let session = state.makeSession(window: windowState)
        let store = SessionStore(fileURL: url("support/session.json"))
        store.provider = { session }
        store.saveNow()

        let restored = makeState()
        restored.restore(try XCTUnwrap(store.load()))

        XCTAssertEqual(restored.fontSize, 15)
        XCTAssertEqual(restored.workspaces.map(\.id), [ops, web])
        XCTAssertEqual(restored.workspace(id: ops)?.expandedDirs, ["deploy"])
        XCTAssertEqual(restored.layout.columns.map(\.workspaceID), [ops, web])
        XCTAssertEqual(restored.layout.columns[0].tabs.map(\.buffer),
                       [.file(path: url("ops/deploy/prod.sh")), .file(path: url("ops/notes.md"))])
        XCTAssertEqual(restored.layout.columns[0].activeIndex, 1)
        XCTAssertEqual(restored.layout.focusedIndex, 1)
        XCTAssertEqual(restored.activeBuffer?.text, "prompt")
        XCTAssertEqual(restored.drafts.map(\.title), ["Chưa đặt tên-1"])
        XCTAssertEqual(restored.buffers[.file(path: url("ops/notes.md"))]?.selection, NSRange(location: 7, length: 2))
        XCTAssertEqual(session.columns.map(\.widthRatio), [0.6, 0.4])
    }

    func testMissingFileTabIsSkippedAndColumnRulesApply() throws {
        let state = makeState()
        state.addWorkspace(url: url("ops"))
        state.addWorkspace(url: url("web"))
        try state.openFile(url("ops/notes.md"))
        try state.openFile(url("web/index.md"))
        let session = state.makeSession(window: windowState)

        try FileManager.default.removeItem(at: url("web/index.md"))
        let restored = makeState()
        restored.restore(session)

        XCTAssertEqual(restored.layout.columns.count, 1)
        XCTAssertEqual(restored.layout.allTabs.map(\.buffer), [.file(path: url("ops/notes.md"))])
        XCTAssertEqual(restored.layout.focusedIndex, 0)
    }

    func testMissingWorkspaceIsKeptAndMarked() throws {
        let state = makeState()
        let web = state.addWorkspace(url: url("web"))
        let session = state.makeSession(window: windowState)
        try FileManager.default.removeItem(at: url("web"))

        let restored = makeState()
        restored.restore(session)
        XCTAssertEqual(restored.workspaces.map(\.id), [web])
        XCTAssertEqual(restored.workspace(id: web)?.isMissing, true)
    }

    func testDebouncedSaveWritesAfterOneSecond() async throws {
        let store = SessionStore(fileURL: url("support/session.json"))
        let state = makeState()
        store.provider = { state.makeSession(window: self.windowState) }
        store.scheduleSave()
        store.scheduleSave()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertNil(store.load())
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertNotNil(store.load())
    }
}

@MainActor
final class EdgeCaseTests: XCTestCase {
    func testCorruptSessionIsBackedUpNotOverwritten() throws {
        let dir = try TemporaryDirectory()
        defer { dir.remove() }
        try dir.makeFile("session.json", contents: "{ hỏng")
        let store = SessionStore(fileURL: dir.url.appendingPathComponent("session.json"))
        XCTAssertNil(store.load())
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.url.path)
        XCTAssertFalse(files.contains("session.json"))
        let backup = try XCTUnwrap(files.first { $0.hasPrefix("session.corrupt-") && $0.hasSuffix(".json") })
        XCTAssertEqual(try String(contentsOf: dir.url.appendingPathComponent(backup), encoding: .utf8), "{ hỏng")
    }

    func testWorkspaceMissingStateFollowsDisk() throws {
        let dir = try TemporaryDirectory()
        defer { dir.remove() }
        try dir.makeDirectory("ops")
        let state = AppState()
        let id = state.addWorkspace(url: dir.url.appendingPathComponent("ops"))
        var changes = 0
        state.onWorkspacesChange = { changes += 1 }

        try FileManager.default.removeItem(at: dir.url.appendingPathComponent("ops"))
        state.refreshMissingWorkspaces()
        XCTAssertEqual(state.workspace(id: id)?.isMissing, true)

        state.refreshMissingWorkspaces()
        XCTAssertEqual(changes, 1, "không đổi thì không báo")

        try dir.makeDirectory("ops")
        state.refreshMissingWorkspaces()
        XCTAssertEqual(state.workspace(id: id)?.isMissing, false)
        XCTAssertEqual(changes, 2)
    }

    func testDiskStampRecordedOnLoadAndSave() throws {
        let dir = try TemporaryDirectory()
        defer { dir.remove() }
        try dir.makeFile("a.sh", contents: "echo 1\n")
        let url = dir.url.appendingPathComponent("a.sh")
        let state = AppState(draftStore: DraftStore(directory: dir.url.appendingPathComponent("drafts")))
        try state.openFile(url)
        let buffer = try XCTUnwrap(state.buffers[.file(path: url)])
        XCTAssertEqual(buffer.diskStamp, DiskStamp.of(url))

        buffer.textStorage.append(NSAttributedString(string: "echo 2\n"))
        state.saveNow(buffer)
        XCTAssertEqual(buffer.diskStamp, DiskStamp.of(url), "sau khi tự ghi, dấu vết khớp → watcher bỏ qua mà không đọc file")
        XCTAssertNotNil(buffer.diskStamp)
    }
}

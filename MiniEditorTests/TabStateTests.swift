import XCTest
@testable import MiniEditor

@MainActor
final class TabStateTests: XCTestCase {
    private var dir: TemporaryDirectory!

    override func setUpWithError() throws {
        dir = try TemporaryDirectory()
        try dir.makeFile("a/one.sh", contents: "echo 1\n")
        try dir.makeFile("a/two.sh", contents: "echo 2\n")
        try dir.makeFile("b/three.md", contents: "# 3\n")
        try dir.makeFile("a/nested/inner.sh", contents: "x")
    }

    override func tearDown() {
        dir.remove()
    }

    private func url(_ path: String) -> URL { dir.url.appendingPathComponent(path) }

    func testOpenFilesCreatesColumnsPerWorkspace() throws {
        let state = AppState()
        let a = state.addWorkspace(url: url("a"))
        let b = state.addWorkspace(url: url("b"))
        var changes = 0
        state.onLayoutChange = { changes += 1 }

        try state.openFile(url("a/one.sh"))
        try state.openFile(url("b/three.md"))
        try state.openFile(url("a/two.sh"))

        XCTAssertEqual(state.layout.columns.map(\.workspaceID), [a, b])
        XCTAssertEqual(state.layout.focusedIndex, 0)
        XCTAssertEqual(state.activeBuffer?.textStorage.string, "echo 2\n")
        XCTAssertEqual(state.buffers.count, 3)
        XCTAssertEqual(changes, 3)
    }

    func testReopeningSameFileReusesBuffer() throws {
        let state = AppState()
        state.addWorkspace(url: url("a"))
        try state.openFile(url("a/one.sh"))
        let buffer = state.activeBuffer
        try state.openFile(url("a/../a/one.sh"))
        XCTAssertTrue(state.activeBuffer === buffer)
        XCTAssertEqual(state.layout.allTabs.count, 1)
    }

    func testClosingTabReleasesBuffer() throws {
        let state = AppState()
        state.addWorkspace(url: url("a"))
        try state.openFile(url("a/one.sh"))
        state.closeActiveTab()
        XCTAssertTrue(state.buffers.isEmpty)
        XCTAssertEqual(state.layout.columns.count, 1)
    }

    func testNestedWorkspacePicksDeepest() {
        let state = AppState()
        let outer = state.addWorkspace(url: url("a"))
        let inner = state.addWorkspace(url: url("a/nested"))
        XCTAssertEqual(state.workspaceID(containing: url("a/nested/inner.sh")), inner)
        XCTAssertEqual(state.workspaceID(containing: url("a/one.sh")), outer)
        XCTAssertNil(state.workspaceID(containing: url("b/three.md")))
        // "a" không được khớp nhầm với "ab/..."
        XCTAssertNil(state.workspaceID(containing: URL(fileURLWithPath: dir.url.path + "/ab/x")))
    }

    func testRemovingWorkspaceClosesItsTabs() throws {
        let state = AppState()
        let a = state.addWorkspace(url: url("a"))
        let b = state.addWorkspace(url: url("b"))
        try state.openFile(url("a/one.sh"))
        try state.openFile(url("b/three.md"))
        state.removeWorkspace(id: a)
        XCTAssertEqual(state.layout.columns.map(\.workspaceID), [b])
        XCTAssertEqual(state.buffers.count, 1)
    }

    func testOpeningMissingFileThrowsAndLeavesLayout() {
        let state = AppState()
        XCTAssertThrowsError(try state.openFile(url("missing.sh")))
        XCTAssertEqual(state.layout, ColumnLayout.initial().withSameIDs(as: state.layout))
        XCTAssertTrue(state.buffers.isEmpty)
    }

    func testNonUTF8FileOpensReadOnly() throws {
        try Data([0x66, 0xFF, 0xFE, 0x67]).write(to: url("a/latin.txt"))
        let buffer = try Buffer.load(url: url("a/latin.txt"))
        XCTAssertTrue(buffer.isReadOnly)
        XCTAssertFalse(try Buffer.load(url: url("a/one.sh")).isReadOnly)
    }
}

private extension ColumnLayout {
    /// Bố cục rỗng ban đầu nhưng dùng lại id cột của `other` để so sánh được.
    func withSameIDs(as other: ColumnLayout) -> ColumnLayout {
        var copy = self
        for index in copy.columns.indices where other.columns.indices.contains(index) {
            copy.columns[index] = Column(id: other.columns[index].id,
                                         workspaceID: copy.columns[index].workspaceID,
                                         tabs: copy.columns[index].tabs,
                                         activeIndex: copy.columns[index].activeIndex)
        }
        return copy
    }
}

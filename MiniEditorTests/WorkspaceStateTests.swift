import XCTest
@testable import MiniEditor

@MainActor
final class WorkspaceStateTests: XCTestCase {
    func testAddIgnoresDuplicatePathAndNotifies() {
        let state = AppState()
        var notifications = 0
        state.onWorkspacesChange = { notifications += 1 }

        let first = state.addWorkspace(url: URL(fileURLWithPath: "/tmp/ops-scripts"))
        let again = state.addWorkspace(url: URL(fileURLWithPath: "/tmp/ops-scripts/"))
        state.addWorkspace(url: URL(fileURLWithPath: "/tmp/other"))

        XCTAssertEqual(first, again)
        XCTAssertEqual(state.workspaces.count, 2)
        XCTAssertEqual(notifications, 2)
        XCTAssertEqual(state.workspaces[0].displayName, "OPS-SCRIPTS")
    }

    func testRemoveWorkspace() {
        let state = AppState()
        let id = state.addWorkspace(url: URL(fileURLWithPath: "/tmp/a"))
        state.addWorkspace(url: URL(fileURLWithPath: "/tmp/b"))
        state.removeWorkspace(id: id)
        XCTAssertEqual(state.workspaces.map(\.url.lastPathComponent), ["b"])
    }

    func testExpansionStateDoesNotNotify() {
        let state = AppState()
        let id = state.addWorkspace(url: URL(fileURLWithPath: "/tmp/a"))
        var notified = false
        state.onWorkspacesChange = { notified = true }

        state.setDirectory("deploy", expanded: true, in: id)
        state.setDirectory("deploy/sub", expanded: true, in: id)
        state.setDirectory("deploy/sub", expanded: false, in: id)
        state.setWorkspace(id, collapsed: true)

        XCTAssertEqual(state.workspace(id: id)?.expandedDirs, ["deploy"])
        XCTAssertEqual(state.workspace(id: id)?.collapsed, true)
        XCTAssertFalse(notified)
    }
}

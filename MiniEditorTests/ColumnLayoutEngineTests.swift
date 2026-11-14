import XCTest
@testable import MiniEditor

/// Kiểm tra mọi quy tắc SPEC §3.2.
final class ColumnLayoutEngineTests: XCTestCase {
    private let wsA = UUID()
    private let wsB = UUID()
    private let wsC = UUID()

    private func file(_ name: String, _ workspace: UUID) -> Tab {
        Tab(buffer: .file(path: URL(fileURLWithPath: "/ws/\(name)")), workspaceID: workspace)
    }

    private func draft() -> Tab {
        Tab(buffer: .draft(UUID()), workspaceID: nil)
    }

    private func open(_ tabs: Tab..., in layout: ColumnLayout = .initial()) -> ColumnLayout {
        tabs.reduce(layout) { ColumnLayoutEngine.open($1, in: $0) }
    }

    private func workspaces(_ layout: ColumnLayout) -> [UUID?] {
        layout.columns.map(\.workspaceID)
    }

    private func buffers(_ column: Column) -> [BufferID] {
        column.tabs.map(\.buffer)
    }

    // MARK: Quy tắc 1: số cột = số workspace có tab, tối thiểu 1

    func testInitialLayoutHasOneEmptyColumn() {
        let layout = ColumnLayout.initial()
        XCTAssertEqual(layout.columns.count, 1)
        XCTAssertNil(layout.columns[0].workspaceID)
        XCTAssertNil(layout.columns[0].activeIndex)
        XCTAssertEqual(layout.focusedIndex, 0)
    }

    func testColumnCountEqualsDistinctWorkspaces() {
        let layout = open(file("a1", wsA), file("b1", wsB), file("a2", wsA), file("c1", wsC), file("b2", wsB))
        XCTAssertEqual(workspaces(layout), [wsA, wsB, wsC])
        XCTAssertEqual(layout.columns.map(\.tabs.count), [2, 2, 1])
    }

    // MARK: Quy tắc 2: mở file

    func testOpeningFileOfExistingColumnAddsTabAndFocusesIt() {
        var layout = open(file("a1", wsA), file("b1", wsB))
        XCTAssertEqual(layout.focusedIndex, 1)
        let a2 = file("a2", wsA)
        layout = ColumnLayoutEngine.open(a2, in: layout)
        XCTAssertEqual(layout.focusedIndex, 0)
        XCTAssertEqual(layout.columns[0].activeTab, a2)
        XCTAssertEqual(layout.columns.count, 2)
    }

    func testOpeningFileOfNewWorkspaceCreatesColumnOnTheRight() {
        let layout = open(file("a1", wsA), file("b1", wsB))
        XCTAssertEqual(workspaces(layout), [wsA, wsB])
        XCTAssertEqual(layout.focusedIndex, 1)
        XCTAssertEqual(layout.columns[1].activeIndex, 0)
    }

    func testSingleDraftOnlyColumnTakesWorkspaceInsteadOfNewColumn() {
        let d = draft()
        var layout = open(d)
        XCTAssertNil(layout.columns[0].workspaceID)
        let a1 = file("a1", wsA)
        layout = ColumnLayoutEngine.open(a1, in: layout)
        XCTAssertEqual(layout.columns.count, 1)
        XCTAssertEqual(layout.columns[0].workspaceID, wsA)
        XCTAssertEqual(buffers(layout.columns[0]), [d.buffer, a1.buffer])
        XCTAssertEqual(layout.columns[0].activeTab, a1)
    }

    func testEmptySingleColumnTakesWorkspace() {
        let layout = open(file("a1", wsA))
        XCTAssertEqual(layout.columns.count, 1)
        XCTAssertEqual(layout.columns[0].workspaceID, wsA)
    }

    func testOpeningAlreadyOpenFileOnlyFocusesIt() {
        let a1 = file("a1", wsA)
        var layout = open(a1, file("a2", wsA), file("b1", wsB))
        layout = ColumnLayoutEngine.open(a1, in: layout)
        XCTAssertEqual(layout.allTabs.filter { $0 == a1 }.count, 1)
        XCTAssertEqual(layout.focusedIndex, 0)
        XCTAssertEqual(layout.columns[0].activeTab, a1)
    }

    // MARK: Quy tắc 3: nháp vào cột đang focus

    func testDraftGoesToFocusedColumnAndNeverCreatesColumn() {
        var layout = open(file("a1", wsA), file("b1", wsB))
        layout = ColumnLayoutEngine.focusColumn(at: 0, in: layout)
        let d = draft()
        layout = ColumnLayoutEngine.open(d, in: layout)
        XCTAssertEqual(layout.columns.count, 2)
        XCTAssertEqual(layout.columns[0].activeTab, d)
        XCTAssertEqual(layout.focusedIndex, 0)
    }

    func testFileOutsideWorkspaceBehavesLikeDraft() {
        var layout = open(file("a1", wsA), file("b1", wsB))
        let outside = Tab(buffer: .file(path: URL(fileURLWithPath: "/tmp/x.sh")), workspaceID: nil)
        layout = ColumnLayoutEngine.open(outside, in: layout)
        XCTAssertEqual(layout.columns.count, 2)
        XCTAssertEqual(layout.columns[1].activeTab, outside)
    }

    // MARK: Quy tắc 4: đóng tab cuối cùng của workspace

    func testClosingLastWorkspaceTabMovesDraftsLeftAndRemovesColumn() {
        let a1 = file("a1", wsA)
        let b1 = file("b1", wsB)
        let d1 = draft()
        var layout = open(a1, b1, d1) // d1 vào cột B (đang focus)
        XCTAssertEqual(buffers(layout.columns[1]), [b1.buffer, d1.buffer])

        layout = ColumnLayoutEngine.close(b1.buffer, in: layout)
        XCTAssertEqual(workspaces(layout), [wsA])
        XCTAssertEqual(buffers(layout.columns[0]), [a1.buffer, d1.buffer])
        XCTAssertEqual(layout.focusedIndex, 0)
        // Cột bị xoá đang focus và đang xem d1 → d1 vẫn đang được xem.
        XCTAssertEqual(layout.columns[0].activeTab, d1)
    }

    func testDraftsMoveRightWhenNoColumnOnTheLeft() {
        let a1 = file("a1", wsA)
        let b1 = file("b1", wsB)
        let d1 = draft()
        var layout = open(a1, b1)
        layout = ColumnLayoutEngine.focusColumn(at: 0, in: layout)
        layout = ColumnLayoutEngine.open(d1, in: layout)

        layout = ColumnLayoutEngine.close(a1.buffer, in: layout)
        XCTAssertEqual(workspaces(layout), [wsB])
        XCTAssertEqual(buffers(layout.columns[0]), [b1.buffer, d1.buffer])
        XCTAssertEqual(layout.focusedIndex, 0)
    }

    func testClosingLastTabOfUnfocusedColumnKeepsActiveTabOfReceiver() {
        let a1 = file("a1", wsA)
        let b1 = file("b1", wsB)
        let c1 = file("c1", wsC)
        let d1 = draft()
        var layout = open(a1, b1, d1, c1) // d1 trong cột B, focus cột C
        layout = ColumnLayoutEngine.close(b1.buffer, in: layout)

        XCTAssertEqual(workspaces(layout), [wsA, wsC])
        XCTAssertEqual(buffers(layout.columns[0]), [a1.buffer, d1.buffer])
        XCTAssertEqual(layout.columns[0].activeTab, a1)
        XCTAssertEqual(layout.focusedIndex, 1) // vẫn là cột C, chỉ dịch chỉ số
    }

    func testClosingLastWorkspaceTabWithoutDraftsRemovesColumn() {
        let a1 = file("a1", wsA)
        let b1 = file("b1", wsB)
        var layout = open(a1, b1)
        layout = ColumnLayoutEngine.close(b1.buffer, in: layout)
        XCTAssertEqual(workspaces(layout), [wsA])
        XCTAssertEqual(layout.focusedIndex, 0)
    }

    func testOnlyColumnBecomesWorkspacelessAndKeepsDrafts() {
        let a1 = file("a1", wsA)
        let d1 = draft()
        var layout = open(a1, d1)
        layout = ColumnLayoutEngine.close(a1.buffer, in: layout)
        XCTAssertEqual(layout.columns.count, 1)
        XCTAssertNil(layout.columns[0].workspaceID)
        XCTAssertEqual(buffers(layout.columns[0]), [d1.buffer])
        XCTAssertEqual(layout.columns[0].activeTab, d1)
    }

    func testClosingEverythingLeavesOneEmptyColumn() {
        let a1 = file("a1", wsA)
        var layout = open(a1)
        layout = ColumnLayoutEngine.close(a1.buffer, in: layout)
        XCTAssertEqual(layout.columns.count, 1)
        XCTAssertNil(layout.columns[0].workspaceID)
        XCTAssertNil(layout.columns[0].activeIndex)
    }

    func testClosingDraftDoesNotRemoveColumn() {
        let a1 = file("a1", wsA)
        let b1 = file("b1", wsB)
        let d1 = draft()
        var layout = open(a1, b1, d1)
        layout = ColumnLayoutEngine.close(d1.buffer, in: layout)
        XCTAssertEqual(workspaces(layout), [wsA, wsB])
    }

    func testClosingNonLastWorkspaceTabKeepsColumn() {
        let a1 = file("a1", wsA)
        let a2 = file("a2", wsA)
        let b1 = file("b1", wsB)
        var layout = open(a1, a2, b1)
        layout = ColumnLayoutEngine.close(a1.buffer, in: layout)
        XCTAssertEqual(workspaces(layout), [wsA, wsB])
        XCTAssertEqual(buffers(layout.columns[0]), [a2.buffer])
    }

    func testClosingUnknownBufferIsNoop() {
        let layout = open(file("a1", wsA))
        XCTAssertEqual(ColumnLayoutEngine.close(.draft(UUID()), in: layout), layout)
    }

    // MARK: Chọn tab đang active sau khi đóng

    func testClosingActiveTabActivatesRightNeighborThenLeft() {
        let tabs = (1...3).map { file("a\($0)", wsA) }
        var layout = open(tabs[0], tabs[1], tabs[2])
        layout = ColumnLayoutEngine.activate(tabs[1].buffer, in: layout)
        layout = ColumnLayoutEngine.close(tabs[1].buffer, in: layout)
        XCTAssertEqual(layout.columns[0].activeTab, tabs[2])
        layout = ColumnLayoutEngine.close(tabs[2].buffer, in: layout)
        XCTAssertEqual(layout.columns[0].activeTab, tabs[0])
    }

    func testClosingTabBeforeActiveKeepsSameActiveTab() {
        let tabs = (1...3).map { file("a\($0)", wsA) }
        var layout = open(tabs[0], tabs[1], tabs[2]) // active = a3
        layout = ColumnLayoutEngine.close(tabs[0].buffer, in: layout)
        XCTAssertEqual(layout.columns[0].activeTab, tabs[2])
    }

    // MARK: Quy tắc 5: gỡ workspace

    func testRemovingWorkspaceClosesItsTabsAndAppliesRule4() {
        let a1 = file("a1", wsA)
        let b1 = file("b1", wsB)
        let b2 = file("b2", wsB)
        let d1 = draft()
        var layout = open(a1, b1, d1, b2)
        layout = ColumnLayoutEngine.removeWorkspace(wsB, from: layout)
        XCTAssertEqual(workspaces(layout), [wsA])
        XCTAssertEqual(buffers(layout.columns[0]), [a1.buffer, d1.buffer])
    }

    func testRemovingOnlyWorkspaceLeavesWorkspacelessColumnWithDrafts() {
        let a1 = file("a1", wsA)
        let d1 = draft()
        var layout = open(a1, d1)
        layout = ColumnLayoutEngine.removeWorkspace(wsA, from: layout)
        XCTAssertEqual(layout.columns.count, 1)
        XCTAssertNil(layout.columns[0].workspaceID)
        XCTAssertEqual(buffers(layout.columns[0]), [d1.buffer])
    }

    func testRemovingWorkspaceWithoutTabsIsNoop() {
        let layout = open(file("a1", wsA))
        XCTAssertEqual(ColumnLayoutEngine.removeWorkspace(wsB, from: layout), layout)
    }

    // MARK: Quy tắc 7: thứ tự cột là thứ tự tạo

    func testColumnOrderIsCreationOrderAndSurvivesRemoval() {
        let b1 = file("b1", wsB)
        var layout = open(file("a1", wsA), b1, file("c1", wsC))
        layout = ColumnLayoutEngine.close(b1.buffer, in: layout)
        layout = ColumnLayoutEngine.open(file("b2", wsB), in: layout)
        XCTAssertEqual(workspaces(layout), [wsA, wsC, wsB])
    }

    func testNewColumnUsesInjectedID() {
        let id = UUID()
        var layout = open(file("a1", wsA))
        layout = ColumnLayoutEngine.open(file("b1", wsB), in: layout, newColumnID: { id })
        XCTAssertEqual(layout.columns[1].id, id)
    }

    // MARK: Focus & chuyển tab

    func testFocusColumnOutOfRangeIsNoop() {
        let layout = open(file("a1", wsA), file("b1", wsB))
        XCTAssertEqual(ColumnLayoutEngine.focusColumn(at: 5, in: layout), layout)
        XCTAssertEqual(ColumnLayoutEngine.focusColumn(at: 0, in: layout).focusedIndex, 0)
    }

    func testSelectAdjacentTabWrapsAround() {
        let tabs = (1...3).map { file("a\($0)", wsA) }
        var layout = open(tabs[0], tabs[1], tabs[2]) // active = a3
        layout = ColumnLayoutEngine.selectAdjacentTab(offset: 1, in: layout)
        XCTAssertEqual(layout.columns[0].activeTab, tabs[0])
        layout = ColumnLayoutEngine.selectAdjacentTab(offset: -1, in: layout)
        XCTAssertEqual(layout.columns[0].activeTab, tabs[2])
    }

    func testSelectAdjacentTabInEmptyColumnIsNoop() {
        let layout = ColumnLayout.initial()
        XCTAssertEqual(ColumnLayoutEngine.selectAdjacentTab(offset: 1, in: layout), layout)
    }

    func testActivateFocusesOwningColumn() {
        let a1 = file("a1", wsA)
        var layout = open(a1, file("a2", wsA), file("b1", wsB))
        layout = ColumnLayoutEngine.activate(a1.buffer, in: layout)
        XCTAssertEqual(layout.focusedIndex, 0)
        XCTAssertEqual(layout.columns[0].activeTab, a1)
    }
}

/// `replace`: nháp được Save As thành file (SPEC §3.5).
final class ColumnLayoutEngineReplaceTests: XCTestCase {
    private let wsA = UUID()
    private let wsB = UUID()

    private func file(_ name: String, _ workspace: UUID?) -> Tab {
        Tab(buffer: .file(path: URL(fileURLWithPath: "/ws/\(name)")), workspaceID: workspace)
    }

    func testDraftSavedIntoSameWorkspaceStaysInPlace() {
        let d = Tab(buffer: .draft(UUID()), workspaceID: nil)
        var layout = ColumnLayoutEngine.open(file("a1", wsA), in: .initial())
        layout = ColumnLayoutEngine.open(d, in: layout)
        layout = ColumnLayoutEngine.open(file("a2", wsA), in: layout)
        let saved = file("new", wsA)
        layout = ColumnLayoutEngine.replace(d.buffer, with: saved, in: layout)
        XCTAssertEqual(layout.columns[0].tabs[1], saved)
        XCTAssertEqual(layout.columns[0].activeIndex, 1)
    }

    func testDraftInWorkspacelessSingleColumnTakesWorkspace() {
        let d = Tab(buffer: .draft(UUID()), workspaceID: nil)
        var layout = ColumnLayoutEngine.open(d, in: .initial())
        layout = ColumnLayoutEngine.replace(d.buffer, with: file("new", wsA), in: layout)
        XCTAssertEqual(layout.columns.count, 1)
        XCTAssertEqual(layout.columns[0].workspaceID, wsA)
    }

    func testDraftSavedIntoOtherWorkspaceMovesToItsColumn() {
        let d = Tab(buffer: .draft(UUID()), workspaceID: nil)
        var layout = ColumnLayoutEngine.open(file("a1", wsA), in: .initial())
        layout = ColumnLayoutEngine.open(file("b1", wsB), in: layout)
        layout = ColumnLayoutEngine.open(d, in: layout) // ở cột B
        let saved = file("new", wsA)
        layout = ColumnLayoutEngine.replace(d.buffer, with: saved, in: layout)
        XCTAssertEqual(layout.columns.map(\.workspaceID), [wsA, wsB])
        XCTAssertEqual(layout.columns[0].activeTab, saved)
        XCTAssertEqual(layout.columns[1].tabs.count, 1)
        XCTAssertEqual(layout.focusedIndex, 0)
    }

    func testDraftSavedIntoNewWorkspaceCreatesColumn() {
        let d = Tab(buffer: .draft(UUID()), workspaceID: nil)
        var layout = ColumnLayoutEngine.open(file("a1", wsA), in: .initial())
        layout = ColumnLayoutEngine.open(d, in: layout)
        layout = ColumnLayoutEngine.replace(d.buffer, with: file("new", wsB), in: layout)
        XCTAssertEqual(layout.columns.map(\.workspaceID), [wsA, wsB])
        XCTAssertEqual(layout.focusedIndex, 1)
    }
}

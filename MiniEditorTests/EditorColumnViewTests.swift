import AppKit
import XCTest
@testable import MiniEditor

@MainActor
final class EditorColumnViewTests: XCTestCase {
    private func makeBuffer(_ text: String) -> Buffer {
        Buffer(id: .draft(UUID()), text: text)
    }

    func testSwitchingTabsSwapsStorageWithoutRecreatingView() {
        let view = EditorColumnView(columnID: UUID(), fontSize: 13)
        let textView = view.textView
        let a = makeBuffer("alpha\nbeta")
        let b = makeBuffer("gamma")

        view.show(a)
        XCTAssertTrue(textView.textStorage === a.textStorage)
        view.show(b)
        XCTAssertTrue(view.textView === textView)
        XCTAssertTrue(textView.textStorage === b.textStorage)
        XCTAssertEqual(textView.lineIndex.lineCount, 1)
    }

    func testSelectionIsRestoredPerBuffer() {
        let view = EditorColumnView(columnID: UUID(), fontSize: 13)
        let a = makeBuffer("alpha\nbeta")
        let b = makeBuffer("gamma")

        view.show(a)
        view.textView.setSelectedRange(NSRange(location: 7, length: 2))
        view.show(b)
        XCTAssertEqual(view.textView.selectedRange(), NSRange(location: 0, length: 0))
        view.show(a)
        XCTAssertEqual(view.textView.selectedRange(), NSRange(location: 7, length: 2))
        XCTAssertEqual(view.textView.cursorPosition.line, 2)
    }

    func testEachBufferHasOwnUndoManager() {
        let view = EditorColumnView(columnID: UUID(), fontSize: 13)
        let a = makeBuffer("")
        let b = makeBuffer("")
        view.show(a)
        XCTAssertTrue(view.textView.undoManager === a.undoManager)
        view.show(b)
        XCTAssertTrue(view.textView.undoManager === b.undoManager)
    }

    func testTypingGoesToDisplayedBufferAndAttachAppliesFont() throws {
        let view = EditorColumnView(columnID: UUID(), fontSize: 15)
        let a = makeBuffer("x")
        view.show(a)
        view.textView.setSelectedRange(NSRange(location: 1, length: 0))
        view.textView.insertText("y", replacementRange: view.textView.selectedRange())
        XCTAssertEqual(a.textStorage.string, "xy")
        let font = try XCTUnwrap(a.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(font.pointSize, 15)
    }

    func testEmptyColumnIsNotEditableAndReadOnlyBufferToo() {
        let view = EditorColumnView(columnID: UUID(), fontSize: 13)
        XCTAssertFalse(view.textView.isEditable)
        view.show(Buffer(id: .draft(UUID()), text: "z", isReadOnly: true))
        XCTAssertFalse(view.textView.isEditable)
        view.show(makeBuffer("ok"))
        XCTAssertTrue(view.textView.isEditable)
        view.show(nil)
        XCTAssertFalse(view.textView.isEditable)
    }

    /// Lỗi: gỡ workspace (đóng hết tab) → cột trống nhưng con trỏ cũ vẫn nhấp nháy giữa màn hình.
    func testEmptyColumnDropsFocusAndCannotBeSelected() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let view = EditorColumnView(columnID: UUID(), fontSize: 13)
        window.contentView?.addSubview(view)
        var focusEvents = 0
        view.onFocus = { focusEvents += 1 }
        view.show(makeBuffer("echo a\n"))
        XCTAssertTrue(window.makeFirstResponder(view.textView))
        focusEvents = 0

        view.show(nil)
        XCTAssertFalse(window.firstResponder === view.textView, "bỏ focus để con trỏ cũ biến mất")
        XCTAssertFalse(view.textView.isSelectable)
        window.makeFirstResponder(view.textView) // như ColumnsViewController trả focus về cột đang focus
        XCTAssertFalse(window.firstResponder === view.textView, "cột trống không nhận focus")

        view.show(makeBuffer("b"))
        XCTAssertTrue(view.textView.isSelectable)
        XCTAssertTrue(window.makeFirstResponder(view.textView))

        // Sang buffer chỉ đọc: làm mới focus nhưng vẫn giữ focus, không báo là người dùng focus cột.
        focusEvents = 0
        view.show(Buffer(id: .draft(UUID()), text: "z", isReadOnly: true))
        XCTAssertTrue(window.firstResponder === view.textView)
        XCTAssertEqual(focusEvents, 0)
        withExtendedLifetime(window) {}
    }

    func testExternalChangeBannerShowsButtonsAndReportsActions() throws {
        let view = EditorColumnView(columnID: UUID(), fontSize: 13)
        let buffer = makeBuffer("x")
        buffer.externalChange = .modified
        var actions: [EditorColumnView.BannerAction] = []
        view.onBannerAction = { action, _ in actions.append(action) }
        view.show(buffer)
        XCTAssertFalse(view.banner.isHidden)
        XCTAssertEqual(view.banner.buttonTitles, ["Nạp bản trên đĩa", "Giữ bản của tôi"])

        buffer.externalChange = .deleted
        view.refreshBanner()
        XCTAssertEqual(view.banner.buttonTitles, ["Lưu lại", "Đóng tab"])
        let buttons = view.banner.subviews.flatMap(\.subviews).compactMap { $0 as? NSButton }
        buttons.forEach { $0.performClick(nil) }
        XCTAssertEqual(actions, [.keepMine, .closeTab])

        buffer.externalChange = nil
        view.refreshBanner()
        XCTAssertTrue(view.banner.isHidden)
    }
}

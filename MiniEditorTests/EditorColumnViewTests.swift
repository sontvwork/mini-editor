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
}

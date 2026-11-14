import AppKit
import XCTest
@testable import MiniEditor

@MainActor
final class CodeTextViewTests: XCTestCase {
    func testUsesTextKit1AndDisablesSubstitutions() {
        let textView = CodeTextView.make(fontSize: 13)
        XCTAssertNotNil(textView.layoutManager)
        XCTAssertNil(textView.textLayoutManager)
        XCTAssertFalse(textView.isRichText)
        XCTAssertFalse(textView.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertFalse(textView.isAutomaticDashSubstitutionEnabled)
        XCTAssertFalse(textView.isAutomaticTextReplacementEnabled)
        XCTAssertFalse(textView.isAutomaticSpellingCorrectionEnabled)
    }

    func testTypingKeepsPlainQuotes() {
        let textView = CodeTextView.make(fontSize: 13)
        textView.insertText("echo \"hi\" -- 'x'", replacementRange: textView.selectedRange())
        XCTAssertEqual(textView.string, "echo \"hi\" -- 'x'")
    }

    func testCursorPositionAndLineIndexInvalidation() {
        let textView = CodeTextView.make(fontSize: 13)
        textView.insertText("ab\ncdé", replacementRange: textView.selectedRange())
        XCTAssertEqual(textView.cursorPosition.line, 2)
        XCTAssertEqual(textView.cursorPosition.column, 4)
        textView.insertText("\n", replacementRange: textView.selectedRange())
        XCTAssertEqual(textView.lineIndex.lineCount, 3)
        XCTAssertEqual(textView.cursorPosition.line, 3)
        XCTAssertEqual(textView.cursorPosition.column, 1)
    }

    func testFontSizeAppliesToExistingText() throws {
        let textView = CodeTextView.make(fontSize: 13)
        textView.insertText("x\ty", replacementRange: textView.selectedRange())
        textView.setFontSize(20)
        let storage = try XCTUnwrap(textView.textStorage)
        let font = try XCTUnwrap(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(font.pointSize, 20)
        let paragraph = try XCTUnwrap(storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(paragraph.minimumLineHeight, 30)
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        XCTAssertEqual(paragraph.defaultTabInterval, spaceWidth * 4, accuracy: 0.001)
        XCTAssertEqual(textView.string, "x\ty") // giữ nguyên ký tự tab
    }
}

@MainActor
final class CodeTextViewHitTestTests: XCTestCase {
    /// Click vào vùng trống dưới văn bản (file kết thúc bằng xuống dòng) → con trỏ ở dòng trống cuối.
    func testClickBelowTextPlacesCaretAtEndOfDocument() throws {
        let textView = CodeTextView.make(fontSize: 13)
        textView.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
        textView.string = "a\nb\n"
        textView.setFontSize(13)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        layoutManager.ensureLayout(for: try XCTUnwrap(textView.textContainer))
        XCTAssertEqual(textView.characterIndexForInsertion(at: NSPoint(x: 50, y: 300)), 4)
    }

    func testMouseDownBelowTextPlacesCaretAtEndOfDocument() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let column = EditorColumnView(columnID: UUID(), fontSize: 13)
        column.frame = NSRect(x: 0, y: 0, width: 500, height: 500)
        window.contentView = column
        let buffer = Buffer(id: .draft(UUID()), text: "#!/bin/bash\nexit 0\n")
        column.show(buffer)
        column.layoutSubtreeIfNeeded()
        let textView = column.textView
        // Text view phải phủ kín vùng nhìn thấy, kể cả khi văn bản ngắn.
        XCTAssertGreaterThan(textView.frame.height, 400)
        let point = textView.convert(NSPoint(x: 100, y: 300), to: nil)
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [],
                                                  timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                  eventNumber: 0, clickCount: 1, pressure: 0))
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                                                    timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                    eventNumber: 0, clickCount: 1, pressure: 1))
        NSApp.postEvent(up, atStart: true)
        textView.mouseDown(with: down)
        XCTAssertEqual(textView.selectedRange().location, 19)
    }
}

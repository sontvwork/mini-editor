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

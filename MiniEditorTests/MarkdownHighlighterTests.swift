import XCTest
@testable import MiniEditor

final class MarkdownHighlighterTests: XCTestCase {
    private func pieces(_ source: String, _ kind: TokenKind) -> [String] {
        let text = source as NSString
        let highlighter = MarkdownHighlighter()
        highlighter.reset(text)
        return highlighter.tokens(in: NSRange(location: 0, length: text.length), of: text)
            .filter { $0.kind == kind }
            .map { text.substring(with: $0.range) }
    }

    func testHeadings() {
        XCTAssertEqual(pieces("# Tiêu đề\n###### sáu\n####### bảy\n#không\n", .heading), ["# Tiêu đề", "###### sáu"])
    }

    func testBoldItalic() {
        XCTAssertEqual(pieces("a **đậm** và __đậm2__", .bold), ["**đậm**", "__đậm2__"])
        XCTAssertEqual(pieces("a *nghiêng* và _ng2_ nhưng snake_case_name", .italic), ["*nghiêng*", "_ng2_"])
        XCTAssertEqual(pieces("**đậm**", .italic), [], "đậm không bị tô nhầm thành nghiêng")
    }

    func testInlineCodeHidesOtherMarkup() {
        XCTAssertEqual(pieces("dùng `**x**` nhé", .string), ["`**x**`"])
        XCTAssertEqual(pieces("dùng `**x**` nhé", .bold), [])
    }

    func testListQuoteLink() {
        XCTAssertEqual(pieces("- a\n* b\n  + c\n12. d\n-không\n", .keyword), ["-", "*", "  +", "12."])
        XCTAssertEqual(pieces("> trích\n", .quote), ["> trích"])
        XCTAssertEqual(pieces("xem [tài liệu](https://x.y/z)", .linkText), ["tài liệu"])
        XCTAssertEqual(pieces("xem [tài liệu](https://x.y/z)", .linkURL), ["https://x.y/z"])
    }

    func testCodeBlockColorsWholeBlockAndNothingInside() {
        let source = "a\n```bash\n# không phải heading\n**x**\n```\nb **y**\n"
        XCTAssertEqual(pieces(source, .string), ["```bash\n# không phải heading\n**x**\n```\n"])
        XCTAssertEqual(pieces(source, .heading), [])
        XCTAssertEqual(pieces(source, .bold), ["**y**"])
    }

    func testUnclosedCodeBlockRunsToEnd() {
        XCTAssertEqual(pieces("a\n```\nb\nc", .string), ["```\nb\nc"])
    }

    func testRehighlightOnlyEditedLinesWhenFencesUnchanged() {
        let highlighter = MarkdownHighlighter()
        let before = "x\n```\ncode\n```\ny\n" as NSString
        highlighter.reset(before)
        // Gõ "z" vào dòng "y".
        let after = "x\n```\ncode\n```\nyz\n" as NSString
        let range = highlighter.rangeToRehighlight(editedRange: NSRange(location: 16, length: 1), changeInLength: 1, in: after)
        XCTAssertEqual(after.substring(with: range), "yz\n")
    }

    func testRehighlightToEndWhenFenceAppears() {
        let highlighter = MarkdownHighlighter()
        let before = "a\n``\nb\n" as NSString
        highlighter.reset(before)
        let after = "a\n```\nb\n" as NSString // gõ thêm một dấu `
        let range = highlighter.rangeToRehighlight(editedRange: NSRange(location: 4, length: 1), changeInLength: 1, in: after)
        XCTAssertEqual(after.substring(with: range), "```\nb\n")
        XCTAssertEqual(highlighter.fenceLineStarts, [2])
    }

    func testFenceShiftedByEditAboveIsNotAChange() {
        let highlighter = MarkdownHighlighter()
        highlighter.reset("a\n```\nb\n```\n" as NSString)
        let after = "aa\n```\nb\n```\n" as NSString
        let range = highlighter.rangeToRehighlight(editedRange: NSRange(location: 1, length: 1), changeInLength: 1, in: after)
        XCTAssertEqual(after.substring(with: range), "aa\n")
    }
}

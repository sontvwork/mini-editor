import XCTest
@testable import MiniEditor

final class BashHighlighterTests: XCTestCase {
    /// Các đoạn chữ được tô theo loại, theo thứ tự xuất hiện.
    private func tokens(_ source: String) -> [(String, TokenKind)] {
        let text = source as NSString
        return BashHighlighter().tokens(in: NSRange(location: 0, length: text.length), of: text)
            .map { (text.substring(with: $0.range), $0.kind) }
    }

    private func pieces(_ source: String, _ kind: TokenKind) -> [String] {
        tokens(source).filter { $0.1 == kind }.map(\.0)
    }

    func testComments() {
        XCTAssertEqual(pieces("# đầu dòng\necho a # cuối\n", .comment), ["# đầu dòng", "# cuối"])
        XCTAssertEqual(pieces("echo a#b", .comment), [], "# dính chữ không phải comment")
        XCTAssertEqual(pieces("echo $# x", .comment), [], "$# là biến")
        XCTAssertEqual(pieces("echo \"a # b\"", .comment), [], "# trong chuỗi")
        XCTAssertEqual(pieces("echo ${#arr[@]}", .comment), [])
    }

    func testStrings() {
        XCTAssertEqual(pieces(#"echo "a \" b" 'c $d'"#, .string), [#""a \" b""#, "'c $d'"])
        XCTAssertEqual(pieces("echo \"chưa đóng\necho x", .string), ["\"chưa đóng"], "chuỗi chưa đóng dừng ở cuối dòng")
    }

    func testVariables() {
        XCTAssertEqual(pieces(#"echo $HOME ${NAME:-x} $1 $@ $? "in $USER" '$NO'"#, .variable),
                       ["$HOME", "${NAME:-x}", "$1", "$@", "$?", "$USER"])
        XCTAssertEqual(pieces("echo $(date)", .variable), [], "$( là command substitution")
    }

    func testKeywordsAndBuiltins() {
        XCTAssertEqual(pieces("if [ -f x ]; then\n  export A=1\nfi\n", .keyword), ["if", "then", "export", "fi"])
        XCTAssertEqual(pieces("my-echo ./if.sh iffy", .keyword), [], "không tô từ khoá nằm trong từ khác")
    }

    func testOffsetsAreRelativeToWholeText() {
        let text = "echo 1\nif x\n" as NSString
        let line2 = text.lineRange(for: NSRange(location: 7, length: 0))
        let result = BashHighlighter().tokens(in: line2, of: text)
        XCTAssertEqual(result, [Token(range: NSRange(location: 7, length: 2), kind: .keyword)])
    }
}

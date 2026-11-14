import XCTest
@testable import MiniEditor

final class LineIndexTests: XCTestCase {
    func testEmptyStringHasOneLine() {
        let index = LineIndex("" as NSString)
        XCTAssertEqual(index.lineStarts, [0])
        XCTAssertEqual(index.line(containing: 0), 0)
    }

    func testLFAndTrailingNewline() {
        let index = LineIndex("ab\ncd\n" as NSString)
        XCTAssertEqual(index.lineStarts, [0, 3, 6])
        XCTAssertEqual(index.line(containing: 2), 0)
        XCTAssertEqual(index.line(containing: 3), 1)
        XCTAssertEqual(index.line(containing: 6), 2)
    }

    func testCRLFCountsOnce() {
        let index = LineIndex("a\r\nb\r\n" as NSString)
        XCTAssertEqual(index.lineStarts, [0, 3, 6])
    }

    func testLoneCR() {
        let index = LineIndex("a\rb\r" as NSString)
        XCTAssertEqual(index.lineStarts, [0, 2, 4])
    }

    func testCRLFAcrossChunkBoundary() {
        let text = String(repeating: "x", count: 4095) + "\r\n" + "y"
        let index = LineIndex(text as NSString)
        XCTAssertEqual(index.lineStarts, [0, 4097])
    }
}

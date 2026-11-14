import AppKit
import XCTest
@testable import MiniEditor

final class EditorFontTests: XCTestCase {
    func testFallbackOrder() {
        var asked: [String] = []
        let font = EditorFont.font(ofSize: 13) { name, size in
            asked.append(name)
            return name == "Courier New" ? NSFont.systemFont(ofSize: size) : nil
        }
        XCTAssertEqual(asked, ["Menlo", "Monaco", "Courier New"])
        XCTAssertEqual(font.pointSize, 13)
    }

    func testFallsBackToSystemMonospaced() {
        let font = EditorFont.font(ofSize: 14) { _, _ in nil }
        XCTAssertEqual(font.pointSize, 14)
        XCTAssertTrue(font.isFixedPitch)
    }

    func testDefaultIsMenlo() {
        XCTAssertEqual(EditorFont.font(ofSize: 13).familyName, "Menlo")
    }
}

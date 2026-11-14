import AppKit
import XCTest
@testable import MiniEditor

final class ThemeTests: XCTestCase {
    func testEditorBackgroundMatchesSpec() throws {
        let color = try XCTUnwrap(Theme.editorBackground.usingColorSpace(.sRGB))
        XCTAssertEqual(Int((color.redComponent * 255).rounded()), 0x1E)
        XCTAssertEqual(Int((color.greenComponent * 255).rounded()), 0x1F)
        XCTAssertEqual(Int((color.blueComponent * 255).rounded()), 0x22)
    }
}

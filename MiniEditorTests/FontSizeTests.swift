import XCTest
@testable import MiniEditor

final class FontSizeTests: XCTestCase {
    func testStepsAndClamps() {
        XCTAssertEqual(FontSize.increased(13), 14)
        XCTAssertEqual(FontSize.decreased(13), 12)
        XCTAssertEqual(FontSize.increased(32), 32)
        XCTAssertEqual(FontSize.decreased(9), 9)
        XCTAssertEqual(FontSize.clamped(100), 32)
        XCTAssertEqual(FontSize.clamped(1), 9)
    }

    func testLineHeightIsOneAndHalf() {
        XCTAssertEqual(FontSize.lineHeight(for: 13), 19.5)
    }

    @MainActor
    func testAppStateNotifiesAndResets() {
        let state = AppState()
        var received: [CGFloat] = []
        state.onFontSizeChange = { received.append($0) }
        state.increaseFontSize()
        state.increaseFontSize()
        state.resetFontSize()
        state.resetFontSize() // không đổi → không báo
        XCTAssertEqual(received, [14, 15, 13])
        XCTAssertEqual(state.fontSize, FontSize.default)
    }
}

import Foundation

/// Nguồn sự thật duy nhất cho UI. M1 mới chỉ giữ cỡ chữ (dùng chung mọi editor).
@MainActor
final class AppState {
    private(set) var fontSize: CGFloat = FontSize.default

    /// Gọi mỗi khi cỡ chữ thay đổi.
    var onFontSizeChange: ((CGFloat) -> Void)?

    func increaseFontSize() { setFontSize(FontSize.increased(fontSize)) }
    func decreaseFontSize() { setFontSize(FontSize.decreased(fontSize)) }
    func resetFontSize() { setFontSize(FontSize.default) }

    func setFontSize(_ size: CGFloat) {
        let newSize = FontSize.clamped(size)
        guard newSize != fontSize else { return }
        fontSize = newSize
        onFontSizeChange?(newSize)
    }
}

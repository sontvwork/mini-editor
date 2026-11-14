import AppKit

/// Nguồn màu duy nhất của app (SPEC §4). Không hard-code màu ở chỗ khác.
enum Theme {
    static let editorBackground = color(0x1E1F22)
    static let sidebarBackground = color(0x18191B)
    static let chromeBackground = color(0x2B2D30)
    static let border = color(0x3A3C40)
    static let borderSubtle = color(0x2E3034)
    static let text = color(0xD4D4D4)
    static let textMuted = color(0x9DA0A6)
    static let lineNumber = color(0x858890)
    static let selectionRow = color(0x2C3A4F)
    static let textSelection = color(0x264F78)
    static let accent = color(0x79B8FF)
    static let syntaxKeyword = color(0xD19FE0)
    static let syntaxString = color(0xA6D189)
    /// Hiển thị nghiêng.
    static let syntaxComment = color(0x8B949E)
    static let syntaxVariable = color(0x79B8FF)
    /// Hiển thị đậm.
    static let syntaxHeading = color(0x79B8FF)
    /// Nền banner lỗi (lỗi lưu file) — SPEC §3.4 "banner đỏ".
    static let bannerError = color(0x6B2B2B)
    /// Nền banner cảnh báo (file chỉ đọc vì không phải UTF-8).
    static let bannerWarning = color(0x5A4A1E)

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

import Foundation

/// Quy tắc cỡ chữ editor (SPEC §3.7): bước 1pt, khoảng 9–32pt, mặc định 13pt.
enum FontSize {
    static let `default`: CGFloat = 13
    static let minimum: CGFloat = 9
    static let maximum: CGFloat = 32

    static func clamped(_ size: CGFloat) -> CGFloat {
        min(max(size.rounded(), minimum), maximum)
    }

    static func increased(_ size: CGFloat) -> CGFloat {
        clamped(size + 1)
    }

    static func decreased(_ size: CGFloat) -> CGFloat {
        clamped(size - 1)
    }

    /// Line height = 1.5 lần cỡ chữ.
    static func lineHeight(for size: CGFloat) -> CGFloat {
        size * 1.5
    }
}

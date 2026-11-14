import AppKit

/// Font editor với thứ tự fallback cố định (SPEC §3.7). Không cho đổi font family.
enum EditorFont {
    static let fallbackNames = ["Menlo", "Monaco", "Courier New"]

    static func font(ofSize size: CGFloat) -> NSFont {
        font(ofSize: size, lookup: { NSFont(name: $0, size: $1) })
    }

    /// `lookup` tách ra để test được thứ tự fallback.
    static func font(ofSize size: CGFloat, lookup: (String, CGFloat) -> NSFont?) -> NSFont {
        for name in fallbackNames {
            if let font = lookup(name, size) { return font }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

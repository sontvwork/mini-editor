import AppKit

/// Split view với thanh chia mảnh màu `Theme.border`.
@MainActor
final class ThemedSplitView: NSSplitView {
    override var dividerColor: NSColor { Theme.border }
}

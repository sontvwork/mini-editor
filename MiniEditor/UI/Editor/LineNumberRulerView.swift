import AppKit

/// Cột số dòng bên trái editor. Chỉ vẽ các dòng đang hiện trên màn hình.
@MainActor
final class LineNumberRulerView: NSRulerView {
    private weak var textView: CodeTextView?
    private var digitCount = 0
    private var attributes: [NSAttributedString.Key: Any] = [:]

    private static let leftPadding: CGFloat = 12
    private static let rightPadding: CGFloat = 8

    init(textView: CodeTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        clipsToBounds = true

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(setNeedsRedraw),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView
        )
        textView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(setNeedsRedraw),
            name: NSView.frameDidChangeNotification, object: textView
        )
        fontDidChange()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) không dùng")
    }

    override var isFlipped: Bool { true }

    /// Gọi khi đổi cỡ chữ.
    func fontDidChange() {
        guard let textView else { return }
        attributes = [.font: textView.editorFont, .foregroundColor: Theme.lineNumber]
        digitCount = 0
        textDidChange()
    }

    /// Gọi khi nội dung đổi: cập nhật độ rộng nếu số chữ số của số dòng thay đổi.
    func textDidChange() {
        guard let textView else { return }
        let digits = max(2, String(textView.lineIndex.lineCount).count)
        if digits != digitCount {
            digitCount = digits
            let digitWidth = ("0" as NSString).size(withAttributes: attributes).width
            ruleThickness = ceil(CGFloat(digits) * digitWidth + Self.leftPadding + Self.rightPadding)
        }
        needsDisplay = true
    }

    @objc private func setNeedsRedraw() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.editorBackground.setFill()
        dirtyRect.fill()
        drawLineNumbers()
    }

    private func drawLineNumbers() {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }

        let origin = textView.textContainerOrigin
        var visible = textView.visibleRect
        visible.origin.y -= origin.y
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        let index = textView.lineIndex
        let length = (textView.string as NSString).length
        let offsetY = convert(NSPoint.zero, from: textView).y + origin.y
        let lineHeight = FontSize.lineHeight(for: textView.editorFont.pointSize)
        let glyphHeight = textView.editorFont.ascender - textView.editorFont.descender
        let textTop = (lineHeight - glyphHeight) / 2
        let rightEdge = bounds.width - Self.rightPadding

        var line = index.line(containing: charRange.location)
        while line < index.lineCount {
            let start = index.lineStart(line)
            if start > NSMaxRange(charRange) { break }

            let fragmentY: CGFloat
            if start >= length {
                // Dòng rỗng cuối file nằm ở "extra line fragment".
                let extra = layoutManager.extraLineFragmentRect
                guard extra.height > 0 else { break }
                fragmentY = extra.minY
            } else {
                let glyph = layoutManager.glyphIndexForCharacter(at: start)
                fragmentY = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
            }

            let label = String(line + 1) as NSString
            let width = label.size(withAttributes: attributes).width
            label.draw(at: NSPoint(x: rightEdge - width, y: fragmentY + offsetY + textTop),
                       withAttributes: attributes)
            line += 1
        }
    }
}

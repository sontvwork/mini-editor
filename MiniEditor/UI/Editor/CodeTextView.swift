import AppKit

/// Editor chính: `NSTextView` chạy TextKit 1 (`NSLayoutManager`), không rich text,
/// tắt hết smart substitution (phá script bash).
@MainActor
final class CodeTextView: NSTextView {
    private let lineLayout = FixedLineHeightLayout()
    private var cachedLineIndex: LineIndex?

    private(set) var editorFont: NSFont = EditorFont.font(ofSize: FontSize.default)

    /// Gọi sau mỗi lần nội dung thay đổi (gõ phím hoặc sửa storage bằng code).
    var onTextStorageEdit: (() -> Void)?

    /// Dựng đủ chuỗi TextKit 1: storage → layout manager → container → view.
    static func make(fontSize: CGFloat) -> CodeTextView {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let textView = CodeTextView(frame: .zero, textContainer: container)
        textView.setFontSize(fontSize)
        return textView
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) không dùng")
    }

    /// Bảng đầu dòng, tính lại lười sau mỗi lần sửa.
    var lineIndex: LineIndex {
        if let cachedLineIndex { return cachedLineIndex }
        let index = LineIndex(string as NSString)
        cachedLineIndex = index
        return index
    }

    /// Dòng/cột (1-based) của đầu vùng chọn. Cột đếm theo ký tự hiển thị.
    var cursorPosition: (line: Int, column: Int) {
        let location = min(selectedRange().location, (string as NSString).length)
        let index = lineIndex
        let line = index.line(containing: location)
        let start = index.lineStart(line)
        let prefix = (string as NSString).substring(with: NSRange(location: start, length: location - start))
        return (line + 1, prefix.count + 1)
    }

    /// Áp cỡ chữ: font, line height 1.5×, tab = 4 khoảng trắng hiển thị.
    func setFontSize(_ size: CGFloat) {
        let font = EditorFont.font(ofSize: size)
        editorFont = font
        let lineHeight = FontSize.lineHeight(for: size)
        lineLayout.update(font: font, lineHeight: lineHeight)

        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = []
        paragraph.defaultTabInterval = spaceWidth * 4
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: Theme.text,
            .paragraphStyle: paragraph,
        ]
        defaultParagraphStyle = paragraph
        typingAttributes = attributes
        if let storage = textStorage, storage.length > 0 {
            storage.beginEditing()
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
            storage.endEditing()
        }
    }

    // MARK: - Private

    private func configure() {
        layoutManager?.delegate = lineLayout
        layoutManager?.allowsNonContiguousLayout = true

        isRichText = false
        importsGraphics = false
        allowsUndo = true
        usesFontPanel = false
        usesRuler = false
        usesFindBar = true

        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticTextCompletionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        smartInsertDeleteEnabled = false
        inlinePredictionType = .no
        mathExpressionCompletionType = .no
        writingToolsBehavior = .none

        drawsBackground = true
        backgroundColor = Theme.editorBackground
        insertionPointColor = Theme.text
        textColor = Theme.text
        selectedTextAttributes = [.backgroundColor: Theme.textSelection]
        textContainerInset = NSSize(width: 6, height: 8)

        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        if let textStorage {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(storageDidProcessEditing(_:)),
                name: NSTextStorage.didProcessEditingNotification,
                object: textStorage
            )
        }
    }

    @objc private func storageDidProcessEditing(_ notification: Notification) {
        guard let storage = notification.object as? NSTextStorage,
              storage.editedMask.contains(.editedCharacters) else { return }
        cachedLineIndex = nil
        onTextStorageEdit?()
    }
}

/// Ép mọi dòng cao đúng `lineHeight` và căn chữ vào giữa dòng.
/// Dùng delegate của layout manager nên không phải sửa `NSTextStorage`.
/// `NSLayoutManagerDelegate` không gắn actor; thực tế chỉ dùng trên main thread.
private final class FixedLineHeightLayout: NSObject, NSLayoutManagerDelegate {
    private var lineHeight: CGFloat = 0
    private var baselineOffset: CGFloat = 0

    func update(font: NSFont, lineHeight: CGFloat) {
        self.lineHeight = lineHeight
        let glyphHeight = font.ascender - font.descender
        baselineOffset = font.ascender + (lineHeight - glyphHeight) / 2
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
        baselineOffset: UnsafeMutablePointer<CGFloat>,
        in textContainer: NSTextContainer,
        forGlyphRange glyphRange: NSRange
    ) -> Bool {
        lineFragmentRect.pointee.size.height = lineHeight
        lineFragmentUsedRect.pointee.size.height = lineHeight
        baselineOffset.pointee = self.baselineOffset
        return true
    }
}

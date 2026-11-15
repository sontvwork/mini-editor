import AppKit

/// Editor chính: `NSTextView` chạy TextKit 1 (`NSLayoutManager`), không rich text,
/// tắt hết smart substitution (phá script bash).
@MainActor
final class CodeTextView: NSTextView {
    private let lineLayout = FixedLineHeightLayout()
    private var cachedLineIndex: LineIndex?

    private(set) var editorFont: NSFont = EditorFont.font(ofSize: FontSize.default)
    private var attributes: [NSAttributedString.Key: Any] = [:]

    /// Gọi sau mỗi lần nội dung thay đổi (gõ phím hoặc sửa storage bằng code).
    var onTextStorageEdit: (() -> Void)?
    /// Gọi khi text view nhận focus bàn phím (để biết cột nào đang focus).
    var onBecomeFirstResponder: (() -> Void)?

    /// Dựng đủ chuỗi TextKit 1: storage → layout manager → container → view.
    static func make(fontSize: CGFloat) -> CodeTextView {
        let storage = NSTextStorage()
        let layoutManager = SyntaxLayoutManager()
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

        attributes = [
            .font: font,
            .foregroundColor: Theme.text,
            .paragraphStyle: paragraph,
        ]
        defaultParagraphStyle = paragraph
        applyAttributesToStorage()
    }

    /// Gắn storage của buffer khác vào view (chuyển tab) rồi tô màu lại. Không tạo lại view.
    func attach(_ storage: NSTextStorage, language: Language = .plain) {
        guard let layoutManager else { return }
        if storage !== textStorage {
            if let old = textStorage {
                NotificationCenter.default.removeObserver(self, name: NSTextStorage.didProcessEditingNotification, object: old)
            }
            layoutManager.replaceTextStorage(storage)
            observe(storage)
            cachedLineIndex = nil
            applyAttributesToStorage()
        }
        setLanguage(language)
    }

    /// Đổi ngôn ngữ: tô màu lại toàn bộ, đổi ký hiệu comment cho ⌘/.
    func setLanguage(_ language: Language) {
        (layoutManager as? SyntaxLayoutManager)?.setLanguage(language)
    }

    var language: Language {
        (layoutManager as? SyntaxLayoutManager)?.language ?? .plain
    }

    /// ⌘/: bật/tắt comment các dòng đang chọn. Bash: `# `; ngôn ngữ khác: không làm gì (SPEC §3.10).
    @objc func toggleLineComment(_ sender: Any?) {
        guard language == .bash, isEditable, let storage = textStorage else { return }
        let text = storage.string as NSString
        let selection = selectedRange()
        let lines = text.lineRange(for: selection)
        let old = text.substring(with: lines)
        let new = LineComment.toggle(old, prefix: "# ")
        guard new != old, shouldChangeText(in: lines, replacementString: new) else { return }
        breakUndoCoalescing()
        storage.replaceCharacters(in: lines, with: new)
        didChangeText()
        let newLength = (new as NSString).length
        if selection.length == 0 {
            // Con trỏ dời theo số ký tự thêm/bớt ở dòng đầu, không lùi quá đầu dòng.
            let firstLineDelta = LineComment.firstLineDelta(old: old, new: new)
            let location = min(max(lines.location, selection.location + firstLineDelta), lines.location + newLength)
            setSelectedRange(NSRange(location: location, length: 0))
        } else {
            let trailingNewline = new.hasSuffix("\n") ? 1 : 0
            setSelectedRange(NSRange(location: lines.location, length: newLength - trailingNewline))
        }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onBecomeFirstResponder?() }
        return accepted
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

        if let textStorage { observe(textStorage) }
    }

    private func observe(_ storage: NSTextStorage) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storageDidProcessEditing(_:)),
            name: NSTextStorage.didProcessEditingNotification,
            object: storage
        )
    }

    /// Font/màu/paragraph cho toàn bộ storage hiện tại và cho chữ sắp gõ.
    /// Sửa thẳng storage nên không ghi vào undo.
    private func applyAttributesToStorage() {
        typingAttributes = attributes
        guard let storage = textStorage, storage.length > 0 else { return }
        storage.beginEditing()
        storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
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

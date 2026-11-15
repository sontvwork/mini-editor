import AppKit

/// Layout manager của một cột editor, kiêm tô màu cú pháp (SPEC §3.8):
/// - Chỉ dùng temporary attributes, không sửa `NSTextStorage` (không bẩn undo, không layout lại).
/// - Tô lười: chỉ tô phần đang nhìn thấy (dư nửa màn hình mỗi phía); phần còn lại được tô ngay trước khi vẽ
///   (`CodeTextView.draw`). `highlighted` giữ các vị trí đã tô đúng.
/// - Sau mỗi lần sửa: dời `highlighted` theo lần sửa và bỏ vùng `Highlighter` báo (thường là các dòng bị sửa;
///   Markdown đổi dấu ``` thì tới cuối văn bản) — chỉ phần nhìn thấy được tô lại ngay.
/// - Áp màu hoãn tới khi storage sửa xong (`RunLoop.perform`, vẫn trước lần vẽ kế tiếp): đổi temporary
///   attributes trong lúc storage đang sửa có thể bắt layout manager sinh glyph → AppKit ném exception.
/// - Temporary attributes không đổi được font → vẽ đậm (viền chữ) / nghiêng (nghiêng hệ toạ độ) giả lập lúc vẽ.
/// Không gắn `@MainActor` vì `NSLayoutManager` không gắn; thực tế chỉ dùng trên main thread cùng text view.
final class SyntaxLayoutManager: NSLayoutManager {
    /// File lớn hơn ~2MB thì tắt tô màu (tính theo đơn vị UTF-16, xấp xỉ byte với văn bản ASCII).
    static let maxHighlightLength = 2 * 1024 * 1024

    private enum FontStyle: Int {
        case bold = 1
        case italic = 2
    }

    private static let fontStyleKey = NSAttributedString.Key("MiniEditorSyntaxFontStyle")
    private static let italicShear: CGFloat = 0.21

    private(set) var language: Language = .plain
    private var highlighter: Highlighter?
    /// Kiểu đậm/nghiêng và màu của đoạn đang vẽ (đặt trong `drawGlyphs`, đọc trong `showCGGlyphs`).
    private var drawingStyle: FontStyle?
    private var drawingColor: NSColor?
    /// Vị trí ký tự đã tô đúng. Ngoài tập này temporary attributes có thể đã cũ.
    private var highlighted = IndexSet()
    /// Cần xoá hết temporary attributes cũ (đổi storage/ngôn ngữ) trước lần tô kế tiếp.
    private var needsClear = false
    private var isFlushScheduled = false

    /// Đổi ngôn ngữ (hoặc vừa gắn storage khác) → tô lại từ đầu.
    @MainActor
    func setLanguage(_ language: Language) {
        self.language = language
        highlighter = language.makeHighlighter()
        rehighlightAll()
    }

    /// Tô lại từ đầu. Đang ở giữa một lần sửa storage (vd. nháp tự chuyển sang Bash khi gõ `#!`) thì hoãn.
    @MainActor
    func rehighlightAll() {
        guard let storage = textStorage else { return }
        if storage.length > Self.maxHighlightLength { highlighter = nil }
        highlighter?.reset(storage.string as NSString)
        highlighted = []
        needsClear = true
        if storage.editedMask.isEmpty {
            flushPendingHighlight()
        } else {
            scheduleFlush()
        }
    }

    override func processEditing(for textStorage: NSTextStorage,
                                 edited editMask: NSTextStorageEditActions,
                                 range newCharRange: NSRange,
                                 changeInLength delta: Int,
                                 invalidatedRange invalidatedCharRange: NSRange) {
        super.processEditing(for: textStorage, edited: editMask, range: newCharRange,
                             changeInLength: delta, invalidatedRange: invalidatedCharRange)
        // Sau `super`: temporary attributes đã được dời theo lần sửa.
        guard editMask.contains(.editedCharacters) else { return }
        textDidEdit(textStorage, range: newCharRange, changeInLength: delta)
    }

    private func textDidEdit(_ textStorage: NSTextStorage, range newCharRange: NSRange, changeInLength delta: Int) {
        guard let highlighter else { return }
        // Dời tập đã tô: bỏ đoạn cũ bị sửa, dời phần phía sau theo độ chênh.
        let oldLength = max(newCharRange.length - delta, 0)
        highlighted.remove(integersIn: newCharRange.location..<(newCharRange.location + oldLength))
        highlighted.shift(startingAt: newCharRange.location + oldLength, by: delta)
        if textStorage.length > Self.maxHighlightLength {
            // Vượt ngưỡng → tắt tô màu, xoá màu cũ.
            self.highlighter = nil
            needsClear = true
        } else {
            let range = highlighter.rangeToRehighlight(editedRange: newCharRange, changeInLength: delta,
                                                       in: textStorage.string as NSString)
            if let bounds = Range(range) { highlighted.remove(integersIn: bounds) }
        }
        scheduleFlush()
    }

    /// Tô phần đang nhìn thấy. Gọi tự động sau mỗi lần sửa/đổi storage.
    @MainActor
    func flushPendingHighlight() {
        ensureHighlighted(visibleCharacterRange())
    }

    /// Tô những dòng trong `range` chưa được tô. Không làm gì khi storage đang sửa.
    func ensureHighlighted(_ range: NSRange) {
        guard let storage = textStorage, storage.editedMask.isEmpty else { return }
        if needsClear {
            needsClear = false
            setTemporaryAttributes([:], forCharacterRange: NSRange(location: 0, length: storage.length))
        }
        guard let highlighter, storage.length > 0 else { return }
        let text = storage.string as NSString
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        guard let lines = Range(text.lineRange(for: clamped)) else { return }
        var missing = IndexSet(integersIn: lines)
        missing.subtract(highlighted)
        for gap in missing.rangeView {
            let gapLines = text.lineRange(for: NSRange(gap))
            apply(highlighter.tokens(in: gapLines, of: text), clearing: gapLines)
            if let bounds = Range(gapLines) { highlighted.insert(integersIn: bounds) }
        }
    }

    /// Tô vùng sắp vẽ (`rect` theo toạ độ text view).
    @MainActor
    func ensureHighlighted(in rect: NSRect, of textView: NSTextView) {
        guard highlighter != nil || needsClear, let container = textView.textContainer else { return }
        let origin = textView.textContainerOrigin
        let glyphs = glyphRange(forBoundingRect: rect.offsetBy(dx: -origin.x, dy: -origin.y), in: container)
        ensureHighlighted(characterRange(forGlyphRange: glyphs, actualGlyphRange: nil))
    }

    /// Ký tự trong vùng nhìn thấy, dư nửa màn hình mỗi phía để cuộn nhẹ không phải tô thêm.
    @MainActor
    private func visibleCharacterRange() -> NSRange {
        guard let textView = firstTextView, let container = textView.textContainer else {
            return NSRange(location: 0, length: 0)
        }
        var rect = textView.visibleRect
        if rect.isEmpty, let scrollView = textView.enclosingScrollView {
            rect = scrollView.documentVisibleRect // chưa nằm trong cửa sổ (test)
        }
        rect = rect.insetBy(dx: 0, dy: -rect.height / 2)
        let origin = textView.textContainerOrigin
        let glyphs = glyphRange(forBoundingRect: rect.offsetBy(dx: -origin.x, dy: -origin.y), in: container)
        return characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
    }

    private func scheduleFlush() {
        guard !isFlushScheduled else { return }
        isFlushScheduled = true
        // Layout manager chỉ dùng trên main thread; block chạy trên main run loop.
        nonisolated(unsafe) weak let manager = self
        RunLoop.main.perform(inModes: [.common]) {
            MainActor.assumeIsolated {
                manager?.isFlushScheduled = false
                manager?.flushPendingHighlight()
            }
        }
    }

    // MARK: - Vẽ đậm/nghiêng

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        drawStyledGlyphs(forGlyphRange: glyphsToShow, at: origin)
    }

    private func drawStyledGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        var location = characters.location
        while location < NSMaxRange(characters) {
            var effective = NSRange()
            let attributes = temporaryAttributes(atCharacterIndex: location, effectiveRange: &effective)
            let run = NSIntersectionRange(effective, characters)
            guard run.length > 0 else { break }
            drawingStyle = (attributes[Self.fontStyleKey] as? Int).flatMap(FontStyle.init(rawValue:))
            drawingColor = attributes[.foregroundColor] as? NSColor
            let glyphs = NSIntersectionRange(glyphRange(forCharacterRange: run, actualCharacterRange: nil), glyphsToShow)
            if glyphs.length > 0 {
                super.drawGlyphs(forGlyphRange: glyphs, at: origin)
            }
            location = NSMaxRange(run)
        }
        drawingStyle = nil
        drawingColor = nil
    }

    override func showCGGlyphs(_ glyphs: UnsafePointer<CGGlyph>,
                               positions: UnsafePointer<CGPoint>,
                               count: Int,
                               font: NSFont,
                               textMatrix: CGAffineTransform,
                               attributes: [NSAttributedString.Key: Any] = [:],
                               in context: CGContext) {
        guard let style = drawingStyle, count > 0 else {
            super.showCGGlyphs(glyphs, positions: positions, count: count, font: font,
                               textMatrix: textMatrix, attributes: attributes, in: context)
            return
        }
        context.saveGState()
        switch style {
        case .bold:
            context.setTextDrawingMode(.fillStroke)
            context.setLineWidth(font.pointSize / 25)
            context.setStrokeColor((drawingColor ?? Theme.text).cgColor)
        case .italic:
            // Nghiêng quanh đường baseline; hệ toạ độ lật (text view flipped) thì đổi dấu.
            let baseline = positions[0].y
            let shear = textMatrix.d < 0 ? -Self.italicShear : Self.italicShear
            context.translateBy(x: 0, y: baseline)
            context.concatenate(CGAffineTransform(a: 1, b: 0, c: shear, d: 1, tx: 0, ty: 0))
            context.translateBy(x: 0, y: -baseline)
        }
        super.showCGGlyphs(glyphs, positions: positions, count: count, font: font,
                           textMatrix: textMatrix, attributes: attributes, in: context)
        context.restoreGState()
    }

    // MARK: - Private

    nonisolated(unsafe) private static let attributesByKind: [TokenKind: [NSAttributedString.Key: Any]] = [
        .keyword: [.foregroundColor: Theme.syntaxKeyword],
        .string: [.foregroundColor: Theme.syntaxString],
        .comment: [.foregroundColor: Theme.syntaxComment, fontStyleKey: FontStyle.italic.rawValue],
        .variable: [.foregroundColor: Theme.syntaxVariable],
        .heading: [.foregroundColor: Theme.syntaxHeading, fontStyleKey: FontStyle.bold.rawValue],
        .bold: [fontStyleKey: FontStyle.bold.rawValue],
        .italic: [fontStyleKey: FontStyle.italic.rawValue],
        .quote: [.foregroundColor: Theme.syntaxComment],
        .linkText: [.foregroundColor: Theme.syntaxVariable],
        .linkURL: [.foregroundColor: Theme.syntaxComment],
    ]

    private func apply(_ tokens: [Token], clearing range: NSRange) {
        setTemporaryAttributes([:], forCharacterRange: range)
        for token in tokens {
            guard let attributes = Self.attributesByKind[token.kind] else { continue }
            addTemporaryAttributes(attributes, forCharacterRange: token.range)
        }
    }
}

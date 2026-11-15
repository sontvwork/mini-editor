import AppKit

/// Layout manager của một cột editor, kiêm tô màu cú pháp (SPEC §3.8):
/// - Chỉ dùng temporary attributes, không sửa `NSTextStorage` (không bẩn undo, không layout lại).
/// - Sau mỗi lần sửa chỉ tô lại vùng `Highlighter` báo (thường là các dòng bị sửa). Vùng được tính ngay khi sửa,
///   nhưng áp màu hoãn tới khi storage sửa xong (`RunLoop.perform`, vẫn trước lần vẽ kế tiếp): đổi temporary
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
    /// Vùng chờ tô lại (toạ độ văn bản hiện tại).
    private var pendingRange: NSRange?
    private var isFlushScheduled = false

    /// Đổi ngôn ngữ (hoặc vừa gắn storage khác) → tô lại toàn bộ.
    func setLanguage(_ language: Language) {
        self.language = language
        highlighter = language.makeHighlighter()
        rehighlightAll()
    }

    /// Tô lại toàn bộ. Đang ở giữa một lần sửa storage (vd. nháp tự chuyển sang Bash khi gõ `#!`) thì hoãn.
    func rehighlightAll() {
        guard let storage = textStorage else { return }
        if storage.length > Self.maxHighlightLength { highlighter = nil }
        highlighter?.reset(storage.string as NSString)
        pendingRange = NSRange(location: 0, length: storage.length)
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
        // Tô sau `super` để temporary attributes đã được dời theo lần sửa.
        guard editMask.contains(.editedCharacters) else { return }
        textDidEdit(textStorage, range: newCharRange, changeInLength: delta)
    }

    private func textDidEdit(_ textStorage: NSTextStorage, range newCharRange: NSRange, changeInLength delta: Int) {
        guard let highlighter else { return }
        let range: NSRange
        if textStorage.length > Self.maxHighlightLength {
            // Vượt ngưỡng → tắt tô màu, xoá màu cũ.
            self.highlighter = nil
            range = NSRange(location: 0, length: textStorage.length)
        } else {
            range = highlighter.rangeToRehighlight(editedRange: newCharRange, changeInLength: delta,
                                                   in: textStorage.string as NSString)
        }
        pendingRange = pendingRange.map {
            NSUnionRange(Self.shift($0, by: newCharRange, changeInLength: delta), range)
        } ?? range
        scheduleFlush()
    }

    /// Áp màu cho vùng đang chờ. Gọi tự động sau mỗi lần sửa; test gọi trực tiếp.
    func flushPendingHighlight() {
        guard let range = pendingRange, let storage = textStorage else { return }
        pendingRange = nil
        let text = storage.string as NSString
        guard range.location <= text.length else { return }
        let lines = text.lineRange(for: NSIntersectionRange(range, NSRange(location: 0, length: text.length)))
        if let highlighter {
            apply(highlighter.tokens(in: lines, of: text), clearing: lines)
        } else {
            setTemporaryAttributes([:], forCharacterRange: lines)
        }
    }

    private func scheduleFlush() {
        guard !isFlushScheduled else { return }
        isFlushScheduled = true
        // Layout manager chỉ dùng trên main thread; block chạy trên main run loop.
        nonisolated(unsafe) weak var manager = self
        RunLoop.main.perform(inModes: [.common]) {
            manager?.isFlushScheduled = false
            manager?.flushPendingHighlight()
        }
    }

    /// Dời một vùng (toạ độ trước lần sửa) theo lần sửa `edited` (toạ độ sau) với độ chênh `delta`.
    static func shift(_ range: NSRange, by edited: NSRange, changeInLength delta: Int) -> NSRange {
        let oldEditEnd = NSMaxRange(edited) - delta
        func map(_ position: Int) -> Int {
            if position <= edited.location { return position }
            if position >= oldEditEnd { return position + delta }
            return NSMaxRange(edited)
        }
        let start = map(range.location)
        return NSRange(location: start, length: max(map(NSMaxRange(range)) - start, 0))
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

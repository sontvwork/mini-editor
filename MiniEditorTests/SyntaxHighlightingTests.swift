import XCTest
@testable import MiniEditor

/// Tô màu trong text view, ⌘/, đổi ngôn ngữ (SPEC §3.8, §3.10).
@MainActor
final class SyntaxHighlightingTests: XCTestCase {
    private func color(_ textView: CodeTextView, at index: Int) -> NSColor? {
        (textView.layoutManager as? SyntaxLayoutManager)?.flushPendingHighlight()
        return textView.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: index, effectiveRange: nil) as? NSColor
    }

    private func makeView(_ text: String, _ language: Language) -> (CodeTextView, NSTextStorage) {
        let textView = CodeTextView.make(fontSize: 13)
        let storage = NSTextStorage(string: text)
        textView.attach(storage, language: language)
        return (textView, storage)
    }

    func testHighlightsWithTemporaryAttributesOnly() {
        let (textView, storage) = makeView("echo $HOME # c\n", .bash)
        XCTAssertEqual(color(textView, at: 0), Theme.syntaxKeyword)
        XCTAssertEqual(color(textView, at: 5), Theme.syntaxVariable)
        XCTAssertEqual(color(textView, at: 11), Theme.syntaxComment)
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, Theme.text,
                       "không sửa màu trong text storage")
    }

    func testEditRehighlightsChangedLine() {
        let (textView, storage) = makeView("echo a\nx\n", .bash)
        XCTAssertNil(color(textView, at: 7))
        storage.replaceCharacters(in: NSRange(location: 7, length: 1), with: "if")
        XCTAssertEqual(color(textView, at: 7), Theme.syntaxKeyword)
        XCTAssertEqual(color(textView, at: 0), Theme.syntaxKeyword, "dòng khác giữ nguyên")
        storage.replaceCharacters(in: NSRange(location: 7, length: 2), with: "iffy")
        XCTAssertNil(color(textView, at: 7))
    }

    func testTypingFenceRecolorsFollowingLines() {
        let (textView, storage) = makeView("``\n# h\n", .markdown)
        XCTAssertEqual(color(textView, at: 3), Theme.syntaxHeading)
        storage.replaceCharacters(in: NSRange(location: 2, length: 0), with: "`")
        XCTAssertEqual(color(textView, at: 4), Theme.syntaxString, "dòng sau ``` thành khối code")
    }

    func testSwitchingLanguageAndStorage() {
        let (textView, _) = makeView("echo x\n", .bash)
        textView.setLanguage(.plain)
        XCTAssertNil(color(textView, at: 0))
        textView.attach(NSTextStorage(string: "# H\n"), language: .markdown)
        XCTAssertEqual(color(textView, at: 0), Theme.syntaxHeading)
    }

    func testMultipleEditsBeforeFlushAreMerged() {
        let (textView, storage) = makeView("a\nb\nc\n", .bash)
        storage.replaceCharacters(in: NSRange(location: 4, length: 1), with: "if")   // dòng 3
        storage.replaceCharacters(in: NSRange(location: 0, length: 1), with: "echo") // dòng 1, dời dòng 3
        XCTAssertEqual(storage.string, "echo\nb\nif\n")
        XCTAssertEqual(color(textView, at: 0), Theme.syntaxKeyword)
        XCTAssertEqual(color(textView, at: 7), Theme.syntaxKeyword)
    }

    func testFlushRunsOnRunLoop() {
        let (textView, storage) = makeView("x\n", .bash)
        storage.replaceCharacters(in: NSRange(location: 0, length: 1), with: "fi")
        RunLoop.current.run(until: Date())
        XCTAssertEqual(textView.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 0,
                                                                  effectiveRange: nil) as? NSColor,
                       Theme.syntaxKeyword)
    }

    func testShiftRange() {
        // Chèn 2 ký tự tại 1: vùng [3,5) cũ → [5,7).
        XCTAssertEqual(SyntaxLayoutManager.shift(NSRange(location: 3, length: 2), by: NSRange(location: 1, length: 2),
                                                 changeInLength: 2), NSRange(location: 5, length: 2))
        // Sửa phía sau vùng → giữ nguyên.
        XCTAssertEqual(SyntaxLayoutManager.shift(NSRange(location: 0, length: 2), by: NSRange(location: 5, length: 1),
                                                 changeInLength: 1), NSRange(location: 0, length: 2))
    }

    func testChangingLanguageWhileStorageIsEditingIsDeferred() {
        let (textView, storage) = makeView("x\n", .markdown)
        let observer = LanguageSwitcher(textView: textView, storage: storage)
        storage.replaceCharacters(in: NSRange(location: 0, length: 1), with: "#!/bin/bash")
        XCTAssertEqual(color(textView, at: 0), Theme.syntaxComment)
        withExtendedLifetime(observer) {}
    }

    func testLargeTextIsNotHighlighted() {
        let big = String(repeating: "echo x\n", count: SyntaxLayoutManager.maxHighlightLength / 7 + 1)
        let (textView, _) = makeView(big, .bash)
        XCTAssertNil(color(textView, at: 0))
    }

    /// SPEC §7: mỗi lần tô màu khi gõ < 2ms trên file 5.000 dòng (đo ở Debug nên cho dư).
    func testKeystrokeOnLargeFileIsFast() {
        let bash = String(repeating: "if [ \"$A\" ]; then echo \"x $B\" # c\nfi\n", count: 2500)
        let markdown = String(repeating: "# h\n- **a** `b` [c](d)\n```\ncode\n```\n", count: 1000)
        for (text, language) in [(bash, Language.bash), (markdown, .markdown)] {
            let (textView, storage) = makeView(text, language)
            let layoutManager = try! XCTUnwrap(textView.layoutManager as? SyntaxLayoutManager)
            let start = ContinuousClock.now
            for i in 0..<20 {
                storage.replaceCharacters(in: NSRange(location: 2000 + i, length: 0), with: "x")
                layoutManager.flushPendingHighlight()
            }
            let perKeystroke = (ContinuousClock.now - start) / 20
            print("[perf] \(language) mỗi phím: \(perKeystroke)")
            XCTAssertLessThan(perKeystroke, .milliseconds(10), "\(language)")
        }
    }

    // MARK: ⌘/

    func testToggleCommentAddsAndRemoves() {
        XCTAssertEqual(LineComment.toggle("  a\n\n  b\n", prefix: "# "), "  # a\n\n  # b\n")
        XCTAssertEqual(LineComment.toggle("  # a\n\n  #b\n", prefix: "# "), "  a\n\n  b\n")
        XCTAssertEqual(LineComment.toggle("# a\nb\n", prefix: "# "), "# # a\n# b\n", "chưa comment hết → thêm")
        XCTAssertEqual(LineComment.toggle("\n", prefix: "# "), "\n")
    }

    func testToggleCommentInTextViewIsUndoable() {
        let (textView, storage) = makeView("echo a\necho b\n", .bash)
        let undo = UndoManager()
        let delegate = UndoDelegate(undo)
        textView.delegate = delegate
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        textView.toggleLineComment(nil)
        XCTAssertEqual(storage.string, "# echo a\necho b\n")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 4, length: 0))
        undo.undo()
        XCTAssertEqual(storage.string, "echo a\necho b\n")
    }

    func testToggleCommentDoesNothingForMarkdown() {
        let (textView, storage) = makeView("a\n", .markdown)
        textView.toggleLineComment(nil)
        XCTAssertEqual(storage.string, "a\n")
    }

    // MARK: Ngôn ngữ trong AppState

    func testDraftSwitchesToBashOnShebangAndLanguageIsSaved() throws {
        let dir = try TemporaryDirectory()
        defer { dir.remove() }
        let state = AppState(draftStore: DraftStore(directory: dir.url.appendingPathComponent("drafts")))
        let id = try state.newDraft()
        let buffer = try XCTUnwrap(state.buffers[.draft(id)])
        var changes = 0
        state.onBufferLanguageChange = { _ in changes += 1 }

        buffer.textStorage.append(NSAttributedString(string: "#!/bin/bash\n"))
        XCTAssertEqual(buffer.language, .bash)
        XCTAssertEqual(state.drafts.first?.language, .bash)

        state.setLanguage(.markdown, of: buffer)
        buffer.textStorage.append(NSAttributedString(string: "echo\n"))
        XCTAssertEqual(buffer.language, .markdown, "đã chọn tay thì không tự đổi lại")
        XCTAssertEqual(changes, 2)
        XCTAssertEqual(state.makeSession(window: .init(window: nil, sidebar: .init(visible: true, width: 240),
                                                      columnWidthRatios: []))
            .bufferState[Session.key(for: .draft(id))]?.language, .markdown)
    }
}

private final class UndoDelegate: NSObject, NSTextViewDelegate {
    let undo: UndoManager
    init(_ undo: UndoManager) { self.undo = undo }
    func undoManager(for view: NSTextView) -> UndoManager? { undo }
}

/// Đổi ngôn ngữ ngay trong thông báo didProcessEditing (giống nháp tự chuyển sang Bash).
@MainActor
private final class LanguageSwitcher: NSObject {
    let textView: CodeTextView

    init(textView: CodeTextView, storage: NSTextStorage) {
        self.textView = textView
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(didEdit),
                                               name: NSTextStorage.didProcessEditingNotification, object: storage)
    }

    @objc private func didEdit() {
        textView.setLanguage(.bash)
    }
}

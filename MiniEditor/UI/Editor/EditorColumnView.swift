import AppKit

/// Một cột editor: `NSScrollView` + `CodeTextView` + cột số dòng.
/// (Thanh tab sẽ thêm ở M3.)
@MainActor
final class EditorColumnView: NSView, NSTextViewDelegate {
    let textView: CodeTextView
    private let scrollView = NSScrollView()
    private let ruler: LineNumberRulerView

    /// Gọi khi vị trí con trỏ đổi: (dòng, cột), 1-based.
    var onCursorChange: ((Int, Int) -> Void)?

    init(fontSize: CGFloat) {
        textView = CodeTextView.make(fontSize: fontSize)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.editorBackground
        scrollView.documentView = textView

        ruler = LineNumberRulerView(textView: textView, scrollView: scrollView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        super.init(frame: .zero)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        textView.delegate = self
        textView.onTextStorageEdit = { [weak self] in
            self?.ruler.textDidChange()
            self?.notifyCursor()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) không dùng")
    }

    func setFontSize(_ size: CGFloat) {
        textView.setFontSize(size)
        ruler.fontDidChange()
    }

    func notifyCursor() {
        let position = textView.cursorPosition
        onCursorChange?(position.line, position.column)
    }

    // MARK: NSTextViewDelegate

    func textViewDidChangeSelection(_ notification: Notification) {
        notifyCursor()
    }
}

import AppKit

/// Một cột editor: thanh tab + `NSScrollView`/`CodeTextView` + cột số dòng.
/// Chuyển tab chỉ đổi `NSTextStorage` gắn vào layout manager, không tạo lại view.
@MainActor
final class EditorColumnView: NSView, NSTextViewDelegate {
    let columnID: Column.ID
    let textView: CodeTextView
    private let tabBar = TabBarView()
    private let scrollView = NSScrollView()
    private let ruler: LineNumberRulerView
    /// Storage gắn vào khi cột không có tab nào.
    private let emptyStorage = NSTextStorage()
    private(set) var displayedBuffer: Buffer?

    /// Vị trí con trỏ đổi: (dòng, cột), 1-based.
    var onCursorChange: ((Int, Int) -> Void)?
    /// Người dùng tương tác với cột (click, gõ) → cột này được focus.
    var onFocus: (() -> Void)?
    var onSelectTab: ((BufferID) -> Void)?
    var onCloseTab: ((BufferID) -> Void)?

    init(columnID: Column.ID, fontSize: CGFloat) {
        self.columnID = columnID
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

        tabBar.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tabBar)
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        textView.delegate = self
        textView.attach(emptyStorage)
        textView.isEditable = false
        textView.onTextStorageEdit = { [weak self] in
            self?.ruler.textDidChange()
            self?.notifyCursor()
        }
        textView.onBecomeFirstResponder = { [weak self] in self?.onFocus?() }
        tabBar.onSelect = { [weak self] id in
            guard let self else { return }
            self.onSelectTab?(id)
            self.window?.makeFirstResponder(self.textView)
        }
        tabBar.onClose = { [weak self] id in self?.onCloseTab?(id) }
        tabBar.onClickEmpty = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.textView)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) không dùng")
    }

    /// Đồng bộ thanh tab và nội dung với model.
    func update(column: Column, buffers: [BufferID: Buffer], isFocused: Bool) {
        let items = column.tabs.map { tab in
            TabBarView.Item(id: tab.buffer,
                            title: buffers[tab.buffer]?.displayName ?? "",
                            isDraft: tab.buffer.isDraft)
        }
        tabBar.update(items: items, activeIndex: column.activeIndex, isFocused: isFocused)
        show(column.activeTab.flatMap { buffers[$0.buffer] })
    }

    /// Hiện buffer (hoặc trống). Lưu trạng thái con trỏ/cuộn của buffer cũ trước khi đổi.
    func show(_ buffer: Buffer?) {
        guard buffer !== displayedBuffer else { return }
        saveDisplayedState()
        displayedBuffer = buffer
        textView.attach(buffer?.textStorage ?? emptyStorage)
        textView.isEditable = buffer.map { !$0.isReadOnly } ?? false

        let length = textView.textStorage?.length ?? 0
        let selection = buffer?.selection ?? NSRange(location: 0, length: 0)
        let location = min(selection.location, length)
        textView.setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
        restoreScroll(to: buffer?.scrollY ?? 0)
        ruler.textDidChange()
        notifyCursor()
    }

    func setFontSize(_ size: CGFloat) {
        textView.setFontSize(size)
        ruler.fontDidChange()
    }

    func notifyCursor() {
        let position = textView.cursorPosition
        onCursorChange?(position.line, position.column)
    }

    // MARK: - Private

    private func saveDisplayedState() {
        guard let displayedBuffer else { return }
        displayedBuffer.selection = textView.selectedRange()
        displayedBuffer.scrollY = scrollView.contentView.bounds.origin.y
    }

    private func restoreScroll(to y: CGFloat) {
        if let layoutManager = textView.layoutManager, let container = textView.textContainer {
            let visible = NSRect(x: 0, y: y, width: container.size.width, height: scrollView.contentSize.height)
            layoutManager.ensureLayout(forBoundingRect: visible, in: container)
        }
        textView.scroll(NSPoint(x: 0, y: y))
    }

    // MARK: NSTextViewDelegate

    func textViewDidChangeSelection(_ notification: Notification) {
        notifyCursor()
    }

    /// Mỗi buffer có undo stack riêng, không lẫn khi chuyển tab.
    func undoManager(for view: NSTextView) -> UndoManager? {
        displayedBuffer?.undoManager
    }
}

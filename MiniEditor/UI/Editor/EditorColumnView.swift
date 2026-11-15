import AppKit

/// Một cột editor: thanh tab + banner + `NSScrollView`/`CodeTextView` + cột số dòng.
/// Chuyển tab chỉ đổi `NSTextStorage` gắn vào layout manager, không tạo lại view.
@MainActor
final class EditorColumnView: NSView, NSTextViewDelegate {
    /// Nút trên banner file đổi bên ngoài (SPEC §3.6).
    enum BannerAction {
        /// [Nạp bản trên đĩa]
        case reloadFromDisk
        /// [Giữ bản của tôi] / [Lưu lại]
        case keepMine
        /// [Đóng tab] (bỏ thay đổi)
        case closeTab
    }

    let columnID: Column.ID
    let textView: CodeTextView
    private let tabBar = TabBarView()
    let banner = BannerView()
    private let scrollView = NSScrollView()
    private let ruler: LineNumberRulerView
    /// Storage gắn vào khi cột không có tab nào.
    private let emptyStorage = NSTextStorage()
    private(set) var displayedBuffer: Buffer?
    /// Đang đổi buffer → bỏ qua các thông báo con trỏ/cuộn do việc đổi storage sinh ra.
    private var isSwitchingBuffer = false
    /// Đang bỏ/nhận lại focus để làm mới con trỏ → không coi là người dùng focus cột.
    private var isRefreshingFocus = false

    /// Vị trí con trỏ đổi: (dòng, cột), 1-based.
    var onCursorChange: ((Int, Int) -> Void)?
    /// Người dùng tương tác với cột (click, gõ) → cột này được focus.
    var onFocus: (() -> Void)?
    var onSelectTab: ((BufferID) -> Void)?
    var onCloseTab: ((BufferID) -> Void)?
    /// Con trỏ hoặc vị trí cuộn của buffer đang hiện đã đổi (cần ghi session).
    var onViewStateChange: (() -> Void)?
    var onBannerAction: ((BannerAction, Buffer) -> Void)?

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

        let stack = NSStackView(views: [tabBar, banner, scrollView])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .width
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        banner.isHidden = true

        textView.delegate = self
        textView.attach(emptyStorage)
        textView.isEditable = false
        textView.onTextStorageEdit = { [weak self] in
            self?.ruler.textDidChange()
            self?.notifyCursor()
        }
        textView.onBecomeFirstResponder = { [weak self] in
            guard let self, !self.isRefreshingFocus else { return }
            self.onFocus?()
        }
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

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipViewDidScroll),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView
        )
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
        isSwitchingBuffer = true
        displayedBuffer = buffer
        textView.attach(buffer?.textStorage ?? emptyStorage, language: buffer?.language ?? .plain)
        applyBufferState()
    }

    /// Nội dung buffer đang hiện vừa được nạp lại từ đĩa: áp lại con trỏ/cuộn/chế độ chỉ đọc đã lưu trong buffer.
    func bufferDidReload() {
        isSwitchingBuffer = true
        applyBufferState()
    }

    /// Ngôn ngữ của buffer đang hiện vừa đổi → tô màu lại.
    func languageDidChange() {
        textView.setLanguage(displayedBuffer?.language ?? .plain)
    }

    /// Banner: file đổi bên ngoài (có nút), đỏ khi lưu lỗi, vàng khi file chỉ đọc (không phải UTF-8).
    func refreshBanner() {
        guard let buffer = displayedBuffer else {
            banner.isHidden = true
            return
        }
        let act = { [weak self, weak buffer] (action: BannerAction) in
            guard let buffer else { return }
            self?.onBannerAction?(action, buffer)
        }
        if buffer.externalChange == .modified {
            banner.show(text: "File đã bị sửa bên ngoài", background: Theme.bannerWarning,
                        actions: [("Nạp bản trên đĩa", { act(.reloadFromDisk) }),
                                  ("Giữ bản của tôi", { act(.keepMine) })])
        } else if buffer.externalChange == .deleted {
            banner.show(text: "File không còn trên đĩa", background: Theme.bannerError,
                        actions: [("Lưu lại", { act(.keepMine) }),
                                  ("Đóng tab", { act(.closeTab) })])
        } else if case let .failed(message) = buffer.saveState {
            banner.show(text: "Không lưu được: \(message) — nội dung vẫn được giữ, sẽ thử lại ở lần lưu sau.",
                        background: Theme.bannerError)
        } else if buffer.isReadOnly {
            banner.show(text: "File không đọc được bằng UTF-8 — đang mở ở chế độ chỉ đọc.",
                        background: Theme.bannerWarning)
        } else {
            banner.isHidden = true
        }
    }

    func setFontSize(_ size: CGFloat) {
        textView.setFontSize(size)
        ruler.fontDidChange()
    }

    func notifyCursor() {
        let position = textView.cursorPosition
        onCursorChange?(position.line, position.column)
    }

    /// Đưa trạng thái cuộn hiện tại vào buffer (khi lưu session hoặc thoát app).
    func saveDisplayedState() {
        guard let displayedBuffer, !isSwitchingBuffer else { return }
        displayedBuffer.selection = textView.selectedRange()
        displayedBuffer.scrollY = scrollView.contentView.bounds.origin.y
    }

    /// Text view luôn cao ít nhất bằng vùng nhìn thấy: click vào khoảng trống dưới văn bản
    /// phải rơi vào text view (con trỏ về cuối văn bản), không rơi vào clip view.
    override func layout() {
        super.layout()
        let visibleHeight = scrollView.contentSize.height
        if textView.minSize.height != visibleHeight {
            textView.minSize = NSSize(width: 0, height: visibleHeight)
            textView.sizeToFit()
        }
    }

    // MARK: - Private

    /// Áp trạng thái của `displayedBuffer` lên text view. Gọi khi `isSwitchingBuffer == true`.
    private func applyBufferState() {
        let buffer = displayedBuffer
        let wasEditable = textView.isEditable
        let editable = buffer.map { !$0.isReadOnly } ?? false
        textView.isEditable = editable
        // Cột trống: không chọn/không focus được (không có gì để gõ).
        textView.isSelectable = buffer != nil
        let length = textView.textStorage?.length ?? 0
        let selection = buffer?.selection ?? NSRange(location: 0, length: 0)
        let location = min(selection.location, length)
        textView.setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
        restoreScroll(to: buffer?.scrollY ?? 0)
        isSwitchingBuffer = false
        // Text view đang focus mà chuyển sang không sửa được: con trỏ (NSTextInsertionIndicator) không tự ẩn,
        // cứ nhấp nháy ở vị trí cũ. Bỏ focus để AppKit ẩn nó; còn buffer (chỉ đọc) thì nhận focus lại.
        if wasEditable, !editable, let window, window.firstResponder === textView {
            isRefreshingFocus = true
            window.makeFirstResponder(nil)
            if buffer != nil { window.makeFirstResponder(textView) }
            isRefreshingFocus = false
        }

        ruler.textDidChange()
        refreshBanner()
        notifyCursor()
    }

    private func restoreScroll(to y: CGFloat) {
        if let layoutManager = textView.layoutManager, let container = textView.textContainer {
            let visible = NSRect(x: 0, y: y, width: container.size.width, height: scrollView.contentSize.height)
            layoutManager.ensureLayout(forBoundingRect: visible, in: container)
        }
        textView.scroll(NSPoint(x: 0, y: y))
    }

    @objc private func clipViewDidScroll() {
        guard !isSwitchingBuffer, let displayedBuffer else { return }
        displayedBuffer.scrollY = scrollView.contentView.bounds.origin.y
        onViewStateChange?()
    }

    // MARK: NSTextViewDelegate

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isSwitchingBuffer else { return }
        if let displayedBuffer {
            displayedBuffer.selection = textView.selectedRange()
            onViewStateChange?()
        }
        notifyCursor()
    }

    /// Mỗi buffer có undo stack riêng, không lẫn khi chuyển tab.
    func undoManager(for view: NSTextView) -> UndoManager? {
        displayedBuffer?.undoManager
    }
}

/// Dải thông báo phía trên editor, có thể kèm nút.
@MainActor
final class BannerView: NSView {
    private let label = NSTextField(wrappingLabelWithString: "")
    private let stack = NSStackView()
    private var actions: [() -> Void] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = Theme.text
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 20),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) không dùng")
    }

    /// Tiêu đề các nút hiện tại (để test).
    var buttonTitles: [String] {
        stack.arrangedSubviews.compactMap { ($0 as? NSButton)?.title }
    }

    var text: String { label.stringValue }

    func show(text: String, background: NSColor, actions: [(String, () -> Void)] = []) {
        label.stringValue = text
        layer?.backgroundColor = background.cgColor
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stack.addArrangedSubview(label)
        self.actions = actions.map(\.1)
        for (index, action) in actions.enumerated() {
            let button = NSButton(title: action.0, target: self, action: #selector(buttonClicked(_:)))
            button.bezelStyle = .push
            button.controlSize = .small
            button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            button.tag = index
            stack.addArrangedSubview(button)
        }
        isHidden = false
    }

    @objc private func buttonClicked(_ sender: NSButton) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag]()
    }
}

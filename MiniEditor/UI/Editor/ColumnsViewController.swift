import AppKit

/// Vùng các cột editor (SPEC §3.2): một `NSSplitView` dọc, thêm/bớt cột theo `AppState.layout`.
@MainActor
final class ColumnsViewController: NSViewController {
    /// Độ rộng tối thiểu khi kéo thanh chia. Ưu tiên 495: thắng thao tác kéo (490)
    /// nhưng thua việc thu nhỏ cửa sổ (500), nên app không ép cửa sổ to ra hay tự gộp cột.
    static let minimumColumnWidth: CGFloat = 200
    private static let minimumWidthPriority = NSLayoutConstraint.Priority(495)

    private let appState: AppState
    private let splitView = ThemedSplitView()
    private var columnViews: [Column.ID: EditorColumnView] = [:]
    /// Đang xử lý việc một text view vừa nhận focus → không gọi lại makeFirstResponder (tránh lồng nhau).
    private var isHandlingResponderFocus = false

    /// Vị trí con trỏ của cột đang focus.
    var onCursorChange: ((Int, Int) -> Void)?
    /// Con trỏ/cuộn/độ rộng cột đổi → cần ghi session.
    var onViewStateChange: (() -> Void)?

    init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) không dùng")
    }

    override func loadView() {
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.arrangesAllSubviews = true
        view = splitView
        NotificationCenter.default.addObserver(
            self, selector: #selector(splitViewDidResize),
            name: NSSplitView.didResizeSubviewsNotification, object: splitView
        )
    }

    var focusedColumnView: EditorColumnView? {
        columnViews[appState.layout.focusedColumn.id]
    }

    /// Đồng bộ cột/tab với `appState.layout`. Gọi sau mỗi lần layout đổi.
    func apply() {
        let layout = appState.layout
        let ids = Set(layout.columns.map(\.id))
        var countChanged = false

        // Gỡ cột trước (lưu trạng thái buffer đang hiện, vì nháp có thể chuyển sang cột khác).
        for (id, view) in columnViews where !ids.contains(id) {
            view.show(nil)
            splitView.removeArrangedSubview(view)
            view.removeFromSuperview()
            columnViews[id] = nil
            countChanged = true
        }

        for (index, column) in layout.columns.enumerated() {
            let view: EditorColumnView
            if let existing = columnViews[column.id] {
                view = existing
            } else {
                view = makeColumnView(id: column.id)
                columnViews[column.id] = view
                countChanged = true
            }
            if splitView.arrangedSubviews.count <= index || splitView.arrangedSubviews[index] !== view {
                splitView.insertArrangedSubview(view, at: index)
            }
            view.update(column: column, buffers: appState.buffers, isFocused: index == layout.focusedIndex)
        }

        if countChanged { equalizeWidths() }
        focusFocusedColumn()
        focusedColumnView?.notifyCursor()
    }

    func setFontSize(_ size: CGFloat) {
        columnViews.values.forEach { $0.setFontSize(size) }
    }

    /// Cập nhật banner của cột đang hiện buffer này.
    func refreshBanner(for buffer: Buffer) {
        columnViews.values.filter { $0.displayedBuffer === buffer }.forEach { $0.refreshBanner() }
    }

    /// Buffer vừa được nạp lại từ đĩa → cột đang hiện nó áp lại con trỏ/cuộn.
    func bufferDidReload(_ buffer: Buffer) {
        columnViews.values.filter { $0.displayedBuffer === buffer }.forEach { $0.bufferDidReload() }
    }

    /// Ghi vị trí con trỏ/cuộn hiện tại vào các buffer đang hiện.
    func saveDisplayedStates() {
        columnViews.values.forEach { $0.saveDisplayedState() }
    }

    /// Tỉ lệ độ rộng các cột theo thứ tự (tổng = 1).
    func columnWidthRatios() -> [Double] {
        let widths = splitView.arrangedSubviews.map { Double($0.frame.width) }
        let total = widths.reduce(0, +)
        guard total > 0 else { return widths.map { _ in 1 / Double(max(widths.count, 1)) } }
        return widths.map { $0 / total }
    }

    /// Đặt độ rộng các cột theo tỉ lệ đã lưu (khôi phục session).
    func applyColumnWidthRatios(_ ratios: [Double]) {
        let count = splitView.arrangedSubviews.count
        guard count > 1, ratios.count == count else { return }
        let sum = ratios.reduce(0, +)
        guard sum > 0 else { return }
        splitView.layoutSubtreeIfNeeded()
        let divider = splitView.dividerThickness
        let available = splitView.bounds.width - divider * CGFloat(count - 1)
        guard available > 0 else { return }
        var position: CGFloat = 0
        for index in 0..<(count - 1) {
            position += available * CGFloat(ratios[index] / sum)
            splitView.setPosition(position + divider * CGFloat(index), ofDividerAt: index)
        }
    }

    // MARK: - Private

    private func makeColumnView(id: Column.ID) -> EditorColumnView {
        let view = EditorColumnView(columnID: id, fontSize: appState.fontSize)
        let minWidth = view.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumColumnWidth)
        minWidth.priority = Self.minimumWidthPriority
        minWidth.isActive = true

        view.onFocus = { [weak self] in
            guard let self else { return }
            self.isHandlingResponderFocus = true
            self.appState.focusColumn(id: id)
            self.isHandlingResponderFocus = false
        }
        view.onSelectTab = { [weak self] buffer in self?.appState.activateTab(buffer) }
        view.onCloseTab = { [weak self] buffer in self?.appState.closeTab(buffer) }
        view.onViewStateChange = { [weak self] in self?.onViewStateChange?() }
        view.onBannerAction = { [weak self] action, buffer in
            guard let self else { return }
            switch action {
            case .reloadFromDisk: self.appState.reloadFromDisk(buffer)
            case .keepMine: self.appState.keepMine(buffer)
            case .closeTab: self.appState.closeTab(buffer.id, discardingChanges: true)
            }
        }
        view.onCursorChange = { [weak self] line, column in
            guard let self, self.appState.layout.focusedColumn.id == id else { return }
            self.onCursorChange?(line, column)
        }
        return view
    }

    @objc private func splitViewDidResize() {
        onViewStateChange?()
    }

    /// Chia đều độ rộng các cột.
    private func equalizeWidths() {
        let count = splitView.arrangedSubviews.count
        guard count > 1 else { return }
        splitView.layoutSubtreeIfNeeded()
        let divider = splitView.dividerThickness
        let width = (splitView.bounds.width - divider * CGFloat(count - 1)) / CGFloat(count)
        guard width > 0 else { return }
        for index in 0..<(count - 1) {
            splitView.setPosition(width * CGFloat(index + 1) + divider * CGFloat(index), ofDividerAt: index)
        }
    }

    /// Đưa focus bàn phím về text view của cột đang focus (nếu chưa ở trong cột đó).
    private func focusFocusedColumn() {
        guard !isHandlingResponderFocus, let window = view.window, let target = focusedColumnView else { return }
        if let responder = window.firstResponder as? NSView, responder.isDescendant(of: target) { return }
        window.makeFirstResponder(target.textView)
    }
}

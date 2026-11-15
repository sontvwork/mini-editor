import AppKit

/// Cửa sổ chính: [sidebar | các cột editor] phía trên, thanh trạng thái dưới cùng.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    static let defaultSidebarWidth: CGFloat = 240
    static let minimumSidebarWidth: CGFloat = 160
    static let defaultFrame = NSRect(x: 100, y: 100, width: 1400, height: 860)

    private let appState: AppState
    private let sessionStore: SessionStore
    private let sidebar: SidebarViewController
    private let columns: ColumnsViewController
    private let statusBar = StatusBarView()
    private let splitViewController = NSSplitViewController()
    private let sidebarItem: NSSplitViewItem
    private var directoryWatcher: DirectoryWatcher?
    /// Theo dõi file đang mở (FSEvents trên thư mục chứa chúng).
    private var openFileWatcher: DirectoryWatcher?
    private var watchedFileDirectories: Set<String> = []
    /// Độ rộng sidebar lần cuối khi còn hiện (để lưu session khi đang ẩn).
    private var lastSidebarWidth = MainWindowController.defaultSidebarWidth

    init(appState: AppState, sessionStore: SessionStore, restoring session: Session?) {
        self.appState = appState
        self.sessionStore = sessionStore
        sidebar = SidebarViewController(appState: appState)
        columns = ColumnsViewController(appState: appState)
        sidebarItem = NSSplitViewItem(viewController: sidebar)

        let window = NSWindow(
            contentRect: Self.defaultFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MiniEditor"
        window.isReleasedWhenClosed = false
        window.backgroundColor = Theme.chromeBackground
        window.minSize = NSSize(width: 480, height: 320)
        window.tabbingMode = .disallowed
        super.init(window: window)

        buildContent(in: window)
        restoreWindowLayout(session, in: window)
        bindState()
        columns.apply()
        if let ratios = session?.columns.map(\.widthRatio) {
            columns.applyColumnWidthRatios(ratios)
        }
        sidebar.highlight(appState.activeBuffer?.id)
        updateStatusBar()
        window.delegate = self
        sessionStore.provider = { [weak self] in self?.makeSession() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) không dùng")
    }

    // MARK: - Lệnh

    /// ⌘O: chọn thư mục làm workspace.
    func showAddWorkspacePanel() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Thêm workspace"
        Task { @MainActor in
            guard await panel.beginSheetModal(for: window) == .OK else { return }
            for url in panel.urls {
                appState.addWorkspace(url: url)
            }
        }
    }

    /// File lớn hơn mức này thì hỏi trước khi mở (SPEC §3.8).
    static let largeFileBytes = 20 * 1024 * 1024

    /// Mở file thành tab (click trên sidebar). File > 20MB → hỏi trước. Lỗi đọc file → báo lỗi.
    func openFile(_ url: URL) {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let alreadyOpen = appState.buffers[.file(path: url)] != nil
        guard size > Self.largeFileBytes, !alreadyOpen, let window else { return performOpenFile(url) }
        let alert = NSAlert()
        alert.messageText = "File lớn (\(size / 1024 / 1024) MB)"
        alert.informativeText = "Mở \(url.lastPathComponent)? File lớn có thể làm app chậm; tô màu sẽ bị tắt."
        alert.addButton(withTitle: "Mở")
        alert.addButton(withTitle: "Huỷ")
        Task { @MainActor in
            if await alert.beginSheetModal(for: window) == .alertFirstButtonReturn {
                performOpenFile(url)
            } else {
                sidebar.highlight(appState.activeBuffer?.id)
            }
        }
    }

    private func performOpenFile(_ url: URL) {
        do {
            try appState.openFile(url)
        } catch {
            sidebar.highlight(appState.activeBuffer?.id)
            showError(error)
        }
    }

    /// ⌘N: nháp mới vào cột đang focus.
    func newDraft() {
        do {
            try appState.newDraft()
        } catch {
            showError(error)
        }
    }

    /// ⌘S: file thường → lưu ngay; nháp → Save As.
    func saveActiveBuffer() {
        guard let buffer = appState.activeBuffer else { return }
        switch buffer.id {
        case .file:
            guard !buffer.isReadOnly else { return NSSound.beep() }
            appState.saveNow(buffer)
        case let .draft(id):
            showSavePanel(forDraft: id, buffer: buffer)
        }
    }

    /// ⌘B: ẩn/hiện sidebar.
    func toggleSidebar() {
        sidebarItem.animator().isCollapsed = !sidebarItem.isCollapsed
    }

    /// Ghi trạng thái hiển thị hiện tại vào buffer rồi tạo session.
    func makeSession() -> Session {
        columns.saveDisplayedStates()
        if !sidebarItem.isCollapsed, sidebar.view.frame.width > 0 {
            lastSidebarWidth = sidebar.view.frame.width
        }
        let state = AppState.WindowLayoutState(
            window: window.map { Session.WindowState(frame: NSStringFromRect($0.frame)) },
            sidebar: Session.SidebarState(visible: !sidebarItem.isCollapsed, width: Double(lastSidebarWidth)),
            columnWidthRatios: columns.columnWidthRatios()
        )
        return appState.makeSession(window: state)
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        appState.markSessionDirty()
    }

    func windowDidResize(_ notification: Notification) {
        appState.markSessionDirty()
    }

    // MARK: - Private

    private func showSavePanel(forDraft id: UUID, buffer: Buffer) {
        guard let window else { return }
        let panel = NSSavePanel()
        let ext = switch buffer.language {
        case .bash: "sh"
        case .markdown: "md"
        case .plain: "txt"
        }
        panel.nameFieldStringValue = "\(buffer.draftTitle).\(ext)"
        if let workspace = appState.focusedWorkspace, !workspace.isMissing {
            panel.directoryURL = workspace.url
        }
        Task { @MainActor in
            guard await panel.beginSheetModal(for: window) == .OK, let url = panel.url else { return }
            do {
                try appState.saveDraft(id, to: url)
            } catch {
                showError(error)
            }
        }
    }

    private func showError(_ error: Error) {
        guard let window else { return }
        NSAlert(error: error).beginSheetModal(for: window)
    }

    private func updateStatusBar() {
        let buffer = appState.activeBuffer
        statusBar.setSaveState(buffer?.saveState, isReadOnly: buffer?.isReadOnly ?? false)
        statusBar.setLanguage(buffer?.language)
    }

    private func bindState() {
        columns.onCursorChange = { [weak self] line, column in
            self?.statusBar.setCursor(line: line, column: column)
        }
        columns.onViewStateChange = { [weak self] in
            self?.appState.markSessionDirty()
        }
        appState.onFontSizeChange = { [weak self] size in
            self?.columns.setFontSize(size)
            self?.statusBar.setFontSize(size)
        }
        appState.onLayoutChange = { [weak self] in
            guard let self else { return }
            self.columns.apply()
            self.sidebar.highlight(self.appState.activeBuffer?.id)
            self.updateStatusBar()
            self.updateWatchedFiles()
        }
        appState.onBufferStatusChange = { [weak self] buffer in
            self?.columns.refreshBanner(for: buffer)
            self?.updateStatusBar()
        }
        appState.onBufferReload = { [weak self] buffer in
            self?.columns.bufferDidReload(buffer)
        }
        appState.onBufferLanguageChange = { [weak self] buffer in
            self?.columns.languageDidChange(for: buffer)
            self?.updateStatusBar()
        }
        statusBar.onSelectLanguage = { [weak self] language in
            guard let self, let buffer = self.appState.activeBuffer else { return }
            self.appState.setLanguage(language, of: buffer)
        }
        appState.onDraftsChange = { [weak self] in
            self?.sidebar.reloadDrafts()
        }
        appState.onSessionDirty = { [weak self] in
            self?.sessionStore.scheduleSave()
        }
        sidebar.onOpenFile = { [weak self] url in self?.openFile(url) }
        sidebar.onOpenDraft = { [weak self] id in
            do {
                try self?.appState.openDraft(id)
            } catch {
                self?.showError(error)
            }
        }
        appState.onWorkspacesChange = { [weak self] in
            self?.sidebar.reloadWorkspaces()
            self?.updateWatchedDirectories()
        }
        directoryWatcher = DirectoryWatcher { [weak self] changes in
            self?.sidebar.applyDirectoryChanges(changes)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(outerSplitViewDidResize),
            name: NSSplitView.didResizeSubviewsNotification, object: splitViewController.splitView
        )
        openFileWatcher = DirectoryWatcher(debounce: .milliseconds(100), fileEvents: true) { [weak self] changes in
            // Thư mục gốc bị đổi/cần quét lại → kiểm tra mọi file đang mở.
            self?.appState.checkExternalChanges(paths: changes.recursivePaths.isEmpty ? changes.paths : nil)
        }
        statusBar.setFontSize(appState.fontSize)
        updateWatchedDirectories()
        updateWatchedFiles()
    }

    /// Chỉ dựng lại stream khi tập thư mục cần theo dõi đổi (không phải mỗi lần chuyển tab).
    private func updateWatchedFiles() {
        let directories = appState.watchedDirectories
        guard directories != watchedFileDirectories else { return }
        watchedFileDirectories = directories
        openFileWatcher?.watch(paths: directories.sorted())
    }

    @objc private func outerSplitViewDidResize() {
        if !sidebarItem.isCollapsed, sidebar.view.frame.width > 0 {
            lastSidebarWidth = sidebar.view.frame.width
        }
        appState.markSessionDirty()
    }

    private func updateWatchedDirectories() {
        directoryWatcher?.watch(paths: appState.workspaces.filter { !$0.isMissing }.map { $0.url.path })
    }

    private func buildContent(in window: NSWindow) {
        let splitView = ThemedSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitViewController.splitView = splitView

        sidebarItem.canCollapse = true
        sidebarItem.minimumThickness = Self.minimumSidebarWidth
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(260)

        let editorItem = NSSplitViewItem(viewController: columns)
        editorItem.minimumThickness = ColumnsViewController.minimumColumnWidth

        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(editorItem)

        let root = RootViewController(main: splitViewController, statusBar: statusBar)
        window.contentViewController = root
    }

    /// Khung cửa sổ và sidebar từ session (không có thì dùng mặc định).
    private func restoreWindowLayout(_ session: Session?, in window: NSWindow) {
        let savedFrame = session?.window.map { NSRectFromString($0.frame) } ?? .zero
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(savedFrame) }
        if savedFrame.width >= window.minSize.width, savedFrame.height >= window.minSize.height, onScreen {
            window.setFrame(savedFrame, display: false)
        } else {
            window.setFrame(Self.defaultFrame, display: false)
            window.center()
        }
        window.contentView?.layoutSubtreeIfNeeded()

        let width = session.map { CGFloat($0.sidebar.width) } ?? Self.defaultSidebarWidth
        lastSidebarWidth = max(width, Self.minimumSidebarWidth)
        splitViewController.splitView.setPosition(lastSidebarWidth, ofDividerAt: 0)
        if session?.sidebar.visible == false {
            sidebarItem.isCollapsed = true
        }
    }
}

/// Nội dung cửa sổ: split view controller phía trên, thanh trạng thái phía dưới.
@MainActor
private final class RootViewController: NSViewController {
    private let main: NSViewController
    private let statusBar: StatusBarView

    init(main: NSViewController, statusBar: StatusBarView) {
        self.main = main
        self.statusBar = statusBar
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) không dùng")
    }

    override func loadView() {
        let container = NSView()
        addChild(main)
        let mainView = main.view
        mainView.translatesAutoresizingMaskIntoConstraints = false
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(mainView)
        container.addSubview(statusBar)
        NSLayoutConstraint.activate([
            mainView.topAnchor.constraint(equalTo: container.topAnchor),
            mainView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            mainView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            mainView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        view = container
    }
}

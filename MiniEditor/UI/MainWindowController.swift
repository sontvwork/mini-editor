import AppKit

/// Cửa sổ chính: [sidebar | các cột editor] phía trên, thanh trạng thái dưới cùng.
@MainActor
final class MainWindowController: NSWindowController {
    static let defaultSidebarWidth: CGFloat = 240
    static let minimumSidebarWidth: CGFloat = 160

    private let appState: AppState
    private let sidebar: SidebarViewController
    private let columns: ColumnsViewController
    private let statusBar = StatusBarView()
    private let splitViewController = NSSplitViewController()
    private let sidebarItem: NSSplitViewItem
    private var directoryWatcher: DirectoryWatcher?

    init(appState: AppState) {
        self.appState = appState
        sidebar = SidebarViewController(appState: appState)
        columns = ColumnsViewController(appState: appState)
        sidebarItem = NSSplitViewItem(viewController: sidebar)

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1400, height: 860),
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
        bindState()

        window.center()
        columns.apply()
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

    /// Mở file thành tab (click trên sidebar). Lỗi đọc file → báo lỗi.
    func openFile(_ url: URL) {
        do {
            try appState.openFile(url)
        } catch {
            sidebar.highlightFile(appState.activeBuffer?.id.fileURL)
            guard let window else { return }
            NSAlert(error: error).beginSheetModal(for: window)
        }
    }

    /// ⌘B: ẩn/hiện sidebar.
    func toggleSidebar() {
        sidebarItem.animator().isCollapsed = !sidebarItem.isCollapsed
    }

    // MARK: - Private

    private func bindState() {
        columns.onCursorChange = { [weak self] line, column in
            self?.statusBar.setCursor(line: line, column: column)
        }
        appState.onFontSizeChange = { [weak self] size in
            self?.columns.setFontSize(size)
            self?.statusBar.setFontSize(size)
        }
        appState.onLayoutChange = { [weak self] in
            guard let self else { return }
            self.columns.apply()
            self.sidebar.highlightFile(self.appState.activeBuffer?.id.fileURL)
        }
        sidebar.onOpenFile = { [weak self] url in self?.openFile(url) }
        appState.onWorkspacesChange = { [weak self] in
            self?.sidebar.reloadWorkspaces()
            self?.updateWatchedDirectories()
        }
        directoryWatcher = DirectoryWatcher { [weak self] changes in
            self?.sidebar.applyDirectoryChanges(changes)
        }
        statusBar.setFontSize(appState.fontSize)
        updateWatchedDirectories()
    }

    private func updateWatchedDirectories() {
        directoryWatcher?.watch(paths: appState.workspaces.map { $0.url.path })
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
        window.setContentSize(NSSize(width: 1400, height: 860))
        root.view.layoutSubtreeIfNeeded()
        splitView.setPosition(Self.defaultSidebarWidth, ofDividerAt: 0)
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

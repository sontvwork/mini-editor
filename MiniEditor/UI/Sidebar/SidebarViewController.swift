import AppKit

/// Nhóm workspace trên sidebar. Con của nhóm là con của thư mục gốc.
@MainActor
private final class WorkspaceItem {
    let id: Workspace.ID
    let root: FileNode
    /// Đường dẫn thật của gốc, để so với đường dẫn FSEvents báo về.
    let realRootPath: String
    /// Trạng thái "không tìm thấy" lúc tạo; đổi thì phải dựng lại cây.
    let wasMissing: Bool

    init(workspace: Workspace) {
        id = workspace.id
        wasMissing = workspace.isMissing
        root = FileNode.root(of: workspace.url)
        realRootPath = DirectoryWatcher.realPath(workspace.url.path)
    }
}

/// Nhóm NHÁP luôn nằm cuối sidebar.
@MainActor
private final class DraftsGroupItem {}

/// Một nháp trong nhóm NHÁP.
@MainActor
private final class DraftItem {
    let id: UUID
    init(id: UUID) { self.id = id }
}

/// Sidebar: `NSOutlineView` dạng source list (SPEC §3.1).
@MainActor
final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    static let draftsTitle = "NHÁP (CHƯA LƯU TÊN)"

    private let appState: AppState
    private let outlineView = NSOutlineView()
    private var workspaceItems: [WorkspaceItem] = []
    private let draftsItem = DraftsGroupItem()
    private var draftItems: [DraftItem] = []
    /// Đang tự mở lại các thư mục → không ghi ngược trạng thái vào AppState.
    private var isRestoringExpansion = false
    /// Buffer đang active trong cột đang focus (được highlight).
    private var highlightedBuffer: BufferID?

    /// Click 1 lần vào file.
    var onOpenFile: ((URL) -> Void)?
    /// Click vào một nháp trong nhóm NHÁP.
    var onOpenDraft: ((UUID) -> Void)?
    /// Menu chuột phải trên nháp.
    var onRenameDraft: ((UUID) -> Void)?
    var onDeleteDraft: ((UUID) -> Void)?

    init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) không dùng")
    }

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.backgroundColor = Theme.sidebarBackground
        outlineView.floatsGroupRows = false
        outlineView.rowSizeStyle = .custom
        outlineView.rowHeight = 22
        outlineView.indentationPerLevel = 12
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outlineView.focusRingType = .none
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(rowClicked(_:))

        let menu = NSMenu()
        menu.delegate = self
        outlineView.menu = menu

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.sidebarBackground
        scrollView.borderType = .noBorder

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = Theme.sidebarBackground.cgColor
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reloadWorkspaces()
    }

    // MARK: - Cập nhật từ AppState / FSEvents

    /// Đồng bộ với `appState.workspaces` (thêm/gỡ), rồi mở lại các nhóm/thư mục đã lưu.
    func reloadWorkspaces() {
        let existing = Dictionary(uniqueKeysWithValues: workspaceItems.map { ($0.id, $0) })
        workspaceItems = appState.workspaces.map { workspace in
            if let item = existing[workspace.id], item.wasMissing == workspace.isMissing { return item }
            return WorkspaceItem(workspace: workspace)
        }
        syncDraftItems()
        outlineView.reloadData()
        withRestoringExpansion {
            outlineView.expandItem(draftsItem)
            for item in workspaceItems {
                guard let workspace = appState.workspace(id: item.id), !workspace.collapsed else { continue }
                outlineView.expandItem(item)
                restoreExpansion(below: item.root, in: item)
            }
        }
        applyHighlight()
    }

    /// Đồng bộ nhóm NHÁP với `appState.drafts`.
    func reloadDrafts() {
        syncDraftItems()
        outlineView.reloadItem(draftsItem, reloadChildren: true)
        withRestoringExpansion { outlineView.expandItem(draftsItem) }
        applyHighlight()
    }

    /// Highlight buffer đang active trong cột đang focus (`nil` = bỏ highlight).
    /// Chỉ chọn dòng đang hiện, không tự mở thư mục cha.
    func highlight(_ buffer: BufferID?) {
        highlightedBuffer = buffer
        applyHighlight()
    }

    /// Đọc lại các thư mục đã nạp mà FSEvents báo có thay đổi.
    func applyDirectoryChanges(_ changes: DirectoryChanges) {
        for item in workspaceItems {
            var nodes: [FileNode] = []
            for path in changes.recursivePaths {
                if let node = loadedNode(forRealPath: path, in: item) {
                    nodes.append(contentsOf: node.loadedDirectories())
                } else if path == item.realRootPath || item.realRootPath.hasPrefix(path + "/") {
                    nodes.append(contentsOf: item.root.loadedDirectories())
                }
            }
            for path in changes.paths {
                if let node = loadedNode(forRealPath: path, in: item), node.isLoaded {
                    nodes.append(node)
                }
            }
            var seen = Set<ObjectIdentifier>()
            for node in nodes where seen.insert(ObjectIdentifier(node)).inserted {
                reload(node, in: item)
            }
        }
    }

    // MARK: - Private

    private func reload(_ node: FileNode, in item: WorkspaceItem) {
        node.reloadChildren()
        let outlineItem: Any = node === item.root ? item : node
        // Nút chưa hiện trên outline (cha đang đóng) thì chỉ cần cập nhật model.
        guard node === item.root || outlineView.row(forItem: node) >= 0 else { return }
        outlineView.reloadItem(outlineItem, reloadChildren: true)
        withRestoringExpansion {
            restoreExpansion(below: node, in: item)
        }
        applyHighlight()
    }

    private func syncDraftItems() {
        let existing = Dictionary(uniqueKeysWithValues: draftItems.map { ($0.id, $0) })
        draftItems = appState.drafts.map { existing[$0.id] ?? DraftItem(id: $0.id) }
    }

    private func applyHighlight() {
        let item: Any?
        switch highlightedBuffer {
        case let .file(url): item = visibleNode(for: url)
        case let .draft(id): item = draftItems.first { $0.id == id }
        case nil: item = nil
        }
        let row = item.map { outlineView.row(forItem: $0) } ?? -1
        guard row >= 0 else {
            outlineView.deselectAll(nil)
            return
        }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
    }

    /// Nút đang hiện trên outline ứng với file (workspace lồng nhau → workspace sâu nhất).
    private func visibleNode(for url: URL) -> FileNode? {
        let path = url.path
        let candidates = workspaceItems.compactMap { item -> (Int, FileNode)? in
            let root = item.root.url.standardizedFileURL.path
            guard path.hasPrefix(root + "/"),
                  let node = item.root.loadedDescendant(atRelativePath: String(path.dropFirst(root.count + 1))),
                  outlineView.row(forItem: node) >= 0 else { return nil }
            return (root.count, node)
        }
        return candidates.max { $0.0 < $1.0 }?.1
    }

    /// Tìm nút đã nạp ứng với đường dẫn thật FSEvents báo về.
    private func loadedNode(forRealPath path: String, in item: WorkspaceItem) -> FileNode? {
        if path == item.realRootPath { return item.root }
        guard path.hasPrefix(item.realRootPath + "/") else { return nil }
        let relative = String(path.dropFirst(item.realRootPath.count + 1))
        guard !DirectoryLister.isHidden(relativePath: relative) else { return nil }
        return item.root.loadedDescendant(atRelativePath: relative)
    }

    /// Mở lại các thư mục con đã lưu là "đang mở" (đệ quy).
    private func restoreExpansion(below node: FileNode, in item: WorkspaceItem) {
        guard let workspace = appState.workspace(id: item.id) else { return }
        for child in node.children ?? [] where child.isDirectory && workspace.expandedDirs.contains(child.relativePath) {
            outlineView.expandItem(child)
            restoreExpansion(below: child, in: item)
        }
    }

    private func withRestoringExpansion(_ body: () -> Void) {
        let previous = isRestoringExpansion
        isRestoringExpansion = true
        body()
        isRestoringExpansion = previous
    }

    private func workspaceItem(containing node: FileNode) -> WorkspaceItem? {
        var current: Any? = node
        while let next = current, !(next is WorkspaceItem) {
            current = outlineView.parent(forItem: next)
        }
        return current as? WorkspaceItem
    }

    @objc private func rowClicked(_ sender: Any?) {
        let row = outlineView.clickedRow
        guard row >= 0 else { return }
        switch outlineView.item(atRow: row) {
        case let node as FileNode where !node.isDirectory:
            onOpenFile?(node.url)
        case let draft as DraftItem:
            onOpenDraft?(draft.id)
        default:
            break
        }
    }

    private func isMissing(_ item: WorkspaceItem) -> Bool {
        appState.workspace(id: item.id)?.isMissing ?? false
    }

    @objc private func removeWorkspace(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? Workspace.ID else { return }
        appState.removeWorkspace(id: id)
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        switch item {
        case nil: workspaceItems.count + 1
        case let workspace as WorkspaceItem: isMissing(workspace) ? 0 : workspace.root.loadedChildren().count
        case let node as FileNode: node.loadedChildren().count
        case is DraftsGroupItem: draftItems.count
        default: 0
        }
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        switch item {
        case nil: index < workspaceItems.count ? workspaceItems[index] : draftsItem
        case let workspace as WorkspaceItem: workspace.root.loadedChildren()[index]
        case let node as FileNode: node.loadedChildren()[index]
        case is DraftsGroupItem: draftItems[index]
        default: draftsItem
        }
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        switch item {
        case let workspace as WorkspaceItem: !isMissing(workspace)
        case let node as FileNode: node.isDirectory
        case is DraftsGroupItem: !draftItems.isEmpty
        default: false
        }
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        item is WorkspaceItem || item is DraftsGroupItem
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        item is DraftItem || (item as? FileNode)?.isDirectory == false
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        SidebarRowView()
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        switch item {
        case let workspace as WorkspaceItem:
            let title = appState.workspace(id: workspace.id)?.displayName ?? ""
            return isMissing(workspace)
                ? groupCell(title: title + " (không tìm thấy)", dimmed: true)
                : groupCell(title: title)
        case is DraftsGroupItem:
            return groupCell(title: Self.draftsTitle)
        case let draft as DraftItem:
            let cell = makeCell(identifier: SidebarCellView.fileIdentifier)
            cell.configure(name: appState.drafts.first { $0.id == draft.id }?.title ?? "", isDirectory: false)
            return cell
        case let node as FileNode:
            let cell = makeCell(identifier: SidebarCellView.fileIdentifier)
            cell.configure(name: node.name, isDirectory: node.isDirectory)
            return cell
        default:
            return nil
        }
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard let item = notification.userInfo?["NSObject"] else { return }
        switch item {
        case let workspace as WorkspaceItem:
            if !isRestoringExpansion { appState.setWorkspace(workspace.id, collapsed: false) }
            withRestoringExpansion { restoreExpansion(below: workspace.root, in: workspace) }
        case let node as FileNode:
            guard let workspace = workspaceItem(containing: node) else { return }
            if !isRestoringExpansion { appState.setDirectory(node.relativePath, expanded: true, in: workspace.id) }
            withRestoringExpansion { restoreExpansion(below: node, in: workspace) }
        default:
            break
        }
        if !isRestoringExpansion { applyHighlight() }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !isRestoringExpansion, let item = notification.userInfo?["NSObject"] else { return }
        switch item {
        case let workspace as WorkspaceItem:
            appState.setWorkspace(workspace.id, collapsed: true)
        case let node as FileNode:
            guard let workspace = workspaceItem(containing: node) else { return }
            appState.setDirectory(node.relativePath, expanded: false, in: workspace.id)
        default:
            break
        }
    }

    private func groupCell(title: String, dimmed: Bool = false) -> SidebarCellView {
        let cell = makeCell(identifier: SidebarCellView.groupIdentifier)
        cell.configureGroup(title: title, dimmed: dimmed)
        return cell
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> SidebarCellView {
        if let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? SidebarCellView {
            return cell
        }
        return SidebarCellView(identifier: identifier)
    }

    // MARK: - NSMenuDelegate (menu chuột phải)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = outlineView.clickedRow
        guard row >= 0 else { return }
        func add(_ title: String, _ action: Selector, _ id: UUID) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = id
            menu.addItem(item)
        }
        switch outlineView.item(atRow: row) {
        case let workspace as WorkspaceItem:
            add("Gỡ khỏi sidebar", #selector(removeWorkspace(_:)), workspace.id)
        case let draft as DraftItem:
            add("Đổi tên", #selector(renameDraft(_:)), draft.id)
            add("Xoá nháp", #selector(deleteDraft(_:)), draft.id)
        default:
            break
        }
    }

    @objc private func renameDraft(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onRenameDraft?(id)
    }

    @objc private func deleteDraft(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onDeleteDraft?(id)
    }
}

/// Ô hiển thị một dòng: tiêu đề nhóm hoặc file/thư mục.
@MainActor
private final class SidebarCellView: NSTableCellView {
    static let groupIdentifier = NSUserInterfaceItemIdentifier("group")
    static let fileIdentifier = NSUserInterfaceItemIdentifier("file")

    private let label = NSTextField(labelWithString: "")
    private let icon = NSImageView()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label

        if identifier == Self.groupIdentifier {
            label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            label.textColor = Theme.textMuted
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        } else {
            label.font = NSFont.systemFont(ofSize: 13)
            label.textColor = Theme.text
            icon.contentTintColor = Theme.textMuted
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
            icon.translatesAutoresizingMaskIntoConstraints = false
            addSubview(icon)
            imageView = icon
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                icon.centerYAnchor.constraint(equalTo: centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4),
                label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) không dùng")
    }

    func configureGroup(title: String, dimmed: Bool) {
        label.stringValue = title
        label.textColor = dimmed ? Theme.textMuted.withAlphaComponent(0.5) : Theme.textMuted
    }

    func configure(name: String, isDirectory: Bool) {
        label.stringValue = name
        icon.image = NSImage(systemSymbolName: isDirectory ? "folder" : "doc", accessibilityDescription: nil)
    }
}

/// Dòng sidebar với màu chọn lấy từ Theme.
@MainActor
private final class SidebarRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        Theme.selectionRow.setFill()
        bounds.fill()
    }

    override func drawBackground(in dirtyRect: NSRect) {
        Theme.sidebarBackground.setFill()
        dirtyRect.fill()
    }
}

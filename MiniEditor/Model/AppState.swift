import Foundation

/// Nguồn sự thật duy nhất cho UI.
@MainActor
final class AppState {
    private(set) var fontSize: CGFloat = FontSize.default
    private(set) var workspaces: [Workspace] = []
    private(set) var layout = ColumnLayout.initial()
    /// Buffer của mọi tab đang mở.
    private(set) var buffers: [BufferID: Buffer] = [:]

    /// Gọi khi bố cục cột/tab hoặc cột đang focus thay đổi.
    var onLayoutChange: (() -> Void)?

    /// Gọi khi danh sách workspace thay đổi (thêm/gỡ). Đổi trạng thái mở/đóng thư mục không gọi.
    var onWorkspacesChange: (() -> Void)?

    /// Gọi mỗi khi cỡ chữ thay đổi.
    var onFontSizeChange: ((CGFloat) -> Void)?

    func increaseFontSize() { setFontSize(FontSize.increased(fontSize)) }
    func decreaseFontSize() { setFontSize(FontSize.decreased(fontSize)) }
    func resetFontSize() { setFontSize(FontSize.default) }

    func setFontSize(_ size: CGFloat) {
        let newSize = FontSize.clamped(size)
        guard newSize != fontSize else { return }
        fontSize = newSize
        onFontSizeChange?(newSize)
    }

    // MARK: - Workspace

    func workspace(id: Workspace.ID) -> Workspace? {
        workspaces.first { $0.id == id }
    }

    /// Thêm workspace; thư mục đã có thì trả về workspace cũ.
    @discardableResult
    func addWorkspace(url: URL) -> Workspace.ID {
        let standardized = url.standardizedFileURL
        if let existing = workspaces.first(where: { $0.url.path == standardized.path }) {
            return existing.id
        }
        let workspace = Workspace(url: standardized)
        workspaces.append(workspace)
        onWorkspacesChange?()
        return workspace.id
    }

    /// Gỡ khỏi sidebar, không xoá gì trên đĩa.
    func removeWorkspace(id: Workspace.ID) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces.remove(at: index)
        onWorkspacesChange?()
        setLayout(ColumnLayoutEngine.removeWorkspace(id, from: layout))
    }

    /// Workspace chứa file (workspace lồng nhau → chọn cái sâu nhất).
    func workspaceID(containing url: URL) -> Workspace.ID? {
        let path = url.standardizedFileURL.path
        return workspaces
            .filter { path.hasPrefix($0.url.path.hasSuffix("/") ? $0.url.path : $0.url.path + "/") }
            .max { $0.url.path.count < $1.url.path.count }?
            .id
    }

    func setDirectory(_ relativePath: String, expanded: Bool, in id: Workspace.ID) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        if expanded {
            workspaces[index].expandedDirs.insert(relativePath)
        } else {
            workspaces[index].expandedDirs.remove(relativePath)
        }
    }

    func setWorkspace(_ id: Workspace.ID, collapsed: Bool) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[index].collapsed = collapsed
    }

    // MARK: - Tab & cột

    /// Mở file thành tab theo quy tắc SPEC §3.2. Đã mở thì chỉ focus tab đó.
    func openFile(_ url: URL) throws {
        let id = BufferID.file(path: url)
        if buffers[id] == nil {
            buffers[id] = try Buffer.load(url: url)
        }
        open(Tab(buffer: id, workspaceID: workspaceID(containing: url)))
    }

    /// Đóng tab. Không bao giờ hỏi lưu.
    func closeTab(_ id: BufferID) {
        setLayout(ColumnLayoutEngine.close(id, in: layout))
    }

    func closeActiveTab() {
        guard let tab = layout.focusedColumn.activeTab else { return }
        closeTab(tab.buffer)
    }

    func activateTab(_ id: BufferID) {
        setLayout(ColumnLayoutEngine.activate(id, in: layout))
    }

    func selectNextTab() {
        setLayout(ColumnLayoutEngine.selectAdjacentTab(offset: 1, in: layout))
    }

    func selectPreviousTab() {
        setLayout(ColumnLayoutEngine.selectAdjacentTab(offset: -1, in: layout))
    }

    func focusColumn(at index: Int) {
        setLayout(ColumnLayoutEngine.focusColumn(at: index, in: layout))
    }

    func focusColumn(id: Column.ID) {
        guard let index = layout.columns.firstIndex(where: { $0.id == id }) else { return }
        focusColumn(at: index)
    }

    /// Buffer đang active trong cột đang focus.
    var activeBuffer: Buffer? {
        layout.focusedColumn.activeTab.flatMap { buffers[$0.buffer] }
    }

    private func open(_ tab: Tab) {
        setLayout(ColumnLayoutEngine.open(tab, in: layout))
    }

    private func setLayout(_ newLayout: ColumnLayout) {
        guard newLayout != layout else { return }
        layout = newLayout
        // Bỏ buffer của tab đã đóng khỏi RAM (nháp vẫn còn trên đĩa từ M4).
        let open = Set(newLayout.allTabs.map(\.buffer))
        buffers = buffers.filter { open.contains($0.key) }
        onLayoutChange?()
    }
}

import Foundation

/// Nguồn sự thật duy nhất cho UI.
@MainActor
final class AppState {
    private(set) var fontSize: CGFloat = FontSize.default
    private(set) var workspaces: [Workspace] = []

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
}

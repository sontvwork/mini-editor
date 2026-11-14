import Foundation

/// Một thư mục trên đĩa được thêm vào sidebar.
struct Workspace: Identifiable, Equatable {
    let id: UUID
    let url: URL
    /// Đường dẫn tương đối (so với gốc workspace) của các thư mục đang mở trên sidebar.
    var expandedDirs: Set<String> = []
    /// Nhóm workspace đang bị thu gọn trên sidebar.
    var collapsed = false

    init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url.standardizedFileURL
    }

    /// Tên hiển thị trên sidebar (viết HOA).
    var displayName: String { url.lastPathComponent.uppercased() }
}

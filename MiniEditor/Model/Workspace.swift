import Foundation

/// Một thư mục trên đĩa được thêm vào sidebar.
struct Workspace: Identifiable, Equatable {
    let id: UUID
    let url: URL
    /// Đường dẫn tương đối (so với gốc workspace) của các thư mục đang mở trên sidebar.
    var expandedDirs: Set<String> = []
    /// Nhóm workspace đang bị thu gọn trên sidebar.
    var collapsed = false
    /// Thư mục không còn trên đĩa lúc khôi phục (hiện mờ kèm "(không tìm thấy)").
    var isMissing = false

    init(id: UUID = UUID(), url: URL, expandedDirs: Set<String> = [], collapsed: Bool = false) {
        self.id = id
        self.url = url.standardizedFileURL
        self.expandedDirs = expandedDirs
        self.collapsed = collapsed
        isMissing = Self.directoryIsMissing(self.url)
    }

    /// Kiểm tra lại thư mục còn trên đĩa không. Trả về `true` nếu trạng thái đổi.
    mutating func refreshMissing() -> Bool {
        let missing = Self.directoryIsMissing(url)
        guard missing != isMissing else { return false }
        isMissing = missing
        return true
    }

    private static func directoryIsMissing(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return !(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue)
    }

    /// Tên hiển thị trên sidebar (viết HOA).
    var displayName: String { url.lastPathComponent.uppercased() }
}

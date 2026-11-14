import Foundation

/// Định danh buffer: file có đường dẫn hoặc file nháp.
enum BufferID: Hashable, Sendable {
    case file(URL)
    case draft(UUID)

    /// Luôn chuẩn hoá đường dẫn để một file chỉ có một ID.
    static func file(path url: URL) -> BufferID {
        .file(url.standardizedFileURL)
    }

    var fileURL: URL? {
        if case let .file(url) = self { return url }
        return nil
    }

    var isDraft: Bool {
        if case .draft = self { return true }
        return false
    }
}

/// Một tab: buffer + workspace nó thuộc về (`nil` = nháp hoặc file ngoài workspace, "ở nhờ" trong cột).
struct Tab: Equatable, Sendable {
    let buffer: BufferID
    let workspaceID: UUID?
}

/// Một cột editor. Mỗi cột thuộc về một workspace (SPEC §3.2), trừ khi là cột duy nhất.
struct Column: Equatable, Identifiable, Sendable {
    let id: UUID
    var workspaceID: UUID?
    var tabs: [Tab] = []
    /// `nil` khi cột không có tab.
    var activeIndex: Int?

    init(id: UUID = UUID(), workspaceID: UUID? = nil, tabs: [Tab] = [], activeIndex: Int? = nil) {
        self.id = id
        self.workspaceID = workspaceID
        self.tabs = tabs
        self.activeIndex = activeIndex
    }

    var activeTab: Tab? {
        guard let activeIndex, tabs.indices.contains(activeIndex) else { return nil }
        return tabs[activeIndex]
    }

    func index(of buffer: BufferID) -> Int? {
        tabs.firstIndex { $0.buffer == buffer }
    }
}

/// Toàn bộ bố cục cột. Luôn có ít nhất 1 cột.
struct ColumnLayout: Equatable, Sendable {
    var columns: [Column]
    var focusedIndex: Int

    static func initial() -> ColumnLayout {
        ColumnLayout(columns: [Column()], focusedIndex: 0)
    }

    var focusedColumn: Column { columns[focusedIndex] }

    /// Vị trí (cột, tab) của một buffer nếu đang mở.
    func location(of buffer: BufferID) -> (column: Int, tab: Int)? {
        for (columnIndex, column) in columns.enumerated() {
            if let tabIndex = column.index(of: buffer) {
                return (columnIndex, tabIndex)
            }
        }
        return nil
    }

    var allTabs: [Tab] { columns.flatMap(\.tabs) }
}

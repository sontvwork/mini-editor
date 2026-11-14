import Foundation

/// Liệt kê nội dung một thư mục theo quy tắc sidebar (SPEC §3.1).
enum DirectoryLister {
    static let hiddenNames: Set<String> = [".git", ".DS_Store", "node_modules", "vendor", ".idea", ".vscode"]

    struct Entry: Equatable {
        let name: String
        let isDirectory: Bool
    }

    /// Bỏ tên bị ẩn; thư mục trước, file sau; mỗi nhóm A→Z kiểu Finder.
    static func entries(at url: URL) -> [Entry] {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: url.path) else { return [] }
        let entries = names.compactMap { name -> Entry? in
            guard !hiddenNames.contains(name) else { return nil }
            var isDirectory: ObjCBool = false
            // fileExists đi theo symlink: symlink tới thư mục được coi là thư mục.
            guard fileManager.fileExists(atPath: url.appendingPathComponent(name).path,
                                         isDirectory: &isDirectory) else { return nil }
            return Entry(name: name, isDirectory: isDirectory.boolValue)
        }
        return sorted(entries)
    }

    static func sorted(_ entries: [Entry]) -> [Entry] {
        entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Đường dẫn tương đối có đi qua thư mục bị ẩn không (vd. `.git/objects`).
    static func isHidden(relativePath: String) -> Bool {
        relativePath.split(separator: "/").contains { hiddenNames.contains(String($0)) }
    }
}

/// Một nút trong cây thư mục của sidebar. Con được nạp lười khi cần.
final class FileNode {
    let url: URL
    let name: String
    let isDirectory: Bool
    /// Đường dẫn tương đối so với gốc workspace; gốc là chuỗi rỗng.
    let relativePath: String

    /// `nil` = chưa nạp.
    private(set) var children: [FileNode]?

    init(url: URL, isDirectory: Bool, relativePath: String) {
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
        self.relativePath = relativePath
    }

    static func root(of url: URL) -> FileNode {
        FileNode(url: url, isDirectory: true, relativePath: "")
    }

    var isLoaded: Bool { children != nil }

    /// Con của nút; nạp từ đĩa ở lần gọi đầu.
    func loadedChildren() -> [FileNode] {
        if let children { return children }
        reloadChildren()
        return children ?? []
    }

    /// Đọc lại từ đĩa, giữ nguyên object của các con còn tồn tại (để outline giữ trạng thái mở).
    func reloadChildren() {
        guard isDirectory else {
            children = []
            return
        }
        var existing: [String: FileNode] = [:]
        for child in children ?? [] {
            existing[child.name] = child
        }
        children = DirectoryLister.entries(at: url).map { entry in
            if let node = existing[entry.name], node.isDirectory == entry.isDirectory {
                return node
            }
            let path = relativePath.isEmpty ? entry.name : relativePath + "/" + entry.name
            return FileNode(url: url.appendingPathComponent(entry.name, isDirectory: entry.isDirectory),
                            isDirectory: entry.isDirectory,
                            relativePath: path)
        }
    }

    /// Tìm nút theo đường dẫn tương đối, chỉ đi qua các thư mục đã nạp (không đọc đĩa).
    func loadedDescendant(atRelativePath path: String) -> FileNode? {
        var node = self
        for component in path.split(separator: "/") {
            guard let next = node.children?.first(where: { $0.name == component }) else { return nil }
            node = next
        }
        return node
    }

    /// Mọi thư mục đã nạp trong cây con (kể cả chính nó).
    func loadedDirectories() -> [FileNode] {
        guard isDirectory, let children else { return [] }
        return [self] + children.flatMap { $0.loadedDirectories() }
    }
}

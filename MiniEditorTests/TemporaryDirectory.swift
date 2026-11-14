import Foundation

/// Thư mục tạm cho test, tự xoá khi `remove()`.
struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiniEditorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func makeFile(_ relativePath: String, contents: String = "") throws {
        let fileURL = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: fileURL)
    }

    func makeDirectory(_ relativePath: String) throws {
        try FileManager.default.createDirectory(at: url.appendingPathComponent(relativePath),
                                                withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

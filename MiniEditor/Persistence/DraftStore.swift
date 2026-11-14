import Foundation

/// Thông tin một nháp (lưu trong session.json); nội dung nằm ở `drafts/<uuid>.txt`.
struct DraftInfo: Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var language: Language
    let createdAt: Date
}

/// Đọc/ghi nội dung nháp trong `~/Library/Application Support/MiniEditor/drafts/`.
struct DraftStore: Sendable {
    static let titlePrefix = "Chưa đặt tên-"

    let directory: URL

    func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).txt")
    }

    func exists(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(for: id).path)
    }

    /// Tạo file nháp rỗng.
    func create(_ id: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write("", id: id)
    }

    func read(_ id: UUID) throws -> String {
        TextFileCodec.decode(try Data(contentsOf: url(for: id))).text
    }

    func write(_ text: String, id: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try AtomicFileWriter.write(Data(text.utf8), to: url(for: id))
    }

    func delete(_ id: UUID) throws {
        try FileManager.default.removeItem(at: url(for: id))
    }

    /// `Chưa đặt tên-N` với N là số nhỏ nhất (≥ 1) chưa ai dùng.
    static func nextTitle(existing titles: [String]) -> String {
        let used = Set(titles.compactMap { title -> Int? in
            guard title.hasPrefix(titlePrefix) else { return nil }
            return Int(title.dropFirst(titlePrefix.count))
        })
        var number = 1
        while used.contains(number) { number += 1 }
        return titlePrefix + String(number)
    }
}

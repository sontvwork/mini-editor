import Foundation

/// Nội dung `session.json` (SPEC §6).
struct Session: Codable, Equatable, Sendable {
    struct WindowState: Codable, Equatable, Sendable {
        /// Dạng `NSStringFromRect`, vd. `{{100, 100}, {1400, 860}}`.
        var frame: String
    }

    struct SidebarState: Codable, Equatable, Sendable {
        var visible: Bool
        var width: Double
    }

    struct WorkspaceState: Codable, Equatable, Sendable {
        var id: UUID
        var path: String
        var expandedDirs: [String]
        var collapsed: Bool
    }

    enum TabState: Codable, Equatable, Sendable {
        case file(path: String)
        case draft(id: UUID)

        private enum CodingKeys: String, CodingKey { case kind, path, id }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(String.self, forKey: .kind) {
            case "file": self = .file(path: try container.decode(String.self, forKey: .path))
            case "draft": self = .draft(id: try container.decode(UUID.self, forKey: .id))
            case let kind:
                throw DecodingError.dataCorruptedError(forKey: .kind, in: container,
                                                       debugDescription: "Không biết kind \(kind)")
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .file(path):
                try container.encode("file", forKey: .kind)
                try container.encode(path, forKey: .path)
            case let .draft(id):
                try container.encode("draft", forKey: .kind)
                try container.encode(id, forKey: .id)
            }
        }
    }

    struct ColumnState: Codable, Equatable, Sendable {
        var workspaceId: UUID?
        var widthRatio: Double
        var activeIndex: Int?
        var tabs: [TabState]
    }

    struct BufferState: Codable, Equatable, Sendable {
        /// `[location, length]`.
        var selection: [Int]
        var scrollY: Double
        var language: Language?
    }

    var version = 1
    var fontSize: Double
    var window: WindowState?
    var sidebar: SidebarState
    var workspaces: [WorkspaceState]
    var drafts: [DraftInfo]
    var columns: [ColumnState]
    var focusedColumn: Int
    /// Khoá: đường dẫn file hoặc id nháp.
    var bufferState: [String: BufferState]

    static func key(for id: BufferID) -> String {
        switch id {
        case let .file(url): url.path
        case let .draft(uuid): uuid.uuidString
        }
    }
}

/// Đọc/ghi `session.json`: ghi atomic, debounce 1 giây, và ghi ngay khi thoát app.
@MainActor
final class SessionStore {
    static let debounce: Duration = .seconds(1)

    let fileURL: URL
    /// Tạo session từ trạng thái hiện tại của app.
    var provider: (() -> Session?)?
    private var saveTask: Task<Void, Never>?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `nil` nếu chưa có file hoặc file hỏng. File hỏng được đổi tên thành `session.corrupt-<thời điểm>.json`
    /// để lần lưu sau không ghi đè mất (danh sách workspace, nháp vẫn còn đó để cứu).
    func load() -> Session? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try Self.decode(data)
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = fileURL.deletingLastPathComponent().appendingPathComponent("session.corrupt-\(stamp).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            NSLog("MiniEditor: session.json hỏng (\(error)), đã chuyển sang \(backup.lastPathComponent)")
            return nil
        }
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard let session = provider?() else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try AtomicFileWriter.write(try Self.encode(session), to: fileURL)
        } catch {
            NSLog("MiniEditor: không ghi được session: \(error)")
        }
    }

    nonisolated static func encode(_ session: Session) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(session)
    }

    nonisolated static func decode(_ data: Data) throws -> Session {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Session.self, from: data)
    }
}

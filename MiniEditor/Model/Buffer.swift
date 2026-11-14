import AppKit

/// Nội dung một tab. Mỗi buffer có đúng 1 `NSTextStorage` và undo stack riêng.
@MainActor
final class Buffer {
    let id: BufferID
    let textStorage: NSTextStorage
    let undoManager = UndoManager()
    /// File không đọc được bằng UTF-8 → chỉ đọc.
    let isReadOnly: Bool

    /// Trạng thái hiển thị, lưu lại khi chuyển tab.
    var selection = NSRange(location: 0, length: 0)
    var scrollY: CGFloat = 0

    init(id: BufferID, text: String, isReadOnly: Bool = false) {
        self.id = id
        self.textStorage = NSTextStorage(string: text)
        self.isReadOnly = isReadOnly
    }

    /// Đọc file. Không phải UTF-8 hợp lệ → mở chỉ đọc (giải mã có thay ký tự lỗi).
    static func load(url: URL) throws -> Buffer {
        let data = try Data(contentsOf: url)
        let id = BufferID.file(path: url)
        if let text = String(data: data, encoding: .utf8) {
            return Buffer(id: id, text: text)
        }
        return Buffer(id: id, text: String(decoding: data, as: UTF8.self), isReadOnly: true)
    }

    var displayName: String {
        switch id {
        case let .file(url): url.lastPathComponent
        case .draft: "Chưa đặt tên" // Tên nháp thật có từ M4.
        }
    }
}

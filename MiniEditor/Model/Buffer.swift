import AppKit

/// Nội dung một tab. Mỗi buffer có đúng 1 `NSTextStorage` và undo stack riêng.
@MainActor
final class Buffer: NSObject {
    enum SaveState: Equatable {
        case saved
        /// Có thay đổi đang chờ hết thời gian debounce.
        case pending
        case failed(String)
    }

    /// Đổi từ `.draft` sang `.file` khi nháp được Save As.
    private(set) var id: BufferID
    let textStorage: NSTextStorage
    let undoManager = UndoManager()
    /// File không đọc được bằng UTF-8 → chỉ đọc, không bao giờ tự lưu.
    let isReadOnly: Bool
    private(set) var lineEnding: LineEnding
    var language: Language
    /// Tên nháp (file thì lấy tên file).
    var draftTitle: String

    /// Có thay đổi chưa ghi xuống đĩa.
    var isDirty = false
    var saveState: SaveState = .saved

    /// Trạng thái hiển thị (con trỏ, cuộn), lưu vào session.
    var selection = NSRange(location: 0, length: 0)
    var scrollY: CGFloat = 0

    /// Gọi khi nội dung bị sửa (không tính đổi thuộc tính hiển thị).
    var onEdit: (() -> Void)?

    init(id: BufferID,
         text: String,
         isReadOnly: Bool = false,
         lineEnding: LineEnding = .lf,
         language: Language = .plain,
         draftTitle: String = "") {
        self.id = id
        self.textStorage = NSTextStorage(string: text)
        self.isReadOnly = isReadOnly
        self.lineEnding = lineEnding
        self.language = language
        self.draftTitle = draftTitle
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storageDidProcessEditing(_:)),
            name: NSTextStorage.didProcessEditingNotification,
            object: textStorage
        )
    }

    /// Đọc file: giữ kiểu xuống dòng; không phải UTF-8 → chỉ đọc.
    static func load(url: URL) throws -> Buffer {
        let decoded = TextFileCodec.decode(try Data(contentsOf: url))
        return Buffer(id: .file(path: url),
                      text: decoded.text,
                      isReadOnly: !decoded.isUTF8,
                      lineEnding: decoded.lineEnding,
                      language: Language.detect(fileName: url.lastPathComponent,
                                                firstLine: Language.firstLine(of: decoded.text)))
    }

    var text: String { textStorage.string }

    var displayName: String {
        switch id {
        case let .file(url): url.lastPathComponent
        case .draft: draftTitle
        }
    }

    /// Nháp đã được lưu thành file thường (SPEC §3.5).
    func becomeFile(_ url: URL) {
        id = .file(path: url)
        lineEnding = .lf
        language = Language.detect(fileName: url.lastPathComponent, firstLine: Language.firstLine(of: text))
    }

    @objc private func storageDidProcessEditing(_ notification: Notification) {
        guard textStorage.editedMask.contains(.editedCharacters) else { return }
        onEdit?()
    }
}

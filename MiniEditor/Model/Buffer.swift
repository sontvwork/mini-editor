import AppKit
import CryptoKit

/// Nội dung một tab. Mỗi buffer có đúng 1 `NSTextStorage` và undo stack riêng.
@MainActor
final class Buffer: NSObject {
    enum SaveState: Equatable {
        case saved
        /// Có thay đổi đang chờ hết thời gian debounce.
        case pending
        case failed(String)
    }

    /// File trên đĩa đã đổi mà app chưa nạp (SPEC §3.6). Trong lúc này tự lưu bị dừng.
    enum ExternalChange: Equatable {
        /// Bị sửa bên ngoài trong khi buffer có thay đổi chưa lưu.
        case modified
        /// Bị xoá hoặc đổi tên.
        case deleted
    }

    /// Đổi từ `.draft` sang `.file` khi nháp được Save As.
    private(set) var id: BufferID
    let textStorage: NSTextStorage
    let undoManager = UndoManager()
    /// File không đọc được bằng UTF-8 → chỉ đọc, không bao giờ tự lưu.
    private(set) var isReadOnly: Bool
    private(set) var lineEnding: LineEnding
    var language: Language
    /// Tên nháp (file thì lấy tên file).
    var draftTitle: String

    /// Có thay đổi chưa ghi xuống đĩa.
    var isDirty = false
    var saveState: SaveState = .saved
    /// Hash nội dung trên đĩa mà app biết lần cuối (lúc mở hoặc lần ghi gần nhất); `nil` = file không tồn tại.
    /// Dùng để nhận ra thay đổi do chính app ghi và phát hiện thay đổi từ bên ngoài.
    var diskDigest: SHA256.Digest?
    var externalChange: ExternalChange?
    /// Đang thay nội dung bằng bản trên đĩa → không coi là người dùng sửa.
    private var isReloading = false

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
        let data = try Data(contentsOf: url)
        let decoded = TextFileCodec.decode(data)
        let buffer = Buffer(id: .file(path: url),
                            text: decoded.text,
                            isReadOnly: !decoded.isUTF8,
                            lineEnding: decoded.lineEnding,
                            language: Language.detect(fileName: url.lastPathComponent,
                                                      firstLine: Language.firstLine(of: decoded.text)))
        buffer.diskDigest = SHA256.hash(data: data)
        return buffer
    }

    /// Thay nội dung bằng bản trên đĩa. Chỉ thay đoạn khác nhau để con trỏ và vùng tô màu
    /// giữ được ở mức gần nhất; xoá undo stack vì các bước cũ không còn khớp nội dung.
    func reload(_ decoded: TextFileCodec.Decoded) {
        let old = textStorage.string as NSString
        let new = decoded.text as NSString
        let change = TextDiff.change(from: old, to: new)
        // Chụp trước: text view đang hiện buffer sẽ ghi đè `selection` trong lúc thay nội dung.
        let previousSelection = selection
        if change.oldRange.length > 0 || change.newRange.length > 0 {
            isReloading = true
            textStorage.replaceCharacters(in: change.oldRange, with: new.substring(with: change.newRange))
            isReloading = false
        }
        selection = TextDiff.adjust(previousSelection, for: change)
        undoManager.removeAllActions()
        lineEnding = decoded.lineEnding
        isReadOnly = !decoded.isUTF8
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
        guard !isReloading, textStorage.editedMask.contains(.editedCharacters) else { return }
        onEdit?()
    }
}

/// Tìm đoạn khác nhau giữa hai văn bản (bỏ phần đầu và phần cuối chung), đơn vị UTF-16.
enum TextDiff {
    struct Change: Equatable {
        /// Đoạn bị thay trong văn bản cũ.
        let oldRange: NSRange
        /// Đoạn thay vào trong văn bản mới.
        let newRange: NSRange
    }

    static func change(from old: NSString, to new: NSString) -> Change {
        let oldLength = old.length
        let newLength = new.length
        var prefix = 0
        while prefix < oldLength, prefix < newLength, old.character(at: prefix) == new.character(at: prefix) {
            prefix += 1
        }
        var suffix = 0
        while suffix < oldLength - prefix, suffix < newLength - prefix,
              old.character(at: oldLength - 1 - suffix) == new.character(at: newLength - 1 - suffix) {
            suffix += 1
        }
        // Không cắt giữa cặp surrogate.
        if prefix > 0, prefix < newLength, UTF16.isTrailSurrogate(new.character(at: prefix)) { prefix -= 1 }
        if suffix > 0, newLength - suffix > prefix, UTF16.isTrailSurrogate(new.character(at: newLength - suffix)) {
            suffix -= 1
        }
        return Change(oldRange: NSRange(location: prefix, length: oldLength - prefix - suffix),
                      newRange: NSRange(location: prefix, length: newLength - prefix - suffix))
    }

    /// Dời vùng chọn theo thay đổi: trước đoạn sửa giữ nguyên, sau đoạn sửa dời theo độ dài,
    /// nằm trong đoạn sửa thì kẹp vào đoạn mới.
    static func adjust(_ selection: NSRange, for change: Change) -> NSRange {
        func map(_ position: Int) -> Int {
            if position <= change.oldRange.location { return position }
            if position >= NSMaxRange(change.oldRange) {
                return position - change.oldRange.length + change.newRange.length
            }
            return min(position, NSMaxRange(change.newRange))
        }
        let start = map(selection.location)
        let end = max(map(NSMaxRange(selection)), start)
        return NSRange(location: start, length: end - start)
    }
}

import CryptoKit
import Foundation

/// Tự động lưu (SPEC §3.4): file 500ms, nháp 300ms sau lần gõ cuối; lưu ngay khi được yêu cầu.
/// Lỗi ghi → giữ nội dung trong RAM, trạng thái `.failed`, thử lại ở lần lưu kế tiếp.
/// Đồng bộ với đĩa (SPEC §3.6): file đổi từ bên ngoài → tự nạp lại, hoặc dừng tự lưu nếu đang có thay đổi chưa lưu.
@MainActor
final class AutosaveService {
    static let fileDelay: Duration = .milliseconds(500)
    static let draftDelay: Duration = .milliseconds(300)
    static let pausedMessage = "Tạm dừng tự lưu vì file trên đĩa đã đổi"

    private let draftStore: DraftStore
    private var pending: [ObjectIdentifier: Task<Void, Never>] = [:]

    /// Ghi dữ liệu xuống đĩa; tách ra để test lỗi ghi.
    var writeData: (Data, URL) throws -> Void = { try AtomicFileWriter.write($0, to: $1) }
    /// Gọi khi `saveState` hoặc `externalChange` của một buffer đổi.
    var onStatusChange: ((Buffer) -> Void)?
    /// Gọi sau khi nội dung buffer được thay bằng bản trên đĩa.
    var onReload: ((Buffer) -> Void)?

    init(draftStore: DraftStore) {
        self.draftStore = draftStore
    }

    /// Nội dung vừa đổi → lên lịch lưu sau thời gian chờ.
    func bufferDidChange(_ buffer: Buffer) {
        guard !buffer.isReadOnly else { return }
        buffer.isDirty = true
        if buffer.externalChange != nil {
            setState(.failed(Self.pausedMessage), of: buffer)
            return
        }
        setState(.pending, of: buffer)
        let key = ObjectIdentifier(buffer)
        pending[key]?.cancel()
        let delay = buffer.id.isDraft ? Self.draftDelay : Self.fileDelay
        pending[key] = Task { [weak self, weak buffer] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, let buffer else { return }
            self.save(buffer)
        }
    }

    /// Lưu ngay nếu có thay đổi chưa ghi (hoặc lần trước lỗi).
    /// Không ghi khi file trên đĩa đã đổi so với bản app biết (tránh đè bản sửa bên ngoài).
    func save(_ buffer: Buffer) {
        cancel(buffer)
        guard buffer.isDirty, !buffer.isReadOnly, buffer.externalChange == nil else { return }
        do {
            switch buffer.id {
            case let .file(url):
                guard checkDisk(buffer) else { return }
                let data = TextFileCodec.encode(buffer.text, lineEnding: buffer.lineEnding)
                try writeData(data, url)
                buffer.setDiskState(data, stamp: DiskStamp.of(url))
            case let .draft(id):
                try FileManager.default.createDirectory(at: draftStore.directory, withIntermediateDirectories: true)
                try writeData(Data(buffer.text.utf8), draftStore.url(for: id))
            }
            buffer.isDirty = false
            setState(.saved, of: buffer)
        } catch {
            setState(.failed(error.localizedDescription), of: buffer)
        }
    }

    func saveAll(_ buffers: some Sequence<Buffer>) {
        for buffer in buffers where buffer.isDirty {
            save(buffer)
        }
    }

    /// Bỏ lịch lưu đang chờ (buffer đã được lưu theo cách khác, vd. Save As).
    func cancel(_ buffer: Buffer) {
        pending.removeValue(forKey: ObjectIdentifier(buffer))?.cancel()
    }

    // MARK: - Thay đổi từ bên ngoài

    /// So file trên đĩa với bản app biết lần cuối (`diskDigest`). Trùng → không làm gì (gồm cả lần ghi của chính app).
    /// Khác: buffer sạch → nạp lại; có thay đổi chưa lưu hoặc file mất → dừng tự lưu, đặt `externalChange`.
    /// Trả về `true` nếu đĩa khớp, được phép ghi.
    @discardableResult
    func checkDisk(_ buffer: Buffer) -> Bool {
        guard case let .file(url) = buffer.id else { return true }
        let stamp = DiskStamp.of(url)
        // Đường nhanh: dấu vết file y như lần app biết → khỏi đọc cả file (gồm lần ghi của chính app).
        if buffer.externalChange == nil, let stamp, stamp == buffer.diskStamp { return true }
        let data = try? Data(contentsOf: url)
        // Có file nhưng không đọc được (mất quyền…): để lần ghi báo lỗi.
        if data == nil, FileManager.default.fileExists(atPath: url.path) { return true }
        if data.map({ SHA256.hash(data: $0) }) == buffer.diskDigest {
            buffer.setDiskState(data, stamp: stamp)
            if buffer.externalChange != nil {
                // Đĩa quay về đúng bản app biết (vd. bị xoá rồi tạo lại y hệt).
                buffer.externalChange = nil
                onStatusChange?(buffer)
                if buffer.isDirty { save(buffer) }
            }
            return true
        }
        cancel(buffer)
        if let data, !buffer.isDirty {
            apply(data, stamp: stamp, to: buffer)
        } else {
            buffer.externalChange = data == nil ? .deleted : .modified
            if buffer.isDirty { setState(.failed(Self.pausedMessage), of: buffer) }
            onStatusChange?(buffer)
        }
        return false
    }

    /// [Giữ bản của tôi] / [Lưu lại]: lấy trạng thái đĩa hiện tại làm mốc rồi ghi đè bằng nội dung trong app.
    func keepMine(_ buffer: Buffer) {
        guard case let .file(url) = buffer.id else { return }
        let stamp = DiskStamp.of(url)
        buffer.setDiskState(try? Data(contentsOf: url), stamp: stamp)
        buffer.externalChange = nil
        buffer.isDirty = true
        save(buffer)
        onStatusChange?(buffer)
    }

    /// [Nạp bản trên đĩa]: bỏ thay đổi trong app. File không còn → chuyển sang trạng thái bị xoá.
    func reloadFromDisk(_ buffer: Buffer) {
        guard case let .file(url) = buffer.id else { return }
        let stamp = DiskStamp.of(url)
        guard let data = try? Data(contentsOf: url) else {
            buffer.externalChange = .deleted
            onStatusChange?(buffer)
            return
        }
        apply(data, stamp: stamp, to: buffer)
    }

    // MARK: - Private

    private func apply(_ data: Data, stamp: DiskStamp?, to buffer: Buffer) {
        cancel(buffer)
        buffer.reload(TextFileCodec.decode(data))
        buffer.setDiskState(data, stamp: stamp)
        buffer.externalChange = nil
        buffer.isDirty = false
        buffer.saveState = .saved
        onReload?(buffer)
        onStatusChange?(buffer)
    }

    private func setState(_ state: Buffer.SaveState, of buffer: Buffer) {
        guard buffer.saveState != state else { return }
        buffer.saveState = state
        onStatusChange?(buffer)
    }
}

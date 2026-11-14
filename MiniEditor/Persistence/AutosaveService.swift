import Foundation

/// Tự động lưu (SPEC §3.4): file 500ms, nháp 300ms sau lần gõ cuối; lưu ngay khi được yêu cầu.
/// Lỗi ghi → giữ nội dung trong RAM, trạng thái `.failed`, thử lại ở lần lưu kế tiếp.
@MainActor
final class AutosaveService {
    static let fileDelay: Duration = .milliseconds(500)
    static let draftDelay: Duration = .milliseconds(300)

    private let draftStore: DraftStore
    private var pending: [ObjectIdentifier: Task<Void, Never>] = [:]

    /// Ghi dữ liệu xuống đĩa; tách ra để test lỗi ghi.
    var writeData: (Data, URL) throws -> Void = { try AtomicFileWriter.write($0, to: $1) }
    /// Gọi khi `saveState` của một buffer đổi.
    var onStatusChange: ((Buffer) -> Void)?

    init(draftStore: DraftStore) {
        self.draftStore = draftStore
    }

    /// Nội dung vừa đổi → lên lịch lưu sau thời gian chờ.
    func bufferDidChange(_ buffer: Buffer) {
        guard !buffer.isReadOnly else { return }
        buffer.isDirty = true
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
    func save(_ buffer: Buffer) {
        let key = ObjectIdentifier(buffer)
        pending[key]?.cancel()
        pending[key] = nil
        guard buffer.isDirty, !buffer.isReadOnly else { return }
        do {
            switch buffer.id {
            case let .file(url):
                try writeData(TextFileCodec.encode(buffer.text, lineEnding: buffer.lineEnding), url)
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

    private func setState(_ state: Buffer.SaveState, of buffer: Buffer) {
        guard buffer.saveState != state else { return }
        buffer.saveState = state
        onStatusChange?(buffer)
    }
}

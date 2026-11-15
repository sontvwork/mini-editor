import CoreServices
import Foundation

/// Các thư mục có thay đổi, gom lại sau debounce.
struct DirectoryChanges: Equatable {
    /// Đường dẫn thật (đã resolve symlink, không có `/` cuối) của các thư mục có con bị thêm/xoá/đổi tên
    /// (chế độ `fileEvents`: của từng file bị đổi).
    var paths: Set<String> = []
    /// Thư mục mà FSEvents yêu cầu quét lại toàn bộ cây con.
    var recursivePaths: Set<String> = []

    var isEmpty: Bool { paths.isEmpty && recursivePaths.isEmpty }
}

/// Theo dõi thư mục bằng FSEvents, gom sự kiện sau debounce. Không có timer chạy liên tục.
/// - Mặc định: báo thư mục có con bị thêm/xoá/đổi tên (cây workspace, debounce 200ms, SPEC §3.1).
/// - `fileEvents: true`: báo đường dẫn từng file bị đổi (file đang mở, SPEC §3.6).
@MainActor
final class DirectoryWatcher {
    private let debounce: Duration
    private let fileEvents: Bool
    private let onChange: (DirectoryChanges) -> Void
    private var stream: FSEventStreamRef?
    private var pending = DirectoryChanges()
    private var debounceTask: Task<Void, Never>?

    init(debounce: Duration = .milliseconds(200), fileEvents: Bool = false,
         onChange: @escaping (DirectoryChanges) -> Void) {
        self.debounce = debounce
        self.fileEvents = fileEvents
        self.onChange = onChange
    }

    isolated deinit {
        stop()
    }

    /// Thay toàn bộ danh sách thư mục cần theo dõi.
    func watch(paths: [String]) {
        stop()
        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
            guard let info else { return }
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            let flags = Array(UnsafeBufferPointer(start: eventFlags, count: count))
            // Stream chạy trên main queue (FSEventStreamSetDispatchQueue bên dưới).
            MainActor.assumeIsolated {
                let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.receive(paths: paths, flags: flags)
            }
        }
        var flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot)
        if fileEvents {
            flags |= FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.05,
            flags
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        pending = DirectoryChanges()
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Đường dẫn thật của một thư mục (FSEvents luôn báo đường dẫn thật, vd. `/private/var/...`).
    nonisolated static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private func receive(paths: [String], flags: [FSEventStreamEventFlags]) {
        let rescanMask = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged
        )
        for (path, flag) in zip(paths, flags) {
            var normalized = path
            while normalized.count > 1, normalized.hasSuffix("/") {
                normalized.removeLast()
            }
            if flag & rescanMask != 0 {
                pending.recursivePaths.insert(normalized)
            } else {
                pending.paths.insert(normalized)
            }
        }
        debounceTask?.cancel()
        debounceTask = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    private func flush() {
        let changes = pending
        pending = DirectoryChanges()
        debounceTask = nil
        if !changes.isEmpty {
            onChange(changes)
        }
    }
}

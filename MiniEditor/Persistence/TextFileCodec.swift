import Foundation

/// Kiểu xuống dòng phát hiện lúc mở file, giữ nguyên khi ghi (SPEC §3.4).
enum LineEnding: String, Codable, Sendable {
    case lf
    case crlf
}

/// Đọc/ghi nội dung file text. Trong buffer luôn dùng `\n`; đổi lại kiểu gốc khi ghi.
enum TextFileCodec {
    struct Decoded: Equatable {
        let text: String
        let lineEnding: LineEnding
        /// `false` khi dữ liệu không phải UTF-8 hợp lệ (mở chỉ đọc).
        let isUTF8: Bool
    }

    static func decode(_ data: Data) -> Decoded {
        let lineEnding = detectLineEnding(data)
        guard var text = String(data: data, encoding: .utf8) else {
            return Decoded(text: String(decoding: data, as: UTF8.self), lineEnding: lineEnding, isUTF8: false)
        }
        if lineEnding == .crlf {
            text = text.replacingOccurrences(of: "\r\n", with: "\n")
        }
        return Decoded(text: text, lineEnding: lineEnding, isUTF8: true)
    }

    static func encode(_ text: String, lineEnding: LineEnding) -> Data {
        switch lineEnding {
        case .lf:
            return Data(text.utf8)
        case .crlf:
            // Chuẩn hoá trước để văn bản dán vào có sẵn \r\n không thành \r\r\n.
            let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            return Data(normalized.replacingOccurrences(of: "\n", with: "\r\n").utf8)
        }
    }

    /// CRLF nếu số dòng kết thúc bằng `\r\n` nhiều hơn hoặc bằng số dòng chỉ có `\n`.
    static func detectLineEnding(_ data: Data) -> LineEnding {
        var crlf = 0
        var lf = 0
        var previous: UInt8 = 0
        for byte in data {
            if byte == 0x0A {
                if previous == 0x0D { crlf += 1 } else { lf += 1 }
            }
            previous = byte
        }
        return crlf > 0 && crlf >= lf ? .crlf : .lf
    }
}

/// Dấu vết rẻ của một file trên đĩa (kích thước, thời gian sửa tới nano giây, inode).
/// Trùng dấu vết → coi như nội dung không đổi, khỏi đọc lại cả file để so hash.
struct DiskStamp: Equatable, Sendable {
    let size: Int64
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
    let inode: UInt64

    /// `nil` nếu file không tồn tại/không stat được. Đi theo symlink.
    nonisolated static func of(_ url: URL) -> DiskStamp? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        return DiskStamp(size: Int64(info.st_size),
                         modifiedSeconds: info.st_mtimespec.tv_sec,
                         modifiedNanoseconds: info.st_mtimespec.tv_nsec,
                         inode: UInt64(info.st_ino))
    }
}

/// Ghi file atomic (file tạm cùng thư mục rồi `rename`) và giữ quyền POSIX (vd. +x).
enum AtomicFileWriter {
    nonisolated static func write(_ data: Data, to url: URL) throws {
        let fileManager = FileManager.default
        // Đi theo symlink để ghi vào file thật, không thay symlink bằng file thường.
        let target = URL(fileURLWithPath: DirectoryWatcher.realPath(url.path))
        let permissions = (try? fileManager.attributesOfItem(atPath: target.path))?[.posixPermissions]
        let temp = target.deletingLastPathComponent()
            .appendingPathComponent(".\(target.lastPathComponent).minieditor-\(UUID().uuidString).tmp")
        try data.write(to: temp, options: .withoutOverwriting)
        do {
            if let permissions {
                try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: temp.path)
            }
            guard rename(temp.path, target.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? fileManager.removeItem(at: temp)
            throw error
        }
    }
}

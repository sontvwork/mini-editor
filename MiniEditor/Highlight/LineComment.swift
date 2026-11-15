import Foundation

/// Bật/tắt comment dòng cho ⌘/ (SPEC §3.10).
enum LineComment {
    /// `block` là các dòng trọn vẹn (có thể có `\n` cuối). Mọi dòng có chữ đều đã comment → bỏ comment;
    /// ngược lại → thêm `prefix` ở mức thụt nhỏ nhất. Dòng trống giữ nguyên.
    static func toggle(_ block: String, prefix: String) -> String {
        let marker = prefix.trimmingCharacters(in: .whitespaces)
        var lines = block.components(separatedBy: "\n")
        let contentIndices = lines.indices.filter { !lines[$0].allSatisfy(\.isWhitespace) }
        guard !contentIndices.isEmpty else { return block }

        let allCommented = contentIndices.allSatisfy { lines[$0].drop(while: isIndent).hasPrefix(marker) }
        if allCommented {
            for i in contentIndices {
                let line = lines[i]
                let indent = line.prefix(while: isIndent)
                var rest = line.dropFirst(indent.count).dropFirst(marker.count)
                if rest.first == " " { rest = rest.dropFirst() }
                lines[i] = String(indent) + rest
            }
        } else {
            let column = contentIndices.map { lines[$0].prefix(while: isIndent).count }.min() ?? 0
            for i in contentIndices {
                let line = lines[i]
                lines[i] = String(line.prefix(column)) + prefix + String(line.dropFirst(column))
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Chênh lệch độ dài (UTF-16) của dòng đầu sau khi bật/tắt comment.
    static func firstLineDelta(old: String, new: String) -> Int {
        func firstLine(_ s: String) -> Int { (s.prefix { $0 != "\n" } as Substring).utf16.count }
        return firstLine(new) - firstLine(old)
    }

    private static func isIndent(_ c: Character) -> Bool { c == " " || c == "\t" }
}

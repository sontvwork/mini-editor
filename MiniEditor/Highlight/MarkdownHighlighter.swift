import Foundation

/// Tô màu Markdown (SPEC §3.8): heading, đậm, nghiêng, inline code, khối code, dấu list, blockquote, link.
/// Khối code phụ thuộc cả văn bản → giữ vị trí các dòng ``` và chỉ tô lại xa hơn khi chúng đổi.
final class MarkdownHighlighter: Highlighter {
    /// Vị trí đầu các dòng mở/đóng khối code, theo thứ tự.
    private(set) var fenceLineStarts: [Int] = []

    private struct Rule {
        let regex: NSRegularExpression
        /// Kiểu cho từng nhóm bắt (0 = cả match).
        let groups: [(Int, TokenKind)]
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Pattern viết cố định trong code, sai là lỗi lập trình.
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }

    private static let blockRules: [Rule] = [
        Rule(regex: regex(#"^#{1,6} .*$"#), groups: [(0, .heading)]),
        Rule(regex: regex(#"^ {0,3}>.*$"#), groups: [(0, .quote)]),
        Rule(regex: regex(#"^[ \t]*(?:[-*+]|\d+\.)(?=[ \t])"#), groups: [(0, .keyword)]),
    ]
    private static let inlineCode = regex(#"`[^`\n]+`"#)
    private static let inlineRules: [Rule] = [
        Rule(regex: regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#), groups: [(0, .bold)]),
        Rule(regex: regex(#"(?<![*\w])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![*\w])"#), groups: [(0, .italic)]),
        Rule(regex: regex(#"(?<![_\w])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![_\w])"#), groups: [(0, .italic)]),
        Rule(regex: regex(#"\[([^\]\n]+)\]\(([^)\s]+)\)"#), groups: [(1, .linkText), (2, .linkURL)]),
    ]

    func reset(_ text: NSString) {
        fenceLineStarts = Self.fenceLineStarts(in: text)
    }

    /// Quét lại vị trí ``` (nhanh, theo dòng). Không đổi → chỉ tô lại các dòng bị sửa;
    /// đổi → tô lại từ chỗ đổi đầu tiên tới cuối văn bản (khối code phía sau có thể bị đảo trạng thái).
    /// ponytail: tô tới cuối văn bản; cần thì dừng ở chỗ trạng thái khối code khớp lại.
    func rangeToRehighlight(editedRange: NSRange, changeInLength delta: Int, in text: NSString) -> NSRange {
        let lines = text.lineRange(for: editedRange)
        let oldEnd = NSMaxRange(editedRange) - delta
        // Vị trí cũ dời theo lần sửa; dòng ``` nằm trong đoạn bị sửa thì coi như mất.
        let shifted = fenceLineStarts.compactMap { start -> Int? in
            if start < editedRange.location { return start }
            if start >= oldEnd { return start + delta }
            return nil
        }
        fenceLineStarts = Self.fenceLineStarts(in: text)
        guard shifted != fenceLineStarts else { return lines }
        var i = 0
        while i < shifted.count, i < fenceLineStarts.count, shifted[i] == fenceLineStarts[i] { i += 1 }
        let firstDifference = [shifted, fenceLineStarts].compactMap { i < $0.count ? $0[i] : nil }.min() ?? 0
        let start = min(lines.location, text.lineRange(for: NSRange(location: min(firstDifference, text.length), length: 0)).location)
        return NSRange(location: start, length: text.length - start)
    }

    func tokens(in range: NSRange, of text: NSString) -> [Token] {
        let blocks = codeBlocks(in: text).filter { NSIntersectionRange($0, range).length > 0 }
        var tokens = blocks.map { Token(range: NSIntersectionRange($0, range), kind: .string) }
        func outsideBlocks(_ r: NSRange) -> Bool {
            !blocks.contains { NSIntersectionRange($0, r).length > 0 }
        }

        for rule in Self.blockRules {
            collect(rule, in: range, of: text, into: &tokens, where: outsideBlocks)
        }
        var codeSpans: [NSRange] = []
        Self.inlineCode.enumerateMatches(in: text as String, range: range) { match, _, _ in
            if let r = match?.range, outsideBlocks(r) { codeSpans.append(r) }
        }
        for rule in Self.inlineRules {
            collect(rule, in: range, of: text, into: &tokens) { r in
                outsideBlocks(r) && !codeSpans.contains { NSIntersectionRange($0, r).length > 0 }
            }
        }
        tokens += codeSpans.map { Token(range: $0, kind: .string) }
        return tokens
    }

    /// Khối code: từ dòng ``` mở tới hết dòng ``` đóng; thiếu dòng đóng thì tới cuối văn bản.
    func codeBlocks(in text: NSString) -> [NSRange] {
        stride(from: 0, to: fenceLineStarts.count, by: 2).map { index in
            let open = fenceLineStarts[index]
            let end = index + 1 < fenceLineStarts.count
                ? NSMaxRange(text.lineRange(for: NSRange(location: fenceLineStarts[index + 1], length: 0)))
                : text.length
            return NSRange(location: open, length: end - open)
        }
    }

    /// Đầu các dòng bắt đầu bằng ``` (cho phép thụt tối đa 3 khoảng trắng).
    static func fenceLineStarts(in text: NSString) -> [Int] {
        var result: [Int] = []
        var location = 0
        while location < text.length {
            let found = text.range(of: "```", options: .literal,
                                   range: NSRange(location: location, length: text.length - location))
            guard found.location != NSNotFound else { break }
            let line = text.lineRange(for: found)
            let indent = found.location - line.location
            if indent <= 3, text.substring(with: NSRange(location: line.location, length: indent)).allSatisfy({ $0 == " " }) {
                result.append(line.location)
            }
            location = NSMaxRange(line)
        }
        return result
    }

    private func collect(_ rule: Rule, in range: NSRange, of text: NSString, into tokens: inout [Token],
                         where accept: (NSRange) -> Bool) {
        rule.regex.enumerateMatches(in: text as String, range: range) { match, _, _ in
            guard let match, accept(match.range) else { return }
            for (group, kind) in rule.groups {
                let r = match.range(at: group)
                if r.location != NSNotFound, r.length > 0 { tokens.append(Token(range: r, kind: kind)) }
            }
        }
    }
}

import Foundation

/// Tô màu Bash bằng một lượt quét ký tự (SPEC §3.8): comment, chuỗi `"…"`/`'…'`, biến (kể cả trong chuỗi
/// nháy kép), từ khoá và builtin.
/// ponytail: chuỗi và heredoc không trải qua nhiều dòng (tô theo dòng); cần thì lưu trạng thái đầu dòng như Markdown.
final class BashHighlighter: Highlighter {
    static let keywords: Set<String> = [
        "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done",
        "case", "esac", "function", "in", "select", "return",
    ]
    static let builtins: Set<String> = [
        "export", "local", "readonly", "source", "alias", "unalias", "echo", "printf",
        "cd", "exit", "set", "unset", "shift", "trap", "eval", "exec",
    ]

    func tokens(in range: NSRange, of text: NSString) -> [Token] {
        var chars = [unichar](repeating: 0, count: range.length)
        text.getCharacters(&chars, range: range)
        var scanner = Scanner(chars: chars, base: range.location)
        scanner.run()
        return scanner.tokens
    }

    private struct Scanner {
        let chars: [unichar]
        let base: Int
        var tokens: [Token] = []

        init(chars: [unichar], base: Int) {
            self.chars = chars
            self.base = base
        }

        mutating func run() {
            var i = 0
            while i < chars.count {
                let c = chars[i]
                switch c {
                case .hash where i == 0 || Self.isSpace(chars[i - 1]):
                    let end = lineEnd(from: i)
                    emit(i, end, .comment)
                    i = end
                case .singleQuote:
                    let end = closingQuote(.singleQuote, from: i + 1, escapes: false)
                    emit(i, end, .string)
                    i = end
                case .doubleQuote:
                    let end = closingQuote(.doubleQuote, from: i + 1, escapes: true)
                    emit(i, end, .string)
                    variables(from: i + 1, to: end)
                    i = end
                case .backslash:
                    i += 2
                case .dollar:
                    if let end = variableEnd(at: i) {
                        emit(i, end, .variable)
                        i = end
                    } else {
                        i += 1
                    }
                case _ where Self.isWordStart(c):
                    var end = i + 1
                    while end < chars.count, Self.isWordPart(chars[end]) { end += 1 }
                    let word = String(utf16CodeUnits: Array(chars[i..<end]), count: end - i)
                    if BashHighlighter.keywords.contains(word) || BashHighlighter.builtins.contains(word) {
                        emit(i, end, .keyword)
                    }
                    i = end
                default:
                    i += 1
                }
            }
        }

        private mutating func emit(_ start: Int, _ end: Int, _ kind: TokenKind) {
            guard end > start else { return }
            tokens.append(Token(range: NSRange(location: base + start, length: end - start), kind: kind))
        }

        /// Biến trong chuỗi nháy kép.
        private mutating func variables(from start: Int, to end: Int) {
            var i = start
            while i < end {
                if chars[i] == .backslash {
                    i += 2
                } else if chars[i] == .dollar, let varEnd = variableEnd(at: i) {
                    let clamped = min(varEnd, end)
                    emit(i, clamped, .variable)
                    i = clamped
                } else {
                    i += 1
                }
            }
        }

        /// `$VAR`, `${…}`, `$1`, `$@`, `$?`, `$#`… Trả về vị trí ngay sau biến; `nil` nếu không phải biến (vd. `$(`).
        private func variableEnd(at i: Int) -> Int? {
            guard i + 1 < chars.count else { return nil }
            let next = chars[i + 1]
            if next == .openBrace {
                var end = i + 2
                while end < chars.count, chars[end] != .closeBrace, chars[end] != .newline { end += 1 }
                return end < chars.count && chars[end] == .closeBrace ? end + 1 : end
            }
            if Self.isIdentifierStart(next) {
                var end = i + 2
                while end < chars.count, Self.isIdentifierPart(chars[end]) { end += 1 }
                return end
            }
            if Self.isDigit(next) || Self.specialParameters.contains(next) { return i + 2 }
            return nil
        }

        /// Vị trí ngay sau dấu đóng; không có thì tới cuối dòng.
        private func closingQuote(_ quote: unichar, from start: Int, escapes: Bool) -> Int {
            var i = start
            while i < chars.count, chars[i] != .newline {
                if escapes, chars[i] == .backslash {
                    i += 2
                    continue
                }
                if chars[i] == quote { return i + 1 }
                i += 1
            }
            return min(i, chars.count)
        }

        private func lineEnd(from start: Int) -> Int {
            var i = start
            while i < chars.count, chars[i] != .newline, chars[i] != .carriageReturn { i += 1 }
            return i
        }

        private static let specialParameters: Set<unichar> = Set("@?#*$!-".utf16)

        private static func isSpace(_ c: unichar) -> Bool {
            c == .space || c == .tab || c == .newline || c == .carriageReturn
        }

        private static func isDigit(_ c: unichar) -> Bool { c >= 0x30 && c <= 0x39 }

        private static func isIdentifierStart(_ c: unichar) -> Bool {
            (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F
        }

        private static func isIdentifierPart(_ c: unichar) -> Bool { isIdentifierStart(c) || isDigit(c) }

        private static func isWordStart(_ c: unichar) -> Bool { isIdentifierStart(c) }

        /// Đọc cả `-`, `.`, `/` để `my-echo`, `./if.sh` không bị tô nhầm từ khoá.
        private static func isWordPart(_ c: unichar) -> Bool {
            isIdentifierPart(c) || c == 0x2D || c == 0x2E || c == 0x2F
        }
    }
}

private extension unichar {
    static let tab: unichar = 0x09
    static let newline: unichar = 0x0A
    static let carriageReturn: unichar = 0x0D
    static let space: unichar = 0x20
    static let doubleQuote: unichar = 0x22
    static let hash: unichar = 0x23
    static let dollar: unichar = 0x24
    static let singleQuote: unichar = 0x27
    static let backslash: unichar = 0x5C
    static let openBrace: unichar = 0x7B
    static let closeBrace: unichar = 0x7D
}

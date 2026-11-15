import Foundation

/// Loại token cú pháp. Màu/kiểu chữ của từng loại do UI quyết định (lấy từ `Theme`).
enum TokenKind: Sendable {
    case keyword
    case string
    case comment
    case variable
    case heading
    case bold
    case italic
    case quote
    case linkText
    case linkURL
}

struct Token: Equatable, Sendable {
    let range: NSRange
    let kind: TokenKind
}

/// Tô màu theo vùng (SPEC §3.8). Token chồng nhau thì token sau đè token trước.
/// Là class vì có thể giữ trạng thái giữa các lần sửa (vd. vị trí ``` của Markdown).
/// Không gắn actor: chỉ là tính toán trên chuỗi, được layout manager gọi trên thread của nó (main).
protocol Highlighter: AnyObject {
    /// Nội dung đổi toàn bộ (gắn buffer, đổi ngôn ngữ).
    func reset(_ text: NSString)
    /// Sau một lần sửa (`editedRange` theo văn bản mới): vùng cần tô lại, đã mở rộng trọn dòng.
    func rangeToRehighlight(editedRange: NSRange, changeInLength: Int, in text: NSString) -> NSRange
    /// Token của `range` (trọn dòng).
    func tokens(in range: NSRange, of text: NSString) -> [Token]
}

extension Highlighter {
    func reset(_ text: NSString) {}

    func rangeToRehighlight(editedRange: NSRange, changeInLength: Int, in text: NSString) -> NSRange {
        text.lineRange(for: editedRange)
    }
}

extension Language {
    func makeHighlighter() -> Highlighter? {
        switch self {
        case .plain: nil
        case .bash: BashHighlighter()
        case .markdown: MarkdownHighlighter()
        }
    }

    var displayName: String {
        switch self {
        case .plain: "Plain"
        case .bash: "Bash"
        case .markdown: "Markdown"
        }
    }
}

import AppKit

/// Thanh trạng thái dưới cùng cửa sổ (SPEC §3.9). M1: `Dòng X, Cột Y` · `Cỡ chữ N`.
@MainActor
final class StatusBarView: NSView {
    static let height: CGFloat = 24

    private let cursorLabel = StatusBarView.makeLabel()
    private let fontSizeLabel = StatusBarView.makeLabel()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.chromeBackground.cgColor

        let topBorder = NSBox()
        topBorder.boxType = .custom
        topBorder.borderWidth = 0
        topBorder.fillColor = Theme.border
        topBorder.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [cursorLabel, fontSizeLabel])
        stack.orientation = .horizontal
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(topBorder)
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            topBorder.topAnchor.constraint(equalTo: topAnchor),
            topBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 1),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) không dùng")
    }

    func setCursor(line: Int, column: Int) {
        cursorLabel.stringValue = "Dòng \(line), Cột \(column)"
    }

    func setFontSize(_ size: CGFloat) {
        fontSizeLabel.stringValue = "Cỡ chữ \(Int(size))"
    }

    private static func makeLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = Theme.textMuted
        return label
    }
}

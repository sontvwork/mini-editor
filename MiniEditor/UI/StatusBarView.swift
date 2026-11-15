import AppKit

/// Thanh trạng thái dưới cùng cửa sổ (SPEC §3.9):
/// ngôn ngữ (click để đổi) · `UTF-8` · `Dòng X, Cột Y` · `Cỡ chữ N` · trạng thái lưu.
@MainActor
final class StatusBarView: NSView {
    static let height: CGFloat = 24

    private let languageButton = NSButton(title: "", target: nil, action: nil)
    private var language: Language?
    private let encodingLabel = StatusBarView.makeLabel()
    private let cursorLabel = StatusBarView.makeLabel()
    private let fontSizeLabel = StatusBarView.makeLabel()
    private let saveLabel = StatusBarView.makeLabel()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.chromeBackground.cgColor

        let topBorder = NSBox()
        topBorder.boxType = .custom
        topBorder.borderWidth = 0
        topBorder.fillColor = Theme.border
        topBorder.translatesAutoresizingMaskIntoConstraints = false

        encodingLabel.stringValue = "UTF-8"
        languageButton.isBordered = false
        languageButton.target = self
        languageButton.action = #selector(showLanguageMenu)
        languageButton.isHidden = true
        let stack = NSStackView(views: [languageButton, encodingLabel, cursorLabel, fontSizeLabel, saveLabel])
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

    /// Chọn ngôn ngữ trong menu.
    var onSelectLanguage: ((Language) -> Void)?

    /// `nil` = không có buffer nào đang active.
    func setLanguage(_ language: Language?) {
        self.language = language
        languageButton.isHidden = language == nil
        languageButton.attributedTitle = NSAttributedString(
            string: language?.displayName ?? "",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: Theme.textMuted]
        )
    }

    func setCursor(line: Int, column: Int) {
        cursorLabel.stringValue = "Dòng \(line), Cột \(column)"
    }

    func setFontSize(_ size: CGFloat) {
        fontSizeLabel.stringValue = "Cỡ chữ \(Int(size))"
    }

    /// `nil` = không có buffer nào đang active.
    func setSaveState(_ state: Buffer.SaveState?, isReadOnly: Bool = false) {
        switch state {
        case nil: saveLabel.stringValue = ""
        case _ where isReadOnly: saveLabel.stringValue = "Chỉ đọc"
        case .saved: saveLabel.stringValue = "● Đã lưu tự động"
        case .pending: saveLabel.stringValue = "Đang lưu…"
        case .failed: saveLabel.stringValue = "⚠ Lỗi lưu"
        }
    }

    @objc private func showLanguageMenu() {
        let menu = NSMenu()
        for option in Language.allCases {
            let item = NSMenuItem(title: option.displayName, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = option == language ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: languageButton.bounds.maxY + 4), in: languageButton)
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let selected = Language(rawValue: raw) else { return }
        onSelectLanguage?(selected)
    }

    private static func makeLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = Theme.textMuted
        return label
    }
}

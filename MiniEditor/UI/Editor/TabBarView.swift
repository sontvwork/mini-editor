import AppKit

/// Thanh tab của một cột (SPEC §3.3).
@MainActor
final class TabBarView: NSView {
    static let height: CGFloat = 32

    struct Item: Equatable {
        let id: BufferID
        let title: String
        let isDraft: Bool
    }

    var onSelect: ((BufferID) -> Void)?
    var onClose: ((BufferID) -> Void)?
    /// Click vào vùng trống của thanh tab.
    var onClickEmpty: (() -> Void)?

    private let scrollView = NSScrollView()
    private let stack = NSStackView()
    private var tabViews: [TabItemView] = []
    private var state: (items: [Item], activeIndex: Int?, isFocused: Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.chromeBackground.cgColor

        stack.orientation = .horizontal
        stack.spacing = 0
        stack.alignment = .height
        stack.translatesAutoresizingMaskIntoConstraints = false

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)

        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = document
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        let bottomBorder = NSBox()
        bottomBorder.boxType = .custom
        bottomBorder.borderWidth = 0
        bottomBorder.fillColor = Theme.borderSubtle
        bottomBorder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bottomBorder)

        let clip = scrollView.contentView
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBorder.topAnchor),
            bottomBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBorder.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomBorder.heightAnchor.constraint(equalToConstant: 1),
            document.topAnchor.constraint(equalTo: clip.topAnchor),
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            document.heightAnchor.constraint(equalTo: clip.heightAnchor),
            document.widthAnchor.constraint(greaterThanOrEqualTo: clip.widthAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) không dùng")
    }

    func update(items: [Item], activeIndex: Int?, isFocused: Bool) {
        if let state, state.items == items, state.activeIndex == activeIndex, state.isFocused == isFocused {
            return
        }
        state = (items, activeIndex, isFocused)

        tabViews.forEach { $0.removeFromSuperview() }
        tabViews = items.enumerated().map { index, item in
            let view = TabItemView(item: item, isActive: index == activeIndex, showsAccent: isFocused && index == activeIndex)
            view.onSelect = { [weak self] in self?.onSelect?(item.id) }
            view.onClose = { [weak self] in self?.onClose?(item.id) }
            stack.addArrangedSubview(view)
            return view
        }
        if let activeIndex, tabViews.indices.contains(activeIndex) {
            let active = tabViews[activeIndex]
            layoutSubtreeIfNeeded()
            active.scrollToVisible(active.bounds)
        }
    }

    override func mouseDown(with event: NSEvent) {
        onClickEmpty?()
    }
}

/// Một tab: tên + nút ×.
@MainActor
private final class TabItemView: NSView {
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?

    init(item: TabBarView.Item, isActive: Bool, showsAccent: Bool) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = (isActive ? Theme.editorBackground : Theme.chromeBackground).cgColor

        let label = NSTextField(labelWithString: item.title)
        let baseFont = NSFont.systemFont(ofSize: 12)
        label.font = item.isDraft ? NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask) : baseFont
        label.textColor = isActive ? Theme.text : Theme.textMuted
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false

        let close = NSButton(title: "", target: nil, action: nil)
        close.isBordered = false
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Đóng tab")
        close.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .medium)
        close.contentTintColor = isActive ? Theme.text : Theme.textMuted
        close.imagePosition = .imageOnly
        close.target = self
        close.action = #selector(closeClicked)
        close.translatesAutoresizingMaskIntoConstraints = false

        let rightBorder = NSBox()
        rightBorder.boxType = .custom
        rightBorder.borderWidth = 0
        rightBorder.fillColor = Theme.borderSubtle
        rightBorder.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        addSubview(close)
        addSubview(rightBorder)
        var constraints = [
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 180),
            close.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 6),
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            close.centerYAnchor.constraint(equalTo: centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 16),
            close.heightAnchor.constraint(equalToConstant: 16),
            rightBorder.topAnchor.constraint(equalTo: topAnchor),
            rightBorder.bottomAnchor.constraint(equalTo: bottomAnchor),
            rightBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            rightBorder.widthAnchor.constraint(equalToConstant: 1),
        ]
        if showsAccent {
            let accent = NSBox()
            accent.boxType = .custom
            accent.borderWidth = 0
            accent.fillColor = Theme.accent
            accent.translatesAutoresizingMaskIntoConstraints = false
            addSubview(accent)
            constraints += [
                accent.topAnchor.constraint(equalTo: topAnchor),
                accent.leadingAnchor.constraint(equalTo: leadingAnchor),
                accent.trailingAnchor.constraint(equalTo: trailingAnchor),
                accent.heightAnchor.constraint(equalToConstant: 2),
            ]
        }
        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) không dùng")
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }

    @objc private func closeClicked() {
        onClose?()
    }
}

@MainActor
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

import AppKit

/// Cửa sổ chính. M1: một editor + thanh trạng thái. (Sidebar và nhiều cột ở M2/M3.)
@MainActor
final class MainWindowController: NSWindowController {
    private let appState: AppState
    private let editor: EditorColumnView
    private let statusBar = StatusBarView()

    init(appState: AppState) {
        self.appState = appState
        editor = EditorColumnView(fontSize: appState.fontSize)

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1400, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MiniEditor"
        window.isReleasedWhenClosed = false
        window.backgroundColor = Theme.chromeBackground
        window.minSize = NSSize(width: 480, height: 320)
        super.init(window: window)

        buildContent(in: window)

        editor.onCursorChange = { [weak self] line, column in
            self?.statusBar.setCursor(line: line, column: column)
        }
        appState.onFontSizeChange = { [weak self] size in
            self?.editor.setFontSize(size)
            self?.statusBar.setFontSize(size)
        }
        statusBar.setFontSize(appState.fontSize)
        editor.notifyCursor()

        window.center()
        window.makeFirstResponder(editor.textView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) không dùng")
    }

    private func buildContent(in window: NSWindow) {
        let content = NSView()
        editor.translatesAutoresizingMaskIntoConstraints = false
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(editor)
        content.addSubview(statusBar)
        NSLayoutConstraint.activate([
            editor.topAnchor.constraint(equalTo: content.topAnchor),
            editor.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            editor.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
    }
}

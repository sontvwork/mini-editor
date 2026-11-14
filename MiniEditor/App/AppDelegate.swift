import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState: AppState
    private let sessionStore: SessionStore
    private var windowController: MainWindowController?

    override init() {
        let support = Self.supportDirectory()
        appState = AppState(draftStore: DraftStore(directory: support.appendingPathComponent("drafts", isDirectory: true)))
        sessionStore = SessionStore(fileURL: support.appendingPathComponent("session.json"))
        super.init()
    }

    /// `~/Library/Application Support/MiniEditor/`. Khi chạy unit test dùng thư mục tạm,
    /// để test không đọc/ghi đè session thật.
    private static func supportDirectory() -> URL {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("MiniEditor-test-\(UUID().uuidString)", isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MiniEditor", isDirectory: true)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Tab của app là tab editor; tắt window tabbing của hệ thống (nó cũng chiếm ⌃Tab).
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.mainMenu = MainMenu.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let session = sessionStore.load()
        if let session {
            appState.restore(session)
        }
        let controller = MainWindowController(appState: appState, sessionStore: sessionStore, restoring: session)
        controller.showWindow(nil)
        windowController = controller
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// App mất focus → lưu mọi thứ.
    func applicationWillResignActive(_ notification: Notification) {
        appState.saveAllBuffers()
        sessionStore.saveNow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.saveAllBuffers()
        sessionStore.saveNow()
    }

    // MARK: - File

    @objc func newDraft(_ sender: Any?) {
        windowController?.newDraft()
    }

    @objc func saveDocument(_ sender: Any?) {
        windowController?.saveActiveBuffer()
    }

    // MARK: - Workspace & sidebar

    @objc func addWorkspace(_ sender: Any?) {
        windowController?.showAddWorkspacePanel()
    }

    @objc func toggleWorkspaceSidebar(_ sender: Any?) {
        windowController?.toggleSidebar()
    }

    // MARK: - Tab & cột

    @objc func closeEditorTab(_ sender: Any?) {
        appState.closeActiveTab()
    }

    @objc func selectNextEditorTab(_ sender: Any?) {
        appState.selectNextTab()
    }

    @objc func selectPreviousEditorTab(_ sender: Any?) {
        appState.selectPreviousTab()
    }

    /// ⌘1…⌘9: `tag` của menu item là chỉ số cột (0-based).
    @objc func focusEditorColumn(_ sender: NSMenuItem) {
        appState.focusColumn(at: sender.tag)
    }

    // MARK: - Cỡ chữ (⌘+ / ⌘− / ⌘0)

    @objc func increaseEditorFontSize(_ sender: Any?) {
        appState.increaseFontSize()
    }

    @objc func decreaseEditorFontSize(_ sender: Any?) {
        appState.decreaseFontSize()
    }

    @objc func resetEditorFontSize(_ sender: Any?) {
        appState.resetFontSize()
    }
}

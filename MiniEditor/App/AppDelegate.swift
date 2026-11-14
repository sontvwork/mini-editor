import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private var windowController: MainWindowController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.mainMenu = MainMenu.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = MainWindowController(appState: appState)
        controller.showWindow(nil)
        windowController = controller
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
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

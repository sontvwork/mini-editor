import AppKit

/// Dựng thanh menu bằng code (không storyboard/xib).
@MainActor
enum MainMenu {
    static func build() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(submenuItem(appMenu()))
        mainMenu.addItem(submenuItem(fileMenu()))
        mainMenu.addItem(submenuItem(editMenu()))
        mainMenu.addItem(submenuItem(viewMenu()))

        let window = windowMenu()
        mainMenu.addItem(submenuItem(window))
        NSApp.windowsMenu = window

        return mainMenu
    }

    private static func submenuItem(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func appMenu() -> NSMenu {
        let name = ProcessInfo.processInfo.processName
        let menu = NSMenu(title: name)
        menu.addItem(withTitle: "About \(name)",
                     action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                     keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide \(name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = menu.addItem(withTitle: "Hide Others",
                                      action: #selector(NSApplication.hideOtherApplications(_:)),
                                      keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(withTitle: "Add Workspace…",
                     action: #selector(AppDelegate.addWorkspace(_:)),
                     keyEquivalent: "o")
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(withTitle: "Toggle Sidebar",
                     action: #selector(AppDelegate.toggleWorkspaceSidebar(_:)),
                     keyEquivalent: "b")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Increase Font Size",
                     action: #selector(AppDelegate.increaseEditorFontSize(_:)),
                     keyEquivalent: "+")
        // ⌘= (không cần Shift) cũng tăng cỡ chữ; mục ẩn chỉ để bắt phím.
        let increaseAlias = menu.addItem(withTitle: "Increase Font Size",
                                         action: #selector(AppDelegate.increaseEditorFontSize(_:)),
                                         keyEquivalent: "=")
        increaseAlias.isHidden = true
        increaseAlias.allowsKeyEquivalentWhenHidden = true
        menu.addItem(withTitle: "Decrease Font Size",
                     action: #selector(AppDelegate.decreaseEditorFontSize(_:)),
                     keyEquivalent: "-")
        menu.addItem(withTitle: "Reset Font Size",
                     action: #selector(AppDelegate.resetEditorFontSize(_:)),
                     keyEquivalent: "0")
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        return menu
    }
}

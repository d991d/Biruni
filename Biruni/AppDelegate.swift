import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Biruni doesn't use a XIB/storyboard for its menu bar - the whole
        // UI (panels, menus, dialogs) is built programmatically to get the
        // hand-drawn retro look, so there's no MainMenu.xib supplying
        // NSApp.mainMenu for free. Build it here instead.
        NSApp.mainMenu = Self.buildMainMenu(target: self)

        let controller = MainWindowController()
        windowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    // Not the generic system About panel: routes to MainWindowController's
    // own About dialog (see showAboutBiruni below) so the native "Biruni"
    // app menu and the F9 Options menu's "About Biruni" show the same
    // explanation of who the app is named for, instead of one showing a
    // blank system panel and the other a real bio.
    @objc private func showAboutBiruni() {
        windowController?.showAbout()
    }

    private static func buildMainMenu(target: AppDelegate) -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        let about = appMenu.addItem(withTitle: "About Biruni", action: #selector(AppDelegate.showAboutBiruni), keyEquivalent: "")
        about.target = target
        appMenu.addItem(.separator())
        let hide = appMenu.addItem(withTitle: "Hide Biruni", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.keyEquivalentModifierMask = [.command]
        appMenu.addItem(.separator())
        let quit = appMenu.addItem(withTitle: "Quit Biruni", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        // Standard Cmd-C/V/X/A/Z bindings for the command line and the
        // built-in editor's text fields - without this menu these text
        // views don't respond to the usual edit shortcuts.
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z").keyEquivalentModifierMask = [.command]
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z").keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x").keyEquivalentModifierMask = [.command]
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c").keyEquivalentModifierMask = [.command]
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v").keyEquivalentModifierMask = [.command]
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a").keyEquivalentModifierMask = [.command]

        return mainMenu
    }
}

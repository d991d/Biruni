import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var windowController: MainWindowController?

    // The @main synthesis for a plain NSApplicationDelegate class is
    // supposed to instantiate this class and assign it as NSApp.delegate
    // automatically, with no nib/storyboard needed. In practice that
    // synthesis was silently not wiring up the delegate here (confirmed by
    // breakpointing applicationDidFinishLaunching and never hitting it,
    // while `sample` showed the process happily idling in
    // -[NSApplication run]'s event loop) - the process launches and never
    // crashes, it just never calls into this class at all, so no window
    // is ever created. Writing main() explicitly bypasses whatever's wrong
    // with that synthesis by doing the delegate assignment ourselves,
    // which is the same thing @NSApplicationMain used to do for free.
    static func main() {
        NSLog("[Biruni-DIAG] custom static main(): start")
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        NSLog("[Biruni-DIAG] delegate assigned: \(delegate), NSApp.delegate=\(String(describing: app.delegate))")
        app.run()
        NSLog("[Biruni-DIAG] app.run() returned (app is quitting)")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[Biruni-DIAG] applicationDidFinishLaunching: start")
        // Biruni doesn't use a XIB/storyboard for its menu bar - the whole
        // UI (panels, menus, dialogs) is built programmatically to get the
        // hand-drawn retro look, so there's no MainMenu.xib supplying
        // NSApp.mainMenu for free. Build it here instead.
        NSApp.mainMenu = Self.buildMainMenu(target: self)
        NSLog("[Biruni-DIAG] main menu built")

        let controller = MainWindowController()
        NSLog("[Biruni-DIAG] MainWindowController() init returned")
        windowController = controller
        controller.showWindow(nil)
        NSLog("[Biruni-DIAG] showWindow(nil) returned")
        controller.window?.makeKeyAndOrderFront(nil)
        NSLog("[Biruni-DIAG] makeKeyAndOrderFront returned; window=\(String(describing: controller.window)) isVisible=\(controller.window?.isVisible ?? false) frame=\(String(describing: controller.window?.frame))")

        NSApp.activate(ignoringOtherApps: true)
        NSLog("[Biruni-DIAG] activate returned; NSApp.windows=\(NSApp.windows)")
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

import AppKit
import NCCore

/// Owns the whole main screen: two panels, the command line, the function
/// key bar, and the F9 pulldown menu. Routes all the NC keyboard commands
/// (F1-F10, Tab, Space, Enter, Backspace) to the right place.
final class MainWindowController: NSWindowController {

    private let leftPanel: PanelViewController
    private let rightPanel: PanelViewController
    private var activePanel: PanelViewController

    private let fsOps = FileSystemService()
    private let archiveService = ArchiveService()

    private var viewerWindows: [ViewerWindowController] = []
    private weak var consoleOutputView: ConsoleOutputView?

    private var root: MainRootView { window!.contentView as! MainRootView }

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        leftPanel = PanelViewController(startPath: home)
        rightPanel = PanelViewController(startPath: home)
        activePanel = leftPanel

        let window = MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Biruni"
        window.backgroundColor = Theme.panelBackground
        window.minSize = NSSize(width: 700, height: 400)
        // See AppDelegate.applicationSupportsSecureRestorableState: this
        // process has no real on-disk .app bundle for AppKit's window
        // state restoration to persist into, which was logging repeated
        // restoration_storage XPC failures on every launch and appeared
        // to be involved in the window intermittently never becoming
        // visible even though the process stayed alive. Opt this window
        // out of that system entirely.
        window.isRestorable = false

        super.init(window: window)

        let rootView = MainRootView(frame: window.contentView!.bounds)
        window.contentView = rootView

        rootView.splitView.addArrangedSubview(leftPanel.view)
        rootView.splitView.addArrangedSubview(rightPanel.view)
        rootView.splitView.delegate = self

        leftPanel.delegate = self
        rightPanel.delegate = self
        leftPanel.isActive = true
        rightPanel.isActive = false

        window.delegate = self
        window.onFunctionKey = { [weak self] number in self?.performFunctionKey(number) }
        window.onCommandKeyEquivalent.append(("s", { [weak self] in self?.saveActiveInlineEditor() }))
        // Belt-and-suspenders alongside the explicit makeFirstResponder call
        // in showWindow(_:) below - this is the idiomatic AppKit way to
        // declare "focus this on launch" and doesn't depend on ordering
        // relative to when the window actually becomes key.
        window.initialFirstResponder = leftPanel.tableView

        rootView.funcKeyBar.onKeyTapped = { [weak self] number in self?.performFunctionKey(number) }
        rootView.menuBar.onActivate = { [weak self] index, frame in self?.showPulldownMenu(index: index, anchorFrame: frame) }

        rootView.commandLine.field.onSubmit = { [weak self] in self?.submitCommandLine() }
        rootView.commandLine.field.onCancel = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.activePanel.tableView)
        }

        leftPanel.reload()
        rightPanel.reload()
        rootView.commandLine.setPromptPath(activePanel.state.location.nearestRealDirectory)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        establishInitialFocusAndSplit()
    }

    /// Sets the initial 50/50 divider position and hands keyboard focus to
    /// the left panel. Dispatched to the next run loop turn rather than
    /// done synchronously here: right after a freshly-created window is
    /// first ordered front, `makeFirstResponder` can be a no-op if the
    /// window hasn't finished becoming key yet, and the split view's
    /// bounds may still be its pre-layout placeholder size. Waiting one
    /// turn guarantees both are settled.
    private func establishInitialFocusAndSplit() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.leftPanel.focus()
            let width = self.root.splitView.bounds.width
            if width > 0 {
                self.root.splitView.setPosition((width - self.root.splitView.dividerThickness) / 2, ofDividerAt: 0)
            }
        }
    }

    // MARK: - Panel helpers

    private func otherPanel(of panel: PanelViewController) -> PanelViewController {
        panel === leftPanel ? rightPanel : leftPanel
    }

    // MARK: - Function keys

    private func performFunctionKey(_ number: Int) {
        // The console overlay (shown after a command-line command runs)
        // wants literally any key to dismiss it and return to the panels -
        // including function keys, which would otherwise fire their normal
        // action underneath it without it going away.
        if consoleOutputView != nil {
            dismissConsoleOutput()
            return
        }
        switch number {
        case 1: showHelp()
        case 2: showUserMenu()
        case 3: viewOperation()
        case 4: editOperation()
        case 5: copyOperation()
        case 6: moveOperation()
        case 7: mkdirOperation()
        case 8: deleteOperation()
        case 9: root.menuBar.activateFirstItem()
        case 10: quitOperation()
        default: break
        }
    }

    private func showHelp() {
        let text = """
        F1  Help            F2  User Menu        F3  View
        F4  Edit            F5  Copy             F6  Move / Rename
        F7  Make Directory  F8  Delete           F9  Pulldown Menu
        F10 Quit

        Tab             Switch active panel
        Space           Mark / unmark file
        Return          Open directory, archive, or file
        Delete/Backspace  Go to parent directory ("..")
        Return (cmd line) Run a shell command in the active panel's folder

        Archives (.zip, .tar, .tar.gz, .tgz) can be entered like folders;
        use Copy (F5) to extract marked items into the other panel.
        """
        RetroDialogs.message(title: "Biruni - Help", message: text, in: window!)
    }

    // MARK: - F3 View / F4 Edit

    private func realFileURL(for entry: FileEntry, in panel: PanelViewController) -> URL? {
        switch panel.state.location {
        case .filesystem(let path):
            return URL(fileURLWithPath: (path as NSString).appendingPathComponent(entry.name))
        case .archive(let archiveURL, let internalPath):
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("nc-mac-\(UUID().uuidString)")
            do {
                try archiveService.extract(
                    archiveURL: archiveURL,
                    internalEntryPath: internalPath + entry.name,
                    isDirectory: false,
                    to: tempDir.path
                )
                return tempDir.appendingPathComponent(internalPath + entry.name)
            } catch {
                RetroDialogs.error(error, in: window!)
                return nil
            }
        }
    }

    private func viewOperation() {
        guard let entry = activePanel.selectedEntry(), entry.kind == .regularFile || entry.kind == .symlink else { return }
        guard let url = realFileURL(for: entry, in: activePanel) else { return }
        let controller = ViewerWindowController(fileURL: url)
        viewerWindows.append(controller)
        controller.showWindow(nil)
    }

    private func editOperation() {
        guard let entry = activePanel.selectedEntry(), entry.kind == .regularFile || entry.kind == .symlink else { return }
        guard let url = realFileURL(for: entry, in: activePanel) else { return }
        presentInlineEditor(forFileAt: url)
    }

    /// The opposite panel becomes the editor, in place, rather than opening
    /// a separate window - the same dual-pane idea NC uses for everything
    /// else, just applied to F4 too.
    private func presentInlineEditor(forFileAt url: URL) {
        let editingPanel = otherPanel(of: activePanel)
        editingPanel.presentEditor(forFileAt: url)
    }

    private func saveActiveInlineEditor() {
        leftPanel.saveInlineEditorIfPresent()
        rightPanel.saveInlineEditorIfPresent()
    }

    // MARK: - F5 Copy

    private func copyOperation() {
        let source = activePanel
        let dest = otherPanel(of: source)
        let items = source.state.selectionForOperation()
        guard !items.isEmpty else { return }

        guard case .filesystem(let destPath) = dest.state.location else {
            RetroDialogs.message(title: "Copy", message: "Can't copy into an archive view. Switch the other panel to a real folder first.", in: window!)
            return
        }
        guard let confirmedDest = RetroDialogs.prompt(
            title: "Copy",
            message: "Copy \(items.count) item(s) to:",
            defaultValue: destPath,
            in: window!
        ) else { return }

        for entry in items {
            do {
                switch source.state.location {
                case .filesystem(let srcPath):
                    let full = (srcPath as NSString).appendingPathComponent(entry.name)
                    try fsOps.copy(from: full, toDirectory: confirmedDest, overwrite: false)
                case .archive(let archiveURL, let internalPath):
                    try archiveService.extract(
                        archiveURL: archiveURL,
                        internalEntryPath: internalPath + entry.name,
                        isDirectory: entry.kind == .directory,
                        to: confirmedDest
                    )
                }
            } catch {
                RetroDialogs.error(error, in: window!)
            }
        }
        source.state.markedNames.removeAll()
        source.reload()
        dest.reload()
    }

    // MARK: - F6 Move / Rename

    private func moveOperation() {
        let source = activePanel
        guard case .filesystem(let srcPath) = source.state.location else {
            RetroDialogs.message(title: "Move", message: "Can't move items from inside an archive view - use Copy (F5) to extract them first.", in: window!)
            return
        }
        let items = source.state.selectionForOperation()
        guard !items.isEmpty else { return }
        let dest = otherPanel(of: source)

        if items.count == 1, let entry = items.first {
            var defaultTarget = entry.name
            if case .filesystem(let destPath) = dest.state.location {
                defaultTarget = (destPath as NSString).appendingPathComponent(entry.name)
            }
            guard let target = RetroDialogs.prompt(
                title: "Rename / Move",
                message: "New name or full path for \"\(entry.name)\":",
                defaultValue: defaultTarget,
                in: window!
            ) else { return }

            let fullSource = (srcPath as NSString).appendingPathComponent(entry.name)
            do {
                if target.contains("/") {
                    let targetDir = (target as NSString).deletingLastPathComponent
                    let targetName = (target as NSString).lastPathComponent
                    try fsOps.move(from: fullSource, toDirectory: targetDir)
                    if targetName != entry.name {
                        let movedPath = (targetDir as NSString).appendingPathComponent(entry.name)
                        try fsOps.rename(from: movedPath, to: targetName)
                    }
                } else if target != entry.name {
                    try fsOps.rename(from: fullSource, to: target)
                }
            } catch {
                RetroDialogs.error(error, in: window!)
            }
        } else {
            guard case .filesystem(let destPath) = dest.state.location else {
                RetroDialogs.message(title: "Move", message: "Can't move into an archive view.", in: window!)
                return
            }
            guard RetroDialogs.confirm(title: "Move", message: "Move \(items.count) item(s) to \(destPath)?", in: window!) else { return }
            for entry in items {
                let full = (srcPath as NSString).appendingPathComponent(entry.name)
                do { try fsOps.move(from: full, toDirectory: destPath) }
                catch { RetroDialogs.error(error, in: window!) }
            }
        }
        source.state.markedNames.removeAll()
        source.reload()
        dest.reload()
    }

    // MARK: - F7 MkDir

    private func mkdirOperation() {
        guard case .filesystem(let path) = activePanel.state.location else {
            RetroDialogs.message(title: "Make Directory", message: "Can't create a folder inside an archive view.", in: window!)
            return
        }
        guard let name = RetroDialogs.prompt(title: "Make Directory", message: "Name for the new folder:", defaultValue: "", in: window!),
              !name.isEmpty else { return }
        do {
            try fsOps.makeDirectory(named: name, in: path)
            activePanel.reload()
        } catch {
            RetroDialogs.error(error, in: window!)
        }
    }

    // MARK: - F8 Delete

    private func deleteOperation() {
        guard case .filesystem(let path) = activePanel.state.location else {
            RetroDialogs.message(title: "Delete", message: "Can't delete items from inside an archive view.", in: window!)
            return
        }
        let items = activePanel.state.selectionForOperation()
        guard !items.isEmpty else { return }
        let names = items.map(\.name).joined(separator: ", ")
        guard RetroDialogs.confirm(
            title: "Delete",
            message: "Delete \(items.count) item(s)?\n\(names)",
            okTitle: "Delete",
            destructive: true,
            in: window!
        ) else { return }

        for entry in items {
            let full = (path as NSString).appendingPathComponent(entry.name)
            do { try fsOps.delete(path: full) }
            catch { RetroDialogs.error(error, in: window!) }
        }
        activePanel.state.markedNames.removeAll()
        activePanel.reload()
    }

    // MARK: - F2 User menu

    private func showUserMenu() {
        let items = UserMenuStore.load()
        var menuItems = items.map { item in
            RetroMenuItem.item("\(item.hotkey)  \(item.label)") { [weak self] in self?.runUserMenuItem(item) }
        }
        if !menuItems.isEmpty {
            menuItems.append(.separator())
        }
        menuItems.append(.item("Edit menu file...") { [weak self] in self?.editUserMenuFile() })
        RetroMenu.popUp(menuItems, at: NSPoint(x: 20, y: 60), in: window!.contentView!)
    }

    private func runUserMenuItem(_ item: UserMenuItem) {
        let dir = activePanel.state.location.nearestRealDirectory
        let result = ShellRunner.runShellLine(item.command, directory: dir)
        leftPanel.reload()
        rightPanel.reload()
        presentConsoleOutput(promptPath: dir, command: item.command, result: result)
    }

    @objc private func editUserMenuFile() {
        _ = UserMenuStore.load()
        presentInlineEditor(forFileAt: UserMenuStore.menuFileURL)
    }

    // MARK: - F9 Pulldown menu

    private func showPulldownMenu(index: Int, anchorFrame: NSRect) {
        let items: [RetroMenuItem]
        switch index {
        case 0:
            items = [
                .item("Refresh") { [weak self] in self?.refreshLeft() },
                .item("Toggle Hidden Files") { [weak self] in self?.toggleHiddenLeft() },
                .item("Go to Home Folder") { [weak self] in self?.goHomeLeft() }
            ]
        case 1:
            items = [
                .item("Copy...  (F5)") { [weak self] in self?.menuCopy() },
                .item("Move / Rename...  (F6)") { [weak self] in self?.menuMove() },
                .item("Make Directory...  (F7)") { [weak self] in self?.menuMkdir() },
                .item("Delete...  (F8)") { [weak self] in self?.menuDelete() },
                .separator(),
                .item("Extract Archive to Other Panel") { [weak self] in self?.menuExtractArchive() },
                .item("Compare Directories") { [weak self] in self?.menuCompare() }
            ]
        case 2:
            items = [
                .item("User Menu...  (F2)") { [weak self] in self?.menuUserMenu() },
                .item("Edit User Menu File") { [weak self] in self?.editUserMenuFile() },
                .item("Focus Command Line") { [weak self] in self?.focusCommandLine() }
            ]
        case 3:
            items = [
                .item("Toggle Hidden Files (Both Panels)") { [weak self] in self?.toggleHiddenBoth() },
                .item("About Biruni") { [weak self] in self?.showAbout() }
            ]
        case 4:
            items = [
                .item("Refresh") { [weak self] in self?.refreshRight() },
                .item("Toggle Hidden Files") { [weak self] in self?.toggleHiddenRight() },
                .item("Go to Home Folder") { [weak self] in self?.goHomeRight() }
            ]
        default:
            items = []
        }
        // anchorFrame is in root.menuBar's own (flipped) coordinate space,
        // so maxY is the bottom edge of the clicked label - exactly where
        // the dropdown should start.
        let anchor = NSPoint(x: anchorFrame.minX, y: anchorFrame.maxY)
        RetroMenu.popUp(items, at: anchor, in: root.menuBar)
    }

    @objc private func refreshLeft() { leftPanel.reload() }
    @objc private func refreshRight() { rightPanel.reload() }

    @objc private func toggleHiddenLeft() { leftPanel.state.showHidden.toggle(); leftPanel.reload() }
    @objc private func toggleHiddenRight() { rightPanel.state.showHidden.toggle(); rightPanel.reload() }
    @objc private func toggleHiddenBoth() {
        let newValue = !leftPanel.state.showHidden
        leftPanel.state.showHidden = newValue
        rightPanel.state.showHidden = newValue
        leftPanel.reload()
        rightPanel.reload()
    }

    @objc private func goHomeLeft() { leftPanel.state.jump(to: fsOps.homeDirectoryPath()); leftPanel.reload() }
    @objc private func goHomeRight() { rightPanel.state.jump(to: fsOps.homeDirectoryPath()); rightPanel.reload() }

    @objc private func menuCopy() { copyOperation() }
    @objc private func menuMove() { moveOperation() }
    @objc private func menuMkdir() { mkdirOperation() }
    @objc private func menuDelete() { deleteOperation() }
    @objc private func menuUserMenu() { showUserMenu() }

    @objc private func menuExtractArchive() {
        guard let entry = activePanel.selectedEntry(), entry.kind == .archive else {
            RetroDialogs.message(title: "Extract Archive", message: "Select a .zip/.tar/.tar.gz/.tgz file first.", in: window!)
            return
        }
        guard case .filesystem(let path) = activePanel.state.location else { return }
        let archiveURL = URL(fileURLWithPath: (path as NSString).appendingPathComponent(entry.name))
        let dest = otherPanel(of: activePanel)
        guard case .filesystem(let destPath) = dest.state.location else {
            RetroDialogs.message(title: "Extract Archive", message: "The other panel needs to be on a real folder.", in: window!)
            return
        }
        do {
            try archiveService.extractAll(archiveURL: archiveURL, to: destPath)
            dest.reload()
        } catch {
            RetroDialogs.error(error, in: window!)
        }
    }

    @objc private func menuCompare() {
        let result = DirectoryComparer.compare(left: leftPanel.state.entries, right: rightPanel.state.entries)
        leftPanel.state.markedNames = result.leftDifferent
        rightPanel.state.markedNames = result.rightDifferent
        leftPanel.reload()
        rightPanel.reload()
        RetroDialogs.message(
            title: "Compare Directories",
            message: "\(result.leftDifferent.count) item(s) marked on the left, \(result.rightDifferent.count) on the right.",
            in: window!
        )
    }

    @objc private func focusCommandLine() {
        window?.makeFirstResponder(root.commandLine.field)
    }

    // Not private: AppDelegate's native "About Biruni" app-menu item calls
    // this too (instead of the generic system About panel), so both places
    // a user might look for "About" - the F9 Options menu and the actual
    // Biruni menu at the top of the screen - show the same explanation of
    // who the app is named for, not a blank system panel plus a separate
    // bio somewhere else.
    @objc func showAbout() {
        RetroDialogs.message(
            title: "Biruni",
            message: """
            Biruni - a native macOS tribute to Norton Commander (1986).

            Named for Abu Rayhan al-Biruni (973-1048), a Persian scholar from Khwarazm and one of the great polymaths of medieval science. Working across mathematics, astronomy, geography, and history, he calculated Earth's radius from a mountaintop using trigonometry, landing within about 1% of its true value; catalogued the calendars and eras of a dozen civilizations in his Chronology of Ancient Nations; and, after years in India, wrote Kitab al-Hind, an unusually even-handed study of Indian society and science for its era. He corresponded with Ibn Sina on the nature of the physical world and was among the first to seriously entertain the idea that the Earth rotates on its own axis.

            Dual-pane file management with the classic blue DOS interface.
            """,
            in: window!
        )
    }

    // MARK: - Command line

    private func submitCommandLine() {
        let text = root.commandLine.field.stringValue
        root.commandLine.field.stringValue = ""
        guard !text.isEmpty else {
            window?.makeFirstResponder(activePanel.tableView)
            return
        }
        let dir = activePanel.state.location.nearestRealDirectory
        let result = ShellRunner.runShellLine(text, directory: dir)
        leftPanel.reload()
        rightPanel.reload()
        presentConsoleOutput(promptPath: dir, command: text, result: result)
    }

    /// Covers the whole window with a real terminal-style transcript of
    /// what the command printed - see `ConsoleOutputView` - dismissed by
    /// any keypress or click, the way DOS-era NC's own shell-out screen
    /// worked. `runUserMenuItem` (F2 menu commands) uses this too, for the
    /// same reason.
    private func presentConsoleOutput(promptPath: String, command: String, result: ShellRunner.Result) {
        guard let contentView = window?.contentView else { return }
        let console = ConsoleOutputView(promptPath: promptPath, command: command, result: result)
        console.frame = contentView.bounds
        console.autoresizingMask = [.width, .height]
        console.onDismiss = { [weak self] in self?.dismissConsoleOutput() }
        contentView.addSubview(console)
        consoleOutputView = console
        window?.makeFirstResponder(console)
    }

    private func dismissConsoleOutput() {
        consoleOutputView?.removeFromSuperview()
        consoleOutputView = nil
        window?.makeFirstResponder(activePanel.tableView)
    }

    // MARK: - Quit

    @objc private func quitOperation() {
        guard RetroDialogs.confirm(title: "Quit", message: "Quit Biruni?", in: window!) else { return }
        NSApp.terminate(nil)
    }
}

// MARK: - PanelViewControllerDelegate

extension MainWindowController: PanelViewControllerDelegate {

    func panelDidBecomeActive(_ panel: PanelViewController) {
        guard panel !== activePanel else { return }
        activePanel.isActive = false
        activePanel = panel
        activePanel.isActive = true
        root.commandLine.setPromptPath(activePanel.state.location.nearestRealDirectory)
    }

    func panelRequestsSwitch(_ panel: PanelViewController) {
        let target = otherPanel(of: panel)
        target.focus()
    }

    func panelDidChangeLocation(_ panel: PanelViewController) {
        if panel === activePanel {
            root.commandLine.setPromptPath(panel.state.location.nearestRealDirectory)
        }
    }

    func panel(_ panel: PanelViewController, didOpenFile entry: FileEntry, atRealPath path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func panel(_ panel: PanelViewController, didFailWithError error: Error) {
        let nsError = error as NSError
        var message = nsError.localizedDescription
        let isPermissionError = (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoPermissionError)
            || (nsError.domain == NSPOSIXErrorDomain)
        if isPermissionError {
            message += "\n\nmacOS protects this folder. Open System Settings > Privacy & Security > Files and Folders, allow Biruni access to it, then try again. The panel has stayed where it was so you can keep browsing."
        }
        RetroDialogs.message(title: "Can't Open Folder", message: message, in: window!)
    }
}

// MARK: - NSSplitViewDelegate

extension MainWindowController: NSSplitViewDelegate {
    /// Keeps the two panels an even 50/50 split as the window resizes,
    /// instead of NSSplitView's default of pinning one side's width and
    /// letting the other absorb the whole delta.
    func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
        guard splitView.arrangedSubviews.count == 2 else {
            splitView.adjustSubviews()
            return
        }
        let thickness = splitView.dividerThickness
        let total = splitView.bounds.width
        let half = max(0, (total - thickness) / 2)
        let height = splitView.bounds.height
        splitView.arrangedSubviews[0].frame = NSRect(x: 0, y: 0, width: half, height: height)
        splitView.arrangedSubviews[1].frame = NSRect(x: half + thickness, y: 0, width: half, height: height)
    }
}

// MARK: - NSWindowDelegate

extension MainWindowController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        RetroDialogs.confirm(title: "Quit", message: "Quit Biruni?", in: sender)
    }
}

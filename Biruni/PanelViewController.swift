import AppKit
import NCCore

protocol PanelViewControllerDelegate: AnyObject {
    func panelDidBecomeActive(_ panel: PanelViewController)
    func panelRequestsSwitch(_ panel: PanelViewController)
    func panelDidChangeLocation(_ panel: PanelViewController)
    func panel(_ panel: PanelViewController, didOpenFile entry: FileEntry, atRealPath path: String)
    func panel(_ panel: PanelViewController, didFailWithError error: Error)
}

/// One side of the dual-pane view: a path header, a column header, the
/// scrolling file list, and a status line. Owns a `PanelState` (from
/// NCCore) that does the actual filesystem/archive work.
final class PanelViewController: NSViewController {

    weak var delegate: PanelViewControllerDelegate?
    let state: PanelState
    var isActive: Bool = false {
        didSet { refreshRowHighlighting() }
    }

    private let pathLabel = RetroControls.label("", font: Theme.monoFontBold(), color: Theme.panelHeader, background: Theme.panelHeaderBG, alignment: .center)
    private let columnHeader = RetroControls.label("", font: Theme.monoFontBold(), color: Theme.panelHeaderBG)
    private let statusLabel = RetroControls.label("", font: Theme.monoFont(size: 11), color: Theme.panelHeader)
    private let scrollView = NSScrollView()
    let tableView = PanelTableView()

    /// Non-nil while F4 has swapped this panel over to editing a file in
    /// place - see `presentEditor(forFileAt:)`.
    private var editorView: PanelEditorView?

    private static let nameWidth = 24
    private static let sizeWidth = 11

    init(startPath: String) {
        self.state = PanelState(startPath: startPath)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func loadView() {
        let root = BorderedPanel()
        root.fillColor = Theme.panelBackground
        root.borderColor = Theme.panelHeaderBG
        self.view = root

        pathLabel.frame = .zero
        columnHeader.frame = .zero
        columnHeader.stringValue = columnHeaderText()
        statusLabel.frame = .zero

        let column = NSTableColumn(identifier: .init("main"))
        column.width = 400
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.backgroundColor = Theme.panelBackground
        tableView.selectionHighlightStyle = .regular
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = false
        tableView.rowHeight = 16
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.onToggleMark = { [weak self] in self?.toggleMark() }
        tableView.onActivateSelection = { [weak self] in self?.activateSelection() }
        tableView.onSwitchPanel = { [weak self] in
            guard let self else { return }
            self.delegate?.panelRequestsSwitch(self)
        }
        tableView.onGoToParent = { [weak self] in self?.goToParent() }
        tableView.onBecameFirstResponder = { [weak self] in
            guard let self else { return }
            self.delegate?.panelDidBecomeActive(self)
        }
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.panelBackground
        scrollView.borderType = .noBorder

        root.addSubview(pathLabel)
        root.addSubview(columnHeader)
        root.addSubview(scrollView)
        root.addSubview(statusLabel)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let bounds = view.bounds
        let headerH: CGFloat = 18
        let colHeaderH: CGFloat = 16
        let statusH: CGFloat = 16
        let margin: CGFloat = 1

        pathLabel.frame = NSRect(x: margin, y: bounds.height - headerH - margin, width: bounds.width - margin * 2, height: headerH)
        columnHeader.frame = NSRect(x: margin, y: bounds.height - headerH - colHeaderH - margin, width: bounds.width - margin * 2, height: colHeaderH)
        statusLabel.frame = NSRect(x: margin, y: margin, width: bounds.width - margin * 2, height: statusH)
        scrollView.frame = NSRect(
            x: margin,
            y: statusH + margin,
            width: bounds.width - margin * 2,
            height: bounds.height - headerH - colHeaderH - statusH - margin * 2
        )
        tableView.tableColumns.first?.width = scrollView.contentSize.width
    }

    // MARK: - Public API

    /// Re-lists the current directory/archive and syncs the UI to match.
    /// Use this for "refresh what's here" (after a copy/delete, toggling
    /// hidden files, etc). For actually navigating (Enter/Backspace), use
    /// `state.activate(_:)` directly followed by `syncUI()` - see
    /// `activateSelection()` / `goToParent()` below - since `activate`
    /// already refreshes internally and rolls itself back on failure.
    func reload() {
        do {
            try state.refresh()
        } catch {
            delegate?.panel(self, didFailWithError: error)
        }
        syncUI()
    }

    /// Updates every visible piece of chrome (path header, rows, selection,
    /// status line) from whatever is currently in `state.entries`, without
    /// touching the filesystem. Safe to call as often as needed.
    private func syncUI() {
        pathLabel.stringValue = " " + state.location.displayPath + " "
        tableView.reloadData()
        let selectedRow = min(state.cursorIndex, max(0, state.entries.count - 1))
        tableView.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
        tableView.scrollRowToVisible(selectedRow)
        updateStatusLine()
        delegate?.panelDidChangeLocation(self)
    }

    func navigate(toPath path: String) {
        state.jump(to: path)
        reload()
    }

    private func columnHeaderText() -> String {
        var s = " " + pad("Name", Self.nameWidth - 1)
        s += pad("Size", Self.sizeWidth, rightAlign: true)
        s += "  Date      Time"
        return s
    }

    private func pad(_ text: String, _ width: Int, rightAlign: Bool = false) -> String {
        if text.count >= width {
            let idx = text.index(text.startIndex, offsetBy: width)
            return String(text[text.startIndex..<idx])
        }
        let padding = String(repeating: " ", count: width - text.count)
        return rightAlign ? padding + text : text + padding
    }

    private func rowText(for entry: FileEntry) -> String {
        var name = entry.name
        if entry.kind == .directory || entry.kind == .parentDirectory {
            name = "[" + name + "]"
        }
        // Archives use their plain name; the magenta color (set in colorFor)
        // is what distinguishes them, not brackets.
        var s = " " + pad(name, Self.nameWidth - 1)
        s += pad(NCFormat.size(entry), Self.sizeWidth, rightAlign: true)
        s += "  " + NCFormat.date(entry.modificationDate)
        s += "  " + NCFormat.time(entry.modificationDate)
        return s
    }

    private func colorFor(_ entry: FileEntry, marked: Bool, isCursorRow: Bool) -> NSColor {
        if isCursorRow { return Theme.cursorText }
        if marked { return Theme.panelMarked }
        switch entry.kind {
        case .directory, .parentDirectory: return Theme.panelDirectory
        case .archive: return Theme.panelArchive
        default: return Theme.panelText
        }
    }

    // MARK: - Actions

    private func toggleMark() {
        let row = tableView.selectedRow
        guard row >= 0 else { return }
        state.toggleMark(at: row)
        // Move cursor down one row after marking, like NC does.
        let nextRow = min(row + 1, state.entries.count - 1)
        state.cursorIndex = nextRow
        reloadPreservingSelection()
        updateStatusLine()
    }

    private func activateSelection() {
        let row = tableView.selectedRow
        guard state.entries.indices.contains(row) else { return }
        let entry = state.entries[row]
        if entry.kind == .regularFile || entry.kind == .symlink {
            if case .filesystem(let path) = state.location {
                let full = (path as NSString).appendingPathComponent(entry.name)
                delegate?.panel(self, didOpenFile: entry, atRealPath: full)
            }
            return
        }
        do {
            if try state.activate(entry) {
                syncUI()
            }
        } catch {
            // state.activate already rolled back to the previous, still-valid
            // location on failure - just surface why (e.g. "Operation not
            // permitted" the first time you enter Desktop/Documents/Downloads
            // before granting Files & Folders access in System Settings).
            delegate?.panel(self, didFailWithError: error)
        }
    }

    @objc private func handleDoubleClick() {
        activateSelection()
    }

    private func goToParent() {
        guard let first = state.entries.first, first.kind == .parentDirectory else { return }
        do {
            if try state.activate(first) { syncUI() }
        } catch {
            delegate?.panel(self, didFailWithError: error)
        }
    }

    private func refreshRowHighlighting() {
        // Triggered from isActive's didSet (a click or Tab-driven panel
        // switch) - just re-tints the active/inactive cursor-row color,
        // the row that's selected doesn't change here.
        reloadPreservingSelection()
    }

    private func updateStatusLine() {
        let marked = state.selectionForOperation()
        if state.markedNames.isEmpty {
            statusLabel.stringValue = " \(state.entries.count) items"
        } else {
            statusLabel.stringValue = " \(marked.count) marked, \(NCFormat.humanSize(state.totalMarkedSize()))"
        }
    }

    func selectedEntry() -> FileEntry? {
        let row = tableView.selectedRow
        guard state.entries.indices.contains(row) else { return nil }
        return state.entries[row]
    }

    // MARK: - Inline editor (F4)

    /// Swaps this panel's content over to an in-place editor for `url`,
    /// covering the normal directory listing until it's closed. If this
    /// panel is already showing an editor for a different file, confirms
    /// discarding any unsaved changes there first.
    func presentEditor(forFileAt url: URL) {
        if let existing = editorView {
            guard existing.confirmClose() else { return }
            existing.removeFromSuperview()
            editorView = nil
        }
        let editor = PanelEditorView(fileURL: url)
        editor.frame = view.bounds
        editor.autoresizingMask = [.width, .height]
        editor.onClose = { [weak self] in self?.dismissEditor() }
        view.addSubview(editor)
        editorView = editor
        editor.focusEditor()
    }

    private func dismissEditor() {
        editorView?.removeFromSuperview()
        editorView = nil
        view.window?.makeFirstResponder(tableView)
    }

    /// No-op if this panel isn't currently showing an editor - safe to call
    /// unconditionally from a global Cmd-S handler.
    func saveInlineEditorIfPresent() {
        editorView?.save()
    }

    var isEditingInline: Bool { editorView != nil }

    /// Used instead of a bare `makeFirstResponder(tableView)` wherever focus
    /// is being handed to this panel (Tab switch, initial launch focus) -
    /// if it's mid-edit, keyboard focus should land in the editor, not on
    /// the (currently hidden-behind-it) file list.
    func focus() {
        if let editorView {
            editorView.focusEditor()
        } else {
            view.window?.makeFirstResponder(tableView)
        }
    }
}

// MARK: - NSTableViewDataSource / Delegate

extension PanelViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        state.entries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let entry = state.entries[row]
        let isCursorRow = (tableView.selectedRow == row)
        let marked = state.markedNames.contains(entry.name)

        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            let field = RetroLabel(labelWithString: "")
            field.font = Theme.monoFont(size: 12)
            field.isBezeled = false
            field.isEditable = false
            field.drawsBackground = false
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(field)
            cell.textField = field
            cell.identifier = identifier
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        cell.textField?.stringValue = rowText(for: entry)
        cell.textField?.textColor = colorFor(entry, marked: marked, isCursorRow: isCursorRow)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = PanelRowView()
        rowView.isActivePanelCursor = isActive
        return rowView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0 else { return }
        state.cursorIndex = row
        // IMPORTANT: do NOT call tableView.reloadData() here, not even
        // deferred. Live NC-DEBUG logging (both for mouse clicks and for
        // arrow-key repeats) proved that reloadData() unconditionally
        // resets NSTableView's selectedRow back to 0 in this table's
        // configuration (allowsEmptySelection = false, and row views are
        // freshly created rather than reused via an identifier) -
        // deferring the call to the next run loop turn didn't avoid the
        // reset, it just meant every *following* keystroke read
        // selectedRow == 0 again, which looked exactly like "the arrow
        // keys don't work". The cyan cursor-bar highlight itself is drawn
        // automatically by PanelRowView.drawSelection() from isSelected,
        // so no reload is actually needed just to move it. The one thing a
        // reload buys us here is refreshing per-row *text color* (see
        // colorFor/isCursorRow) - a cosmetic nicety not worth reintroducing
        // this whole bug class for, so it's intentionally skipped. Any
        // code path that legitimately needs a reload (toggleMark,
        // refreshRowHighlighting, syncUI) goes through
        // reloadPreservingSelection() below instead, which reloads and
        // then explicitly re-applies the intended row afterwards.
    }

    /// Use this instead of a bare tableView.reloadData() anywhere the
    /// current cursor row needs to survive the reload - see the long
    /// comment in tableViewSelectionDidChange above for why a plain
    /// reloadData() call silently resets the selection to row 0.
    private func reloadPreservingSelection() {
        let row = state.cursorIndex
        tableView.reloadData()
        if state.entries.indices.contains(row) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }
}

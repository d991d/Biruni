import AppKit

/// NSTableView subclass used for each NC panel. NSTableView already gives us
/// correct arrow/PageUp/PageDown/Home/End navigation and selection tracking
/// "for free" - we only need to intercept the NC-specific keys on top of that:
/// Space (mark/unmark), Return (enter directory / open), Tab (switch panel),
/// and Backspace (go up a directory).
final class PanelTableView: NSTableView {

    var onToggleMark: (() -> Void)?
    var onActivateSelection: (() -> Void)?
    var onSwitchPanel: (() -> Void)?
    var onGoToParent: (() -> Void)?
    var onBecameFirstResponder: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    // Belt-and-suspenders: a table view should already claim first
    // responder on click via the normal AppKit click-to-focus path, but
    // asking explicitly removes any dependency on the window already being
    // key at the moment of the click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onBecameFirstResponder?() }
        return result
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49: // Space
            onToggleMark?()
        case 36, 76: // Return, Enter (numpad)
            onActivateSelection?()
        case 48: // Tab
            onSwitchPanel?()
        case 51: // Backspace / Delete
            onGoToParent?()
        // Arrow/paging keys used to be left to fall through to
        // super.keyDown(_:) on the assumption that NSTableView's default
        // interpretKeyEvents()-driven moveUp(_:)/moveDown(_:) handling
        // would "just work", the way it does in a normal, fully
        // nib/bundle-backed app. In this app (a bare SwiftPM executable
        // with no real .app bundle/main nib) that default path was
        // observed to not reliably move the selection at all - so these
        // are now handled explicitly and deterministically instead of
        // depending on it.
        case 126: // Up arrow
            moveSelection(by: -1)
        case 125: // Down arrow
            moveSelection(by: 1)
        case 116: // Page Up
            moveSelection(by: -max(1, visiblePageRowCount()))
        case 121: // Page Down
            moveSelection(by: max(1, visiblePageRowCount()))
        case 115: // Home
            moveSelection(to: 0)
        case 119: // End
            moveSelection(to: numberOfRows - 1)
        default:
            super.keyDown(with: event)
        }
    }

    private func visiblePageRowCount() -> Int {
        guard rowHeight > 0 else { return 1 }
        return Int(visibleRect.height / rowHeight)
    }

    private func moveSelection(by delta: Int) {
        guard numberOfRows > 0 else { return }
        moveSelection(to: selectedRow + delta)
    }

    private func moveSelection(to row: Int) {
        guard numberOfRows > 0 else { return }
        let clamped = min(max(row, 0), numberOfRows - 1)
        selectRowIndexes(IndexSet(integer: clamped), byExtendingSelection: false)
        scrollRowToVisible(clamped)
    }
}

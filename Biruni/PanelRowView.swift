import AppKit

/// Draws each panel row with the DOS blue background and a solid cyan bar
/// for the cursor row, instead of macOS's native blue selection highlight.
final class PanelRowView: NSTableRowView {

    /// Whether this row is the "cursor" row of a panel that currently has
    /// keyboard focus (vs. the other, inactive panel).
    var isActivePanelCursor: Bool = true

    override func drawBackground(in dirtyRect: NSRect) {
        Theme.panelBackground.setFill()
        dirtyRect.fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none, isSelected else { return }
        let color = isActivePanelCursor ? Theme.cursorBackground : Theme.inactiveCursorBG
        color.setFill()
        bounds.fill()
    }

    override var isEmphasized: Bool {
        get { false }
        set { /* ignore - we don't want macOS's blur/emphasis behavior */ }
    }
}

import AppKit

/// A plain label that turns off antialiasing/interpolation before drawing,
/// so the monospaced text reads as crisp, blocky DOS-mode text instead of
/// smoothed modern-Mac type. Used for every static label in the app (panel
/// rows, headers, status lines, function-key bar labels).
final class RetroLabel: NSTextField {
    override func draw(_ dirtyRect: NSRect) {
        let context = NSGraphicsContext.current
        let previousAntialias = context?.shouldAntialias
        context?.shouldAntialias = false
        context?.imageInterpolation = .none
        super.draw(dirtyRect)
        if let previousAntialias { context?.shouldAntialias = previousAntialias }
    }
}

/// Small helpers for building the retro DOS look out of plain AppKit views
/// without repeating boilerplate everywhere.
enum RetroControls {

    static func label(
        _ text: String,
        font: NSFont = Theme.monoFont(),
        color: NSColor = Theme.panelText,
        background: NSColor = .clear,
        alignment: NSTextAlignment = .left
    ) -> NSTextField {
        let field = RetroLabel(labelWithString: text)
        field.font = font
        field.textColor = color
        field.alignment = alignment
        field.drawsBackground = background != .clear
        field.backgroundColor = background
        field.isBezeled = false
        field.isEditable = false
        field.isSelectable = false
        field.lineBreakMode = .byClipping
        field.usesSingleLineMode = true
        return field
    }

    /// A flat NSView with a solid fill color, used as a colored bar/panel.
    static func filledView(_ color: NSColor) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = color.cgColor
        return view
    }
}

/// A simple solid-color background NSView that also draws a 1px border,
/// used for the double-line-ish frame around panels and dialogs.
final class BorderedPanel: NSView {
    var fillColor: NSColor = Theme.panelBackground
    var borderColor: NSColor = Theme.panelHeaderBG

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.shouldAntialias = false
        fillColor.setFill()
        dirtyRect.fill()
        borderColor.setStroke()
        let path = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        path.stroke()
    }
}

import AppKit

/// NC's F9 pulldown menu bar: "Left  Files  Commands  Options  Right" in
/// black-on-gray along the very top of the screen. Clicking (or F9, which
/// opens the first item) pops up a RetroMenu anchored under the label -
/// drawn in NC's own light-gray/cyan-highlight style rather than native
/// NSMenu chrome.
final class PulldownMenuBarView: NSView {

    static let titles = ["Left", "Files", "Commands", "Options", "Right"]

    /// Called with the item index and its frame (in this view) when clicked
    /// or activated via F9.
    var onActivate: ((Int, NSRect) -> Void)?

    private var itemFrames: [NSRect] = []

    override var isFlipped: Bool { true }

    // A RetroMenu popup can take key status away from the main window
    // (e.g. after Escape/click-away). Without this, the *first* click on a
    // menu-bar label after that would only re-activate the window instead
    // of opening the menu, requiring a second click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.shouldAntialias = false
        NSGraphicsContext.current?.imageInterpolation = .none

        Theme.menuBarBackground.setFill()
        bounds.fill()

        itemFrames.removeAll()
        var x: CGFloat = 8
        let font = Theme.monoFontBold(size: 12)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Theme.menuBarText]

        for title in Self.titles {
            let padded = "  \(title)  "
            let size = padded.size(withAttributes: attrs)
            let frame = NSRect(x: x, y: 0, width: size.width, height: bounds.height)
            itemFrames.append(frame)
            let textRect = NSRect(x: x, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
            padded.draw(in: textRect, withAttributes: attrs)
            x += size.width + 4
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (index, frame) in itemFrames.enumerated() where frame.contains(point) {
            onActivate?(index, frame)
            return
        }
    }

    /// Used when F9 is pressed with the keyboard rather than clicked;
    /// opens the "Left" menu, matching NC's default F9 behavior.
    func activateFirstItem() {
        guard let frame = itemFrames.first else { return }
        onActivate?(0, frame)
    }
}

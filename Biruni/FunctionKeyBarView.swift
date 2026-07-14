import AppKit

/// The classic F1..F10 bar along the bottom of the screen: "1Help 2Menu
/// 3View 4Edit 5Copy 6RenMov 7MkDir 8Delete 9PullDn 10Quit", each rendered
/// as a black number on a cyan label.
final class FunctionKeyBarView: NSView {

    static let labels = [
        "Help", "Menu", "View", "Edit", "Copy",
        "RenMov", "MkDir", "Delete", "PullDn", "Quit"
    ]

    var onKeyTapped: ((Int) -> Void)?

    private var itemFrames: [NSRect] = []

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.shouldAntialias = false
        NSGraphicsContext.current?.imageInterpolation = .none

        Theme.funcKeyBarBackground.setFill()
        bounds.fill()

        let count = Self.labels.count
        let itemWidth = bounds.width / CGFloat(count)
        itemFrames.removeAll()

        let numberFont = Theme.monoFontBold(size: 11)
        let labelFont = Theme.monoFont(size: 11)

        for (index, label) in Self.labels.enumerated() {
            let x = CGFloat(index) * itemWidth
            let frame = NSRect(x: x, y: 0, width: itemWidth, height: bounds.height)
            itemFrames.append(frame)

            let number = "\(index + 1)"
            let numberAttrs: [NSAttributedString.Key: Any] = [.font: numberFont, .foregroundColor: Theme.funcKeyNumber]
            let numberSize = number.size(withAttributes: numberAttrs)
            let numberRect = NSRect(x: x + 2, y: (bounds.height - numberSize.height) / 2, width: numberSize.width, height: numberSize.height)
            number.draw(in: numberRect, withAttributes: numberAttrs)

            let labelRect = NSRect(x: numberRect.maxX + 2, y: 0, width: itemWidth - numberSize.width - 4, height: bounds.height)
            Theme.funcKeyLabelBG.setFill()
            labelRect.fill()
            let labelAttrs: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: Theme.funcKeyLabelText]
            let labelSize = label.size(withAttributes: labelAttrs)
            let labelDrawRect = NSRect(
                x: labelRect.minX + 2,
                y: (bounds.height - labelSize.height) / 2,
                width: labelSize.width,
                height: labelSize.height
            )
            label.draw(in: labelDrawRect, withAttributes: labelAttrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (index, frame) in itemFrames.enumerated() where frame.contains(point) {
            onKeyTapped?(index + 1)
            return
        }
    }
}

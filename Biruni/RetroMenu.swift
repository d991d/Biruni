import AppKit

/// One entry in a RetroMenu dropdown: either a selectable item with an
/// action, or a thin separator line.
struct RetroMenuItem {
    let title: String
    let isSeparator: Bool
    let action: (() -> Void)?

    static func item(_ title: String, action: @escaping () -> Void) -> RetroMenuItem {
        RetroMenuItem(title: title, isSeparator: false, action: action)
    }

    static func separator() -> RetroMenuItem {
        RetroMenuItem(title: "", isSeparator: true, action: nil)
    }
}

/// A dropdown menu drawn in Norton Commander's own light-gray-background,
/// black-text, cyan-highlight style - replacing native NSMenu, whose
/// translucent white background, rounded corners, and blue highlight read
/// as modern macOS chrome and clashed with the rest of the retro UI.
///
/// Presented non-modally, the way a real menu bar behaves: showing a menu
/// does not block interaction with the rest of the app. Clicking anywhere
/// outside the menu (including a different pulldown label, which switches
/// straight to that menu) or in another app dismisses it; picking a row
/// runs that item's action.
///
/// An earlier version used `NSApp.runModal(for:)` to present the menu,
/// which - unlike native NSMenu - genuinely froze every other window in
/// the app until an item was picked: clicking a different pulldown label,
/// or anywhere else, did nothing at all until the open menu was dismissed.
/// This version uses ordinary event monitors instead, exactly so that
/// doesn't happen.
enum RetroMenu {
    /// `point` is in `view`'s own coordinate system and is treated as the
    /// desired top-left corner of the menu (e.g. the bottom-left of the
    /// menu-bar label that was clicked).
    static func popUp(_ items: [RetroMenuItem], at point: NSPoint, in view: NSView) {
        guard let hostWindow = view.window else { return }
        let pointInWindow = view.convert(point, to: nil)
        let pointOnScreen = hostWindow.convertPoint(toScreen: pointInWindow)
        RetroMenuSession.show(items: items, atScreenPoint: pointOnScreen, relativeTo: hostWindow)
    }
}

/// Owns the lifetime of one open RetroMenu: the panel itself, plus the
/// event monitors that watch for a click outside it (dismiss, and for
/// clicks inside this app let the click continue on to whatever it hit -
/// e.g. a different pulldown label - instead of swallowing it).
private final class RetroMenuSession {
    private static var current: RetroMenuSession?

    private let panel: RetroMenuPanel
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var hasEnded = false

    static func show(items: [RetroMenuItem], atScreenPoint point: NSPoint, relativeTo hostWindow: NSWindow) {
        // Only one RetroMenu open at a time - closing whichever one is
        // already up (with no action) before opening the new one is what
        // makes clicking a second pulldown label switch menus directly,
        // the way a real menu bar does, instead of requiring two clicks.
        current?.end(runAction: nil)

        let session = RetroMenuSession(items: items)
        current = session
        session.present(atScreenPoint: point, relativeTo: hostWindow)
    }

    private init(items: [RetroMenuItem]) {
        panel = RetroMenuPanel(items: items)
    }

    private func present(atScreenPoint point: NSPoint, relativeTo hostWindow: NSWindow) {
        panel.setFrameTopLeftPoint(point)

        // Keep the whole menu on-screen even if the anchor is close to a
        // screen edge, the way NSMenu.popUp does automatically.
        if let screenFrame = (hostWindow.screen ?? NSScreen.main)?.visibleFrame {
            var frame = panel.frame
            if frame.maxX > screenFrame.maxX { frame.origin.x -= (frame.maxX - screenFrame.maxX) }
            if frame.minX < screenFrame.minX { frame.origin.x = screenFrame.minX }
            if frame.minY < screenFrame.minY { frame.origin.y = screenFrame.minY }
            panel.setFrame(frame, display: false)
        }

        panel.onChoose = { [weak self] action in self?.end(runAction: action) }
        panel.onCancel = { [weak self] in self?.end(runAction: nil) }

        panel.orderFrontRegardless()
        panel.makeKey()

        // Any click on one of THIS app's windows other than the menu
        // itself dismisses it. Returning the event (rather than nil) lets
        // it keep going to whatever it actually hit, so a click on a
        // different pulldown label opens that menu in the same click.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.window !== self.panel {
                self.end(runAction: nil)
            }
            return event
        }
        // A click in a different app entirely (no NSEvent.window in this
        // app to compare against) also dismisses it.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.end(runAction: nil)
        }
    }

    private func end(runAction action: (() -> Void)?) {
        guard !hasEnded else { return }
        hasEnded = true
        if RetroMenuSession.current === self {
            RetroMenuSession.current = nil
        }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        panel.orderOut(nil)
        action?()
    }
}

private final class RetroMenuPanel: NSPanel {
    var onChoose: ((() -> Void)?) -> Void = { _ in }
    var onCancel: () -> Void = {}
    private let menuView: RetroMenuView

    init(items: [RetroMenuItem]) {
        menuView = RetroMenuView(items: items)
        let size = menuView.intrinsicSize
        menuView.frame = NSRect(origin: .zero, size: size)

        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = true
        hasShadow = true
        // NOT .popUpMenu: that window level was observed to make macOS
        // apply its own automatic vibrancy/translucency pass to the
        // window, visibly muting/graying out the solid colors this view
        // draws (the cyan highlight came out a dull gray-teal instead of
        // matching the bright cyan used everywhere else in the app).
        // .floating sits above the main window without that treatment.
        level = .floating
        // Force light appearance so a system Dark Mode setting can't
        // reinterpret any of these colors either - they're meant to be
        // fixed DOS palette values, not appearance-adaptive ones.
        appearance = NSAppearance(named: .aqua)
        backgroundColor = Theme.menuBarBackground
        isReleasedWhenClosed = false
        contentView = menuView
        initialFirstResponder = menuView
        // NSWindow does not forward mouseMoved events to its views unless
        // this is set - without it, hovering over an item never highlights
        // it (only an actual click/drag does, via mouseDown/mouseDragged).
        acceptsMouseMovedEvents = true

        menuView.onChoose = { [weak self] action in self?.onChoose(action) }
        menuView.onCancel = { [weak self] in self?.onCancel() }
    }

    override var canBecomeKey: Bool { true }

    // Backstop for dismissal paths the click monitors don't cover, e.g.
    // Cmd-Tabbing to another app via the keyboard rather than a click.
    override func resignKey() {
        super.resignKey()
        onCancel()
    }
}

private final class RetroMenuView: NSView {
    private struct Row {
        let item: RetroMenuItem
        let frame: NSRect
    }

    private let items: [RetroMenuItem]
    private var rows: [Row] = []
    private var highlightedRow: Int?
    var onChoose: ((() -> Void)?) -> Void = { _ in }
    var onCancel: () -> Void = {}

    private static let rowHeight: CGFloat = 20
    private static let separatorHeight: CGFloat = 9
    private static let horizontalPadding: CGFloat = 14
    private static let font = Theme.monoFontBold(size: 12)

    var intrinsicSize: NSSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: Self.font]
        let maxTitleWidth = items.map { $0.title.size(withAttributes: attrs).width }.max() ?? 100
        let width = max(150, ceil(maxTitleWidth) + Self.horizontalPadding * 2)
        let height = items.reduce(CGFloat(4)) { partial, item in
            partial + (item.isSeparator ? Self.separatorHeight : Self.rowHeight)
        } + 4
        return NSSize(width: width, height: height)
    }

    init(items: [RetroMenuItem]) {
        self.items = items
        super.init(frame: .zero)
        layoutRows(width: intrinsicSize.width)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private func layoutRows(width: CGFloat) {
        var y: CGFloat = 4
        var built: [Row] = []
        for item in items {
            let h = item.isSeparator ? Self.separatorHeight : Self.rowHeight
            built.append(Row(item: item, frame: NSRect(x: 0, y: y, width: width, height: h)))
            y += h
        }
        rows = built
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.shouldAntialias = false
        Theme.menuBarBackground.setFill()
        bounds.fill()

        let baseAttrs: [NSAttributedString.Key: Any] = [.font: Self.font]

        for (index, row) in rows.enumerated() {
            if row.item.isSeparator {
                let lineY = row.frame.midY
                let path = NSBezierPath()
                path.move(to: NSPoint(x: 6, y: lineY))
                path.line(to: NSPoint(x: bounds.width - 6, y: lineY))
                path.lineWidth = 1
                DOSColor.darkGray.setStroke()
                path.stroke()
                continue
            }

            let isHighlighted = (index == highlightedRow) && row.item.action != nil
            if isHighlighted {
                Theme.menuHighlightBG.setFill()
                row.frame.fill()
            }

            var rowAttrs = baseAttrs
            rowAttrs[.foregroundColor] = row.item.action == nil ? DOSColor.darkGray : Theme.menuBarText
            let textHeight = row.item.title.size(withAttributes: rowAttrs).height
            let textRect = NSRect(
                x: Self.horizontalPadding,
                y: row.frame.minY + (row.frame.height - textHeight) / 2,
                width: row.frame.width - Self.horizontalPadding * 2,
                height: textHeight
            )
            row.item.title.draw(in: textRect, withAttributes: rowAttrs)
        }

        DOSColor.black.setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }

    private func rowIndex(at point: NSPoint) -> Int? {
        rows.firstIndex { $0.frame.contains(point) && !$0.item.isSeparator && $0.item.action != nil }
    }

    override func mouseMoved(with event: NSEvent) { updateHighlight(for: event) }
    override func mouseDragged(with event: NSEvent) { updateHighlight(for: event) }
    override func mouseDown(with event: NSEvent) { updateHighlight(for: event) }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = rowIndex(at: point) {
            choose(index)
        }
    }

    private func updateHighlight(for event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let newHighlight = rowIndex(at: point)
        if newHighlight != highlightedRow {
            highlightedRow = newHighlight
            needsDisplay = true
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125: // Down arrow
            moveHighlight(by: 1)
        case 126: // Up arrow
            moveHighlight(by: -1)
        case 36, 76: // Return / Enter
            if let index = highlightedRow { choose(index) }
        case 53: // Escape
            onCancel()
        default:
            break
        }
    }

    private func moveHighlight(by delta: Int) {
        let selectable = rows.indices.filter { !rows[$0].item.isSeparator && rows[$0].item.action != nil }
        guard !selectable.isEmpty else { return }
        guard let current = highlightedRow, let currentPos = selectable.firstIndex(of: current) else {
            highlightedRow = delta > 0 ? selectable.first : selectable.last
            needsDisplay = true
            return
        }
        let nextPos = (currentPos + delta + selectable.count) % selectable.count
        highlightedRow = selectable[nextPos]
        needsDisplay = true
    }

    private func choose(_ index: Int) {
        guard rows.indices.contains(index), let action = rows[index].item.action else { return }
        onChoose(action)
    }
}

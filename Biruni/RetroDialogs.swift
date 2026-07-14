import AppKit

/// Retro-styled replacement for the old NSAlert-based dialogs (MkDir /
/// Rename-Move / Copy destination / Delete confirmation / error and info
/// messages), drawn in the app's own light-gray dialog-box style
/// (`Theme.dialogBackground` / `dialogBorder` / `dialogText`) instead of
/// native macOS NSAlert chrome - matching how `RetroMenu.swift` replaced
/// native `NSMenu`.
///
/// Unlike RetroMenu, these dialogs ARE genuinely modal - they block the
/// caller until answered, via `NSApp.runModal(for:)`. That's correct here
/// (the same way `NSAlert.runModal()` already blocked before this change):
/// a "type a destination path and press OK" dialog is *supposed* to hold up
/// the calling operation until the user answers. That's a different thing
/// from the earlier RetroMenu bug, where a transient menu - which should
/// never block the rest of the app - was mistakenly made app-modal.
enum RetroDialogs {

    static func prompt(title: String, message: String, defaultValue: String, in window: NSWindow) -> String? {
        let dialog = RetroDialogWindow(title: title, message: message, style: .prompt(defaultValue: defaultValue), okTitle: "OK", destructive: false)
        guard dialog.runModal(relativeTo: window) == .ok else { return nil }
        return dialog.textFieldValue
    }

    static func confirm(title: String, message: String, okTitle: String = "OK", destructive: Bool = false, in window: NSWindow) -> Bool {
        let dialog = RetroDialogWindow(title: title, message: message, style: .confirm, okTitle: okTitle, destructive: destructive)
        return dialog.runModal(relativeTo: window) == .ok
    }

    static func message(title: String, message: String, in window: NSWindow) {
        let dialog = RetroDialogWindow(title: title, message: message, style: .message, okTitle: "OK", destructive: false)
        _ = dialog.runModal(relativeTo: window)
    }

    static func error(_ error: Error, in window: NSWindow) {
        message(title: "Error", message: error.localizedDescription, in: window)
    }
}

private enum RetroDialogStyle {
    case prompt(defaultValue: String)
    case confirm
    case message

    var hasCancel: Bool {
        switch self {
        case .prompt, .confirm: return true
        case .message: return false
        }
    }
}

private enum RetroDialogResponse {
    case ok
    case cancel
}

private final class RetroDialogWindow: NSWindow {
    private let dialogView: RetroDialogView
    private var responseCode: RetroDialogResponse = .cancel

    var textFieldValue: String { dialogView.textFieldValue }

    init(title: String, message: String, style: RetroDialogStyle, okTitle: String, destructive: Bool) {
        dialogView = RetroDialogView(title: title, message: message, style: style, okTitle: okTitle, destructive: destructive)
        let size = dialogView.intrinsicSize
        dialogView.frame = NSRect(origin: .zero, size: size)

        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = true
        hasShadow = true
        level = .modalPanel
        // Force light appearance, same reasoning as RetroMenu: these are
        // fixed DOS palette colors, not appearance-adaptive ones.
        appearance = NSAppearance(named: .aqua)
        backgroundColor = Theme.dialogBackground
        isReleasedWhenClosed = false
        contentView = dialogView
        initialFirstResponder = dialogView.fieldForFirstResponder ?? dialogView

        dialogView.onOK = { [weak self] in self?.finish(.ok) }
        dialogView.onCancel = { [weak self] in self?.finish(.cancel) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override var canBecomeKey: Bool { true }

    func runModal(relativeTo hostWindow: NSWindow) -> RetroDialogResponse {
        let hostFrame = hostWindow.frame
        let x = hostFrame.midX - frame.width / 2
        let y = hostFrame.midY - frame.height / 2
        setFrameOrigin(NSPoint(x: x, y: y))
        makeKeyAndOrderFront(nil)
        NSApp.runModal(for: self)
        orderOut(nil)
        return responseCode
    }

    private func finish(_ response: RetroDialogResponse) {
        responseCode = response
        NSApp.stopModal()
    }
}

private final class RetroDialogView: NSView, NSTextFieldDelegate {
    private let titleText: String
    private let messageText: String
    private let style: RetroDialogStyle

    private var textField: NSTextField?
    private let okButton: RetroDialogButton
    private let cancelButton: RetroDialogButton?

    var onOK: () -> Void = {}
    var onCancel: () -> Void = {}

    private static let messageFont = Theme.monoFont(size: 12)
    private static let titleFont = Theme.monoFontBold(size: 13)
    private static let contentWidth: CGFloat = 320
    private static let padding: CGFloat = 16

    private var messageRect: NSRect = .zero
    private var titleRect: NSRect = .zero
    private var separatorY: CGFloat = 0

    var textFieldValue: String { textField?.stringValue ?? "" }
    var fieldForFirstResponder: NSView? { textField }

    private static func wrappedMessageHeight(_ text: String) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: messageFont]
        return ceil((text as NSString).boundingRect(
            with: NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        ).height)
    }

    var intrinsicSize: NSSize {
        let width = Self.contentWidth + Self.padding * 2
        var y: CGFloat = Self.padding
        y += Self.titleFont.pointSize + 4 + 6 // title line + gap before separator
        y += 8 // separator + spacing after it
        y += Self.wrappedMessageHeight(messageText) + 12
        if case .prompt = style {
            y += 24 + 12
        }
        y += RetroDialogButton.height + Self.padding
        return NSSize(width: width, height: max(y, 110))
    }

    init(title: String, message: String, style: RetroDialogStyle, okTitle: String, destructive: Bool) {
        self.titleText = title
        self.messageText = message
        self.style = style
        self.okButton = RetroDialogButton(title: okTitle, isDestructive: destructive)
        self.cancelButton = style.hasCancel ? RetroDialogButton(title: "Cancel", isDestructive: false) : nil
        super.init(frame: .zero)

        if case .prompt(let defaultValue) = style {
            let field = NSTextField()
            field.stringValue = defaultValue
            field.font = Theme.monoFont(size: 13)
            field.textColor = Theme.dialogText
            field.backgroundColor = .white
            field.drawsBackground = true
            field.isBezeled = true
            field.bezelStyle = .squareBezel
            field.delegate = self
            addSubview(field)
            textField = field
        }

        okButton.onClick = { [weak self] in self?.onOK() }
        addSubview(okButton)
        if let cancelButton {
            cancelButton.onClick = { [weak self] in self?.onCancel() }
            addSubview(cancelButton)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func viewWillDraw() {
        super.viewWillDraw()
        layoutSubviews()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutSubviews()
    }

    private func layoutSubviews() {
        let width = bounds.width
        guard width > 0 else { return }
        var y: CGFloat = Self.padding
        titleRect = NSRect(x: Self.padding, y: y, width: width - Self.padding * 2, height: Self.titleFont.pointSize + 4)
        y += titleRect.height + 6
        separatorY = y
        y += 8

        let msgHeight = Self.wrappedMessageHeight(messageText)
        messageRect = NSRect(x: Self.padding, y: y, width: width - Self.padding * 2, height: msgHeight)
        y += msgHeight + 12

        if let textField {
            textField.frame = NSRect(x: Self.padding, y: y, width: width - Self.padding * 2, height: 24)
            y += 24 + 12
        }

        var buttonX = width - Self.padding
        let okWidth = okButton.intrinsicWidth
        buttonX -= okWidth
        okButton.frame = NSRect(x: buttonX, y: y, width: okWidth, height: RetroDialogButton.height)
        if let cancelButton {
            let cancelWidth = cancelButton.intrinsicWidth
            buttonX -= (cancelWidth + 10)
            cancelButton.frame = NSRect(x: buttonX, y: y, width: cancelWidth, height: RetroDialogButton.height)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.shouldAntialias = false

        Theme.dialogBackground.setFill()
        bounds.fill()

        var titleAttrs: [NSAttributedString.Key: Any] = [.font: Self.titleFont]
        titleAttrs[.foregroundColor] = Theme.dialogText
        let titleSize = titleText.size(withAttributes: titleAttrs)
        let centeredTitleRect = NSRect(x: (bounds.width - titleSize.width) / 2, y: titleRect.minY, width: titleSize.width, height: titleSize.height)
        titleText.draw(in: centeredTitleRect, withAttributes: titleAttrs)

        let sepPath = NSBezierPath()
        sepPath.move(to: NSPoint(x: 8, y: separatorY))
        sepPath.line(to: NSPoint(x: bounds.width - 8, y: separatorY))
        sepPath.lineWidth = 1
        DOSColor.darkGray.setStroke()
        sepPath.stroke()

        var msgAttrs: [NSAttributedString.Key: Any] = [.font: Self.messageFont]
        msgAttrs[.foregroundColor] = Theme.dialogText
        (messageText as NSString).draw(with: messageRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: msgAttrs)

        DOSColor.black.setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 2
        border.stroke()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onOK()      // Return / Enter
        case 53: onCancel()      // Escape
        default: super.keyDown(with: event)
        }
    }

    // Catches Return/Escape while the text field's field editor has focus
    // (NSTextField normally swallows these before they'd reach keyDown above).
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            onOK()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onCancel()
            return true
        }
        return false
    }
}

/// A small clickable "[ OK ]"-style button, drawn the way classic DOS-era
/// dialog boxes rendered their buttons - bracketed text rather than a
/// modern beveled/rounded NSButton - highlighting cyan on hover to match
/// RetroMenu's row highlight.
private final class RetroDialogButton: NSView {
    private let title: String
    private let isDestructive: Bool
    var onClick: () -> Void = {}
    private var isHighlighted = false
    private var trackingArea: NSTrackingArea?

    static let font = Theme.monoFontBold(size: 12)
    static let height: CGFloat = 22

    var intrinsicWidth: CGFloat {
        let label = "[ \(title) ]"
        return ceil(label.size(withAttributes: [.font: Self.font]).width) + 14
    }

    init(title: String, isDestructive: Bool) {
        self.title = title
        self.isDestructive = isDestructive
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.shouldAntialias = false
        if isHighlighted {
            Theme.menuHighlightBG.setFill()
            bounds.fill()
        }
        let label = "[ \(title) ]"
        var attrs: [NSAttributedString.Key: Any] = [.font: Self.font]
        attrs[.foregroundColor] = isDestructive ? DOSColor.red : Theme.dialogText
        let size = label.size(withAttributes: attrs)
        let rect = NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        label.draw(in: rect, withAttributes: attrs)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) { isHighlighted = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHighlighted = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) { onClick() }
    }
}

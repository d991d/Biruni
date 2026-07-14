import AppKit

/// The view F4 swaps into the *opposite* panel's content area, replacing
/// its directory listing until the file is saved/closed - "the opposite
/// panel becomes the editor" instead of opening a separate window the way
/// the old `EditorWindowController` did. Visually matches the panel it's
/// covering: same header/status-line chrome, same retro colors and mono
/// font as the rest of the app.
final class PanelEditorView: NSView {
    let fileURL: URL

    private let textView = EditorTextView()
    private let scrollView = NSScrollView()
    private let titleLabel = RetroControls.label("", font: Theme.monoFontBold(), color: Theme.panelHeader, background: Theme.panelHeaderBG, alignment: .center)
    private let statusLabel = RetroControls.label(" Cmd-S Save   Esc Close (discards unsaved changes) ", font: Theme.monoFont(size: 11), color: Theme.panelHeader)

    private var isDirty = false {
        didSet { updateTitle() }
    }

    /// Fired after the user presses Escape and (if there were unsaved
    /// changes) confirms discarding them. The owning panel is responsible
    /// for actually removing this view and restoring the file listing.
    var onClose: (() -> Void)?

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init(frame: .zero)

        titleLabel.frame = .zero
        statusLabel.frame = .zero

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.panelBackground
        scrollView.borderType = .noBorder

        textView.isEditable = true
        textView.isRichText = false
        textView.font = Theme.monoFont(size: 12)
        textView.textColor = Theme.panelText
        textView.backgroundColor = Theme.panelBackground
        textView.insertionPointColor = Theme.panelMarked
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self
        textView.string = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        textView.onEscape = { [weak self] in
            guard let self else { return }
            if self.confirmClose() { self.onClose?() }
        }

        scrollView.documentView = textView

        addSubview(titleLabel)
        addSubview(scrollView)
        addSubview(statusLabel)

        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func layout() {
        super.layout()
        let headerH: CGFloat = 18
        let statusH: CGFloat = 16
        let margin: CGFloat = 1
        titleLabel.frame = NSRect(x: margin, y: bounds.height - headerH - margin, width: bounds.width - margin * 2, height: headerH)
        statusLabel.frame = NSRect(x: margin, y: margin, width: bounds.width - margin * 2, height: statusH)
        scrollView.frame = NSRect(
            x: margin,
            y: statusH + margin,
            width: bounds.width - margin * 2,
            height: bounds.height - headerH - statusH - margin * 2
        )
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
    }

    func focusEditor() {
        window?.makeFirstResponder(textView)
    }

    private func updateTitle() {
        let name = fileURL.lastPathComponent
        titleLabel.stringValue = " Editing: \(name)\(isDirty ? " (edited)" : "") "
    }

    func save() {
        do {
            try textView.string.write(to: fileURL, atomically: true, encoding: .utf8)
            isDirty = false
        } catch {
            guard let window else { return }
            RetroDialogs.error(error, in: window)
        }
    }

    /// Returns true if it's fine to close now - either there were no
    /// unsaved changes, or the user confirmed discarding them.
    func confirmClose() -> Bool {
        guard isDirty, let window else { return true }
        return RetroDialogs.confirm(
            title: "Unsaved Changes",
            message: "\(fileURL.lastPathComponent) has unsaved changes. Close without saving?",
            okTitle: "Discard",
            destructive: true,
            in: window
        )
    }
}

extension PanelEditorView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        isDirty = true
    }
}

/// Plain NSTextView doesn't treat Escape as anything in particular; AppKit's
/// default key-binding table maps it to `cancelOperation:`, which is the
/// hook to override to actually act on it.
private final class EditorTextView: NSTextView {
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

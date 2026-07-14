import AppKit
import NCCore

/// Shown covering the whole window after a command-line command runs - the
/// way real DOS-era Norton Commander briefly swapped away from its own
/// screen to show whatever the shelled-out command actually printed to the
/// console, then waited for a keypress before returning to the panels.
///
/// Replaces the earlier behavior (a small popup dialog with the captured
/// output only when it was non-empty), which didn't read as "a terminal"
/// at all - this always shows a real prompt line, the full stdout+stderr
/// transcript, and an exit code if the command failed, and dismisses on
/// literally any keypress or click, like a "press any key to continue".
final class ConsoleOutputView: NSView {
    var onDismiss: (() -> Void)?

    private let textView = NSTextView()
    private let scrollView = NSScrollView()
    private let hintLabel = RetroControls.label(
        " Press any key to return to Biruni ",
        font: Theme.monoFontBold(size: 11),
        color: Theme.commandLineBackground,
        background: Theme.commandLineText,
        alignment: .center
    )

    init(promptPath: String, command: String, result: ShellRunner.Result) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.commandLineBackground.cgColor

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.commandLineBackground
        scrollView.borderType = .noBorder

        textView.isEditable = false
        // Deliberately not selectable either: this is a display-only
        // transcript, not a text field, and keeping it non-interactive
        // means the container view always stays first responder, so
        // literally any key or click reliably dismisses it - no edge case
        // where a click into the text view steals focus first.
        textView.isSelectable = false
        textView.font = Theme.monoFont(size: 12)
        textView.backgroundColor = Theme.commandLineBackground
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(Self.buildTranscript(promptPath: promptPath, command: command, result: result))

        scrollView.documentView = textView
        addSubview(scrollView)
        addSubview(hintLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func layout() {
        super.layout()
        let hintH: CGFloat = 18
        hintLabel.frame = NSRect(x: 0, y: bounds.height - hintH, width: bounds.width, height: hintH)
        scrollView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - hintH)
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        // Scroll to the bottom so a long-running command's tail (the part
        // most likely to matter, e.g. an error at the end) is what's
        // visible without the user needing to scroll first.
        textView.scrollToEndOfDocument(nil)
    }

    private static func buildTranscript(promptPath: String, command: String, result: ShellRunner.Result) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let promptAttrs: [NSAttributedString.Key: Any] = [.font: Theme.monoFontBold(size: 12), .foregroundColor: Theme.commandLineText]
        out.append(NSAttributedString(string: "\(promptPath) $ \(command)\n\n", attributes: promptAttrs))

        let bodyAttrs: [NSAttributedString.Key: Any] = [.font: Theme.monoFont(size: 12), .foregroundColor: Theme.panelText]
        let combinedOutput = result.stdout + result.stderr
        if combinedOutput.isEmpty {
            out.append(NSAttributedString(string: "(no output)\n", attributes: bodyAttrs))
        } else {
            out.append(NSAttributedString(string: combinedOutput.hasSuffix("\n") ? combinedOutput : combinedOutput + "\n", attributes: bodyAttrs))
        }

        if result.exitCode != 0 {
            let errAttrs: [NSAttributedString.Key: Any] = [.font: Theme.monoFontBold(size: 12), .foregroundColor: DOSColor.lightRed]
            out.append(NSAttributedString(string: "\n[exit code \(result.exitCode)]\n", attributes: errAttrs))
        }
        return out
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) { onDismiss?() }
    override func mouseDown(with event: NSEvent) { onDismiss?() }
}

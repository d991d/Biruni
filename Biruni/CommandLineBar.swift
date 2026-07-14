import AppKit

/// Text field used for the command line at the bottom of the screen.
/// Return submits, Escape returns focus to the active panel.
final class CommandLineField: NSTextField {
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: // Return / Enter
            onSubmit?()
        case 53: // Escape
            onCancel?()
        default:
            super.keyDown(with: event)
        }
    }
}

/// NC's command line: a prompt showing the active panel's directory,
/// followed by an editable field where you can type shell commands that
/// run in that directory (just like typing at the DOS prompt below the
/// panels in the real thing).
final class CommandLineBar: NSView {

    let promptLabel = RetroControls.label("$ ", font: Theme.monoFont(size: 12), color: Theme.commandLineText)
    let field = CommandLineField()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.commandLineBackground.cgColor

        field.font = Theme.monoFont(size: 12)
        field.textColor = Theme.commandLineText
        field.backgroundColor = Theme.commandLineBackground
        field.drawsBackground = true
        field.isBezeled = false
        field.focusRingType = .none

        promptLabel.translatesAutoresizingMaskIntoConstraints = false
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(promptLabel)
        addSubview(field)

        NSLayoutConstraint.activate([
            promptLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            promptLabel.topAnchor.constraint(equalTo: topAnchor),
            promptLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
            promptLabel.widthAnchor.constraint(equalToConstant: 90),

            field.leadingAnchor.constraint(equalTo: promptLabel.trailingAnchor, constant: 2),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            field.topAnchor.constraint(equalTo: topAnchor),
            field.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func setPromptPath(_ path: String) {
        let shortened = path.count > 40 ? "..." + path.suffix(37) : path
        promptLabel.stringValue = "\(shortened) $ "
    }
}

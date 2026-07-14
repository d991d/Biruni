import AppKit

/// A plain NSSplitView with the divider recolored to match the retro
/// theme instead of the default macOS gray.
final class RetroSplitView: NSSplitView {
    override var dividerColor: NSColor { Theme.panelHeaderBG }
    override var dividerThickness: CGFloat { 2 }
}

/// Lays out the four bands of the main screen (pulldown menu bar, dual
/// panels, command line, function-key bar).
///
/// The two panels live inside a plain `NSSplitView` rather than a
/// hand-rolled pair of containers with manual frame or constraint math.
/// Two earlier layout implementations (manual `resizeSubviews` frames,
/// then Auto Layout constraints on two custom container views) both
/// produced the exact same symptom - the left pane never actually
/// appearing - which pointed at something more fundamental than either
/// specific layout technique. NSSplitView is Apple's own dual-pane
/// widget, used throughout macOS (Xcode, Mail, Finder); handing pane
/// arrangement to it removes essentially all custom positioning code as
/// a suspect.
final class MainRootView: NSView {

    let menuBar = PulldownMenuBarView()
    let splitView = RetroSplitView()
    let commandLine = CommandLineBar(frame: .zero)
    let funcKeyBar = FunctionKeyBarView()

    private static let menuBarHeight: CGFloat = 20
    private static let commandLineHeight: CGFloat = 20
    private static let funcKeyBarHeight: CGFloat = 22

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.panelBackground.cgColor

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.wantsLayer = true
        splitView.layer?.backgroundColor = Theme.panelBackground.cgColor

        for subview in [menuBar, splitView, commandLine, funcKeyBar] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }

        NSLayoutConstraint.activate([
            menuBar.topAnchor.constraint(equalTo: topAnchor),
            menuBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            menuBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            menuBar.heightAnchor.constraint(equalToConstant: Self.menuBarHeight),

            funcKeyBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            funcKeyBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            funcKeyBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            funcKeyBar.heightAnchor.constraint(equalToConstant: Self.funcKeyBarHeight),

            commandLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            commandLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            commandLine.bottomAnchor.constraint(equalTo: funcKeyBar.topAnchor),
            commandLine.heightAnchor.constraint(equalToConstant: Self.commandLineHeight),

            splitView.topAnchor.constraint(equalTo: menuBar.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: commandLine.topAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
}

import AppKit

/// The classic 16-color DOS console palette, as Norton Commander used it.
/// Named after the standard CGA/EGA color indices so the mapping to the
/// original app is obvious.
enum DOSColor {
    static let black       = NSColor(calibratedRed: 0.00, green: 0.00, blue: 0.00, alpha: 1)
    static let blue        = NSColor(calibratedRed: 0.00, green: 0.00, blue: 0.67, alpha: 1)
    static let green       = NSColor(calibratedRed: 0.00, green: 0.67, blue: 0.00, alpha: 1)
    static let cyan        = NSColor(calibratedRed: 0.00, green: 0.67, blue: 0.67, alpha: 1)
    static let red         = NSColor(calibratedRed: 0.67, green: 0.00, blue: 0.00, alpha: 1)
    static let magenta     = NSColor(calibratedRed: 0.67, green: 0.00, blue: 0.67, alpha: 1)
    static let brown       = NSColor(calibratedRed: 0.67, green: 0.33, blue: 0.00, alpha: 1)
    static let lightGray   = NSColor(calibratedRed: 0.67, green: 0.67, blue: 0.67, alpha: 1)
    static let darkGray    = NSColor(calibratedRed: 0.33, green: 0.33, blue: 0.33, alpha: 1)
    static let brightBlue  = NSColor(calibratedRed: 0.33, green: 0.33, blue: 1.00, alpha: 1)
    static let brightGreen = NSColor(calibratedRed: 0.33, green: 1.00, blue: 0.33, alpha: 1)
    static let brightCyan  = NSColor(calibratedRed: 0.33, green: 1.00, blue: 1.00, alpha: 1)
    static let lightRed    = NSColor(calibratedRed: 1.00, green: 0.33, blue: 0.33, alpha: 1)
    static let lightMagenta = NSColor(calibratedRed: 1.00, green: 0.33, blue: 1.00, alpha: 1)
    static let yellow      = NSColor(calibratedRed: 1.00, green: 1.00, blue: 0.33, alpha: 1)
    static let white       = NSColor(calibratedRed: 1.00, green: 1.00, blue: 1.00, alpha: 1)
}

/// Maps DOS colors onto the specific NC UI roles, so views reference
/// `Theme.panelBackground` etc. rather than raw palette entries.
enum Theme {
    static let panelBackground   = DOSColor.blue
    static let panelText         = DOSColor.lightGray
    static let panelDirectory    = DOSColor.white
    static let panelArchive      = DOSColor.lightMagenta
    static let panelMarked       = DOSColor.yellow
    static let panelHeader       = DOSColor.white
    static let panelHeaderBG     = DOSColor.cyan
    static let cursorBackground  = DOSColor.cyan
    static let cursorText        = DOSColor.black
    static let inactiveCursorBG  = DOSColor.darkGray

    static let statusBarBackground = DOSColor.lightGray
    static let statusBarText       = DOSColor.black

    static let funcKeyBarBackground = DOSColor.black
    static let funcKeyNumber        = DOSColor.white
    static let funcKeyLabelBG       = DOSColor.cyan
    static let funcKeyLabelText     = DOSColor.black

    static let commandLineText = DOSColor.yellow
    static let commandLineBackground = DOSColor.black

    static let menuBarBackground = DOSColor.lightGray
    static let menuBarText       = DOSColor.black
    static let menuHighlightBG   = DOSColor.cyan

    static let dialogBackground = DOSColor.lightGray
    static let dialogBorder     = DOSColor.black
    static let dialogText       = DOSColor.black

    // Menlo reads a lot closer to a DOS text-mode font than SF Mono does -
    // less rounded, chunkier at small sizes. Falls back to the system
    // monospace font on the off chance Menlo isn't present.
    static func monoFont(size: CGFloat = 13) -> NSFont {
        NSFont(name: "Menlo-Regular", size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func monoFontBold(size: CGFloat = 13) -> NSFont {
        NSFont(name: "Menlo-Bold", size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
    }
}

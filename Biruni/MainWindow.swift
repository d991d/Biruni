import AppKit

/// Custom NSWindow so the F1-F10 keys always trigger NC actions no matter
/// which subview (table, command line) currently has keyboard focus.
/// `performKeyEquivalent` runs before normal first-responder keyDown
/// dispatch, which is exactly the hook AppKit provides for "global to this
/// window" shortcuts like this.
final class MainWindow: NSWindow {

    var onFunctionKey: ((Int) -> Void)?

    /// Cmd-key shortcuts that need to work no matter what has focus, the
    /// same reasoning as `onFunctionKey` above - used by the inline F4
    /// editor (Cmd-S to save) once it's embedded in a panel instead of
    /// living in its own `KeyEquivalentWindow`.
    var onCommandKeyEquivalent: [(String, () -> Void)] = []

    private static let functionKeyCodes: [UInt16: Int] = [
        122: 1, 120: 2, 99: 3, 118: 4, 96: 5,
        97: 6, 98: 7, 100: 8, 101: 9, 109: 10
    ]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, let number = Self.functionKeyCodes[event.keyCode] {
            onFunctionKey?(number)
            return true
        }
        if event.type == .keyDown, event.modifierFlags.contains(.command), let chars = event.charactersIgnoringModifiers {
            for (key, action) in onCommandKeyEquivalent where chars == key {
                action()
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

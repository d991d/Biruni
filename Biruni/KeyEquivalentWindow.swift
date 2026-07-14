import AppKit

/// NSWindow doesn't expose a per-window menu, so single-window utility
/// windows (viewer/editor) that want a Cmd-key shortcut without a full
/// app menu bar item override `performKeyEquivalent` directly.
final class KeyEquivalentWindow: NSWindow {
    var onCommandKeyEquivalent: [(String, () -> Void)] = []

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), let chars = event.charactersIgnoringModifiers {
            for (key, action) in onCommandKeyEquivalent where chars == key {
                action()
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

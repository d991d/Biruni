import AppKit

/// F3 "Quick View": a read-only window showing a text file's contents in
/// the retro palette. For binary files, falls back to a hex dump of the
/// first chunk of the file, which is what NC's viewer did too.
final class ViewerWindowController: NSWindowController {

    convenience init(fileURL: URL) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "View: \(fileURL.lastPathComponent)"
        window.backgroundColor = Theme.panelBackground

        let scrollView = NSScrollView(frame: window.contentView!.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.panelBackground

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = Theme.monoFont(size: 12)
        textView.textColor = Theme.panelText
        textView.backgroundColor = Theme.panelBackground
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.string = Self.loadDisplayText(for: fileURL)

        scrollView.documentView = textView
        window.contentView = scrollView

        self.init(window: window)
    }

    private static func loadDisplayText(for url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else {
            return "(could not read file)"
        }
        if let text = String(data: data, encoding: .utf8), !text.contains("\0") {
            return text
        }
        // Binary fallback: classic hex + ASCII dump of the first 8 KB.
        let chunk = data.prefix(8192)
        return hexDump(chunk)
    }

    private static func hexDump(_ data: Data) -> String {
        var lines: [String] = []
        let bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + 16, bytes.count)
            let slice = bytes[offset..<end]
            let hex = slice.map { String(format: "%02X", $0) }.joined(separator: " ")
            let ascii = slice.map { (32...126).contains($0) ? String(UnicodeScalar($0)) : "." }.joined()
            let offsetStr = String(format: "%08X", offset)
            lines.append("\(offsetStr)  \(hex.padding(toLength: 48, withPad: " ", startingAt: 0))  \(ascii)")
            offset = end
        }
        return lines.joined(separator: "\n")
    }
}

import Foundation

/// A single line in NC's F2 user menu: a hotkey, a label, and the shell
/// command it runs (in the active panel's directory).
public struct UserMenuItem: Identifiable, Equatable {
    public let id = UUID()
    public var hotkey: Character
    public var label: String
    public var command: String

    public init(hotkey: Character, label: String, command: String) {
        self.hotkey = hotkey
        self.label = label
        self.command = command
    }
}

/// Reads/writes NC's classic `nc.menu`-style file so the F2 menu is
/// user-editable without touching code. File format, one entry per line:
///
///   <hotkey>|<label>|<shell command>
///
/// Blank lines and lines starting with '#' are ignored. If the file doesn't
/// exist yet, a starter menu with a few genuinely useful entries is written.
public enum UserMenuStore {

    public static var menuFileURL: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("nc-mac", isDirectory: true)
        return base.appendingPathComponent("menu.txt")
    }

    public static func load() -> [UserMenuItem] {
        let url = menuFileURL
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            let defaults = defaultMenu()
            try? save(defaults)
            return defaults
        }
        var items: [UserMenuItem] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let fields = trimmed.components(separatedBy: "|")
            guard fields.count >= 3, let hotkey = fields[0].first else { continue }
            items.append(UserMenuItem(hotkey: hotkey, label: fields[1], command: fields[2...].joined(separator: "|")))
        }
        return items.isEmpty ? defaultMenu() : items
    }

    public static func save(_ items: [UserMenuItem]) throws {
        let url = menuFileURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var lines = ["# Biruni - user menu (F2)", "# Format: hotkey|label|shell command", ""]
        for item in items {
            lines.append("\(item.hotkey)|\(item.label)|\(item.command)")
        }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func defaultMenu() -> [UserMenuItem] {
        [
            UserMenuItem(hotkey: "1", label: "List files by size", command: "ls -lhS"),
            UserMenuItem(hotkey: "2", label: "Show disk usage here", command: "du -sh ./* 2>/dev/null | sort -h"),
            UserMenuItem(hotkey: "3", label: "Git status", command: "git status"),
            UserMenuItem(hotkey: "4", label: "Open Terminal here", command: "open -a Terminal .")
        ]
    }
}

import Foundation

/// Formats file sizes and dates the way Norton Commander did:
/// right-aligned, comma-grouped byte counts, "<DIR>" for directories.
public enum NCFormat {

    public static func size(_ entry: FileEntry) -> String {
        switch entry.kind {
        case .parentDirectory, .directory:
            return "<DIR>"
        default:
            return grouped(entry.size)
        }
    }

    public static func grouped(_ value: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    public static func date(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yy"
        return formatter.string(from: date)
    }

    public static func time(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// Human-readable size for status lines, e.g. "1.2 MB".
    public static func humanSize(_ bytes: Int64) -> String {
        let units = ["bytes", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        if unitIndex == 0 {
            return "\(bytes) \(units[0])"
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }
}

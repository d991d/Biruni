import Foundation

/// A single row in an NC-style panel: either a real filesystem entry,
/// or a virtual entry inside an archive being browsed as a directory.
public struct FileEntry: Identifiable, Equatable, Hashable {

    public enum Kind: Equatable, Hashable {
        case parentDirectory      // the ".." entry
        case directory
        case regularFile
        case symlink
        case archive               // a file that can be entered like a directory (.zip/.tar/.tar.gz/.tgz)
    }

    public let id: String          // stable identity: full path (or archive-relative path)
    public let name: String
    public let kind: Kind
    public let size: Int64
    public let modificationDate: Date?
    public let permissions: String? // e.g. "rwxr-xr-x", nil for archive entries we can't stat
    public let isMarked: Bool

    public init(
        id: String,
        name: String,
        kind: Kind,
        size: Int64,
        modificationDate: Date?,
        permissions: String? = nil,
        isMarked: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.size = size
        self.modificationDate = modificationDate
        self.permissions = permissions
        self.isMarked = isMarked
    }

    public var isDirectoryLike: Bool {
        kind == .directory || kind == .parentDirectory
    }

    public func markedCopy(_ marked: Bool) -> FileEntry {
        FileEntry(
            id: id, name: name, kind: kind, size: size,
            modificationDate: modificationDate, permissions: permissions,
            isMarked: marked
        )
    }

    /// Recognized archive extensions that get treated as "enterable" containers.
    public static let archiveExtensions: Set<String> = [
        "zip", "tar", "gz", "tgz", "tar.gz"
    ]

    public static func kindForRegularFile(name: String) -> Kind {
        let lower = name.lowercased()
        if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz")
            || lower.hasSuffix(".zip") || lower.hasSuffix(".tar") {
            return .archive
        }
        return .regularFile
    }
}

import Foundation

public enum NCError: Error, LocalizedError {
    case notADirectory(String)
    case alreadyExists(String)
    case operationFailed(String)
    case cannotDeleteNonEmpty(String)

    public var errorDescription: String? {
        switch self {
        case .notADirectory(let p): return "Not a directory: \(p)"
        case .alreadyExists(let p): return "Already exists: \(p)"
        case .operationFailed(let msg): return msg
        case .cannotDeleteNonEmpty(let p): return "Directory not empty: \(p)"
        }
    }
}

/// Wraps FileManager to provide the directory listing + file operations
/// an NC-style panel needs. Operates purely on real filesystem paths;
/// archive browsing is handled separately by ArchiveService.
public final class FileSystemService {

    public init() {}

    private let fm = FileManager.default

    /// Lists the contents of `path`, sorted the way NC sorts by default:
    /// directories first (alphabetically), then files (alphabetically),
    /// with a leading ".." entry unless we're at the filesystem root.
    public func listDirectory(at path: String, showHidden: Bool) throws -> [FileEntry] {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            throw NCError.notADirectory(path)
        }

        let names = try fm.contentsOfDirectory(atPath: path)
        var dirs: [FileEntry] = []
        var files: [FileEntry] = []

        for name in names {
            if !showHidden && name.hasPrefix(".") { continue }
            let fullPath = (path as NSString).appendingPathComponent(name)
            guard let attrs = try? fm.attributesOfItem(atPath: fullPath) else { continue }

            let fileType = attrs[.type] as? FileAttributeType
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let modDate = attrs[.modificationDate] as? Date
            let perms = permissionString(attrs)

            let entry: FileEntry
            if fileType == .typeDirectory {
                entry = FileEntry(id: fullPath, name: name, kind: .directory, size: 0, modificationDate: modDate, permissions: perms)
                dirs.append(entry)
            } else if fileType == .typeSymbolicLink {
                entry = FileEntry(id: fullPath, name: name, kind: .symlink, size: size, modificationDate: modDate, permissions: perms)
                files.append(entry)
            } else {
                let kind = FileEntry.kindForRegularFile(name: name)
                entry = FileEntry(id: fullPath, name: name, kind: kind, size: size, modificationDate: modDate, permissions: perms)
                files.append(entry)
            }
        }

        dirs.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        files.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        var result: [FileEntry] = []
        if (path as NSString).standardizingPath != "/" {
            let parent = (path as NSString).deletingLastPathComponent
            result.append(FileEntry(id: parent.isEmpty ? "/" : parent, name: "..", kind: .parentDirectory, size: 0, modificationDate: nil))
        }
        result.append(contentsOf: dirs)
        result.append(contentsOf: files)
        return result
    }

    private func permissionString(_ attrs: [FileAttributeKey: Any]) -> String? {
        guard let posix = (attrs[.posixPermissions] as? NSNumber)?.uint16Value else { return nil }
        let type = attrs[.type] as? FileAttributeType
        var s = (type == .typeDirectory) ? "d" : "-"
        let bits: [(UInt16, String)] = [
            (0o400, "r"), (0o200, "w"), (0o100, "x"),
            (0o040, "r"), (0o020, "w"), (0o010, "x"),
            (0o004, "r"), (0o002, "w"), (0o001, "x")
        ]
        for (mask, ch) in bits {
            s += (posix & mask) != 0 ? ch : "-"
        }
        return s
    }

    // MARK: - Operations

    public func makeDirectory(named name: String, in parentPath: String) throws {
        let target = (parentPath as NSString).appendingPathComponent(name)
        if fm.fileExists(atPath: target) {
            throw NCError.alreadyExists(target)
        }
        try fm.createDirectory(atPath: target, withIntermediateDirectories: false)
    }

    public func rename(from oldPath: String, to newName: String) throws {
        let parent = (oldPath as NSString).deletingLastPathComponent
        let target = (parent as NSString).appendingPathComponent(newName)
        if fm.fileExists(atPath: target) {
            throw NCError.alreadyExists(target)
        }
        try fm.moveItem(atPath: oldPath, toPath: target)
    }

    public func move(from sourcePath: String, toDirectory destDir: String) throws {
        let name = (sourcePath as NSString).lastPathComponent
        let target = (destDir as NSString).appendingPathComponent(name)
        if fm.fileExists(atPath: target) {
            throw NCError.alreadyExists(target)
        }
        try fm.moveItem(atPath: sourcePath, toPath: target)
    }

    public func copy(from sourcePath: String, toDirectory destDir: String, overwrite: Bool = false) throws {
        let name = (sourcePath as NSString).lastPathComponent
        let target = (destDir as NSString).appendingPathComponent(name)
        if fm.fileExists(atPath: target) {
            if overwrite {
                try fm.removeItem(atPath: target)
            } else {
                throw NCError.alreadyExists(target)
            }
        }
        try fm.copyItem(atPath: sourcePath, toPath: target)
    }

    public func delete(path: String) throws {
        try fm.removeItem(atPath: path)
    }

    public func fileSizeAndDate(at path: String) -> (Int64, Date?)? {
        guard let attrs = try? fm.attributesOfItem(atPath: path) else { return nil }
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let date = attrs[.modificationDate] as? Date
        return (size, date)
    }

    public func homeDirectoryPath() -> String {
        fm.homeDirectoryForCurrentUser.path
    }
}

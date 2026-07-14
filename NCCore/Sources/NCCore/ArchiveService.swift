import Foundation

/// One entry as reported by `unzip -l` / `tar -tvf`, with a slash-separated
/// path relative to the archive root (e.g. "folder/sub/file.txt").
public struct ArchiveRawEntry {
    public let path: String
    public let size: Int64
    public let dateString: String

    public init(path: String, size: Int64, dateString: String) {
        self.path = path
        self.size = size
        self.dateString = dateString
    }
}

/// Lets an NC panel "enter" a .zip/.tar/.tar.gz/.tgz file exactly like a
/// directory, by shelling out to the system's `unzip` and `tar` rather than
/// linking a compression library. This keeps the app dependency-free but
/// means listing/extraction depend on those command-line tools being present
/// (they ship with macOS by default).
public final class ArchiveService {

    public init() {}

    public func isSupported(_ url: URL) -> Bool {
        let lower = url.lastPathComponent.lowercased()
        return lower.hasSuffix(".zip") || lower.hasSuffix(".tar")
            || lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz")
    }

    /// Flat listing of every entry in the archive. Callers slice this into
    /// per-directory views with `children(of:in:)`.
    public func listRawEntries(archiveURL: URL) -> [ArchiveRawEntry] {
        let path = archiveURL.path
        let lower = path.lowercased()
        if lower.hasSuffix(".zip") {
            return parseZipListing(ShellRunner.run("unzip", ["-l", path]).stdout)
        } else if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz") {
            return parseTarListing(ShellRunner.run("tar", ["-tzvf", path]).stdout)
        } else if lower.hasSuffix(".tar") {
            return parseTarListing(ShellRunner.run("tar", ["-tvf", path]).stdout)
        }
        return []
    }

    /// Synthesizes an NC-style directory listing for `internalDir` (""
    /// for archive root, otherwise a slash-terminated path like "folder/")
    /// from the flat raw entry list, the same way NC shows a "..".
    public func children(of internalDir: String, in rawEntries: [ArchiveRawEntry], includeParent: Bool) -> [FileEntry] {
        var seenDirs = Set<String>()
        var dirs: [FileEntry] = []
        var files: [FileEntry] = []

        for raw in rawEntries {
            guard raw.path.hasPrefix(internalDir) else { continue }
            let remainder = String(raw.path.dropFirst(internalDir.count))
            guard !remainder.isEmpty else { continue }

            if let slashIndex = remainder.firstIndex(of: "/") {
                let dirName = String(remainder[remainder.startIndex..<slashIndex])
                if !dirName.isEmpty, !seenDirs.contains(dirName) {
                    seenDirs.insert(dirName)
                    dirs.append(FileEntry(
                        id: internalDir + dirName + "/",
                        name: dirName,
                        kind: .directory,
                        size: 0,
                        modificationDate: nil
                    ))
                }
            } else {
                files.append(FileEntry(
                    id: internalDir + remainder,
                    name: remainder,
                    kind: FileEntry.kindForRegularFile(name: remainder),
                    size: raw.size,
                    modificationDate: nil
                ))
            }
        }

        dirs.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        files.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        var result: [FileEntry] = []
        if includeParent {
            let parent = parentOf(internalDir)
            result.append(FileEntry(id: parent, name: "..", kind: .parentDirectory, size: 0, modificationDate: nil))
        }
        result.append(contentsOf: dirs)
        result.append(contentsOf: files)
        return result
    }

    public func parentOf(_ internalDir: String) -> String {
        // internalDir is "" (root) or "a/b/" -> parent is "a/" ; parent of "a/" is "".
        guard !internalDir.isEmpty else { return "" }
        let trimmed = String(internalDir.dropLast()) // drop trailing slash
        guard let lastSlash = trimmed.lastIndex(of: "/") else { return "" }
        return String(trimmed[trimmed.startIndex...lastSlash])
    }

    /// Extracts a single entry (file or directory subtree) to `destinationDir`.
    public func extract(archiveURL: URL, internalEntryPath: String, isDirectory: Bool, to destinationDir: String) throws {
        let path = archiveURL.path
        let lower = path.lowercased()
        try FileManager.default.createDirectory(atPath: destinationDir, withIntermediateDirectories: true)

        if lower.hasSuffix(".zip") {
            let pattern = isDirectory ? internalEntryPath + "*" : internalEntryPath
            let result = ShellRunner.run("unzip", ["-o", path, pattern, "-d", destinationDir])
            if result.exitCode != 0 {
                throw NCError.operationFailed(result.stderr.isEmpty ? "unzip failed" : result.stderr)
            }
        } else {
            var args: [String] = []
            if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz") {
                args = ["-xzf", path, "-C", destinationDir, internalEntryPath]
            } else {
                args = ["-xf", path, "-C", destinationDir, internalEntryPath]
            }
            let result = ShellRunner.run("tar", args)
            if result.exitCode != 0 {
                throw NCError.operationFailed(result.stderr.isEmpty ? "tar failed" : result.stderr)
            }
        }
    }

    public func extractAll(archiveURL: URL, to destinationDir: String) throws {
        let path = archiveURL.path
        let lower = path.lowercased()
        try FileManager.default.createDirectory(atPath: destinationDir, withIntermediateDirectories: true)

        if lower.hasSuffix(".zip") {
            let result = ShellRunner.run("unzip", ["-o", path, "-d", destinationDir])
            if result.exitCode != 0 {
                throw NCError.operationFailed(result.stderr.isEmpty ? "unzip failed" : result.stderr)
            }
        } else {
            let args = (lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz"))
                ? ["-xzf", path, "-C", destinationDir]
                : ["-xf", path, "-C", destinationDir]
            let result = ShellRunner.run("tar", args)
            if result.exitCode != 0 {
                throw NCError.operationFailed(result.stderr.isEmpty ? "tar failed" : result.stderr)
            }
        }
    }

    // MARK: - Parsing

    private func parseZipListing(_ output: String) -> [ArchiveRawEntry] {
        var entries: [ArchiveRawEntry] = []
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = rawLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 4, let length = Int64(parts[0]) else { continue }
            let name = parts[3...].joined(separator: " ")
            guard !name.isEmpty, name.lowercased() != "name" else { continue }
            entries.append(ArchiveRawEntry(path: name, size: length, dateString: parts.count > 1 ? parts[1] : ""))
        }
        return entries
    }

    private func parseTarListing(_ output: String) -> [ArchiveRawEntry] {
        var entries: [ArchiveRawEntry] = []
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = rawLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            // permissions, links, owner, group, size, month, day, time/year, name...
            guard parts.count >= 9, let size = Int64(parts[4]) else { continue }
            var name = parts[8...].joined(separator: " ")
            if let arrowRange = name.range(of: " -> ") {
                name = String(name[name.startIndex..<arrowRange.lowerBound])
            }
            if name.hasSuffix("/") {
                name = String(name.dropLast())
                // Directory entries are re-derived from file paths in children(of:in:),
                // but keeping them here too is harmless since children() dedupes by name.
                name += "/"
            }
            entries.append(ArchiveRawEntry(path: name, size: size, dateString: "\(parts[5]) \(parts[6]) \(parts[7])"))
        }
        return entries
    }
}

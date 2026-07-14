import Foundation

/// Where a panel is currently "looking": a real directory, or a spot
/// inside an archive that's being browsed like one.
public enum PanelLocation: Equatable {
    case filesystem(path: String)
    case archive(archiveURL: URL, internalPath: String)

    public var displayPath: String {
        switch self {
        case .filesystem(let path):
            return path
        case .archive(let url, let internalPath):
            return url.path + " :: /" + internalPath
        }
    }

    public var isInsideArchive: Bool {
        if case .archive = self { return true }
        return false
    }

    /// A real, on-disk directory usable as a shell cwd / copy destination.
    /// For archive locations this is the directory containing the archive.
    public var nearestRealDirectory: String {
        switch self {
        case .filesystem(let path):
            return path
        case .archive(let url, _):
            return url.deletingLastPathComponent().path
        }
    }
}

/// Pure application logic for one NC panel: current location, the entries
/// shown, the cursor, and the set of marked (selected) file names. Holds no
/// UI references so it can be driven and unit-tested independently of AppKit.
public final class PanelState {

    public let fs: FileSystemService
    public let archives: ArchiveService

    public private(set) var location: PanelLocation
    public private(set) var entries: [FileEntry] = []
    public var markedNames: Set<String> = []
    public var cursorIndex: Int = 0
    public var showHidden: Bool = false

    // Cache of the flat archive listing for the archive we're currently inside,
    // so re-entering subdirectories doesn't re-shell-out every time.
    private var cachedArchiveURL: URL?
    private var cachedArchiveEntries: [ArchiveRawEntry] = []

    public init(startPath: String, fs: FileSystemService = FileSystemService(), archives: ArchiveService = ArchiveService()) {
        self.location = .filesystem(path: startPath)
        self.fs = fs
        self.archives = archives
    }

    /// Jumps straight to a real filesystem path (used by "Go to folder",
    /// swapping panels, restoring the last-used directory, etc.). Caller
    /// is expected to call refresh() afterwards.
    public func jump(to path: String) {
        location = .filesystem(path: path)
        markedNames.removeAll()
        cursorIndex = 0
    }

    public func jump(to newLocation: PanelLocation) {
        location = newLocation
        markedNames.removeAll()
        cursorIndex = 0
    }

    public func refresh() throws {
        switch location {
        case .filesystem(let path):
            entries = try fs.listDirectory(at: path, showHidden: showHidden)
        case .archive(let url, let internalPath):
            let raw = rawArchiveEntries(for: url)
            entries = archives.children(of: internalPath, in: raw, includeParent: true)
        }
        markedNames.formIntersection(Set(entries.map(\.name)))
        cursorIndex = min(cursorIndex, max(0, entries.count - 1))
    }

    private func rawArchiveEntries(for url: URL) -> [ArchiveRawEntry] {
        if cachedArchiveURL == url {
            return cachedArchiveEntries
        }
        let raw = archives.listRawEntries(archiveURL: url)
        cachedArchiveURL = url
        cachedArchiveEntries = raw
        return raw
    }

    /// Handles pressing Enter / double-click on a row: descends into
    /// directories and archives, or goes up on "..". Returns true if the
    /// location changed. On success, `entries` has already been refreshed
    /// for the new location - the caller doesn't need to call refresh()
    /// separately. If the new location can't actually be listed (e.g. a
    /// permission-protected folder like Desktop/Documents/Downloads before
    /// the user has granted access), `location` is left unchanged and the
    /// underlying error is thrown, so the panel never ends up pointed at a
    /// directory it couldn't read.
    @discardableResult
    public func activate(_ entry: FileEntry) throws -> Bool {
        guard let target = activationTarget(for: entry) else { return false }

        let previousLocation = location
        let previousEntries = entries
        let previousCursor = cursorIndex

        location = target
        markedNames.removeAll()
        cursorIndex = 0

        do {
            try refresh()
            return true
        } catch {
            // Roll back completely so the panel stays in a consistent,
            // still-navigable state instead of pointing at a location it
            // couldn't actually list.
            location = previousLocation
            entries = previousEntries
            cursorIndex = previousCursor
            throw error
        }
    }

    private func activationTarget(for entry: FileEntry) -> PanelLocation? {
        switch entry.kind {
        case .parentDirectory:
            switch location {
            case .filesystem(let path):
                let parent = (path as NSString).deletingLastPathComponent
                return .filesystem(path: parent.isEmpty ? "/" : parent)
            case .archive(let url, let internalPath):
                if internalPath.isEmpty {
                    // already at archive root's ".." -> leave the archive entirely
                    return .filesystem(path: url.deletingLastPathComponent().path)
                }
                return .archive(archiveURL: url, internalPath: archives.parentOf(internalPath))
            }

        case .directory:
            switch location {
            case .filesystem(let path):
                return .filesystem(path: (path as NSString).appendingPathComponent(entry.name))
            case .archive(let url, let internalPath):
                return .archive(archiveURL: url, internalPath: internalPath + entry.name + "/")
            }

        case .archive:
            // Only enterable when we're on the real filesystem; NC didn't
            // support archives-within-archives without extracting first.
            guard case .filesystem(let path) = location else { return nil }
            let archiveURL = URL(fileURLWithPath: (path as NSString).appendingPathComponent(entry.name))
            return .archive(archiveURL: archiveURL, internalPath: "")

        case .regularFile, .symlink:
            return nil
        }
    }

    public func toggleMark(at index: Int) {
        guard entries.indices.contains(index) else { return }
        let entry = entries[index]
        guard entry.kind != .parentDirectory else { return }
        if markedNames.contains(entry.name) {
            markedNames.remove(entry.name)
        } else {
            markedNames.insert(entry.name)
        }
    }

    /// Entries to act on for F5/F6/F8: the marked set, or just the cursor
    /// row if nothing is marked (NC's behavior).
    public func selectionForOperation() -> [FileEntry] {
        if markedNames.isEmpty {
            guard entries.indices.contains(cursorIndex) else { return [] }
            let entry = entries[cursorIndex]
            return entry.kind == .parentDirectory ? [] : [entry]
        }
        return entries.filter { markedNames.contains($0.name) }
    }

    public func totalMarkedSize() -> Int64 {
        selectionForOperation().reduce(0) { $0 + $1.size }
    }
}

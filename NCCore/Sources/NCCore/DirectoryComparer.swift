import Foundation

/// Implements NC's "Compare Directories" command (Files menu): marks, in
/// each panel, the entries that are unique to that side or that differ in
/// size/modification date from their same-named counterpart on the other side.
public enum DirectoryComparer {

    public struct Result {
        /// Names that should end up marked (selected) in the left panel.
        public let leftDifferent: Set<String>
        /// Names that should end up marked (selected) in the right panel.
        public let rightDifferent: Set<String>
    }

    public static func compare(left: [FileEntry], right: [FileEntry]) -> Result {
        let leftFiles = left.filter { $0.kind == .regularFile || $0.kind == .archive }
        let rightFiles = right.filter { $0.kind == .regularFile || $0.kind == .archive }

        let leftByName = Dictionary(uniqueKeysWithValues: leftFiles.map { ($0.name, $0) })
        let rightByName = Dictionary(uniqueKeysWithValues: rightFiles.map { ($0.name, $0) })

        var leftDiff = Set<String>()
        var rightDiff = Set<String>()

        for (name, entry) in leftByName {
            if let other = rightByName[name] {
                if entry.size != other.size || !sameDay(entry.modificationDate, other.modificationDate) {
                    leftDiff.insert(name)
                    rightDiff.insert(name)
                }
            } else {
                leftDiff.insert(name)
            }
        }
        for (name, _) in rightByName where leftByName[name] == nil {
            rightDiff.insert(name)
        }

        return Result(leftDifferent: leftDiff, rightDifferent: rightDiff)
    }

    private static func sameDay(_ a: Date?, _ b: Date?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return abs(a.timeIntervalSince(b)) < 2 // filesystem timestamp rounding
    }
}

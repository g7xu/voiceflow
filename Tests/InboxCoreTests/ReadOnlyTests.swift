import Foundation
import Testing

/// Spec §2 and §12: the app never changes user files, and writes only under `AppPaths`. Checked
/// against the source text of everything that ships, since no runtime test can prove an absence.
@Suite struct ReadOnlyTests {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    static func shippedSources() throws -> [(name: String, text: String)] {
        try ["Sources/InboxCore", "Sources/ContextInbox"].flatMap { dir in
            let root = repo.appendingPathComponent(dir)
            let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
            return try files.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
        }
    }

    /// Writes that are allowed, by file: creating the app's own folder, and the settings file, the
    /// spike's bookmark record and layout snapshots inside it.
    static let allowed: [String: Set<String>] = [
        "AppPaths.swift": ["createDirectory("],
        "Settings.swift": [".write(to: paths.config"],
        "Spike.swift": [".write(to: bookmarkFile)"],
        "Snapshot.swift": [".write(to: snapshotDir", "status.write(to: snapshotDir"],
    ]

    static let forbidden = [
        "moveItem(", "removeItem(", "trashItem(", "copyItem(", "replaceItem", "linkItem(", "createSymbolicLink(",
        "createFile(", "createDirectory(", "setxattr(", "removexattr(", "setResourceValue", "setAttributes(",
        ".write(to:", "FileHandle(forWriting", "forUpdating", "unlink(", "rename(", "rmdir(", "truncate(",
    ]

    @Test func sourcesAreFound() throws {
        #expect(try Self.shippedSources().count > 10)
    }

    @Test func noFileMutationsOutsideAllowedSpots() throws {
        for (name, text) in try Self.shippedSources() {
            for line in text.split(separator: "\n") {
                let code = line.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
                for pattern in Self.forbidden where code.contains(pattern) {
                    let ok = Self.allowed[name]?.contains { code.contains($0) } ?? false
                    #expect(ok, "\(name): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
    }
}

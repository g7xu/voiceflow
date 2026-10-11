import Foundation

public protocol DirectoryLister: Sendable {
    /// The top-level entries of `folder` that count as inbox items. Directories, packages and
    /// symlinks are single entries. Throws when the folder can't be listed, which the scanner treats
    /// as "unknown", never as "empty".
    func list(_ folder: URL) throws -> [URL]
}

public struct LiveDirectoryLister: DirectoryLister {
    public init() {}

    public func list(_ folder: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.addedToDirectoryDateKey, .isDirectoryKey, .volumeUUIDStringKey],
            options: [.skipsHiddenFiles]
        )
        .filter { !InboxFilter.isInProgressDownload($0) }
    }
}

enum InboxFilter {
    /// Chrome (`.crdownload`), Safari (a `.download` folder) and Firefox (`.part`) rename the file
    /// when the download completes, so an in-progress entry would only ever show up as `gone`.
    static let inProgressExtensions: Set<String> = ["crdownload", "download", "part"]

    static func isInProgressDownload(_ url: URL) -> Bool {
        inProgressExtensions.contains(url.pathExtension.lowercased())
    }
}

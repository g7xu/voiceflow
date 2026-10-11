import Foundation

public protocol BookmarkResolving: Sendable {
    func create(_ url: URL) -> Data?
    func resolve(_ data: Data) -> URL?
}

public struct LiveBookmarks: BookmarkResolving {
    public init() {}

    public func create(_ url: URL) -> Data? {
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Never shows UI or mounts volumes: a scan must not block on a dialog or a network share.
    public func resolve(_ data: Data) -> URL? {
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting],
                        relativeTo: nil, bookmarkDataIsStale: &stale)
    }
}

/// Decides what happened to a tracked item that a successful listing no longer shows.
struct DepartureClassifier {
    enum Departure: Equatable {
        case done(Item.DoneReason, currentPath: String?)
        /// It resolves to the top level of an inbox: the scan raced a move.
        case stillInInbox
    }

    let metadata: any MetadataReading
    let bookmarks: any BookmarkResolving
    let trashRoots: [URL]
    let inboxRoots: [URL]

    func classify(_ item: Item) -> Departure {
        guard let data = item.bookmark, let url = bookmarks.resolve(data) else { return .done(.gone, currentPath: nil) }
        // A bookmark prefers the original path, so after a file is replaced by a new one with the
        // same name it resolves to the newcomer.
        guard (try? metadata.identity(of: url)) == item.identity else { return .done(.gone, currentPath: nil) }

        let parent = Paths.canonicalDirectory(url.deletingLastPathComponent())
        if trashRoots.contains(where: { Paths.isWithin(parent, Paths.canonicalDirectory($0)) })
            || parent.contains("/.Trashes/") || parent.hasSuffix("/.Trashes") {
            return .done(.trashed, currentPath: url.path)
        }
        if inboxRoots.contains(where: { Paths.canonicalDirectory($0) == parent }) {
            return .stillInInbox
        }
        return .done(.moved, currentPath: url.path)
    }
}

enum Paths {
    /// Comparable form of a directory: symlinks resolved (so /var and /private/var agree), no
    /// trailing slash. Only directories are resolved; resolving an item's own path would follow it
    /// when the item is itself a symlink.
    static func canonicalDirectory(_ url: URL) -> String {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// `dir` is `root` or somewhere below it.
    static func isWithin(_ dir: String, _ root: String) -> Bool {
        dir == root || dir.hasPrefix(root + "/")
    }
}

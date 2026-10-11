import Foundation

/// Everything the app writes lives under `root`. Tests point it at a temporary directory.
public struct AppPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static func live() -> AppPaths {
        AppPaths(root: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ContextInbox"))
    }

    public var database: URL { root.appendingPathComponent("items.sqlite") }
    public var config: URL { root.appendingPathComponent("config.json") }

    public func ensureExists() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
}

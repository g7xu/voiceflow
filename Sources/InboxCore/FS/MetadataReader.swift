import Darwin
import Foundation

/// Unparsed metadata for one inbox entry; `MetadataParsing` turns it into display values.
public struct RawMetadata: Sendable {
    public var identity: FileIdentity
    /// nil on volumes that don't record it.
    public var addedAt: Date?
    public var isDirectory: Bool
    public var whereFroms: Data?
    public var quarantine: String?

    public init(identity: FileIdentity, addedAt: Date?, isDirectory: Bool, whereFroms: Data?, quarantine: String?) {
        self.identity = identity
        self.addedAt = addedAt
        self.isDirectory = isDirectory
        self.whereFroms = whereFroms
        self.quarantine = quarantine
    }
}

public enum MetadataError: Error, CustomStringConvertible {
    case stat(path: String, errno: Int32)
    case noVolumeUUID(path: String)

    public var description: String {
        switch self {
        case let .stat(path, code): "can't stat \(path): \(String(cString: strerror(code)))"
        case let .noVolumeUUID(path): "\(path) is on a volume without a persistent UUID"
        }
    }
}

public protocol MetadataReading: Sendable {
    func read(_ url: URL) throws -> RawMetadata
    func identity(of url: URL) throws -> FileIdentity
}

public struct LiveMetadataReader: MetadataReading {
    public init() {}

    /// Uses `lstat` because `URLResourceValues.fileIdentifier` is documented as not to be persisted.
    public func identity(of url: URL) throws -> FileIdentity {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw MetadataError.stat(path: url.path, errno: errno) }
        guard let volume = try url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString else {
            throw MetadataError.noVolumeUUID(path: url.path)
        }
        return FileIdentity(volumeUUID: volume, inode: UInt64(info.st_ino))
    }

    public func read(_ url: URL) throws -> RawMetadata {
        let values = try url.resourceValues(forKeys: [.addedToDirectoryDateKey, .isDirectoryKey])
        return RawMetadata(
            identity: try identity(of: url),
            addedAt: values.addedToDirectoryDate,
            isDirectory: values.isDirectory ?? false,
            whereFroms: XAttr.read(url.path, "com.apple.metadata:kMDItemWhereFroms"),
            quarantine: XAttr.read(url.path, "com.apple.quarantine").flatMap { String(data: $0, encoding: .utf8) }
        )
    }
}

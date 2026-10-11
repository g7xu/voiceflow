/// Survives renames and moves within a volume. Assumes an inode number isn't reused while a row
/// still refers to it, which holds on APFS.
public struct FileIdentity: Hashable, Sendable, Codable {
    public let volumeUUID: String
    public let inode: UInt64

    public init(volumeUUID: String, inode: UInt64) {
        self.volumeUUID = volumeUUID
        self.inode = inode
    }
}

import Darwin
import Foundation

enum XAttr {
    /// nil when the attribute is absent or can't be read. Never follows a symlink.
    static func read(_ path: String, _ name: String) -> Data? {
        let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
        guard read > 0 else { return nil }
        return data.prefix(read)
    }
}

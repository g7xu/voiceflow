import Darwin
import Foundation

/// A fresh directory under the system temp folder, deleted when the value is released.
final class TempDir {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("inbox-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func file(_ name: String, _ contents: String = "x") throws -> URL {
        let target = url.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: target)
        return target
    }

    @discardableResult
    func dir(_ name: String) throws -> URL {
        let target = url.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }
}

func setXAttr(_ url: URL, _ name: String, _ value: Data) throws {
    let status = value.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, value.count, 0, 0) }
    guard status == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}

func inode(_ url: URL) -> UInt64 {
    var info = stat()
    lstat(url.path, &info)
    return UInt64(info.st_ino)
}

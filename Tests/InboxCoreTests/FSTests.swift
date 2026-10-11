import Foundation
import Testing
@testable import InboxCore

@Suite struct DirectoryListerTests {
    @Test func listsTopLevelItemsOnly() throws {
        let tmp = try TempDir()
        let pdf = try tmp.file("a.pdf")
        try tmp.file(".hidden")
        try tmp.file(".DS_Store")
        try tmp.file("b.pdf.crdownload")
        try tmp.file("c.zip.part")
        try tmp.dir("d.zip.download")
        try tmp.file("App.app/Contents/Info.plist")
        try tmp.file("folder/inside.txt")
        try FileManager.default.createSymbolicLink(at: tmp.url.appendingPathComponent("link"), withDestinationURL: pdf)

        let names = try LiveDirectoryLister().list(tmp.url).map(\.lastPathComponent).sorted()
        #expect(names == ["App.app", "a.pdf", "folder", "link"])
    }

    @Test func missingFolderThrows() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-\(UUID().uuidString)")
        #expect(throws: (any Error).self) { try LiveDirectoryLister().list(missing) }
    }

    @Test func emptyFolderIsEmptyNotAnError() throws {
        let tmp = try TempDir()
        #expect(try LiveDirectoryLister().list(tmp.url).isEmpty)
    }
}

@Suite struct MetadataReaderTests {
    @Test func readsIdentityDateAddedAndXAttrs() throws {
        let tmp = try TempDir()
        let file = try tmp.file("lec05.pdf")
        let froms = try PropertyListSerialization.data(
            fromPropertyList: ["https://cdn.example.com/f?sig=1", "https://canvas.example.edu/courses/1"],
            format: .binary, options: 0)
        try setXAttr(file, "com.apple.metadata:kMDItemWhereFroms", froms)
        try setXAttr(file, "com.apple.quarantine", Data("0081;6ac9778d;Chrome;E0FE4E62-2ACD-4FB2-B032-24C3CBD0791B".utf8))

        let raw = try LiveMetadataReader().read(file)
        #expect(raw.identity.inode == inode(file))
        #expect(!raw.identity.volumeUUID.isEmpty)
        #expect(raw.addedAt != nil)
        #expect(!raw.isDirectory)

        let provenance = MetadataParsing.provenance(raw)
        #expect(provenance == Provenance(sourceURL: "https://cdn.example.com/f",
                                         referrerURL: "https://canvas.example.edu/courses/1",
                                         savedBy: "Chrome"))
    }

    @Test func plainLocalFileHasNoProvenance() throws {
        let tmp = try TempDir()
        let raw = try LiveMetadataReader().read(try tmp.file("Screenshot.png"))
        #expect(MetadataParsing.provenance(raw) == Provenance())
    }

    @Test func identitySurvivesRename() throws {
        let tmp = try TempDir()
        let before = try tmp.file("old.txt")
        let id = try LiveMetadataReader().identity(of: before)
        let after = tmp.url.appendingPathComponent("new.txt")
        try FileManager.default.moveItem(at: before, to: after)
        #expect(try LiveMetadataReader().identity(of: after) == id)
    }

    @Test func symlinkIdentityIsTheLinkItself() throws {
        let tmp = try TempDir()
        let target = try tmp.file("a.pdf")
        let link = tmp.url.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(try LiveMetadataReader().identity(of: link).inode == inode(link))
        #expect(inode(link) != inode(target))
    }
}

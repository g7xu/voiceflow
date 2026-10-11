import Foundation
import Testing
@testable import InboxCore

@Suite struct MetadataParsingTests {
    @Test func quarantineFromChrome() throws {
        let q = try #require(MetadataParsing.quarantine("0081;6ac9778d;Chrome;E0FE4E62-2ACD-4FB2-B032-24C3CBD0791B"))
        #expect(q.agent == "Chrome")
        #expect(q.timestamp == Date(timeIntervalSince1970: 0x6ac9778d))
    }

    @Test func quarantineWithTrailingNulAndNoAgent() throws {
        let q = try #require(MetadataParsing.quarantine("0083;5f000000;;\0"))
        #expect(q.agent == nil)
        #expect(q.timestamp == Date(timeIntervalSince1970: 0x5f000000))
    }

    @Test func quarantineRejectsGarbage() {
        #expect(MetadataParsing.quarantine("nonsense") == nil)
    }

    @Test func airDropAgentIsRenamed() {
        #expect(MetadataParsing.displayAgent("sharingd") == "AirDrop")
        #expect(MetadataParsing.displayAgent("Safari") == "Safari")
    }

    @Test func webOriginsKeepsHttpEntriesInOrder() throws {
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["https://cdn.example.com/f/abc?token=SECRET", "https://canvas.example.edu/courses/1/files"],
            format: .binary, options: 0)
        let origins = MetadataParsing.webOrigins(plist)
        #expect(origins.source == "https://cdn.example.com/f/abc")
        #expect(origins.referrer == "https://canvas.example.edu/courses/1/files")
    }

    @Test func webOriginsDropsMailSenderAndSubject() throws {
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["Sam <sam@example.com>", "Re: Q3 plan", "message:%3Cid@example.com%3E"],
            format: .binary, options: 0)
        let origins = MetadataParsing.webOrigins(plist)
        #expect(origins.source == nil)
        #expect(origins.referrer == nil)
    }

    @Test func webOriginsToleratesNonPlist() {
        #expect(MetadataParsing.webOrigins(Data("junk".utf8)).source == nil)
    }

    @Test(arguments: [
        ("https://user:pw@example.com/a/b?q=1#frag", "https://example.com/a/b"),
        ("HTTP://Example.com", "HTTP://Example.com"),
        ("data:text/plain;base64,AAAA", nil),
        ("blob:https://example.com/uuid", nil),
        ("file:///Users/x/a.pdf", nil),
    ] as [(String, String?)])
    func sanitizedURL(input: String, expected: String?) {
        #expect(MetadataParsing.sanitizedURL(input) == expected)
    }

    @Test(arguments: [
        ("https://canvas.example.edu/courses/123/files", "canvas.example.edu/courses/123/files"),
        ("https://example.com/blog/lecture-5-scheduling-slides-2026", "example.com/blog/lecture-5-scheduling-slides-2026"),
        ("https://docs.example.com/document/d/1aB2cD3eF4gH5iJ6kL7mN8oP9qR0sT/edit",
         "docs.example.com/document/d/…/edit"),
        ("https://share.example.com/s/9-xQ3vB7nM2kL8pR4tY6wZ1aS5dF0gH==", "share.example.com/s/…"),
        ("https://example.com/f/3F2504E0-4F89-11D3-9A0C-0305E82C3301/view", "example.com/f/…/view"),
        ("https://example.com/sha/e3b0c44298fc1c149afbf4c8996fb924", "example.com/sha/…"),
        ("https://example.com/", "example.com"),
    ])
    func displaySourceMasksOpaqueSegments(referrer: String, expected: String) {
        #expect(MetadataParsing.displaySource(source: nil, referrer: referrer) == expected)
    }

    @Test func displaySourcePrefersReferrerPage() {
        #expect(MetadataParsing.displaySource(source: "https://cdn.example.com/x", referrer: "https://canvas.example.edu/courses/1/files/")
                == "canvas.example.edu/courses/1/files")
        #expect(MetadataParsing.displaySource(source: "https://cdn.example.com/x/y", referrer: nil) == "cdn.example.com")
        #expect(MetadataParsing.displaySource(source: nil, referrer: nil) == nil)
    }
}

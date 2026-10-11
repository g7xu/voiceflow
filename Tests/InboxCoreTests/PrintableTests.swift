import Testing
@testable import InboxCore

@Suite struct PrintableTests {
    @Test(arguments: [
        ("lec05 scheduling.pdf", "lec05 scheduling.pdf"),
        ("截图 2026-10-07.png", "截图 2026-10-07.png"),
        ("café.pdf", "café.pdf"),
        ("evil\u{1B}]0;pwned\u{07}.pdf", "evil\\u{1B}]0;pwned\\u{7}.pdf"),
        ("tab\tand\nnewline", "tab\\u{9}and\\u{A}newline"),
        ("invoice\u{202E}fdp.exe", "invoice\\u{202E}fdp.exe"),
        ("c1\u{9B}31m", "c1\\u{9B}31m"),
    ])
    func escape(input: String, expected: String) {
        #expect(Printable.escape(input) == expected)
    }
}

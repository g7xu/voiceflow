public enum Printable {
    /// `text` with control characters and bidirectional-override characters replaced by `\u{…}`
    /// escapes. Filenames and URLs come from the internet: unescaped, one could carry terminal
    /// escape sequences, break a TSV row or Markdown line, or visually reorder a name
    /// ("invoice‮fdp.exe").
    public static func escape(_ text: String) -> String {
        var out = ""
        out.unicodeScalars.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.unicodeScalars {
            if scalar.properties.generalCategory == .control || isBidiControl(scalar) {
                out += "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    private static func isBidiControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069: true
        default: false
        }
    }
}

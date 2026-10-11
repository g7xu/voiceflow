import Foundation

public struct Quarantine: Equatable, Sendable {
    public var timestamp: Date?
    public var agent: String?
}

public enum MetadataParsing {
    /// The http(s) entries of kMDItemWhereFroms, sanitized: normally the download URL, then the page
    /// that linked to it. Mail stores the sender and subject in the same list, and those are dropped.
    public static func webOrigins(_ whereFroms: Data) -> (source: String?, referrer: String?) {
        guard let list = try? PropertyListSerialization.propertyList(from: whereFroms, format: nil) as? [Any] else {
            return (nil, nil)
        }
        let urls = list.compactMap { ($0 as? String).flatMap(sanitizedURL) }
        return (urls.first, urls.dropFirst().first)
    }

    /// `com.apple.quarantine` holds `flags;hex unix seconds;agent;event UUID`.
    public static func quarantine(_ raw: String) -> Quarantine? {
        let fields = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines))
            .split(separator: ";", omittingEmptySubsequences: false)
        guard fields.count >= 3 else { return nil }
        let seconds = UInt64(fields[1], radix: 16)
        return Quarantine(
            timestamp: seconds.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            agent: fields[2].isEmpty ? nil : String(fields[2])
        )
    }

    private static let agentNames = ["sharingd": "AirDrop"]

    public static func displayAgent(_ agent: String) -> String {
        agentNames[agent] ?? agent
    }

    /// `scheme://host/path` only. Query strings and fragments often carry access tokens, and the
    /// result ends up in a prompt pasted elsewhere. Anything other than http(s) gives nil.
    public static func sanitizedURL(_ string: String) -> String? {
        guard var parts = URLComponents(string: string),
              let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = parts.host, !host.isEmpty
        else { return nil }
        parts.user = nil
        parts.password = nil
        parts.query = nil
        parts.fragment = nil
        return parts.string
    }

    /// The referring page as host + path, else only the download's host: download paths can embed
    /// tokens (signed CDN links), referring pages rarely do.
    public static func displaySource(source: String?, referrer: String?) -> String? {
        if let referrer, let page = URLComponents(string: referrer), let host = page.host {
            let path = page.path.hasSuffix("/") ? String(page.path.dropLast()) : page.path
            return host + path
        }
        return source.flatMap { URLComponents(string: $0)?.host }
    }
}

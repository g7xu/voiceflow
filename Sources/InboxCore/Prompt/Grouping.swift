import Foundation

/// Items that arrived during (or just after) the same event, or the items with no event.
public struct ItemGroup: Equatable, Sendable, Identifiable {
    /// nil for the "no calendar event" group.
    public var event: EventMatch?
    public var items: [Item]

    public var id: String {
        guard let event else { return "none" }
        return "\(event.kind.rawValue)|\(event.title)|\(event.start.timeIntervalSince1970)|\(event.calendarTitle)"
    }
}

/// Event groups in order of event start ("during" before "after" for the same event), then the
/// no-event group. Items within a group are oldest first. The prompt reads in this order; the list
/// UI reverses it.
public func groupItems(_ items: [Item]) -> [ItemGroup] {
    var byKey: [String: ItemGroup] = [:]
    for item in items {
        let group = ItemGroup(event: item.event, items: [])
        byKey[group.id, default: group].items.append(item)
    }
    let groups = byKey.values.map { group in
        var sorted = group
        sorted.items.sort { ($0.addedAt, $0.inboxPath) < ($1.addedAt, $1.inboxPath) }
        return sorted
    }
    return groups.sorted { a, b in
        switch (a.event, b.event) {
        case (nil, nil): return false
        case (nil, _): return false
        case (_, nil): return true
        case let (x?, y?):
            if x.start != y.start { return x.start < y.start }
            if x.kind != y.kind { return x.kind == .during }
            return (x.title, x.calendarTitle) < (y.title, y.calendarTitle)
        }
    }
}

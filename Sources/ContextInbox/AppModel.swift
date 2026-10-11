import AppKit
import InboxCore
import Observation

@MainActor @Observable
final class AppModel {
    enum Filter: String, CaseIterable, Identifiable {
        case tracked = "Tracked", done = "Done"
        var id: Self { self }
    }

    /// Focus-triggered scans are skipped if one ran this recently; the Scan button always runs.
    static let focusRescanInterval: TimeInterval = 30

    private(set) var settings: InboxSettings
    private(set) var items: [Item] = []
    var filter: Filter = .tracked
    var selection: Set<Int64> = []
    private(set) var isScanning = false
    private(set) var lastReport: ScanReport?
    private(set) var lastScanAt: Date?
    private(set) var errorMessage: String?
    /// A short confirmation, e.g. after copying the prompt.
    var notice: String?
    private(set) var calendarAccess: Bool
    private(set) var availableCalendars: [CalendarInfo] = []

    let calendar = EventKitCalendarSource()
    private let settingsStore: SettingsStore
    private let store: ItemStore?

    init(paths: AppPaths = .live()) {
        settingsStore = SettingsStore(paths: paths)
        var problems: [String] = []
        do {
            settings = try settingsStore.load()
        } catch {
            settings = InboxSettings()
            problems.append("Couldn't read settings (\(error.localizedDescription)); showing defaults.")
        }
        do {
            try paths.ensureExists()
            store = try ItemStore.open(at: paths.database)
        } catch {
            store = nil
            problems.append("Couldn't open the database: \(error.localizedDescription)")
        }
        errorMessage = problems.isEmpty ? nil : problems.joined(separator: " ")
        calendarAccess = calendar.hasFullAccess
        refreshCalendars()
        reload()
    }

    var trackedItems: [Item] { items.filter { $0.status == .tracked } }

    /// Newest group first, the reverse of the prompt's reading order.
    var trackedGroups: [ItemGroup] { groupItems(trackedItems).reversed() }

    var doneItems: [Item] {
        items.filter { $0.status == .done }.sorted { $0.statusAt > $1.statusAt }
    }

    var selectedTrackedIDs: [Int64] {
        trackedItems.compactMap(\.id).filter(selection.contains)
    }

    func scan(force: Bool = false) {
        guard let store, settings.firstRunDone, !isScanning else { return }
        if !force, let lastScanAt, Date().timeIntervalSince(lastScanAt) < Self.focusRescanInterval { return }
        isScanning = true
        refreshCalendars()
        let scanner = Scanner(store: store, calendar: calendar)
        let scanSettings = settings.scanSettings(available: availableCalendars)
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try scanner.scan(scanSettings) }
            }.value
            isScanning = false
            lastScanAt = Date()
            switch result {
            case let .success(report):
                lastReport = report
                errorMessage = nil
            case let .failure(error):
                errorMessage = "Scan failed: \(error.localizedDescription)"
            }
            reload()
        }
    }

    /// Copies the prompt for the selected tracked items, or for all of them when none are selected.
    func copyPrompt() {
        let chosen = selectedTrackedIDs.isEmpty ? trackedItems : trackedItems.filter { selection.contains($0.id ?? -1) }
        guard !chosen.isEmpty else { return }
        let text = PromptGenerator().render(items: chosen, inboxPaths: settings.inboxPaths,
                                            destinationRoot: settings.destinationRoot)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        notice = "Copied a prompt for \(chosen.count) \(chosen.count == 1 ? "file" : "files"). Paste it into Claude."
    }

    func markDone(_ ids: [Int64]) {
        perform { try $0.markDone(ids: ids, reason: .manual, at: Date()) }
        selection.subtract(ids)
    }

    func trackAgain(_ ids: [Int64]) {
        perform { try $0.trackAgain(ids: ids, at: Date()) }
    }

    func save(_ newSettings: InboxSettings) {
        do {
            try settingsStore.save(newSettings)
            settings = newSettings
        } catch {
            errorMessage = "Couldn't save settings: \(error.localizedDescription)"
        }
    }

    func requestCalendarAccess() async {
        do {
            calendarAccess = try await calendar.requestAccess()
        } catch {
            errorMessage = "Calendar access failed: \(error.localizedDescription)"
        }
        refreshCalendars()
    }

    private func refreshCalendars() {
        calendarAccess = calendar.hasFullAccess
        availableCalendars = calendarAccess
            ? calendar.calendars().sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
            : []
    }

    private func perform(_ change: (ItemStore) throws -> Int) {
        guard let store else { return }
        do {
            _ = try change(store)
        } catch {
            errorMessage = error.localizedDescription
        }
        reload()
    }

    private func reload() {
        guard let store else { return }
        do {
            items = try store.items()
            selection.formIntersection(items.compactMap(\.id))
        } catch {
            errorMessage = "Couldn't read the database: \(error.localizedDescription)"
        }
    }
}

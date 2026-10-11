import AppKit
import InboxCore
import QuickLook
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var preview: URL?

    var body: some View {
        VStack(spacing: 0) {
            list
            Divider()
            StatusBar(model: model)
        }
        .toolbar { toolbar }
        .quickLookPreview($preview)
        .sheet(isPresented: Binding(get: { !model.settings.firstRunDone }, set: { _ in })) {
            FirstRunView(model: model)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.scan()
        }
        .task { model.scan(force: true) }
    }

    @ViewBuilder private var list: some View {
        switch model.filter {
        case .tracked where model.trackedItems.isEmpty:
            ContentUnavailableView("Nothing to organize", systemImage: "tray",
                                   description: Text("New files in your inbox folders appear here after a scan."))
        case .done where model.doneItems.isEmpty:
            ContentUnavailableView("Nothing done yet", systemImage: "checkmark.circle",
                                   description: Text("Files you or Claude move out of your inbox folders appear here."))
        case .tracked:
            List(selection: $model.selection) {
                ForEach(model.trackedGroups) { group in
                    Section {
                        ForEach(group.items) { item in
                            ItemRow(item: item, detail: Display.detail(item)).tag(item.id ?? -1)
                        }
                    } header: {
                        GroupHeader(group: group)
                    }
                }
            }
            .contextMenu(forSelectionType: Int64.self) { ids in menu(for: ids) }
            .onKeyPress(.space) { quickLook() }
        case .done:
            List(selection: $model.selection) {
                ForEach(model.doneItems) { item in
                    ItemRow(item: item, detail: Display.doneDetail(item)).tag(item.id ?? -1)
                }
            }
            .contextMenu(forSelectionType: Int64.self) { ids in menu(for: ids) }
            .onKeyPress(.space) { quickLook() }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Show", selection: $model.filter) {
                Text("Tracked (\(model.trackedItems.count))").tag(AppModel.Filter.tracked)
                Text("Done (\(model.doneItems.count))").tag(AppModel.Filter.done)
            }
            .pickerStyle(.segmented)
            .onChange(of: model.filter) { model.selection = [] }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.scan(force: true) } label: { Label("Scan", systemImage: "arrow.clockwise") }
                .help("Scan the inbox folders now")
                .keyboardShortcut("r")
                .disabled(model.isScanning)
            Button { model.markDone(model.selectedTrackedIDs) } label: { Label("Mark Done", systemImage: "checkmark.circle") }
                .help("Stop tracking the selected files without moving them")
                .disabled(model.selectedTrackedIDs.isEmpty)
            Button { model.copyPrompt() } label: { Label("Copy Prompt", systemImage: "doc.on.clipboard") }
                .help(model.selectedTrackedIDs.isEmpty ? "Copy a prompt for all tracked files" : "Copy a prompt for the selected files")
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model.trackedItems.isEmpty)
        }
    }

    @ViewBuilder private func menu(for ids: Set<Int64>) -> some View {
        let chosen = model.items.filter { ids.contains($0.id ?? -1) }
        if let first = chosen.first {
            Button("Quick Look") { preview = Self.location(of: first) }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting(chosen.map(Self.location))
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(chosen.map { Self.location(of: $0).path }.joined(separator: "\n"),
                                               forType: .string)
            }
            Divider()
            let tracked = chosen.filter { $0.status == .tracked }.compactMap(\.id)
            let manual = chosen.filter { $0.doneReason == .manual }.compactMap(\.id)
            if !tracked.isEmpty { Button("Mark Done") { model.markDone(tracked) } }
            if !manual.isEmpty { Button("Track Again") { model.trackAgain(manual) } }
        }
    }

    private func quickLook() -> KeyPress.Result {
        guard let item = model.items.first(where: { model.selection.contains($0.id ?? -1) }) else { return .ignored }
        preview = Self.location(of: item)
        return .handled
    }

    /// Where the file is now, as far as the app knows.
    static func location(of item: Item) -> URL {
        URL(fileURLWithPath: item.currentPath ?? item.inboxPath)
    }
}

struct ItemRow: View {
    let item: Item
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: ContentView.location(of: item).path))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(Display.name(item))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 2)
    }
}

struct GroupHeader: View {
    let group: ItemGroup

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Display.groupTitle(group)).font(.headline)
            if let detail = Display.groupDetail(group) {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct StatusBar: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            if model.isScanning {
                ProgressView().controlSize(.small)
                Text("Scanning…")
            } else if let report = model.lastReport, let at = model.lastScanAt {
                Text(Display.reportSummary(report, at: at))
            }
            if let skipped = model.lastReport?.calendarSkipped {
                Label("No event context: \(skipped)", systemImage: "calendar.badge.exclamationmark")
                    .foregroundStyle(.orange)
                if !model.calendarAccess {
                    Button("Allow Calendar Access") { Task { await model.requestCalendarAccess() } }
                        .controlSize(.small)
                }
            }
            ForEach((model.lastReport?.folderErrors ?? [:]).sorted(by: { $0.key < $1.key }), id: \.key) { path, _ in
                Label("Can't read \(Display.tilde(path))", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .help("Check System Settings › Privacy & Security › Files & Folders. Nothing in this folder was marked done.")
            }
            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red).lineLimit(1)
            }
            Spacer()
            if let notice = model.notice {
                Text(notice).foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

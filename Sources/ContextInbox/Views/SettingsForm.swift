import AppKit
import InboxCore
import SwiftUI

/// The settings fields, shared by the first-run sheet and the Settings window.
struct SettingsForm: View {
    @Binding var settings: InboxSettings
    let model: AppModel
    @State private var folderProblem: String?

    var body: some View {
        Form {
            Section {
                ForEach(settings.inboxPaths, id: \.self) { path in
                    HStack {
                        Label(Display.tilde(path), systemImage: "folder")
                        Spacer()
                        Button { settings.inboxPaths.removeAll { $0 == path } } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .disabled(settings.inboxPaths.count == 1)
                    }
                }
                Button("Add Folder…", action: addFolder)
            } header: {
                Text("Inbox folders")
            } footer: {
                Text("Only the top level is scanned. Moving a file into a subfolder counts as organizing it.")
            }

            Section("Calendars") {
                if model.calendarAccess {
                    if model.availableCalendars.isEmpty {
                        Text("No calendars yet. Add Google or Outlook in System Settings › Internet Accounts.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.availableCalendars) { info in
                        Toggle(isOn: calendarBinding(info)) {
                            Text(info.title)
                            Text(info.sourceTitle)
                        }
                    }
                    Picker("After an event ends, match files for", selection: $settings.matchWindowMinutes) {
                        Text("No time (during only)").tag(0)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                        Text("4 hours").tag(240)
                    }
                } else {
                    Button("Allow Calendar Access…") { Task { await model.requestCalendarAccess() } }
                    Text("Each file is matched to the event you were in when it arrived. Google and Outlook calendars appear once they're added in System Settings › Internet Accounts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Scanning") {
                Picker("Track files added in the last", selection: $settings.backfillDays) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("180 days").tag(180)
                    Text("365 days").tag(365)
                }
            }

            Section {
                HStack {
                    Text(settings.destinationRoot.map(Display.tilde) ?? "Not set")
                        .foregroundStyle(settings.destinationRoot == nil ? .secondary : .primary)
                    Spacer()
                    if settings.destinationRoot != nil {
                        Button("Clear") { settings.destinationRoot = nil }
                    }
                    Button("Choose…", action: chooseDestination)
                }
            } header: {
                Text("Organize into")
            } footer: {
                Text("The prompt asks Claude to organize files into subfolders of this folder.")
            }
        }
        .formStyle(.grouped)
        .alert("Can't use this folder", isPresented: Binding(get: { folderProblem != nil }, set: { if !$0 { folderProblem = nil } })) {
            Button("OK") {}
        } message: {
            Text(folderProblem ?? "")
        }
    }

    private func addFolder() {
        guard let url = Self.pickFolder(prompt: "Add") else { return }
        if let problem = InboxFolderCheck.problem(with: url) {
            folderProblem = problem
        } else if !settings.inboxPaths.contains(url.path) {
            settings.inboxPaths.append(url.path)
        }
    }

    private func chooseDestination() {
        if let url = Self.pickFolder(prompt: "Choose") { settings.destinationRoot = url.path }
    }

    private static func pickFolder(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Choosing any calendar turns "all but birthdays and subscriptions" into an explicit list.
    private func calendarBinding(_ info: CalendarInfo) -> Binding<Bool> {
        Binding(
            get: { settings.calendarIDs(available: model.availableCalendars).contains(info.id) },
            set: { on in
                var ids = settings.calendarIDs(available: model.availableCalendars)
                if on { ids.insert(info.id) } else { ids.remove(info.id) }
                settings.calendars = model.availableCalendars.filter { ids.contains($0.id) }.map(CalendarRef.init)
            }
        )
    }
}

struct FirstRunView: View {
    let model: AppModel
    @State private var draft: InboxSettings

    init(model: AppModel) {
        self.model = model
        _draft = State(initialValue: model.settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to ContextInbox").font(.title2.bold())
                Text("ContextInbox remembers where each new file came from and what was on your calendar when it arrived, then writes a prompt so Claude can organize them. It never moves, renames or deletes anything itself.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            SettingsForm(settings: $draft, model: model)
            HStack {
                Spacer()
                Button("Start Scanning") {
                    var settings = draft
                    settings.firstRunDone = true
                    model.save(settings)
                    model.scan(force: true)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.inboxPaths.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 580, height: 680)
        .interactiveDismissDisabled()
    }
}

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        SettingsForm(settings: Binding(get: { model.settings }, set: { model.save($0) }), model: model)
            .frame(width: 540, height: 600)
    }
}

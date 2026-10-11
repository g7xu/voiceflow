import AppKit
import InboxCore
import SwiftUI

/// `--snapshot --inbox PATH...`: renders the window's views to PNGs for checking layout without
/// screen-recording permission. Uses a throwaway data folder; everything lands under
/// `<App Support>/snapshots`.
enum Snapshot {
    @MainActor
    static func run(_ args: [String]) async throws {
        let inboxes = try ScanOptions(args).inboxes.map(\.path)
        let snapshotDir = AppPaths.live().root.appendingPathComponent("snapshots")
        let paths = AppPaths(root: snapshotDir.appendingPathComponent("data-\(UUID().uuidString)"))
        try paths.ensureExists()
        try SettingsStore(paths: paths).save(InboxSettings(inboxPaths: inboxes, firstRunDone: true))

        let model = AppModel(paths: paths)
        model.scan(force: true)
        while model.isScanning { try await Task.sleep(for: .milliseconds(50)) }

        try await render(ContentView(model: model), size: CGSize(width: 880, height: 560), name: "main.png", in: snapshotDir)
        // cacheDisplay only captures AppKit-drawn views (List and Form rows); pure SwiftUI views like
        // the status bar render through ImageRenderer instead.
        let statusRenderer = ImageRenderer(content: StatusBar(model: model).frame(width: 880).background(.background))
        statusRenderer.scale = 2
        guard let status = statusRenderer.nsImage?.tiffRepresentation.flatMap(NSBitmapImageRep.init)?
            .representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try status.write(to: snapshotDir.appendingPathComponent("status.png"))
        if let first = model.trackedItems.first?.id { model.markDone([first]) }
        model.filter = .done
        try await render(ContentView(model: model), size: CGSize(width: 880, height: 320), name: "done.png", in: snapshotDir)
        try await render(SettingsForm(settings: .constant(model.settings), model: model),
                         size: CGSize(width: 580, height: 680), name: "settings.png", in: snapshotDir)
        print("wrote main.png, done.png, settings.png to \(Printable.escape(snapshotDir.path))")
    }

    @MainActor
    private static func render(_ view: some View, size: CGSize, name: String, in snapshotDir: URL) async throws {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled],
                              backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // Lets the table views behind List populate their rows before capture.
        try await Task.sleep(for: .milliseconds(400))
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds),
              let png = { hosting.cacheDisplay(in: hosting.bounds, to: rep); return rep.representation(using: .png, properties: [:]) }()
        else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: snapshotDir.appendingPathComponent(name))
    }
}

import AppKit

enum Headless {
    /// Runs `body` inside an accessory (no Dock icon) NSApplication, so privacy prompts can appear,
    /// then exits. `open --stdout` hands us a file, which would otherwise be block-buffered.
    @MainActor
    static func run(_ body: @escaping @Sendable () async throws -> Void) -> Never {
        setvbuf(stdout, nil, _IOLBF, 0)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task {
            var status: Int32 = 0
            do {
                try await body()
            } catch {
                FileHandle.standardError.write(Data("error: \(error)\n".utf8))
                status = 1
            }
            fflush(stdout)
            exit(status)
        }
        app.run()
        exit(0)
    }
}

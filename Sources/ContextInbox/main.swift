import AppKit

// One executable, several roles. Headless roles are launched through scripts/headless.sh so
// macOS attributes privacy prompts and grants to this app, not to the terminal.
let args = Array(CommandLine.arguments.dropFirst())

switch args.first {
case "--spike":
    let rest = Array(args.dropFirst())
    Headless.run { try await Spike.run(rest) }
case "--scan-print":
    let rest = Array(args.dropFirst())
    Headless.run { try ScanPrint.run(rest) }
case "--prompt":
    let rest = Array(args.dropFirst())
    Headless.run { try PromptRole.run(rest) }
case "--mark-done":
    let rest = Array(args.dropFirst())
    Headless.run { try MarkDoneRole.run(rest) }
case "--snapshot":
    let rest = Array(args.dropFirst())
    Headless.run { try await Snapshot.run(rest) }
default:
    InboxApp.main()
}

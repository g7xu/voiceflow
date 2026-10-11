import AppKit

// One executable, several roles. Headless roles are launched through scripts/headless.sh so
// macOS attributes privacy prompts and grants to this app, not to the terminal.
let args = Array(CommandLine.arguments.dropFirst())

switch args.first {
case "--spike":
    let rest = Array(args.dropFirst())
    Headless.run { try await Spike.run(rest) }
default:
    print("ContextInbox: the window isn't built yet; try --spike")
}

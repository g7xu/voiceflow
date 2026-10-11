# ContextInbox

Remembers where each file in Downloads and Desktop came from, so Claude can organize them.

ContextInbox scans your inbox folders and records, for every item, the page it was downloaded from,
the app that saved it, and the calendar event you were in when it arrived. It then writes a
Markdown prompt you paste into Claude, which proposes a folder structure and moves the files. The
app itself never moves, renames or deletes anything, and it uses no AI.

This repo started as the voiceflow hackathon project (a voice-memo triage demo, still in git
history). ContextInbox keeps that project's idea — capture loses context that retrieval can't
recover — and applies it to files.

## Install

Requires macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`).

```bash
scripts/build-app.sh
```

```bash
open build/ContextInbox.app
```

To keep privacy permissions across rebuilds, create a self-signed code-signing certificate named
`ContextInbox Dev` first (Keychain Access → Certificate Assistant → Create a Certificate, type
Code Signing). The build script uses it automatically.

## Development

```bash
swift run inbox-tests
```

Behavior, design decisions and the build plan are in [docs/v1-spec.md](docs/v1-spec.md).

The app icon is drawn in code (`scripts/icon/`), with separate artwork for 64 px and below. After
changing it, regenerate `Resources/AppIcon.icns`:

```bash
scripts/make-icon.sh
```

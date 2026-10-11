#!/bin/bash
# Builds build/ContextInbox.app from the release product.
# Signs with $SIGN_ID, else the "ContextInbox Dev" self-signed cert if the keychain has it, else
# ad-hoc. Ad-hoc signatures change on every build, so macOS asks for privacy access again each time.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/ContextInbox.app"
cd "$ROOT"

if [[ -z "${SIGN_ID:-}" ]] && security find-certificate -c "ContextInbox Dev" >/dev/null 2>&1; then
    SIGN_ID="ContextInbox Dev"
fi

swift build -c release --product ContextInbox
BIN="$(swift build -c release --show-bin-path)/ContextInbox"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ContextInbox"
# The signature seals Info.plist, so it must be in place first.
cp Info.plist "$APP/Contents/Info.plist"

codesign --force --sign "${SIGN_ID:--}" "$APP"
echo "built $APP (signed: ${SIGN_ID:-ad-hoc})"

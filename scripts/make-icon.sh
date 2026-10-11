#!/bin/bash
# Regenerates Resources/AppIcon.icns from the drawing code in scripts/icon/. The .icns is committed,
# so building the app doesn't need this; run it after changing the icon.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swiftc -O -o "$WORK/icon-gen" "$ROOT"/scripts/icon/*.swift
"$WORK/icon-gen" "$WORK/AppIcon.iconset"
iconutil -c icns -o "$ROOT/Resources/AppIcon.icns" "$WORK/AppIcon.iconset"
echo "wrote $ROOT/Resources/AppIcon.icns"

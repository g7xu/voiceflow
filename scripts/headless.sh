#!/bin/bash
# Runs a headless role of the built app, e.g. `scripts/headless.sh --spike metadata`.
# It goes through LaunchServices so privacy prompts and grants belong to ContextInbox. Running
# the binary directly would borrow the terminal's grants and hide permission problems.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"
open -n -W --stdout "$OUT/stdout" --stderr "$OUT/stderr" "$ROOT/build/ContextInbox.app" --args "$@"
cat "$OUT/stdout"
cat "$OUT/stderr" >&2

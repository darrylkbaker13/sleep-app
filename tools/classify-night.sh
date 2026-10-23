#!/bin/sh
# Runs Apple's sound classifier over saved nights on a Mac, using the app's own analysis code.
# Usage: tools/classify-night.sh path/to/<session>.json [more.json ...]
set -e
here="$(cd "$(dirname "$0")" && pwd)"
app="$here/../Loop Sense"
out="${TMPDIR:-/tmp}/classify-night"
swiftc -O -o "$out" \
    "$app/SessionStore.swift" "$app/NightAnalysis.swift" "$app/SoundClassifier.swift" \
    "$here/classify-night/main.swift" 2>&1 | grep -v "warning:" || true
"$out" "$@"

#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:?Usage: build_replay_viewer.sh OUTPUT}"
if [[ "$output" != "$root"/* || -L "$output" ]]; then
  echo "Replay output must be a directory inside the project" >&2
  exit 1
fi
export EM_CACHE="${EM_CACHE:-$root/build/emscripten-cache}"
export GALCON_WEB="$root/build/web"
mkdir -p "$EM_CACHE" "$output"
cd "$root"
nim c -d:release -d:emscripten -d:replayViewer src/galcon.nim
cp "$GALCON_WEB/galcon.html" "$output/index.html"
for suffix in js wasm data; do
  cp "$GALCON_WEB/galcon.$suffix" "$output/galcon.$suffix"
done
cp assets/banner.png "$output/banner.png"
cp LICENSE "$output/LICENSE"

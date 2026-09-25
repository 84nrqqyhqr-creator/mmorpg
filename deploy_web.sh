#!/usr/bin/env bash
set -euo pipefail

# --------- config ----------
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
PRESET="Web"
OUT_DIR="exports/web"

HOST="gamestudio@64.225.2.31"
REMOTE_WEB="/var/www/mmorpg"
URL="https://64-225-2-31.sslip.io"
# --------------------------

echo "==> Exporting web client..."
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

"$GODOT" --headless --export-release "$PRESET" "$OUT_DIR/index.html"

echo "==> Checking build outputs..."
ls -lah "$OUT_DIR"

echo "==> Uploading to $HOST:$REMOTE_WEB ..."
rsync -az --delete "$OUT_DIR/" "$HOST:$REMOTE_WEB/"

echo "✅ Done. Play at $URL"

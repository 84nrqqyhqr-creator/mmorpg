#!/usr/bin/env bash
set -euo pipefail

# --------- config ----------
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
PRESET="ServerLinux"
OUT_DIR="exports/server/build/latest"

HOST="gamestudio@64.225.2.31"
REMOTE_BIN="/home/gamestudio/srv/game/bin"
SERVICE="mmorpg-server.service"
PORT="8080"
PROCESS_NAME="server.x86_64"
# --------------------------

echo "==> Exporting server build..."
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

"$GODOT" --headless --export-release "$PRESET" "$OUT_DIR/server.x86_64"

echo "==> Checking build outputs..."
ls -lah "$OUT_DIR"/server.*

echo "==> Uploading artifacts as .new..."
scp "$OUT_DIR/server.x86_64" "$HOST:~/server.x86_64.new"
scp "$OUT_DIR/server.pck"    "$HOST:~/server.pck.new"
scp "$OUT_DIR/server.sh"     "$HOST:~/server.sh.new"

echo "==> Activating on server + restarting service..."
ssh "$HOST" bash -s -- "$SERVICE" "$REMOTE_BIN" "$PORT" "$PROCESS_NAME" <<'REMOTE'
set -euo pipefail
SERVICE="$1"
REMOTE_BIN="$2"
PORT="$3"
PROCESS_NAME="$4"

echo "Stopping service..."
sudo -n /bin/systemctl stop "$SERVICE"

echo "Swapping files..."
mv -f ~/server.x86_64.new "$REMOTE_BIN/server.x86_64"
mv -f ~/server.pck.new    "$REMOTE_BIN/server.pck"
mv -f ~/server.sh.new     "$REMOTE_BIN/server.sh"

chmod +x "$REMOTE_BIN/server.x86_64" "$REMOTE_BIN/server.sh"

echo "Starting service..."
sudo -n /bin/systemctl start "$SERVICE"

echo "Service status:"
sudo -n /bin/systemctl status "$SERVICE" --no-pager -l | sed -n '1,25p'

echo "Waiting for port $PORT..."
for i in {1..40}; do
  if ss -lnt 2>/dev/null | grep -q ":$PORT"; then
    echo "✅ Port $PORT is listening"
    ss -lnt | grep ":$PORT" || true
    break
  fi
  sleep 0.25
done

ss -lnt 2>/dev/null | grep -q ":$PORT" || { echo "❌ ERROR: $PORT not listening"; exit 1; }

# Confirm the service PID is our server binary (no sudo needed)
PID="$(systemctl show -p MainPID --value "$SERVICE" || true)"
echo "MainPID=$PID"
if [[ -z "${PID}" || "${PID}" == "0" ]]; then
  echo "❌ ERROR: systemd did not report a valid MainPID"
  exit 1
fi

COMM="$(ps -p "$PID" -o comm= 2>/dev/null || true)"
ARGS="$(ps -p "$PID" -o args= 2>/dev/null || true)"
echo "Process: comm=$COMM"
echo "Process: args=$ARGS"

if [[ "$COMM" != "$PROCESS_NAME" ]]; then
  echo "❌ ERROR: service PID is not $PROCESS_NAME (got '$COMM')"
  exit 1
fi

echo "✅ $PROCESS_NAME is running and port $PORT is open"
echo "Done."
REMOTE

#!/bin/bash
# Deploy the exported launcher build to the arcade cabinet.
# Run from Git Bash / Linux: bash tools/deploy_launcher.sh
# Keep in sync with deploy_launcher.nu.
#
# Single SSH connection: both files are streamed through stdin via tar,
# extracted to a temp dir, then renamed into place (a rename avoids the
# "Text file busy" error you get overwriting a running binary in place).
set -euo pipefail

HOST="${ARCADE_HOST:-alien@172.31.78.116}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
mkdir -p "$BUILD_DIR"

# Export the Linux build first (preset "Linux" in export_presets.cfg).
GODOT="${GODOT_EDITOR:-godot}"
command -v "$GODOT" >/dev/null 2>&1 || {
  echo "Godot editor not found — set GODOT_EDITOR to your editor binary." >&2
  exit 1
}
echo ">> Exporting Linux build with $GODOT"
"$GODOT" --headless --path "$PROJECT_DIR" --export-release "Linux" "$BUILD_DIR/launcher.x86_64"

for f in launcher.x86_64 launcher.pck; do
  [ -f "$BUILD_DIR/$f" ] || { echo "Missing $BUILD_DIR/$f — export failed?" >&2; exit 1; }
done

REMOTE='
set -e
# Binary lives in /arcade directly: exported Godot pins its CWD to the exe
# dir, so exe dir == data root keeps games/, scores/, logs/ resolving there.
D=/arcade
mkdir -p "$D/.new"
tar -xf - -C "$D/.new"
chmod +x "$D/.new/launcher.x86_64"
mv -f "$D/.new/launcher.x86_64" "$D/launcher.x86_64"
mv -f "$D/.new/launcher.pck"    "$D/launcher.pck"
rmdir "$D/.new"
echo ">> files installed in $D"
pids=$(pgrep -x launcher.x86_64 || true)
if [ -z "$pids" ]; then
    echo ">> launcher not running — nothing to restart"
elif kill $pids 2>/dev/null; then
    echo ">> launcher stopped (pid $pids); systemd will respawn it with the new build"
else
    owner=$(ps -o user= -p $(echo $pids | cut -d" " -f1))
    echo ">> WARN: cannot signal launcher pid $pids — it runs as user $owner, not $(whoami)."
    echo ">>       New build is deployed but NOT live. Restart it as that user, e.g.:"
    echo ">>       sudo systemctl restart arcade-launcher"
fi
'

echo ">> Deploying to $HOST — single connection, one login"
tar -C "$BUILD_DIR" -cf - launcher.x86_64 launcher.pck | ssh "$HOST" "$REMOTE"
echo ">> Deploy complete."

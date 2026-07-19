#!/bin/bash
# watch_games.sh - Monitor ./games (relative to CWD) for changes and signal
# the launcher. The systemd unit runs this with WorkingDirectory=/arcade.
set -e

GAMES_DIR="$PWD/games"
EVENT_FILE="/tmp/arcade_event"

# Check if inotifywait is installed
if ! command -v inotifywait &> /dev/null; then
    echo "Error: inotifywait is not installed. Please install inotify-tools:"
    echo "  sudo apt-get install inotify-tools"
    exit 1
fi

# Check if games directory exists
if [ ! -d "$GAMES_DIR" ]; then
    echo "Warning: $GAMES_DIR does not exist. Creating it..."
    mkdir -p "$GAMES_DIR"
fi

# SFTP uploads often drop the exec bit; game binaries need it to launch.
# Note: chmod emits IN_ATTRIB only, which we don't watch, so no event loop.
fix_exec_bit() {
    local path="$1"
    case "$path" in
        *.AppImage|*.x86_64)
            if [ -f "$path" ] && [ ! -x "$path" ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') - Setting executable: $path"
                chmod +x "$path" || echo "Warning: chmod failed for $path"
            fi
            ;;
    esac
}

# Startup sweep: fix binaries uploaded while the watcher wasn't running
find "$GAMES_DIR" -type f \( -name '*.AppImage' -o -name '*.x86_64' \) ! -perm -u+x -print0 | \
    while IFS= read -r -d '' path; do
        fix_exec_bit "$path"
    done

echo "Watching $GAMES_DIR for changes..."

# Monitor recursively for create, delete, move, and write events
inotifywait -m -r -e create,delete,move,close_write "$GAMES_DIR" --format '%w%f' | while read -r path; do
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Change detected: $path"
    fix_exec_bit "$path"
    echo "games_changed" > "$EVENT_FILE"
done

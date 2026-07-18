# c-base Arcade Upload Spec v1.0

Game upload specification for the c-base Arcade Launcher.

## Overview

The c-base Arcade Launcher supports drop-in games via simple folder uploads to `/arcade/games/`. Each game is a self-contained folder with all required assets and metadata.

## Folder Structure

```
/arcade/games/<your_game_folder>/
├── game.x86_64 or game.AppImage    # Required: Linux executable (any exec-bit file works)
├── game.pck                         # Bare Godot exports only: pack file, same base name as exec
├── game.json                        # Recommended: Metadata
├── preview.mp4 or preview.ogv      # Recommended: Gameplay video
├── screenshot.png                   # Recommended: Fallback image
└── icon.png                        # Recommended: List icon
```

## Required Files

### 1. Linux Executable

The **only required file** — everything else is optional.

**File name:** anything. `*.x86_64` and `*.AppImage` are always recognized;
any other file with the exec bit set works too (e.g. a bare Unity binary).
If several qualify, conventionally-named ones win.

**Requirements:**
- Linux x86_64 build
- Executable bit set (`chmod +x`) — SFTP uploads often drop it!

### 2. Godot Pack File (bare Godot exports only)

Needed only for Godot exports **without an embedded PCK**. Unity games and
AppImages never need one.

**File name:** same base name as the executable, ending in `.pck` — the
launcher starts the executable without path arguments, so Godot finds the
pack by filename. A mismatched name means the game won't start.

**Example:**
```bash
game.x86_64 + game.pck   # ✓
game.x86_64 + data.pck   # ✗ won't start
```

### 3. Required Input Actions

Your game **MUST** implement these Godot InputMap actions:

- `ui_up`, `ui_down`, `ui_left`, `ui_right` - Navigation
- `ui_accept` - Start/confirm (Button 1)
- `ui_cancel` - Back/menu (Button 2)
- **`ui_exit`** - **MANDATORY:** Exit game and return to launcher

**Critical:** The `ui_exit` action must immediately quit your game using `get_tree().quit()`. Without this, players cannot return to the launcher!

Example GDScript implementation:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_exit"):
        get_tree().quit()
```

### 4. Display Settings

The launcher starts your game with `--fullscreen`. To avoid a distorted
picture on arbitrary screens, set in `project.godot`:

```ini
[display]
window/stretch/mode="canvas_items"   # or "viewport" for pixel art
window/stretch/aspect="keep"         # or "expand" — never "ignore" (distorts)
```

Design for 16:9 (e.g. 1920×1080), but don't assume the exact resolution.

## Unity Games

Upload the Linux build output as-is:

```
/arcade/games/<your_game_folder>/
├── mygame.x86_64          # Unity player executable
├── UnityPlayer.so         # Unity 2019+
├── mygame_Data/           # Data directory
└── game.json / screenshot.png / icon.png / preview.ogv   # optional
```

Detection is automatic (`UnityPlayer.so` or `*_Data`); no `.pck` involved.
Games are started with `-screen-fullscreen 1`.

**Input:** the Godot InputMap contract doesn't apply — read the cabinet
controls via Unity's input system, and quit to the launcher on the exit
button (Godot's `ui_exit` button) via `Application.Quit()`.

## Recommended Files

### 1. Game Metadata (game.json)

Provides information displayed in the launcher.

**File name:** `game.json`

**Format:**
```json
{
  "title": "Your Game Title",
  "author": "Your Name or Studio",
  "description": "A short description of your game. What makes it fun? What's the goal?",
  "players": 2,
  "year": 2024
}
```

**Fields:**
- `title` (string): Display name of your game
- `author` (string): Your name, studio, or "Anonymous"
- `description` (string): 1-3 sentences about the game
- `players` (integer): Maximum number of players (1, 2, 3, 4, etc.)
- `year` (integer): Release year

**Fallback:** If `game.json` is missing, the launcher will use the folder name as the title.

### 2. Preview Video

**File name:** `preview.mp4` or `preview.ogv` (prefer .ogv for better compatibility)

**Requirements:**
- 5-15 seconds of gameplay footage
- Resolution: 1280x720 or 1920x1080
- Format: Ogg Theora (.ogv) recommended, MP4 supported but may vary by system
- Low or no audio (optional)
- Shows typical gameplay, not just title screen

**Purpose:** Displays in the details panel when your game is selected, giving players a preview of gameplay.

**Tip:** Use OBS Studio or ffmpeg to record gameplay:
```bash
ffmpeg -i gameplay.mp4 -c:v libtheora -q:v 7 -c:a libvorbis -q:a 5 preview.ogv
```

### 3. Screenshot

**File name:** `screenshot.png`

**Requirements:**
- PNG format
- Minimum 1280x720, recommended 1920x1080
- Shows gameplay or title screen
- Used as fallback if preview video is missing

**Purpose:** Static image displayed when video isn't available.

### 4. Icon

**File name:** `icon.png`

**Requirements:**
- PNG format
- 64x64 to 256x256 pixels (128x128 recommended)
- Square aspect ratio
- Transparent background optional

**Purpose:** Small icon shown in the game list next to your game title.

## Enforcement Rules

The launcher handles missing files gracefully:

| Condition | Launcher Behavior |
|-----------|------------------|
| No executable in folder | Game hidden from list |
| Missing `.pck` (bare Godot export) | Game listed but fails to start |
| Missing `ui_exit` action | Game shown but players can't return to launcher (BAD!) |
| Missing `game.json` | Uses folder name as title, shows "Unknown" author |
| Missing `preview.mp4/.ogv` | Falls back to `screenshot.png` |
| Missing `screenshot.png` | Falls back to `icon.png` |
| Missing `icon.png` | Shows no icon, game still launchable |
| Invalid JSON in `game.json` | Ignores metadata, uses folder name |

## Input Device Support

Players use arcade joysticks and buttons. Your game should support:

**Minimum (required):**
- Joystick/D-Pad for movement
- Button 1 (ui_accept) for confirm/start
- Button 2 (ui_cancel) for back/pause
- **ui_exit** action for returning to launcher

**Recommended:**
- Multiple buttons for different actions
- 1-4 player support
- Clear on-screen button prompts (e.g., "Press Button 1 to start")

## Score Submission (Optional)

Games can submit high scores to the launcher's score system.

**Location:** `/arcade/scores/<your_game_id>.json`

**Game ID:** Your folder name (e.g., `space_shooter`)

**Format:**
```json
[
  {"name": "AAA", "score": 10000},
  {"name": "BBB", "score": 8500},
  {"name": "CCC", "score": 7200}
]
```

**Example GDScript code:**
```gdscript
func submit_score(player_name: String, score: int) -> void:
    var game_id = "space_shooter"  # Use your folder name
    var scores_path = "/arcade/scores/%s.json" % game_id

    # Load existing scores
    var scores = []
    if FileAccess.file_exists(scores_path):
        var file = FileAccess.open(scores_path, FileAccess.READ)
        scores = JSON.parse_string(file.get_as_text())
        if typeof(scores) != TYPE_ARRAY:
            scores = []

    # Add new score
    scores.append({"name": player_name, "score": score})

    # Sort descending
    scores.sort_custom(func(a, b): return a["score"] > b["score"])

    # Keep top 10
    if scores.size() > 10:
        scores = scores.slice(0, 10)

    # Save
    var file = FileAccess.open(scores_path, FileAccess.WRITE)
    file.store_string(JSON.stringify(scores, "  "))
```

## Upload Methods

### Method 1: SFTP (Recommended)

```bash
sftp arcade@<cabinet-ip>
cd /arcade/games
mkdir my_game
cd my_game
put game.x86_64
put game.pck
put game.json
put screenshot.png
put icon.png
put preview.ogv
quit
```

### Method 2: SCP

```bash
scp -r my_game/ arcade@<cabinet-ip>:/arcade/games/
```

### Method 3: Rsync

```bash
rsync -avz my_game/ arcade@<cabinet-ip>:/arcade/games/my_game/
```

## Testing Checklist

Before uploading your game:

- [ ] Game exports correctly for Linux x86_64
- [ ] Executable is present (bare Godot exports: matching `.pck` too)
- [ ] Executable has execute permission (`chmod +x game.x86_64`)
- [ ] `ui_exit` action is implemented and quits the game
- [ ] All input actions (ui_up, ui_down, ui_accept, ui_cancel) work
- [ ] Game runs fullscreen
- [ ] Game.json is valid JSON with all fields
- [ ] Screenshot shows gameplay clearly
- [ ] Preview video is 5-15 seconds, reasonable file size (<50MB)
- [ ] Icon is clear at 128x128 pixels
- [ ] Game handles joystick/gamepad input
- [ ] Game tested on Linux (VM or native)

## Common Issues

### Game doesn't appear in launcher

**Cause:** Missing required files or incorrect file extensions

**Fix:**
- Ensure an executable exists and has its exec bit (`chmod +x`)
- Check file names (case-sensitive on Linux)

### Can't return to launcher from game

**Cause:** Missing or broken `ui_exit` input action

**Fix:**
- Implement `ui_exit` action in your game's InputMap
- Add code to handle `ui_exit` and call `get_tree().quit()`

### Preview video doesn't play

**Cause:** MP4 codec issues or corrupted file

**Fix:**
- Convert video to Ogg Theora (.ogv) format
- Reduce video resolution to 1280x720
- Ensure file is not corrupted

### Game runs slowly

**Cause:** High system requirements or inefficient code

**Fix:**
- Optimize game performance
- Lower graphics settings
- Test on target hardware before upload

### Permissions errors

**Cause:** Uploaded files don't have correct permissions

**Fix:**
```bash
# On the cabinet
chmod +x /arcade/games/my_game/*.x86_64
chmod 644 /arcade/games/my_game/*.pck
chmod 644 /arcade/games/my_game/*.json
```

## Best Practices

1. **Test on Linux:** Always test your game on Linux before uploading
2. **Keep it small:** Optimize asset sizes to reduce upload time
3. **Clear controls:** Show button prompts on title screen
4. **Fast loading:** Minimize loading times for better arcade experience
5. **Attract mode:** Make your game's title screen eye-catching
6. **Exit gracefully:** Save player progress before exiting on `ui_exit`
7. **Error handling:** Handle missing assets gracefully
8. **Fullscreen:** Always run in fullscreen mode
9. **Audio levels:** Keep volume reasonable, respect system audio
10. **Multiplayer:** Clearly indicate if game supports multiple players

## Example Game Folder

Complete example of a well-structured game:

```
/arcade/games/space_invaders_2024/
├── space_invaders.x86_64           # Executable (5.2 MB)
├── space_invaders.pck              # Game data (12.8 MB)
├── game.json                       # Metadata
├── preview.ogv                     # 10-second gameplay clip (8.3 MB)
├── screenshot.png                  # Title screen (1920x1080, 890 KB)
└── icon.png                        # Ship sprite (128x128, 15 KB)
```

**game.json:**
```json
{
  "title": "Space Invaders 2024",
  "author": "RetroGames Studio",
  "description": "Classic arcade shooter with modern graphics. Defend Earth from alien invaders across 10 challenging waves!",
  "players": 2,
  "year": 2024
}
```

## Version History

- **v1.0** (2024) - Initial specification

## Questions?

For questions or issues:
- Check the main [README.md](README.md)
- Review [INSTALL.md](INSTALL.md) for setup issues
- Report bugs on GitHub: [repository URL]

---

**Happy game making! We can't wait to see your games on the c-base arcade cabinet! 🚀**

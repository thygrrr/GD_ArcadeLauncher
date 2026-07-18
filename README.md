# c-base Arcade Launcher

A fullscreen sci-fi arcade game launcher for Godot 4.7, designed for physical arcade cabinets running Ubuntu Linux with X11.

## Features

- Automatic game detection from `/arcade/games` directory
- Fullscreen launcher with space-station OS theme
- Drop-in game support via SFTP upload
- Preview videos and screenshots for each game
- Per-game high score tracking
- Live game list refresh without restart
- Attract mode with auto-scrolling
- Boot sequence animation
- Gamepad and keyboard support

## System Requirements

- Ubuntu Linux (20.04 or newer recommended)
- X11 display server (Wayland should be disabled)
- Godot 4.7 or compatible version
- inotify-tools package for live refresh

## Quick Start

For detailed installation instructions, see [INSTALL.md](INSTALL.md).

1. Set up Ubuntu with X11
2. Create `/arcade` directory structure
3. Export and install the launcher
4. Install systemd services
5. Upload games to `/arcade/games`

## Game Upload Specification

See [GAME_SPEC.md](GAME_SPEC.md) for the complete game upload specification (c-base Arcade Upload Spec v1.0).

### Quick Summary

Each game folder under `/arcade/games/` must contain:

**Required:**
- Linux executable: `*.x86_64` OR `*.AppImage`
- Godot pack: `*.pck`
- Must support `ui_exit` input action to quit

**Strongly Recommended:**
- `game.json` - metadata (title, author, description, players, year)
- `preview.mp4` or `preview.ogv` - gameplay clip (5-15 seconds)
- `screenshot.png` - fallback image
- `icon.png` - list entry icon

## Project Structure

```
GD_ArcadeLauncher/
├── project.godot
├── scenes/
│   ├── Boot.tscn          # Boot sequence (optional)
│   ├── Launcher.tscn      # Main launcher UI
│   └── GameEntry.tscn     # Game list item template
├── scripts/
│   ├── Boot.gd
│   ├── Launcher.gd        # Main controller
│   ├── GameInfo.gd        # Game data model
│   ├── GameScanner.gd     # Directory scanner
│   └── ScoreStore.gd      # High score manager
├── media/
│   ├── sounds/
│   ├── fonts/
│   └── shaders/
├── tools/
│   └── watch_games.sh     # inotify watcher script
└── install/
	└── systemd/
		├── arcade-launcher.service
		└── arcade-watch.service
```

## Development

Built with Godot 4.7 using GDScript.

### Input Actions

The launcher uses standard Godot input actions:
- `ui_up`, `ui_down` - Navigate game list
- `ui_accept` - Launch selected game
- `ui_cancel` - Back/cancel
- `ui_exit` - Exit game (required for all games)

### Building and Exporting

1. Open the project in Godot 4.7.x
2. Go to Project → Export
3. Select Linux/X11 preset
4. Export as `launcher.x86_64` with embedded PCK or separate `.pck` file

## Contributing

Contributions welcome! Please ensure:
- Code follows existing GDScript style
- New features are documented
- Game upload specification compatibility is maintained

## License

[Add your license here]

## Credits

Developed for the c-base space station arcade cabinet.

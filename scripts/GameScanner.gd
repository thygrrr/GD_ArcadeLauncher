# res://scripts/GameScanner.gd
# Scans /arcade/games directory and builds GameInfo objects
extends Node
class_name GameScanner

const GAMES_DIR := "/arcade/games"

# Fullscreen flag per engine, resolved at scan time so the launch path stays
# engine-agnostic. Only display args are passed: Godot 4.4+ export templates
# reject path overrides like --main-pack, and the binary finds its pck on its
# own (embedded, or basename-matched next to the executable).
const ENGINE_ARGS := {
	"godot": ["--fullscreen"],
	"unity": ["-screen-fullscreen", "1"],
}

var _is_linux := OS.get_name() == "Linux"

# Populated after each scan_games() call; used by admin overlay
var scan_warnings: Array[String] = []

func scan_games() -> Array[GameInfo]:
	scan_warnings.clear()
	var results: Array[GameInfo] = []
	var dir := DirAccess.open(GAMES_DIR)
	if dir == null:
		push_error("Games directory not found: %s" % GAMES_DIR)
		scan_warnings.append("ERROR: Cannot open %s" % GAMES_DIR)
		return results

	dir.list_dir_begin()
	var directory_name := dir.get_next()
	while directory_name != "":
		if dir.current_is_dir() and not directory_name.begins_with("."):
			var info := _scan_game_folder(GAMES_DIR.path_join(directory_name))
			if info != null:
				if info.is_launchable():
					results.append(info)
				else:
					scan_warnings.append("SKIP: %s (no executable found)" % directory_name)
		directory_name = dir.get_next()
	dir.list_dir_end()
	return results

func _scan_game_folder(folder: String) -> GameInfo:
	var info := GameInfo.new()
	info.folder_path = folder
	info.game_id = folder.get_file()

	var exec_path: String = ""

	var dir := DirAccess.open(folder)
	if dir == null:
		return null

	var json_path := folder.path_join("game.json")
	var preview_path := folder.path_join("preview.mp4")
	var screenshot_path := folder.path_join("screenshot.png")
	var icon_path := folder.path_join("icon.png")

	var fallback_exec := ""
	var engine := "godot"
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir():
			if f.ends_with(".x86_64") or f.ends_with(".AppImage"):
				exec_path = folder.path_join(f)
			elif f == "preview.ogv":
				preview_path = folder.path_join(f)
			elif f == "UnityPlayer.so":
				engine = "unity"
			elif exec_path == "" and fallback_exec == "" and _looks_executable(folder.path_join(f)):
				fallback_exec = folder.path_join(f)
		elif f.ends_with("_Data"):
			# Unity builds older than 2019 have no UnityPlayer.so, but always
			# ship a <name>_Data directory next to the executable.
			engine = "unity"
		f = dir.get_next()
	dir.list_dir_end()

	# Executable names are free-form: if nothing matched the conventional
	# extensions, the first exec-bit ELF or script file counts (Unity builds
	# are often a bare "gamename" binary with no extension).
	if exec_path == "":
		exec_path = fallback_exec
	elif _is_linux and not _looks_executable(exec_path):
		# A conventionally-named "executable" that isn't actually runnable
		# (empty file from a botched upload, missing exec bit) would exec as
		# an empty shell script and exit 0 silently — reject it loudly.
		scan_warnings.append("WARN: %s — %s is empty/not ELF or lacks +x; rejected"
			% [info.game_id, exec_path.get_file()])
		exec_path = fallback_exec

	info.exec_path = exec_path
	info.launch_args = PackedStringArray(ENGINE_ARGS[engine])

	if FileAccess.file_exists(icon_path): info.icon_path = icon_path
	if FileAccess.file_exists(screenshot_path): info.screenshot_path = screenshot_path
	if FileAccess.file_exists(preview_path): info.preview_path = preview_path

	# Use exec mtime as the game's modification time (most stable sentinel)
	var mtime_source := exec_path if exec_path != "" else json_path
	if mtime_source != "" and FileAccess.file_exists(mtime_source):
		info.last_modified = int(FileAccess.get_modified_time(mtime_source))

	_load_metadata(info, json_path)
	_fallback_title(info)
	return info

func _looks_executable(path: String) -> bool:
	# Exec bits only exist on the cabinet's Linux filesystem; during Windows
	# development only conventionally-named executables are detected.
	if not _is_linux:
		return false
	# SFTP uploads routinely stamp exec bits on everything, so the bit alone
	# isn't enough: positively identify binaries by magic bytes instead of
	# maintaining a denylist of asset extensions. Shared libraries are ELF
	# too, hence the explicit .so exclusion.
	if path.get_extension().to_lower() == "so":
		return false
	if FileAccess.get_unix_permissions(path) & 0x49 == 0:   # ---x--x--x
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var magic := file.get_buffer(4)
	if magic.size() < 4:
		return false
	var is_elf := magic == PackedByteArray([0x7F, 0x45, 0x4C, 0x46])  # \x7FELF
	var is_script := magic[0] == 0x23 and magic[1] == 0x21             # "#!"
	return is_elf or is_script

func _load_metadata(info: GameInfo, json_path: String) -> void:
	if not FileAccess.file_exists(json_path):
		return
	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	info.title = str(d.get("title", info.title))
	info.author = str(d.get("author", info.author))
	info.description = str(d.get("description", info.description))
	info.players = int(d.get("players", info.players))
	info.year = int(d.get("year", info.year))

func _fallback_title(info: GameInfo) -> void:
	if info.title.strip_edges() == "":
		info.title = info.game_id.replace("_", " ").capitalize()

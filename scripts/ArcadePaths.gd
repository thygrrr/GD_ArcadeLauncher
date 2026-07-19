# res://scripts/ArcadePaths.gd
# Resolves all launcher data locations relative to the process working
# directory (the systemd units set WorkingDirectory=/arcade), so the same
# build also works in a local dev checkout without hardcoded absolute paths.
class_name ArcadePaths

static var base_dir: String = _resolve_cwd()
static var games_dir: String = base_dir.path_join("games")
static var scores_dir: String = base_dir.path_join("scores")
static var logs_dir: String = base_dir.path_join("logs")
static var state_file: String = base_dir.path_join("launcher_state.json")

static func _resolve_cwd() -> String:
	var dir := DirAccess.open(".")
	return dir.get_current_dir() if dir != null else "."

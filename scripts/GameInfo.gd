# res://scripts/GameInfo.gd
# Data class representing a single arcade game
class_name GameInfo

var game_id: String        # stable id derived from folder name (or hash later)
var title: String = ""
var author: String = "Unknown"
var description: String = ""
var players: int = 1
var year: int = 0

var folder_path: String = ""
var exec_path: String = ""
var launch_args: PackedStringArray = []   # engine-specific, filled by GameScanner
var icon_path: String = ""
var screenshot_path: String = ""
var preview_path: String = ""
var last_modified: int = 0

func is_launchable() -> bool:
	return exec_path != ""

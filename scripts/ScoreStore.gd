# res://scripts/ScoreStore.gd
# Manages per-game high scores stored in scores/ under the working directory
extends Node
class_name ScoreStore

const MAX_SCORES := 10

func load_scores(game_id: String) -> Array:
	var path := ArcadePaths.scores_dir.path_join("%s.json" % game_id)
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_ARRAY:
		return []
	return parsed

func save_scores(game_id: String, scores: Array) -> void:
	DirAccess.make_dir_recursive_absolute(ArcadePaths.scores_dir)
	var path := ArcadePaths.scores_dir.path_join("%s.json" % game_id)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(scores, "  "))

func submit_score(game_id: String, player_name: String, score: int) -> void:
	var scores := load_scores(game_id)
	scores.append({"name": player_name, "score": score})
	scores.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
	if scores.size() > MAX_SCORES:
		scores = scores.slice(0, MAX_SCORES)
	save_scores(game_id, scores)

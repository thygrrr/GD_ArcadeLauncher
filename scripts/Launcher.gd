# res://scripts/Launcher.gd
# Main arcade launcher controller
extends Control

# ── Constants ──────────────────────────────────────────────────────────────────
const EVENT_FILE := "/tmp/arcade_event"
const GAME_LOG_DIR := "/arcade/logs"
const STATE_FILE := "/arcade/launcher_state.json"
const ADMIN_HOLD_THRESHOLD := 3.0   # seconds to hold ACCEPT+CANCEL for admin
const PAGE_SIZE := 5                 # entries to skip on page up/down
const NEW_GAME_SECONDS := 86400      # 24 h — games newer than this get ★ NEW badge

# ── Node references ────────────────────────────────────────────────────────────
@onready var game_list: VBoxContainer        = $MainLayout/GameListPanel/VBoxContainer/ScrollContainer/GameList
@onready var scroll_container: ScrollContainer = $MainLayout/GameListPanel/VBoxContainer/ScrollContainer
@onready var title_label: Label              = $MainLayout/GameDetailsPanel/VBoxContainer/TitleLabel
@onready var author_label: Label             = $MainLayout/GameDetailsPanel/VBoxContainer/AuthorLabel
@onready var desc_label: RichTextLabel       = $MainLayout/GameDetailsPanel/VBoxContainer/DescriptionLabel
@onready var meta_label: Label               = $MainLayout/GameDetailsPanel/VBoxContainer/MetaLabel
@onready var preview: VideoStreamPlayer      = $MainLayout/GameDetailsPanel/VBoxContainer/MediaContainer/PreviewVideo
@onready var icon_or_shot: TextureRect       = $MainLayout/GameDetailsPanel/VBoxContainer/MediaContainer/IconOrScreenshot
@onready var score_list: VBoxContainer       = $MainLayout/GameDetailsPanel/VBoxContainer/ScorePanel/ScoreList
@onready var score_panel: VBoxContainer      = $MainLayout/GameDetailsPanel/VBoxContainer/ScorePanel
@onready var fade_rect: ColorRect            = $FadeLayer/FadeRect
@onready var debounce_timer: Timer           = $DebounceTimer
@onready var attract_timer: Timer            = $AttractTimer
@onready var selection_glow: TextureRect     = $SelectionGlow
@onready var glow_pulse_timer: Timer         = $GlowPulseTimer
@onready var game_count_label: Label         = $Footer/HBoxContainer/GameCountLabel
@onready var attract_overlay: CanvasLayer    = $AttractOverlay
@onready var attract_label: Label            = $AttractOverlay/AttractLabel
@onready var admin_overlay: CanvasLayer      = $AdminOverlay
@onready var admin_info: RichTextLabel       = $AdminOverlay/AdminPanel/VBoxContainer/AdminInfo
@onready var ui_sfx: AudioStreamPlayer       = $UiSfx
@onready var ui_confirm_sfx: AudioStreamPlayer = $UiConfirmSfx
@onready var clock_label: Label              = $Header/HBoxContainer/StatusIndicator/ClockLabel

# ── Services ───────────────────────────────────────────────────────────────────
var scanner := GameScanner.new()
var score_store := ScoreStore.new()

# ── State ──────────────────────────────────────────────────────────────────────
var games: Array[GameInfo] = []
var selected_index: int = 0
var launching: bool = false
var _game_pid: int = -1
var _game_log_path: String = ""
var in_attract_mode: bool = false
var last_game_id: String = ""

var _glow_pulse: float = 0.0
var _attract_scroll_timer: float = 0.0
var _attract_blink_timer: float = 0.0
var _attract_blink_state: bool = true
var _admin_hold_time: float = 0.0
var _list_build_id: int = 0
var _texture_cache: Dictionary = {}   # path -> Texture2D (null for failed loads)

var _clock_tick: float = 0.0             # seconds since last clock update
var _glitch_cooldown: float = 0.0        # seconds until next ambient glitch burst
var _typewriter_tween: Tween = null      # active typewriter animation
var _glitch_layer: CanvasLayer = null    # CanvasLayer hosting effects + glitch bars

# ── Lifecycle ──────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Same WM race guard as Boot.gd, in case the boot scene is skipped
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	add_child(scanner)
	add_child(score_store)

	fade_rect.modulate.a = 1.0
	attract_overlay.visible = false
	admin_overlay.visible = false

	debounce_timer.one_shot = true
	debounce_timer.wait_time = 0.5
	debounce_timer.timeout.connect(_reload_games)

	attract_timer.one_shot = true
	attract_timer.wait_time = 30.0
	attract_timer.timeout.connect(_enter_attract_mode)
	_reset_attract_timer()

	glow_pulse_timer.timeout.connect(_update_glow_pulse)

	# Generate procedural UI sounds (no audio files required)
	ui_sfx.stream = _create_beep(880.0, 0.05)
	ui_sfx.volume_db = -6.0
	ui_confirm_sfx.stream = _create_beep(1320.0, 0.12)
	ui_confirm_sfx.volume_db = -4.0

	_load_state()
	_reload_games()
	_fade_in(0.8)
	_setup_effects()
	_update_clock()

func _process(delta: float) -> void:
	# ── Game watchdog: launcher stays alive while a game runs (a frozen
	# Wayland client gets close-requested) but dormant — input blocked by
	# the guards, everything below skipped until the game exits.
	if _game_pid >= 0:
		if not OS.is_process_running(_game_pid):
			_on_game_exited()
		return

	# ── Clock (update once per second) ──
	_clock_tick += delta
	if _clock_tick >= 1.0:
		_clock_tick -= 1.0
		_update_clock()

	# ── Ambient glitch bursts ──
	if not in_attract_mode and not launching:
		_glitch_cooldown -= delta
		if _glitch_cooldown <= 0.0:
			_glitch_cooldown = randf_range(15.0, 35.0)
			_fire_ambient_glitch()

	# ── Filesystem watcher ──
	if FileAccess.file_exists(EVENT_FILE):
		DirAccess.remove_absolute(EVENT_FILE)
		if not debounce_timer.is_stopped():
			debounce_timer.stop()
		debounce_timer.start()

	# ── Attract mode: auto-scroll + blinking label ──
	if in_attract_mode and not games.is_empty():
		_attract_scroll_timer += delta
		if _attract_scroll_timer >= 5.0:
			_attract_scroll_timer = 0.0
			_select_game((selected_index + 1) % games.size())

		_attract_blink_timer += delta
		if _attract_blink_timer >= 0.55:
			_attract_blink_timer = 0.0
			_attract_blink_state = !_attract_blink_state
			attract_label.visible = _attract_blink_state

	# ── Admin hold combo: ACCEPT + CANCEL held for 3 s ──
	if not admin_overlay.visible and not launching and not in_attract_mode:
		if Input.is_action_pressed("ui_accept") and Input.is_action_pressed("ui_cancel"):
			_admin_hold_time += delta
			if _admin_hold_time >= ADMIN_HOLD_THRESHOLD:
				_admin_hold_time = 0.0
				_show_admin_overlay()
		else:
			_admin_hold_time = 0.0

func _update_glow_pulse() -> void:
	_glow_pulse += 0.1
	if not games.is_empty() and selection_glow.visible:
		var pulse := sin(_glow_pulse * 2.0) * 0.3 + 0.7
		selection_glow.modulate = Color(0, 0.8, 1, 0.4 * pulse)

# ── Game list ──────────────────────────────────────────────────────────────────
func _reload_games() -> void:
	if launching:
		return
	_texture_cache.clear()
	games = scanner.scan_games()
	games.sort_custom(func(a, b): return a.title.naturalnocasecmp_to(b.title) < 0)
	_rebuild_list()

func _rebuild_list() -> void:
	# Increment build ID so any in-flight coroutines from previous builds abort
	_list_build_id += 1
	var build_id := _list_build_id

	for c in game_list.get_children():
		c.queue_free()

	if games.is_empty():
		_select_game(0)
		selection_glow.visible = false
		_update_game_count()
		return

	var now := int(Time.get_unix_time_from_system())

	for i in range(games.size()):
		var g := games[i]
		var entry := preload("res://scenes/GameEntry.tscn").instantiate()
		var button: Button         = entry.get_node("EntryButton")
		var title_node: Label      = entry.get_node("EntryButton/HBoxContainer/VBoxContainer/Title")
		var meta_node: Label       = entry.get_node("EntryButton/HBoxContainer/VBoxContainer/Meta")
		var new_badge: Label       = entry.get_node("EntryButton/HBoxContainer/VBoxContainer/NewBadge")
		var icon_node: TextureRect = entry.get_node("EntryButton/HBoxContainer/IconFrame/Icon")
		var status_ind: Label      = entry.get_node("EntryButton/HBoxContainer/StatusIndicator")

		title_node.text = g.title
		meta_node.text  = _meta_text(g)
		status_ind.text = ""

		# ★ NEW badge: visible if the game was added within the last 24 h
		new_badge.visible = g.last_modified > 0 and (now - g.last_modified) < NEW_GAME_SECONDS

		icon_node.texture = _load_external_texture(g.icon_path)

		button.focus_mode = Control.FOCUS_ALL
		var idx := i
		button.pressed.connect(func(): _on_game_selected(idx))
		button.focus_entered.connect(func(): _select_game(idx))

		# Start invisible; staggered fade-in via pure tweens (no await in loop)
		entry.modulate.a = 0.0
		game_list.add_child(entry)

		var tween := create_tween()
		tween.tween_interval(i * 0.04)
		tween.tween_property(entry, "modulate:a", 1.0, 0.25)

	_update_game_count()

	# One frame for layout to settle, then focus and restore selection
	await get_tree().process_frame
	if build_id != _list_build_id:
		return  # another rebuild fired while we were waiting — bail

	_restore_last_selection()

	var focus_idx := clampi(selected_index, 0, game_list.get_child_count() - 1)
	if game_list.get_child_count() > 0:
		game_list.get_child(focus_idx).get_node("EntryButton").grab_focus()

func _restore_last_selection() -> void:
	if last_game_id.is_empty():
		_select_game(0)
		return
	for i in range(games.size()):
		if games[i].game_id == last_game_id:
			_select_game(i)
			return
	_select_game(0)

func _on_game_selected(idx: int) -> void:
	_select_game(idx)
	_launch_selected()

func _select_game(i: int) -> void:
	if games.is_empty():
		if _typewriter_tween and _typewriter_tween.is_valid():
			_typewriter_tween.kill()
		title_label.text  = "NO MODULES DETECTED"
		author_label.text = ""
		desc_label.text   = "[color=#00DDFF]Upload a game folder to /arcade/games to begin.[/color]"
		meta_label.text   = ""
		_stop_preview()
		icon_or_shot.texture = null
		score_panel.visible  = false
		selection_glow.visible = false
		_update_game_count()
		return

	selected_index = clampi(i, 0, games.size() - 1)
	var g: GameInfo = games[selected_index]

	title_label.text  = g.title.to_upper()
	author_label.text = "OPERATOR: %s" % g.author
	_type_description(g.description if g.description != "" else "No mission briefing available.")
	meta_label.text   = _meta_text(g)

	_animate_selection_change()
	_show_preview_or_fallback(g)
	_show_scores(g.game_id)
	_update_game_count()
	_update_status_indicators()
	_update_selection_glow()   # async — reads position after layout frame

	if game_list.get_child_count() > selected_index:
		var btn := game_list.get_child(selected_index).get_node("EntryButton")
		if not btn.has_focus():
			btn.grab_focus()
		_scroll_to_selected()

func _meta_text(g: GameInfo) -> String:
	var parts: Array[String] = []
	if g.players > 0: parts.append("%dP" % g.players)
	if g.year > 0:    parts.append(str(g.year))
	return " • ".join(parts) if parts.size() > 0 else ""

func _update_game_count() -> void:
	if games.is_empty():
		game_count_label.text = "NO MODULES"
	else:
		game_count_label.text = "MODULE %d / %d" % [selected_index + 1, games.size()]

func _update_status_indicators() -> void:
	for i in range(game_list.get_child_count()):
		var ind: Label = game_list.get_child(i).get_node("EntryButton/HBoxContainer/StatusIndicator")
		ind.text = "►" if i == selected_index else ""

func _scroll_to_selected() -> void:
	if game_list.get_child_count() <= selected_index:
		return
	var entry := game_list.get_child(selected_index)
	var target : float = entry.position.y - scroll_container.size.y / 2.0 + entry.size.y / 2.0
	target = clampf(target, 0.0, maxf(0.0, game_list.size.y - scroll_container.size.y))
	var tween := create_tween()
	tween.tween_property(scroll_container, "scroll_vertical", int(target), 0.25) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _update_selection_glow() -> void:
	# Defer one frame so layout positions are valid after list rebuild
	await get_tree().process_frame
	if game_list.get_child_count() <= selected_index:
		selection_glow.visible = false
		return
	selection_glow.visible = true
	var entry := game_list.get_child(selected_index)
	selection_glow.size = entry.size + Vector2(20, 20)
	var tween := create_tween()
	tween.tween_property(selection_glow, "global_position", entry.global_position - Vector2(10, 10), 0.2) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _animate_selection_change() -> void:
	var tween := create_tween()
	tween.tween_property(title_label, "scale", Vector2(1.05, 1.05), 0.1)
	tween.tween_property(title_label, "scale", Vector2(1.0,  1.0),  0.15)

# ── Media ──────────────────────────────────────────────────────────────────────
func _show_preview_or_fallback(g: GameInfo) -> void:
	_stop_preview()
	preview.visible      = false
	icon_or_shot.visible = true

	# Scanner only sets asset paths for files that exist — no re-stat needed
	if g.preview_path.ends_with(".ogv"):
		var stream := VideoStreamTheora.new()
		stream.file = g.preview_path
		preview.stream  = stream
		preview.visible = true
		icon_or_shot.visible = false
		preview.play()
		preview.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(preview, "modulate:a", 1.0, 0.4)
		return

	var img_path := g.screenshot_path if g.screenshot_path != "" else g.icon_path
	if img_path != "":
		icon_or_shot.texture = _load_external_texture(img_path)
		icon_or_shot.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(icon_or_shot, "modulate:a", 1.0, 0.4)
	else:
		icon_or_shot.texture = null

func _load_external_texture(path: String) -> Texture2D:
	# Assets live outside the pck (ResourceLoader can't load them) — decode
	# directly, cached per scan; failed loads cache null.
	if path == "":
		return null
	if _texture_cache.has(path):
		return _texture_cache[path]
	var tex: Texture2D = null
	var img := Image.new()
	if img.load(path) == OK:
		tex = ImageTexture.create_from_image(img)
	_texture_cache[path] = tex
	return tex

func _stop_preview() -> void:
	if preview.is_playing():
		preview.stop()
	preview.stream = null

# ── Scores ─────────────────────────────────────────────────────────────────────
func _show_scores(game_id: String) -> void:
	for c in score_list.get_children():
		c.queue_free()
	var scores := score_store.load_scores(game_id)
	if scores.is_empty():
		score_panel.visible = false
		return
	score_panel.visible = true
	for i in range(min(scores.size(), 10)):
		var e: Dictionary = scores[i]
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
		label.text = "%d. %s — %s" % [i + 1, e.get("name", "???"), str(e.get("score", 0))]
		score_list.add_child(label)

# ── Input ──────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	# Admin overlay intercepts all input while open
	if admin_overlay.visible:
		if event.is_action_pressed("ui_cancel"):
			_hide_admin_overlay()
			get_viewport().set_input_as_handled()
		return

	if launching:
		return

	# Any input exits attract mode
	if in_attract_mode:
		_exit_attract_mode()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_accept"):
		ui_confirm_sfx.play()
		_launch_selected()
		_reset_attract_timer()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		ui_sfx.play()
		_navigate_list(1)
		_reset_attract_timer()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		ui_sfx.play()
		_navigate_list(-1)
		_reset_attract_timer()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_page_down"):
		ui_sfx.play()
		_navigate_list(PAGE_SIZE)
		_reset_attract_timer()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_page_up"):
		ui_sfx.play()
		_navigate_list(-PAGE_SIZE)
		_reset_attract_timer()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_reset_attract_timer()
		get_viewport().set_input_as_handled()

func _navigate_list(direction: int) -> void:
	if games.is_empty():
		return
	var new_index: int
	if abs(direction) == 1:
		# Single step: wrap around ends for natural feel
		new_index = ((selected_index + direction) % games.size() + games.size()) % games.size()
	else:
		# Page jump: clamp so you don't overshoot
		new_index = clampi(selected_index + direction, 0, games.size() - 1)
	_select_game(new_index)

# ── Launch ─────────────────────────────────────────────────────────────────────
func _launch_selected() -> void:
	# Reentrancy guard — every launch path funnels through here
	if launching:
		return
	if games.is_empty():
		return
	var g: GameInfo = games[selected_index]

	launching = true
	attract_timer.stop()
	# Focus navigation eats ui_* actions before _unhandled_input sees them —
	# the GUI layer must be disabled explicitly.
	get_viewport().gui_disable_input = true
	last_game_id = g.game_id
	_save_state()

	# Brief dramatic flash on title before fade
	var flash := create_tween()
	flash.tween_property(title_label, "scale",    Vector2(1.2, 1.2), 0.15)
	flash.parallel().tween_property(title_label, "modulate", Color(0, 1, 1, 1),  0.15)

	_fade_out(0.3)
	await get_tree().create_timer(0.3).timeout

	# Non-blocking spawn; the watchdog in _process() ends the session when
	# the game exits. The sh wrapper logs game output + exit code.
	DirAccess.make_dir_recursive_absolute(GAME_LOG_DIR)
	_game_log_path = GAME_LOG_DIR.path_join("%s.log" % g.game_id)
	var sh_args: PackedStringArray = [
		"-c",
		'"$0" "$@" > "%s" 2>&1; echo "[launcher] exit code $?" >> "%s"'
			% [_game_log_path, _game_log_path],
		g.exec_path,
	]
	sh_args.append_array(g.launch_args)
	print("LAUNCH: %s %s — game output in %s" % [g.exec_path, " ".join(g.launch_args), _game_log_path])
	_game_pid = OS.create_process("/bin/sh", sh_args)
	if _game_pid < 0:
		push_error("Failed to spawn game '%s'" % g.game_id)
		_end_game_session()

func _on_game_exited() -> void:
	print("RETURN: game exited — output and exit code in %s" % _game_log_path)
	_end_game_session()

func _end_game_session() -> void:
	_game_pid = -1
	Input.flush_buffered_events()
	get_viewport().gui_disable_input = false
	title_label.scale    = Vector2(1.0, 1.0)
	title_label.modulate = Color(1, 1, 1, 1)
	_fade_in(0.4)
	launching = false
	_reset_attract_timer()

# ── Fades ──────────────────────────────────────────────────────────────────────
func _fade_out(seconds: float) -> void:
	fade_rect.visible    = true
	fade_rect.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(fade_rect, "modulate:a", 1.0, seconds)

func _fade_in(seconds: float) -> void:
	fade_rect.visible    = true
	fade_rect.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(fade_rect, "modulate:a", 0.0, seconds)
	tw.finished.connect(func(): fade_rect.visible = false)

# ── Attract mode ───────────────────────────────────────────────────────────────
func _reset_attract_timer() -> void:
	if not attract_timer.is_stopped():
		attract_timer.stop()
	attract_timer.start()

func _enter_attract_mode() -> void:
	if games.is_empty():
		return
	in_attract_mode          = true
	_attract_scroll_timer    = 0.0
	_attract_blink_timer     = 0.0
	_attract_blink_state     = true
	attract_label.visible    = true
	attract_overlay.visible  = true

func _exit_attract_mode() -> void:
	in_attract_mode         = false
	_attract_scroll_timer   = 0.0
	attract_overlay.visible = false
	_reset_attract_timer()

# ── Admin overlay ──────────────────────────────────────────────────────────────
func _show_admin_overlay() -> void:
	_populate_admin_info()
	admin_overlay.visible = true

func _hide_admin_overlay() -> void:
	admin_overlay.visible = false
	_reset_attract_timer()

func _populate_admin_info() -> void:
	var now_str := Time.get_datetime_string_from_system(false, true)
	var text := ""
	text += "[color=#00FFCC]Games loaded:[/color]  %d\n" % games.size()
	text += "[color=#00FFCC]Games dir:   [/color]  /arcade/games\n"
	text += "[color=#00FFCC]System time: [/color]  %s\n" % now_str
	text += "[color=#00FFCC]Engine:      [/color]  Godot 4.5\n"
	text += "[color=#00FFCC]Last played: [/color]  %s\n\n" % (last_game_id if last_game_id != "" else "—")

	var warnings := scanner.scan_warnings
	if warnings.is_empty():
		text += "[color=#00FF99]✓ No scan warnings.[/color]\n"
	else:
		text += "[color=#FF6600]⚠ Scan warnings (%d):[/color]\n" % warnings.size()
		for w in warnings:
			text += "  [color=#FFAA44]• %s[/color]\n" % w

	admin_info.text = text

# ── Persistence ────────────────────────────────────────────────────────────────
func _save_state() -> void:
	var f := FileAccess.open(STATE_FILE, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"last_game_id": last_game_id}))

func _load_state() -> void:
	if not FileAccess.file_exists(STATE_FILE):
		return
	var f := FileAccess.open(STATE_FILE, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		last_game_id = str(parsed.get("last_game_id", ""))

# ── Visual effects ──────────────────────────────────────────────────────────────
func _setup_effects() -> void:
	# Effects layer 65: above UI and AttractOverlay(60), below AdminOverlay(90)
	# and FadeLayer(100). Glitch bars spawn here at runtime.
	_glitch_layer = CanvasLayer.new()
	_glitch_layer.layer = 65
	add_child(_glitch_layer)

	# Vignette — dark corner overlay, transparent at centre.
	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vmat := ShaderMaterial.new()
	vmat.shader = load("res://media/shaders/vignette.gdshader")
	vignette.material = vmat
	_glitch_layer.add_child(vignette)

	# Full-screen scanline pass over all UI panels (multiplicative blend).
	var scan := ColorRect.new()
	scan.set_anchors_preset(Control.PRESET_FULL_RECT)
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var smat := ShaderMaterial.new()
	smat.shader = load("res://media/shaders/scanline_overlay.gdshader")
	scan.material = smat
	_glitch_layer.add_child(scan)

	_glitch_cooldown = randf_range(15.0, 35.0)

func _update_clock() -> void:
	var t := Time.get_time_dict_from_system()
	clock_label.text = "%02d:%02d:%02d" % [t.hour, t.minute, t.second]

func _type_description(plain_text: String) -> void:
	# Animate the description typing out character-by-character on selection.
	if _typewriter_tween and _typewriter_tween.is_valid():
		_typewriter_tween.kill()
	if plain_text.is_empty():
		desc_label.text = ""
		return
	var char_count := plain_text.length()
	# Speed: ~22 ms/char, clamped between 0.3 s and 2.5 s total.
	var duration := clampf(char_count * 0.022, 0.3, 2.5)
	desc_label.text = ""
	_typewriter_tween = create_tween()
	_typewriter_tween.tween_method(
		func(n: int): desc_label.text = "[color=#AADDFF]%s[/color]" % plain_text.left(n),
		0, char_count, duration
	).set_trans(Tween.TRANS_LINEAR)

func _fire_ambient_glitch() -> void:
	# Spawn a cluster of brief translucent horizontal bars for a screen-glitch feel.
	var base_colors: Array[Color] = [
		Color(0.0, 0.8, 1.0),  # cyan
		Color(1.0, 0.0, 0.8),  # magenta
		Color(0.0, 1.0, 0.5),  # green
	]
	for j in randi_range(2, 5):
		var base := base_colors[randi() % base_colors.size()]
		var bar  := ColorRect.new()
		bar.color    = Color(base.r, base.g, base.b, randf_range(0.1, 0.4))
		bar.position = Vector2(0.0, float(randi_range(80, 980)))
		bar.size     = Vector2(1920.0, float(randi_range(1, 7)))
		_glitch_layer.add_child(bar)
		var tw := create_tween()
		tw.tween_interval(float(j) * randf_range(0.0, 0.05))
		tw.tween_property(bar, "modulate:a", 0.0, randf_range(0.05, 0.2))
		tw.tween_callback(bar.queue_free)

# ── Audio ──────────────────────────────────────────────────────────────────────
func _create_beep(frequency: float, duration: float) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format   = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo   = false
	wav.mix_rate = 44100
	var sample_count := int(44100.0 * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in sample_count:
		var t   := float(i) / 44100.0
		var env := 1.0 - (t / duration)           # linear fade-out envelope
		var s   := int(sin(TAU * frequency * t) * 8192.0 * env)
		data[i * 2]     = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	wav.data = data
	return wav

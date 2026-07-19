extends Node

# Synced verbatim from aieh-template scripts/game_input.gd (this comment block
# aside) — fix bugs there first, then re-copy. Launcher-specific configuration
# lives in scenes/game_input.tscn: pause_overlay_enabled and ui_exit_enabled
# are both OFF because the launcher must never pause or quit from cabinet
# buttons (ui_exit is the *games'* exit-to-launcher binding).

# Autoloaded input configuration (GameInput, from scenes/game_input.tscn).
# Owns everything input-related:
# - Installs an SDL mapping so the CY-1121 cabinet's two unrecognized
#   "Twin USB" banks present as standard gamepads (panel buttons
#   1-6 = A/B/X/Y/LB/RB, Start = start, Select = back). The GUID is read
#   from the connected device because SDL GUIDs differ between Windows
#   (dev) and Linux (cabinet), and the name prefix is matched loosely
#   because the OS-reported name differs too ("Twin USB Gamepad" on
#   Windows, "Twin USB Joystick" on Linux).
# - Assigns joypads to players dynamically: the two lowest connected
#   device ids drive p1_* and p2_* (project.godot's hardcoded 0/1 are
#   just placeholders). The cabinet's banks enumerate P2-first
#   (button-layout.svg, corrected 2026-07-18: P1 = device 1, P2 =
#   device 0), so cabinet pads get the reversed order by default;
#   swap_player_devices flips whichever default applies.
# - The white Start buttons are NOT wired crosswise: each reports b9 on
#   its own player's device (button-layout.svg), so p1_start/p2_start
#   bind straight to their own player's device. force_cross_start_devices
#   remains for hardware that IS wired crosswise.
# - map_all_inputs_to_p1: single-player convenience — every control drives p1_*.
# - Pause overlay: pressing p1_start/p2_start pauses the tree and shows
#   "hold pause button for 3 seconds to quit — tap to continue"; holding
#   the button (including the press that opened the overlay) quits.
# - Quits immediately on ui_exit, as GD_ArcadeLauncher's GAME_SPEC.md
#   requires (the black center button on the cabinet, Back/View on a pad,
#   F10 on keyboard) — unless ui_exit_enabled is off. It is currently OFF
#   in scenes/game_input.tscn: the cabinet's black button is stuck down,
#   so quitting goes through the pause overlay (hold Start) instead.

const CABINET_PAD_PREFIX := "Twin USB"
# Panel buttons A/B/C/D/blue/green = raw b0-b5 -> A/B/X/Y/LB/RB; the black
# center button is b8 (back) and the white Start buttons are b9 (start).
const CABINET_LAYOUT := "a:b0,b:b1,x:b2,y:b3,leftshoulder:b4,rightshoulder:b5,back:b8,start:b9,leftx:a0,lefty:a1,dpup:h0.1,dpright:h0.2,dpdown:h0.4,dpleft:h0.8"

const PAUSE_ACTIONS: Array[StringName] = [&"p1_start", &"p2_start"]
const PAUSE_QUIT_HOLD_SECONDS := 3.0

## Map All Inputs to P1 — when enabled, the joypad bindings of every p1_*
## action match any device, and every p2_* binding (keyboard and joypad) is
## rerouted onto the matching p1_* action, so all controls drive Player 1
## and the p2_* actions go silent.
## Can also be toggled at runtime via GameInput.map_all_inputs_to_p1.
@export var map_all_inputs_to_p1 := false: set = set_map_all_inputs_to_p1

## Swap which physical joypad drives P1 vs P2, relative to the default.
## Default: lowest device id = P1 — except cabinet ("Twin USB") pads, whose
## banks enumerate P2-first (button-layout.svg: P1 = device 1, P2 = device 0)
## and so get the reversed order automatically. Flip this if the sides still
## come out reversed.
## Can also be toggled at runtime via GameInput.swap_player_devices.
@export var swap_player_devices := false: set = set_swap_player_devices

## The cabinet's white Start buttons are NOT wired crosswise — each is b9 on
## its own player's device (button-layout.svg), so starts bind straight.
## Set this to cross them (p1_start on P2's device and vice versa) for
## hardware that IS wired crosswise, or in tests.
@export var force_cross_start_devices := false: set = set_force_cross_start_devices

## Pause overlay: pressing a Start button (white cabinet buttons, keys 1/2)
## pauses the tree and shows "hold to quit — tap to continue". Disable for
## games that implement their own pause menu.
@export var pause_overlay_enabled := true: set = set_pause_overlay_enabled

## Instant quit on ui_exit (black cabinet button / Back / F10), required by
## GAME_SPEC.md. Temporarily OFF in scenes/game_input.tscn because the
## cabinet's black button is stuck in the down position — quit via the pause
## overlay (hold Start 3 s) instead. Re-enable once the hardware is fixed.
@export var ui_exit_enabled := true

# Device ids currently driving each player's joypad bindings (read-only;
# managed by _reassign_devices). A player whose device id has no connected
# pad simply receives no joypad input.
var p1_device := 0
var p2_device := 1

var _p2_moved_events: Dictionary = {}  # p2 action StringName -> its InputEvents, now living on the p1 twin

var _pause_layer: CanvasLayer
var _pause_hint: Label
var _pause_hold_action := StringName()  # pause action currently held, if any
var _pause_hold_time := 0.0
var _pause_opening_press := false  # current hold is the press that opened the overlay
var _paused_by_overlay := false

func _ready() -> void:
	# The pause overlay must keep processing (and receiving input) while the
	# tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_pause_overlay()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	for device in Input.get_connected_joypads():
		_map_if_cabinet_pad(device)
	_reassign_devices()
	if map_all_inputs_to_p1:
		_apply_pooling()

func _unhandled_input(event: InputEvent) -> void:
	if ui_exit_enabled and event.is_action_pressed("ui_exit"):
		get_tree().quit()
		return
	for action in PAUSE_ACTIONS:
		if event.is_action_pressed(action):
			_on_pause_button_pressed(action)
		elif event.is_action_released(action) and action == _pause_hold_action:
			_on_pause_button_released()

func set_map_all_inputs_to_p1(value: bool) -> void:
	if map_all_inputs_to_p1 == value:
		return
	map_all_inputs_to_p1 = value
	if not is_node_ready():
		return  # _ready applies the initial value
	if value:
		_apply_pooling()
	else:
		_revert_pooling()

func set_swap_player_devices(value: bool) -> void:
	if swap_player_devices == value:
		return
	swap_player_devices = value
	if not is_node_ready():
		return  # _ready applies the initial value
	_reassign_devices()

func set_force_cross_start_devices(value: bool) -> void:
	if force_cross_start_devices == value:
		return
	force_cross_start_devices = value
	if not is_node_ready():
		return  # _ready applies the initial value
	_apply_device_assignment()

func set_pause_overlay_enabled(value: bool) -> void:
	pause_overlay_enabled = value
	if not value and _paused_by_overlay:
		_pause_hold_action = StringName()
		_pause_opening_press = false
		_close_pause_overlay()

func _reassign_devices() -> void:
	var pads := Input.get_connected_joypads()
	pads.sort()
	var first: int = pads[0] if pads.size() >= 1 else 0
	var second: int = pads[1] if pads.size() >= 2 else first + 1
	# Cabinet banks enumerate P2-first (button-layout.svg: P1 = device 1,
	# P2 = device 0), so cabinet pads default to the reversed order;
	# swap_player_devices flips whichever default applies.
	var reversed := swap_player_devices != _cabinet_pad_connected()
	p1_device = second if reversed else first
	p2_device = first if reversed else second
	_apply_device_assignment()

func _apply_device_assignment() -> void:
	# Rewrites the device field of every p1_*/p2_* joypad binding. GameInput
	# owns those fields — the ids in project.godot are only placeholders.
	# While pooled, p1_* is left untouched: its joypad events stay at -1.
	# Starts are not crossed on the cabinet (button-layout.svg) — crossing
	# only happens when force_cross_start_devices asks for it.
	var cross := force_cross_start_devices
	for action in InputMap.get_actions():
		var action_name := String(action)
		var device: int
		if action_name.begins_with("p1_") and not map_all_inputs_to_p1:
			device = p2_device if (cross and action_name == "p1_start") else p1_device
		elif action_name.begins_with("p2_"):
			device = p1_device if (cross and action_name == "p2_start") else p2_device
		else:
			continue
		for event in InputMap.action_get_events(action):
			if _is_joypad_event(event):
				event.device = device
	_release_player_actions()

func _apply_pooling() -> void:
	for action in InputMap.get_actions():
		if String(action).begins_with("p1_"):
			for event in InputMap.action_get_events(action):
				if _is_joypad_event(event):
					event.device = -1
	# Only p2's keyboard events actually move onto the p1 twin — p1's own
	# joypad events at device -1 already cover every pad, and InputMap
	# treats -1 as a wildcard when matching duplicates, so a moved p2 joypad
	# event could neither be added nor later erased reliably. p2's joypad
	# events are just parked in _p2_moved_events until the revert.
	for action in InputMap.get_actions():
		var action_name := String(action)
		if not action_name.begins_with("p2_"):
			continue
		var target := StringName("p1_" + action_name.substr(3))
		if not InputMap.has_action(target):
			continue
		var moved: Array[InputEvent] = []
		moved.assign(InputMap.action_get_events(action))
		for event in moved:
			InputMap.action_erase_event(action, event)
			if not _is_joypad_event(event):
				InputMap.action_add_event(target, event)
		if not moved.is_empty():
			_p2_moved_events[action] = moved
	_release_player_actions()

func _revert_pooling() -> void:
	for action in _p2_moved_events:
		var target := StringName("p1_" + String(action).substr(3))
		for event in _p2_moved_events[action]:
			if not _is_joypad_event(event):
				InputMap.action_erase_event(target, event)
			InputMap.action_add_event(action, event)
	_p2_moved_events.clear()
	# Restores per-player devices on everything, including the joypad events
	# that just returned to their p2_* homes.
	_apply_device_assignment()

func _release_player_actions() -> void:
	# The bindings just changed, so pressed state captured under the old
	# bindings can never see its matching release event — without this, a
	# control held across the toggle stays stuck pressed forever.
	for action in InputMap.get_actions():
		var action_name := String(action)
		if action_name.begins_with("p1_") or action_name.begins_with("p2_"):
			Input.action_release(action)

func _cabinet_pad_connected() -> bool:
	for device in Input.get_connected_joypads():
		if Input.get_joy_name(device).begins_with(CABINET_PAD_PREFIX):
			return true
	return false

func _is_joypad_event(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		_map_if_cabinet_pad(device)
	_reassign_devices()

func _map_if_cabinet_pad(device: int) -> void:
	var joy_name := Input.get_joy_name(device)
	if not joy_name.begins_with(CABINET_PAD_PREFIX):
		return
	var guid := Input.get_joy_guid(device)
	if guid.is_empty():
		return
	Input.add_joy_mapping("%s,%s,%s" % [guid, joy_name, CABINET_LAYOUT], true)

# --- Pause overlay ----------------------------------------------------------
# Tap a Start button to pause; while paused, tap again to continue. Holding
# a Start button for PAUSE_QUIT_HOLD_SECONDS quits — including the press
# that opened the overlay, so "hold Start" quits from anywhere.

func _on_pause_button_pressed(action: StringName) -> void:
	if not pause_overlay_enabled:
		return
	if _paused_by_overlay:
		_pause_opening_press = false
	elif not get_tree().paused:
		get_tree().paused = true
		_paused_by_overlay = true
		_pause_layer.visible = true
		_pause_opening_press = true
	else:
		return  # the game paused the tree itself — stay out of its way
	_pause_hold_action = action
	_pause_hold_time = 0.0
	_update_pause_hint()

func _on_pause_button_released() -> void:
	var was_opening := _pause_opening_press
	_pause_hold_action = StringName()
	_pause_opening_press = false
	if _paused_by_overlay and not was_opening:
		_close_pause_overlay()
	else:
		_update_pause_hint()

func _close_pause_overlay() -> void:
	_paused_by_overlay = false
	if _pause_layer != null:
		_pause_layer.visible = false
	get_tree().paused = false

func _process(delta: float) -> void:
	if _pause_hold_action == StringName():
		return
	if not Input.is_action_pressed(_pause_hold_action):
		# The release event went missing (e.g. bindings were rewritten
		# mid-hold) — treat it as an aborted hold, not a tap.
		_pause_hold_action = StringName()
		_pause_opening_press = false
		_update_pause_hint()
		return
	_pause_hold_time += delta
	if _pause_hold_time >= PAUSE_QUIT_HOLD_SECONDS:
		get_tree().quit()
		return
	_update_pause_hint()

func _update_pause_hint() -> void:
	if _pause_hold_action != StringName() and _pause_hold_time > 0.0:
		_pause_hint.text = "Quitting in %.1f s — keep holding" % (PAUSE_QUIT_HOLD_SECONDS - _pause_hold_time)
	else:
		_pause_hint.text = "Hold pause button for 3 seconds to quit — tap to continue"

func _build_pause_overlay() -> void:
	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = 100
	_pause_layer.visible = false
	add_child(_pause_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	box.add_child(title)

	_pause_hint = Label.new()
	_pause_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_hint.add_theme_font_size_override("font_size", 28)
	box.add_child(_pause_hint)
	_update_pause_hint()

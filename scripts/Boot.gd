# res://scripts/Boot.gd
# Cyberpunk boot sequence with glitch effects and dramatic animations
extends Control

@onready var boot_log: RichTextLabel = $VBoxContainer/BootLog
@onready var boot_timer: Timer = $BootTimer
@onready var glitch_timer: Timer = $GlitchTimer
@onready var fade_rect: ColorRect = $FadeLayer/FadeRect
@onready var loading_bar: ProgressBar = $VBoxContainer/LoadingBar
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var title_label: Label = $VBoxContainer/Title
@onready var version_label: Label = $VBoxContainer/Version

var boot_lines: Array[String] = [
	"[color=#00FF99]>>> SYSTEM BOOT INITIATED[/color]",
	"[color=#AAAAAA]Checking hardware integrity...[/color]",
	"",
	"[color=#00CCFF][ OK ][/color] Quantum processor online",
	"[color=#00CCFF][ OK ][/color] Neural interface connected",
	"[color=#00CCFF][ OK ][/color] Holographic display array active",
	"[color=#00CCFF][ OK ][/color] Arcade input matrix detected",
	"[color=#00CCFF][ OK ][/color] Audio synthesis core ready",
	"",
	"[color=#FF9900]>>> Scanning game modules...[/color]",
	"[color=#00CCFF][ OK ][/color] /arcade/games mounted [ENCRYPTED]",
	"[color=#00CCFF][ OK ][/color] Score database initialized",
	"[color=#00CCFF][ OK ][/color] Player profiles loaded",
	"",
	"[color=#FF00FF]>>> Establishing neural link...[/color]",
	"[color=#00FF99][ OK ][/color] Cybernetic interface synchronized",
	"",
	"[color=#00FF00]LAUNCH SEQUENCE: [b]COMPLETE[/b][/color]",
	"",
	"[color=#FFFF00]WELCOME TO THE GRID, OPERATOR[/color]"
]

var current_line: int = 0
var boot_progress: float = 0.0
var glitch_active: bool = false
var _boot_sfx: AudioStreamPlayer

func _ready() -> void:
	# Fullscreen can race the WM at session startup — re-assert it
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	boot_log.text = ""
	loading_bar.value = 0.0

	# Generate chirp sound for boot lines
	_boot_sfx = AudioStreamPlayer.new()
	add_child(_boot_sfx)
	_boot_sfx.stream = _create_beep(660.0, 0.06)
	_boot_sfx.volume_db = -10.0

	# Animate title entrance
	title_label.modulate.a = 0.0
	version_label.modulate.a = 0.0

	var tween: Tween = create_tween()
	tween.tween_property(title_label, "modulate:a", 1.0, 0.5)
	tween.parallel().tween_property(version_label, "modulate:a", 1.0, 0.5)

	await get_tree().create_timer(0.8).timeout

	boot_timer.timeout.connect(_show_next_line)
	boot_timer.start()

	glitch_timer.timeout.connect(_random_glitch)
	glitch_timer.start()

func _process(delta: float) -> void:
	boot_progress = float(current_line) / float(boot_lines.size())
	loading_bar.value = lerpf(loading_bar.value, boot_progress, delta * 2.0)

	if current_line < boot_lines.size():
		if current_line < 8:
			status_label.text = "INITIALIZING SYSTEMS..."
			status_label.modulate = Color(0, 1, 0.5, 1)
		elif current_line < 13:
			status_label.text = "LOADING MODULES..."
			status_label.modulate = Color(0, 0.8, 1, 1)
		else:
			status_label.text = "SYNCHRONIZING..."
			status_label.modulate = Color(1, 0, 0.8, 1)

func _random_glitch() -> void:
	if randf() > 0.7:
		_apply_glitch_effect()

func _apply_glitch_effect() -> void:
	if glitch_active:
		return

	glitch_active = true

	var colors: Array[Color] = [
		Color(1, 0, 0, 0.3),
		Color(0, 1, 1, 0.3),
		Color(1, 0, 1, 0.3)
	]
	var glitch_color: Color = colors[randi() % colors.size()]

	# Save original position before nudging
	var original_x := title_label.position.x

	boot_log.modulate = glitch_color
	title_label.position.x += randf_range(-5.0, 5.0)

	await get_tree().create_timer(0.05).timeout

	boot_log.modulate = Color.WHITE
	title_label.position.x = original_x  # restore, not hardcoded 0

	glitch_active = false

func _show_next_line() -> void:
	if current_line >= boot_lines.size():
		boot_timer.stop()
		glitch_timer.stop()
		status_label.text = "READY"
		status_label.modulate = Color(0, 1, 0, 1)
		await get_tree().create_timer(0.5).timeout
		_transition_to_launcher()
		return

	var line: String = boot_lines[current_line]
	boot_log.text += line + "\n"

	# Chirp on non-empty lines
	if line.strip_edges() != "" and not _boot_sfx.playing:
		_boot_sfx.play()

	await get_tree().process_frame
	boot_log.scroll_to_line(boot_log.get_line_count() - 1)

	current_line += 1

func _transition_to_launcher() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(loading_bar, "modulate:a", 0.0, 0.3)
	tween.parallel().tween_property(boot_log, "modulate:a", 0.0, 0.3)
	tween.parallel().tween_property(status_label, "scale", Vector2(1.5, 1.5), 0.3)
	tween.parallel().tween_property(status_label, "modulate", Color(0, 1, 0.5, 0), 0.3)

	await get_tree().create_timer(0.3).timeout

	fade_rect.visible = true
	fade_rect.modulate.a = 0.0
	var fade_tween: Tween = create_tween()
	fade_tween.tween_property(fade_rect, "modulate:a", 1.0, 0.5)
	await fade_tween.finished

	get_tree().change_scene_to_file("res://scenes/Launcher.tscn")

func _create_beep(frequency: float, duration: float) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = false
	wav.mix_rate = 44100
	var sample_count := int(44100.0 * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in sample_count:
		var t := float(i) / 44100.0
		var env := 1.0 - (t / duration)
		var sample := int(sin(TAU * frequency * t) * 8192.0 * env)
		data[i * 2] = sample & 0xFF
		data[i * 2 + 1] = (sample >> 8) & 0xFF
	wav.data = data
	return wav

extends Control
## Section F, step 6 (setup half) — the New Game / seat-configuration screen.
##
## Mobile-first landscape: a centred column of large (>=48px) tap targets. v1 ships
## the 3-player game (2P/4P layouts are deferred data slots), so seat COUNT is fixed
## at 3 here; each seat has a Human/AI toggle defaulting to AI, per the plan. Tapping
## a toggle flips that seat. "Start Game" builds the match via GameController and
## swaps in the BoardView scene.
##
## This is the app's main scene. It owns no rules — it only collects seat specs and
## hands them to GameController.start_match().

const SEAT_COLORS: Array = [&"green", &"blue", &"red"]
const COLOR_SWATCH := {
	&"green": Color(0.35, 0.78, 0.40),
	&"blue": Color(0.35, 0.55, 0.92),
	&"red": Color(0.90, 0.40, 0.40),
}
const BOARD_SCENE := "res://scenes/BoardView.tscn"

# Per-seat human flag; index matches SEAT_COLORS. Default: seat 0 (green) is the
# human player, the rest AI — the common "me + 2 AI" solo game.
var _is_human: Array = [true, false, false]
var _seat_buttons: Array = []   # the toggle Button per seat


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	# Full-rect dark backdrop.
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.11, 0.14)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 18)
	margin.add_child(col)

	var title := Label.new()
	title.text = "WASTELAND WARRIORS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	col.add_child(title)

	var sub := Label.new()
	sub.text = "3-player game — tap a seat to switch Human / AI"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	sub.modulate = Color(1, 1, 1, 0.7)
	col.add_child(sub)

	# One big toggle row per seat.
	for i in range(SEAT_COLORS.size()):
		col.add_child(_make_seat_row(i))

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	col.add_child(spacer)

	var start := Button.new()
	start.text = "START GAME"
	start.custom_minimum_size = Vector2(320, 64)
	start.add_theme_font_size_override("font_size", 26)
	start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start.pressed.connect(_on_start_pressed)
	col.add_child(start)


func _make_seat_row(i: int) -> Control:
	var color: StringName = SEAT_COLORS[i]
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)

	var swatch := ColorRect.new()
	swatch.color = COLOR_SWATCH.get(color, Color.WHITE)
	swatch.custom_minimum_size = Vector2(48, 48)
	row.add_child(swatch)

	var name_lbl := Label.new()
	name_lbl.text = str(color).capitalize()
	name_lbl.custom_minimum_size = Vector2(110, 0)
	name_lbl.add_theme_font_size_override("font_size", 24)
	row.add_child(name_lbl)

	var toggle := Button.new()
	toggle.toggle_mode = true
	toggle.button_pressed = _is_human[i]
	toggle.custom_minimum_size = Vector2(200, 56)
	toggle.add_theme_font_size_override("font_size", 22)
	toggle.toggled.connect(_on_seat_toggled.bind(i))
	_seat_buttons.append(toggle)
	_refresh_toggle_text(i)
	row.add_child(toggle)
	return row


func _on_seat_toggled(pressed: bool, i: int) -> void:
	_is_human[i] = pressed
	_refresh_toggle_text(i)


func _refresh_toggle_text(i: int) -> void:
	var btn: Button = _seat_buttons[i]
	btn.text = "HUMAN" if _is_human[i] else "AI"


func _on_start_pressed() -> void:
	var seats: Array = []
	for i in range(SEAT_COLORS.size()):
		seats.append({"color": SEAT_COLORS[i], "is_ai": not _is_human[i]})
	var seed := int(Time.get_unix_time_from_system())
	# GameController is an autoload; it builds GameState + agents and starts the
	# round-loop coroutine. BoardView (loaded next) connects to its signals.
	GameController.start_match(seats, seed)
	get_tree().change_scene_to_file(BOARD_SCENE)

extends CanvasLayer
class_name WinScreen
## Section F, step 6 — the end-of-game screen.
##
## Raised on GameController.game_over(winner). Shows who won (a player color, or the
## "Facility wins / everybody loses" tie-break sentinel) and offers New Game, which
## returns to the SetupScreen so seats can be reconfigured. Owns no rules.

const SETUP_SCENE := "res://scenes/SetupScreen.tscn"
const FACILITY := &"facility"
const PLAYER_COLORS := {
	&"green": Color(0.35, 0.78, 0.40),
	&"blue": Color(0.35, 0.55, 0.92),
	&"red": Color(0.90, 0.40, 0.40),
}

var _root: Control
var _headline: Label
var _sub: Label


func _ready() -> void:
	layer = 30   # above everything
	_build_ui()
	visible = false


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.09, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.position = Vector2(-260, -150)
	col.custom_minimum_size = Vector2(520, 300)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 22)
	_root.add_child(col)

	_headline = Label.new()
	_headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_headline.add_theme_font_size_override("font_size", 52)
	col.add_child(_headline)

	_sub = Label.new()
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_font_size_override("font_size", 22)
	_sub.modulate = Color(1, 1, 1, 0.75)
	col.add_child(_sub)

	var new_game := Button.new()
	new_game.text = "NEW GAME"
	new_game.custom_minimum_size = Vector2(300, 64)
	new_game.add_theme_font_size_override("font_size", 26)
	new_game.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	new_game.pressed.connect(_on_new_game)
	col.add_child(new_game)


## Show the win screen for `winner` (a color StringName, or the Facility sentinel).
func show_winner(winner) -> void:
	if winner == FACILITY or str(winner) == "facility":
		_headline.text = "THE FACILITY WINS"
		_headline.add_theme_color_override("font_color", Color(0.8, 0.7, 0.4))
		_sub.text = "A tie — nobody secured enough Old Tech. Everybody loses."
	else:
		_headline.text = "%s WINS" % str(winner).to_upper()
		_headline.add_theme_color_override("font_color", PLAYER_COLORS.get(winner, Color.WHITE))
		_sub.text = "Secured 3 Old Tech in the Rally Zone."
	visible = true


func _on_new_game() -> void:
	get_tree().change_scene_to_file(SETUP_SCENE)

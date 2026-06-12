extends CanvasLayer
class_name GameHUD
## Section F, step 1 — the persistent in-game overlay (phase/turn banner + hotseat
## hand-off cover). Lives on top of the BoardView. It owns NO rules and never
## touches GameState; it only reflects GameController signals and, for the hand-off,
## gates the next human's view until they tap "ready".
##
## Mobile-first landscape: banner pinned top-centre (readable, not a tiny corner
## control); the hand-off cover is a full-rect opaque panel with one big button in
## the lower-centre thumb arc.

signal handoff_confirmed(color)   ## the next human tapped "I'm ready"
signal pass_pressed()             ## the active human tapped Pass (end their action turn)

const PLAYER_COLORS := {
	&"green": Color(0.35, 0.78, 0.40),
	&"blue": Color(0.35, 0.55, 0.92),
	&"red": Color(0.90, 0.40, 0.40),
}
const PHASE_NAMES := {
	0: "Recruitment",   # GameState.Phase.RECRUITMENT
	1: "Action",        # GameState.Phase.ACTION
	2: "Guardian",      # GameState.Phase.GUARDIAN
}

var _banner: PanelContainer
var _banner_label: Label
var _cover: Control
var _cover_label: Label
var _cover_sub: Label
var _ready_btn: Button
var _pending_handoff_color: StringName = &""

# Action bar (lower thumb arc): a prompt + a big Pass button, shown only during the
# active human's Action turn.
var _action_bar: Control
var _action_hint: Label
var _hint_panel: PanelContainer
var _pass_btn: Button


var _tooltip: PanelContainer
var _tooltip_label: Label


func _ready() -> void:
	layer = 10   # above the board (which is a plain Node2D on the default layer)
	_build_banner()
	_build_action_bar()
	_build_tooltip()
	_build_cover()


func _build_tooltip() -> void:
	_tooltip = PanelContainer.new()
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.10, 0.95)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.25)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	_tooltip.add_theme_stylebox_override("panel", sb)
	_tooltip_label = Label.new()
	_tooltip_label.add_theme_font_size_override("font_size", 14)
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_child(_tooltip_label)
	add_child(_tooltip)


## Show a unit-stat tooltip at `screen_pos`. `text` is the multi-line stat block.
func show_tooltip(text: String, screen_pos: Vector2) -> void:
	_tooltip_label.text = text
	_tooltip.visible = true
	# Offset slightly up-right of the cursor; keep on-screen.
	var vp := get_viewport().get_visible_rect().size
	var pos := screen_pos + Vector2(16, -10)
	pos.x = min(pos.x, vp.x - 220)
	pos.y = max(pos.y, 8)
	_tooltip.position = pos


func hide_tooltip() -> void:
	if _tooltip != null:
		_tooltip.visible = false


# ---------------------------------------------------------------------------
#  Phase / turn banner
# ---------------------------------------------------------------------------

func _build_banner() -> void:
	_banner = PanelContainer.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.position = Vector2(-220, 10)   # nudged so the 440-wide panel is centred
	_banner.custom_minimum_size = Vector2(440, 48)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.88)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_banner.add_theme_stylebox_override("panel", sb)

	_banner_label = Label.new()
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.add_theme_font_size_override("font_size", 22)
	_banner_label.text = "Setting up…"
	_banner.add_child(_banner_label)
	add_child(_banner)


## Update the banner to "[COLOR] — [Phase]" with the seat colour.
func show_turn(color: StringName, phase: int) -> void:
	var col: Color = PLAYER_COLORS.get(color, Color.WHITE)
	var phase_name: String = PHASE_NAMES.get(phase, "—")
	_banner_label.text = "%s  —  %s phase" % [str(color).to_upper(), phase_name]
	_banner_label.add_theme_color_override("font_color", col)


func set_phase(phase: int) -> void:
	# Guardian (and any no-seat) phase has no acting player — show it plainly,
	# without a dangling "— " seat dash. Recruitment/Action get their seat name
	# from the subsequent show_turn() call.
	var phase_name: String = PHASE_NAMES.get(phase, "—")
	if phase == 2:   # GameState.Phase.GUARDIAN
		_banner_label.text = "Guardian phase"
		_banner_label.add_theme_color_override("font_color", Color(0.78, 0.70, 0.92))


# ---------------------------------------------------------------------------
#  Action bar (Pass button + hint), lower-centre thumb arc
# ---------------------------------------------------------------------------

func _build_action_bar() -> void:
	_action_bar = Control.new()
	# Anchor to the bottom edge, full width, so children sit in the lower thumb arc.
	_action_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_action_bar.visible = false
	# Don't eat clicks meant for the board; only the Pass button is interactive.
	_action_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_action_bar)

	# Hint sits just UNDER the top banner (clear of the board centre and the
	# bottom-left hand strip), in a small dark pill so it reads over the board. It's a
	# direct HUD child so its anchors are SCREEN-relative (not the bottom bar's).
	var hint_panel := PanelContainer.new()
	hint_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hint_panel.position = Vector2(-360, 64)
	hint_panel.custom_minimum_size = Vector2(720, 0)
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(0.08, 0.09, 0.12, 0.80)
	hsb.set_corner_radius_all(8)
	hsb.content_margin_left = 14
	hsb.content_margin_right = 14
	hsb.content_margin_top = 5
	hsb.content_margin_bottom = 5
	hint_panel.add_theme_stylebox_override("panel", hsb)
	hint_panel.visible = false   # raised only during the active human's Action turn
	add_child(hint_panel)
	_hint_panel = hint_panel

	_action_hint = Label.new()
	_action_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_action_hint.add_theme_font_size_override("font_size", 17)
	_action_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_action_hint.text = "Tap a space to Activate, or Pass."
	_action_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.add_child(_action_hint)

	# Pass button: bottom-right thumb arc, clear of the bottom-left hand strip.
	_pass_btn = Button.new()
	_pass_btn.text = "PASS"
	_pass_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_pass_btn.position = Vector2(-184, -76)
	_pass_btn.custom_minimum_size = Vector2(160, 56)
	_pass_btn.add_theme_font_size_override("font_size", 22)
	_pass_btn.pressed.connect(func(): pass_pressed.emit())
	_action_bar.add_child(_pass_btn)


## Show/hide the action bar (Pass + hint pill); `hint` updates the prompt line.
func set_action_bar(shown: bool, hint: String = "") -> void:
	_action_bar.visible = shown
	if _hint_panel != null:
		_hint_panel.visible = shown
	if shown and hint != "":
		_action_hint.text = hint


func set_action_hint(hint: String) -> void:
	_action_hint.text = hint


# ---------------------------------------------------------------------------
#  Hotseat hand-off cover
# ---------------------------------------------------------------------------

func _build_cover() -> void:
	_cover = Control.new()
	_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.visible = false
	# Block all input to the board while raised.
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.09, 1.0)   # fully opaque: hides the board
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_cover.add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 22)
	# Centre the VBox on screen.
	col.position = Vector2(-260, -120)
	col.custom_minimum_size = Vector2(520, 240)
	_cover.add_child(col)

	var pass_lbl := Label.new()
	pass_lbl.text = "Pass the device"
	pass_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pass_lbl.add_theme_font_size_override("font_size", 26)
	pass_lbl.modulate = Color(1, 1, 1, 0.7)
	col.add_child(pass_lbl)

	_cover_label = Label.new()
	_cover_label.text = ""
	_cover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cover_label.add_theme_font_size_override("font_size", 44)
	col.add_child(_cover_label)

	_cover_sub = Label.new()
	_cover_sub.text = "Hand the phone to this player, then tap Ready."
	_cover_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cover_sub.add_theme_font_size_override("font_size", 18)
	_cover_sub.modulate = Color(1, 1, 1, 0.6)
	col.add_child(_cover_sub)

	_ready_btn = Button.new()
	_ready_btn.text = "I'M READY"
	_ready_btn.custom_minimum_size = Vector2(300, 64)
	_ready_btn.add_theme_font_size_override("font_size", 26)
	_ready_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_ready_btn.pressed.connect(_on_ready_pressed)
	col.add_child(_ready_btn)

	add_child(_cover)


func is_handoff_up() -> bool:
	return _cover.visible


## Raise the cover for the named human seat. The banner is hidden behind it; the
## board is fully obscured so no hidden info leaks across the pass.
func show_handoff(color: StringName) -> void:
	_pending_handoff_color = color
	var col: Color = PLAYER_COLORS.get(color, Color.WHITE)
	_cover_label.text = "%s's turn" % str(color).to_upper()
	_cover_label.add_theme_color_override("font_color", col)
	_cover.visible = true


func _on_ready_pressed() -> void:
	_cover.visible = false
	var c := _pending_handoff_color
	_pending_handoff_color = &""
	emit_signal("handoff_confirmed", c)

extends Control
class_name CardUI
## Section F, step 4 — a reusable card widget. Hand it an ActionCardData and it
## renders itself (greybox: a coloured panel by card type, name, and body text).
## Art arrives in Section G; this is the data-driven shell the plan asks for.
##
## Emits `tapped(card)` on click so the hand can zoom it (tap-to-zoom, not hover —
## phones have no hover). Pure presentation: owns no rules, never touches GameState.

signal tapped(card)

const TYPE_COLORS := {
	0: Color(0.30, 0.50, 0.34),   # RECRUITMENT — green-ish
	1: Color(0.30, 0.42, 0.62),   # MOVEMENT — blue-ish
	2: Color(0.60, 0.34, 0.34),   # ATTACK — red-ish
}
const TYPE_NAMES := {0: "RECRUITMENT", 1: "MOVEMENT", 2: "ATTACK"}

var card = null                       # the ActionCardData this widget shows
var _name_lbl: Label
var _type_lbl: Label
var _text_lbl: Label
var _panel: PanelContainer
var _sb: StyleBoxFlat
var _selected: bool = false
var _base_color: Color


func _init(card_data = null, card_size: Vector2 = Vector2(150, 210)) -> void:
	card = card_data
	custom_minimum_size = card_size
	_build(card_size)


func _build(card_size: Vector2) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	pivot_offset = card_size * 0.5   # scale from centre when selected

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The panel must not eat the click before this Control's gui_input sees it.
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sb = StyleBoxFlat.new()
	var ctype: int = int(card.card_type) if card != null else 0
	_base_color = TYPE_COLORS.get(ctype, Color(0.3, 0.3, 0.34))
	_sb.bg_color = _base_color
	_sb.set_corner_radius_all(10)
	_sb.set_border_width_all(2)
	_sb.border_color = Color(0, 0, 0, 0.5)
	_sb.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", _sb)
	add_child(_panel)

	# Real card art (Section G.1). When present, the artwork carries the name,
	# type and rules text, so we show the image full-bleed and skip the greybox
	# labels. Missing art (e.g. a not-yet-drawn card) keeps the text shell.
	var art: Texture2D = null
	if card != null and "id" in card:
		art = ArtRegistry.card(card.id)
	if art != null:
		var pic := TextureRect.new()
		pic.texture = art
		pic.set_anchors_preset(Control.PRESET_FULL_RECT)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(pic)
		return

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE   # let clicks fall through to this card
	_panel.add_child(col)

	_type_lbl = Label.new()
	_type_lbl.text = TYPE_NAMES.get(ctype, "?")
	_type_lbl.add_theme_font_size_override("font_size", 11)
	_type_lbl.modulate = Color(1, 1, 1, 0.75)
	col.add_child(_type_lbl)

	_name_lbl = Label.new()
	_name_lbl.text = str(card.card_name) if card != null else ""
	_name_lbl.add_theme_font_size_override("font_size", 15)
	_name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_name_lbl)

	var sep := HSeparator.new()
	col.add_child(sep)

	_text_lbl = Label.new()
	_text_lbl.text = str(card.text) if card != null else ""
	_text_lbl.add_theme_font_size_override("font_size", 12)
	_text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_text_lbl)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		tapped.emit(card)
		accept_event()


## Dim a card that can't be played in the current context (wrong phase/type).
func set_playable(playable: bool) -> void:
	modulate = Color(1, 1, 1, 1.0) if playable else Color(1, 1, 1, 0.4)


## Selected cards brighten and gain a thick gold border. We DON'T scale or move the
## card — doing so inside the ScrollContainer clips the top label and the bottom
## text. A purely visual highlight reads clearly without fighting the layout.
func set_selected(sel: bool) -> void:
	if sel == _selected:
		return
	_selected = sel
	if _sb != null:
		_sb.bg_color = _base_color.lightened(0.20) if sel else _base_color
		_sb.border_color = Color(0.98, 0.85, 0.20) if sel else Color(0, 0, 0, 0.5)
		_sb.set_border_width_all(5 if sel else 2)

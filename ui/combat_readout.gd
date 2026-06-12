extends CanvasLayer
class_name CombatReadout
## Section F, step 5 — the PLAIN combat readout.
##
## Combat is resolved by the headless CombatResolver, which emits a replayable event
## log (declare -> roll -> assign -> apply -> deaths). Animation of that log is
## Section G; here we just render it as human-readable text/number lines in a
## scrollable panel with a Close button, so a player can see exactly what happened
## (who rolled what, who got hit, who died). It owns NO rules — it only formats the
## log dictionaries the resolver produced.

signal closed()

var _root: Control
var _list: VBoxContainer
var _title: Label

const FACE_NAMES := ["", "1", "2", "3", "4", "5", "6"]


func _ready() -> void:
	layer = 24   # above the board/hand, below target pickers (26)
	_build_ui()
	visible = false


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.08, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-300, -240)
	panel.custom_minimum_size = Vector2(600, 480)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.13, 0.17, 1.0)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	_title = Label.new()
	_title.text = "Combat"
	_title.add_theme_font_size_override("font_size", 26)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 3)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	var close := Button.new()
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(200, 52)
	close.add_theme_font_size_override("font_size", 22)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(_on_close)
	col.add_child(close)


## Show the readout for one combat `event_log` (an Array of dicts from the resolver).
func show_log(event_log: Array) -> void:
	for c in _list.get_children():
		c.queue_free()
	for ev in event_log:
		var line: Variant = _format_event(ev)
		if not (line is Dictionary):
			continue
		var lbl := Label.new()
		lbl.text = str(line["text"])
		lbl.add_theme_font_size_override("font_size", 15)
		lbl.modulate = line["color"]
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(lbl)
	if _list.get_child_count() == 0:
		var none := Label.new()
		none.text = "(no combat events)"
		none.modulate = Color(1, 1, 1, 0.6)
		_list.add_child(none)
	visible = true


## Map one resolver event dict to a {text, color} line. Returns "" to skip.
func _format_event(ev) -> Variant:
	if not (ev is Dictionary):
		return ""
	match ev.get("event", ""):
		"combat_start":
			var sides: Array = ev.get("sides", [])
			return _line("⚔  Combat: %s" % " vs ".join(_names(sides)), Color(1, 0.9, 0.5))
		"round_start":
			return _line("— Round %d —" % int(ev.get("round", 0)), Color(0.8, 0.85, 1.0))
		"sticky_bomb":
			return _line("  Sticky Bomb vs %s (%d dice)" % [_name(ev.get("side")), int(ev.get("dice", 0))], Color(0.95, 0.7, 0.4))
		"hits_first":
			return _line("  %s strikes first (%d dice)" % [_name(ev.get("side")), int(ev.get("dice", 0))], Color(0.9, 0.8, 0.6))
		"die":
			var face: int = int(ev.get("face", 0))
			var mark := ""
			if ev.get("crit", false):
				mark = "  ✸ CRIT"
			elif ev.get("hit", false):
				mark = "  ● hit"
			else:
				mark = "  ○ miss"
			return _line("    %s rolls %d%s" % [_name(ev.get("side")), face, mark],
				Color(0.85, 1.0, 0.85) if ev.get("hit", false) else Color(0.7, 0.7, 0.72))
		"reroll":
			return _line("    ↻ %s re-rolls a miss (was %d)" % [_name(ev.get("side")), int(ev.get("from", 0))], Color(0.75, 0.85, 1.0))
		"hit_assigned":
			return _line("    → %s takes a hit (%d/%d dmg)" % [
				_unit_name(ev.get("unit")), int(ev.get("damage_total", 0)),
				int(ev.get("effective_defense", 0))], Color(1.0, 0.8, 0.8))
		"death":
			return _line("    ☠  %s (%s) is destroyed" % [_unit_name(ev.get("unit")), _name(ev.get("side"))], Color(1.0, 0.5, 0.5))
		"round_end":
			return ""   # keep it tidy
		"combat_end":
			# survivors = { side -> Array of surviving unit ids }. Show the count.
			var surv: Dictionary = ev.get("survivors", {})
			var parts: Array = []
			for side in surv.keys():
				var v = surv[side]
				var cnt: int = v.size() if v is Array else int(v)
				parts.append("%s: %d" % [_name(side), cnt])
			return _line("✔  Survivors — %s" % ("  ·  ".join(parts) if not parts.is_empty() else "none"), Color(0.7, 1.0, 0.7))
		_:
			return ""


func _line(text: String, color: Color) -> Dictionary:
	return {"text": text, "color": color}


func _name(side) -> String:
	return str(side).capitalize() if side != null else "?"


func _names(sides: Array) -> Array:
	var out: Array = []
	for s in sides:
		out.append(_name(s))
	return out


func _unit_name(uid) -> String:
	return str(uid).capitalize() if uid != null else "Unit"


func _on_close() -> void:
	visible = false
	closed.emit()

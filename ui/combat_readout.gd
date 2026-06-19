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
	panel.position = Vector2(-340, -240)
	panel.custom_minimum_size = Vector2(680, 480)
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
	scroll.custom_minimum_size = Vector2(640, 360)
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
## Layout: structural events (combat start, round headers, survivors) are full-width
## header rows; every event that belongs to a participant (rolls, hits, deaths) goes
## into THAT side's column, so each combatant's actions read top-to-bottom in its own
## lane. Columns are created in first-seen order from the combat_start sides list.
func show_log(event_log: Array) -> void:
	for c in _list.get_children():
		c.queue_free()
	# 1. Determine the participating sides (from combat_start, else discovered).
	var sides: Array = []
	for ev in event_log:
		if ev is Dictionary and ev.get("event", "") == "combat_start":
			for sd in ev.get("sides", []):
				if not (sd in sides):
					sides.append(sd)
	for ev in event_log:
		if ev is Dictionary and ev.has("side") and ev.get("side") != null:
			var sd = ev.get("side")
			if not (sd in sides):
				sides.append(sd)

	# 2. Build the column grid: one VBox per side under a coloured header.
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_child(columns)
	var side_box := {}   # side -> VBoxContainer
	var col_w: int = int(max(160, 540.0 / float(max(sides.size(), 1)) - 14))
	for sd in sides:
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 3)
		cv.custom_minimum_size = Vector2(col_w, 0)
		var head := Label.new()
		head.text = _name(sd)
		head.add_theme_font_size_override("font_size", 18)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.modulate = _side_color(sd)
		cv.add_child(head)
		columns.add_child(cv)
		side_box[sd] = cv

	# 3. Walk the log: side-bearing events into their column, structural ones as
	#    full-width header rows below the columns.
	var had_any := false
	for ev in event_log:
		var line: Variant = _format_event(ev)
		if not (line is Dictionary):
			continue
		had_any = true
		var lbl := Label.new()
		lbl.text = str(line["text"]).strip_edges()
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.modulate = line["color"]
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var sd = ev.get("side") if ev is Dictionary else null
		if sd != null and side_box.has(sd):
			side_box[sd].add_child(lbl)
		else:
			# Structural / multi-side row — full width under the columns.
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_list.add_child(lbl)
	if not had_any:
		var none := Label.new()
		none.text = "(no combat events)"
		none.modulate = Color(1, 1, 1, 0.6)
		_list.add_child(none)
	visible = true


## Player/guardian colour for a column header.
func _side_color(side) -> Color:
	match str(side):
		"green": return Color(0.45, 0.85, 0.5)
		"blue": return Color(0.45, 0.65, 0.95)
		"red": return Color(0.95, 0.5, 0.5)
		"guardian": return Color(0.78, 0.6, 0.9)
		_: return Color(0.9, 0.9, 0.9)


## Map one resolver event dict to a {text, color} line. Returns "" to skip.
func _format_event(ev) -> Variant:
	if not (ev is Dictionary):
		return ""
	match ev.get("event", ""):
		"combat_start":
			var sides: Array = ev.get("sides", [])
			return _line("⚔  Combat: %s" % " vs ".join(_names(sides)), Color(1, 0.9, 0.5))
		"round_start":
			return _line("— Round %d —" % (int(ev.get("round", 0)) + 1), Color(0.8, 0.85, 1.0))
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
			# Name the rolling unit when known (e.g. "Blue Warrior rolls 5"), else side.
			var roller := _name(ev.get("side"))
			var uid = ev.get("unit", &"")
			if uid != null and str(uid) != "":
				roller = "%s %s" % [_name(ev.get("side")), _unit_name(uid)]
			return _line("    %s rolls %d%s" % [roller, face, mark],
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

extends CanvasLayer
class_name InfoPanel
## Section G.4 — "surface hidden info." A togglable panel that shows, per player:
## Old Tech captured, hand size, bag size, Coward odds (chance the next single
## draw is a Coward), and the unit composition still in the bag. This is data the
## engine already tracks but that a player otherwise can't see — exposing it keeps
## decisions informed (the build plan's readability goal). Owns NO rules.

const PLAYER_COLORS := {
	&"green": Color(0.45, 0.85, 0.5),
	&"blue": Color(0.45, 0.65, 0.95),
	&"red": Color(0.95, 0.5, 0.5),
}

var _root: Control
var _list: VBoxContainer
var _toggle: Button
var _open := false


func _ready() -> void:
	layer = 23
	_build()
	visible = true        # the toggle button is always available
	_set_panel_open(false)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Toggle button, top-right.
	_toggle = Button.new()
	_toggle.text = "ℹ INFO"
	_toggle.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_toggle.position = Vector2(-130, 12)
	_toggle.custom_minimum_size = Vector2(116, 40)
	_toggle.pressed.connect(_on_toggle)
	_root.add_child(_toggle)

	# The panel itself, slides under the button.
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-340, 60)
	panel.custom_minimum_size = Vector2(324, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.15, 0.96)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(16)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.35, 0.4, 0.5, 0.8)
	panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	var title := Label.new()
	title.text = "Game Info"
	title.add_theme_font_size_override("font_size", 20)
	col.add_child(title)

	col.add_child(HSeparator.new())

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	col.add_child(_list)


func _on_toggle() -> void:
	_set_panel_open(not _open)
	if _open:
		refresh()


func _set_panel_open(open: bool) -> void:
	_open = open
	var panel := _root.get_node_or_null("Panel")
	if panel != null:
		panel.visible = open
	if _toggle != null:
		_toggle.text = "ℹ INFO ▴" if open else "ℹ INFO ▾"


## Rebuild the per-player rows from the current GameState.
func refresh() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		c.queue_free()
	if not _open:
		return
	var players := _get_players()
	if players.is_empty():
		var none := Label.new()
		none.text = "(no game in progress)"
		none.modulate = Color(1, 1, 1, 0.6)
		_list.add_child(none)
		return
	for p in players:
		_list.add_child(_player_block(p))


func _player_block(p) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var col: Color = PLAYER_COLORS.get(p.color, Color.WHITE)
	var head := Label.new()
	# Name + a colour SWATCH glyph so ownership reads without relying on colour alone.
	head.text = "◆ %s%s" % [str(p.color).capitalize(), "  (AI)" if p.is_ai else ""]
	head.add_theme_font_size_override("font_size", 17)
	head.add_theme_color_override("font_color", col)
	box.add_child(head)

	var bag_size: int = p.bag_size() if p.has_method("bag_size") else p.bag.size()
	var cowards: int = p.coward_count() if p.has_method("coward_count") else 0
	var odds := 0.0
	if bag_size > 0:
		odds = 100.0 * float(cowards) / float(bag_size)

	_add_stat(box, "Old Tech", "★ %d / 3" % p.old_tech_count)
	_add_stat(box, "Hand", "%d cards" % p.hand.size())
	_add_stat(box, "Bag", "%d (%d Cowards)" % [bag_size, cowards])
	_add_stat(box, "Next-draw Coward odds", "%.0f%%" % odds)
	if p.artefacts != null and not p.artefacts.is_empty():
		_add_stat(box, "Artifacts", str(p.artefacts.size()))

	# Unit composition left in the bag (real units only).
	var comp := _bag_composition(p)
	if not comp.is_empty():
		var clbl := Label.new()
		clbl.text = "  Units in bag: " + comp
		clbl.add_theme_font_size_override("font_size", 12)
		clbl.modulate = Color(0.8, 0.85, 0.9)
		clbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(clbl)
	return box


func _add_stat(box: VBoxContainer, label: String, value: String) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 13)
	l.modulate = Color(0.7, 0.74, 0.8)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var v := Label.new()
	v.text = value
	v.add_theme_font_size_override("font_size", 13)
	row.add_child(v)
	box.add_child(row)


## "2 Warrior, 1 Heavy" style summary of real units still in the bag.
func _bag_composition(p) -> String:
	var counts := {}
	for e in p.bag:
		if e == &"coward":
			continue
		counts[e] = int(counts.get(e, 0)) + 1
	var parts := []
	for k in counts.keys():
		parts.append("%d %s" % [counts[k], str(k).capitalize()])
	return ", ".join(parts)


func _get_players() -> Array:
	var gs := get_tree().root.get_node_or_null("GameState")
	if gs == null:
		return []
	if "players" in gs and gs.players is Array:
		return gs.players
	if gs.has_method("get_players"):
		var out := []
		for c in [&"green", &"blue", &"red"]:
			var p = gs.get_player(c)
			if p != null:
				out.append(p)
		return out
	return []

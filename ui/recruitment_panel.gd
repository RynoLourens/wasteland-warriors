extends CanvasLayer
class_name RecruitmentPanel
## Section F, step 2 — the Recruitment UI.
##
## Presents the three Recruitment choices (Deploy / Recruit / Punish Cowards) as
## large tap targets, shows the acting player's bag composition, and — for Recruit —
## a simple unit picker. It owns NO rules: it reads the Player model to display bag
## odds and emits a plain recruitment INTENT (the same dictionary a ScriptedAgent or
## HeuristicAgent returns) via `choice_made`, which BoardView forwards to the seat's
## HumanAgent.submit(). The FSM/Player still validate and apply.
##
## Recruit is EITHER 3 regular Units (Warriors) OR 2 Special Units (rulebook). Lady
## Seraph's passive (seraph_recruit) lifts these to 5 / 3. The player first picks the
## mode (Regular vs Special), then the units, capped accordingly.

signal choice_made(intent)

# Regular Units ("Units"): Warrior, Scout, Gunner, Heavy.
# Special Units: Berserker, Manstopper, Infiltrator, Sapperteur.
const REGULAR_IDS := [&"warrior", &"scout", &"gunner", &"heavy"]
const SPECIAL_IDS := [&"berserker", &"manstopper", &"infiltrator", &"sapperteur"]
const UNIT_NAMES := {
	&"warrior": "Warrior", &"scout": "Scout", &"heavy": "Heavy", &"gunner": "Gunner",
	&"berserker": "Berserker", &"manstopper": "Manstopper",
	&"infiltrator": "Infiltrator", &"sapperteur": "Sapperteur",
}

var _root: Control
var _bag_label: Label
var _title: Label
var _result_label: Label
var _choice_box: VBoxContainer
var _recruit_box: VBoxContainer       # the unit picker (hidden until Recruit tapped)
var _recruit_count_label: Label
var _confirm_recruit_btn: Button

var _color: StringName = &""
var _player = null
var _recruit_pick: Array = []         # chosen unit ids (multiset)
var _seraph: bool = false             # Lady Seraph passive (5 regular / 3 special)
var _recruit_mode: String = ""        # "regular" | "special"
var _recruit_cap: int = 3             # cap for the current mode
var _mode_box: VBoxContainer          # the Regular/Special mode chooser
var _recruit_grid: GridContainer      # rebuilt per mode


func _ready() -> void:
	layer = 20   # above the board and the HUD banner
	_build_ui()
	visible = false


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.08, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-330, -230)
	panel.custom_minimum_size = Vector2(660, 460)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.13, 0.17, 1.0)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 28)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)

	_bag_label = Label.new()
	_bag_label.add_theme_font_size_override("font_size", 18)
	_bag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bag_label.modulate = Color(1, 1, 1, 0.82)
	col.add_child(_bag_label)

	# The three primary choices.
	_choice_box = VBoxContainer.new()
	_choice_box.add_theme_constant_override("separation", 12)
	col.add_child(_choice_box)

	_choice_box.add_child(_big_button("DEPLOY  —  draw 3 from bag", _on_deploy))
	_choice_box.add_child(_big_button("RECRUIT  —  add Units to bag", _on_recruit_open))
	_choice_box.add_child(_big_button("PUNISH COWARDS  —  draw 5, remove Cowards", _on_punish))

	# The Recruit MODE chooser (Regular vs Special), shown when Recruit is tapped.
	_mode_box = VBoxContainer.new()
	_mode_box.add_theme_constant_override("separation", 12)
	_mode_box.visible = false
	col.add_child(_mode_box)
	var mode_lbl := Label.new()
	mode_lbl.text = "Recruit which?"
	mode_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_lbl.add_theme_font_size_override("font_size", 18)
	_mode_box.add_child(mode_lbl)
	_mode_box.add_child(_big_button("3 REGULAR UNITS (Warriors)", _on_pick_regular))
	_mode_box.add_child(_big_button("2 SPECIAL UNITS", _on_pick_special))
	_mode_box.add_child(_big_button("BACK", _on_recruit_back))

	# The Recruit unit picker (hidden until a mode is chosen).
	_recruit_box = VBoxContainer.new()
	_recruit_box.add_theme_constant_override("separation", 8)
	_recruit_box.visible = false
	col.add_child(_recruit_box)

	_recruit_count_label = Label.new()
	_recruit_count_label.add_theme_font_size_override("font_size", 18)
	_recruit_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_recruit_box.add_child(_recruit_count_label)

	_recruit_grid = GridContainer.new()
	_recruit_grid.columns = 2
	_recruit_grid.add_theme_constant_override("h_separation", 10)
	_recruit_grid.add_theme_constant_override("v_separation", 8)
	_recruit_box.add_child(_recruit_grid)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	_confirm_recruit_btn = _big_button("CONFIRM RECRUIT", _on_recruit_confirm)
	_confirm_recruit_btn.custom_minimum_size = Vector2(240, 52)
	btn_row.add_child(_confirm_recruit_btn)
	var back := _big_button("BACK", _on_recruit_mode_back)
	back.custom_minimum_size = Vector2(140, 52)
	btn_row.add_child(back)
	_recruit_box.add_child(btn_row)

	_result_label = Label.new()
	_result_label.add_theme_font_size_override("font_size", 18)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.modulate = Color(0.8, 0.95, 0.8)
	col.add_child(_result_label)


func _big_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(600, 56)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	return b


func _recruit_add_button(uid: StringName) -> Button:
	var b := Button.new()
	b.text = "+ " + str(UNIT_NAMES.get(uid, str(uid)))
	b.custom_minimum_size = Vector2(280, 48)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(_on_recruit_pick.bind(uid))
	return b


# ---------------------------------------------------------------------------
#  Public: open for a seat
# ---------------------------------------------------------------------------

## Raise the panel for `color`, reading `player` (the Player model) for bag odds and
## leader-based recruit cap.
func open_for(color: StringName, player) -> void:
	_color = color
	_player = player
	_recruit_pick.clear()
	_recruit_mode = ""
	_seraph = player != null and player.leader != null \
			and player.leader.passive_effect_id == &"seraph_recruit"
	_title.text = "%s — Recruitment" % str(color).to_upper()
	_refresh_bag()
	_result_label.text = ""
	_choice_box.visible = true
	_mode_box.visible = false
	_recruit_box.visible = false
	visible = true


func _refresh_bag() -> void:
	# Bag contents are HIDDEN INFO — the player only knows HOW MANY tokens are in the
	# bag, not the mix (that uncertainty is core to the draw). Show the total only.
	if _player == null:
		_bag_label.text = ""
		return
	var total: int = _player.bag_size()
	_bag_label.text = "Bag: %d token%s" % [total, "" if total == 1 else "s"]


# ---------------------------------------------------------------------------
#  Choice handlers — each builds an intent and emits choice_made
# ---------------------------------------------------------------------------

func _on_deploy() -> void:
	_emit_and_close({"play_recruitment_card": -1, "choice": "deploy", "recruit_ids": []})


func _on_punish() -> void:
	_emit_and_close({"play_recruitment_card": -1, "choice": "punish", "recruit_ids": []})


## Recruit tapped -> choose Regular or Special mode first.
func _on_recruit_open() -> void:
	_choice_box.visible = false
	_mode_box.visible = true
	_recruit_box.visible = false


## BACK from the mode chooser -> main choices.
func _on_recruit_back() -> void:
	_mode_box.visible = false
	_recruit_box.visible = false
	_choice_box.visible = true


## BACK from the unit picker -> mode chooser.
func _on_recruit_mode_back() -> void:
	_recruit_box.visible = false
	_mode_box.visible = true


func _on_pick_regular() -> void:
	_recruit_mode = "regular"
	_recruit_cap = 5 if _seraph else 3
	_open_unit_picker(REGULAR_IDS)


func _on_pick_special() -> void:
	_recruit_mode = "special"
	_recruit_cap = 3 if _seraph else 2
	_open_unit_picker(SPECIAL_IDS)


func _open_unit_picker(ids: Array) -> void:
	_recruit_pick.clear()
	for c in _recruit_grid.get_children():
		c.queue_free()
	for uid in ids:
		_recruit_grid.add_child(_recruit_add_button(uid))
	_mode_box.visible = false
	_recruit_box.visible = true
	_refresh_recruit_count()


func _on_recruit_pick(uid: StringName) -> void:
	if _recruit_pick.size() >= _recruit_cap:
		return
	_recruit_pick.append(uid)
	_refresh_recruit_count()


func _refresh_recruit_count() -> void:
	var names: Array = []
	for uid in _recruit_pick:
		names.append(str(UNIT_NAMES.get(uid, str(uid))))
	var picked := ", ".join(names) if not names.is_empty() else "(none yet)"
	_recruit_count_label.text = "%s — pick up to %d  —  %d/%d:  %s" \
		% [_recruit_mode.to_upper(), _recruit_cap, _recruit_pick.size(), _recruit_cap, picked]


func _on_recruit_confirm() -> void:
	if _recruit_pick.is_empty():
		_recruit_count_label.text = "Pick at least one Unit, or tap BACK."
		return
	_emit_and_close({
		"play_recruitment_card": -1,
		"choice": "recruit",
		"recruit_ids": _recruit_pick.duplicate(),
	})


func _emit_and_close(intent: Dictionary) -> void:
	visible = false
	emit_signal("choice_made", intent)

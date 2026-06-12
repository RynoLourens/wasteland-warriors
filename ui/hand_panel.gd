extends CanvasLayer
class_name HandPanel
## Section F, step 4 — the player's Action-card hand.
##
## Shows the ACTIVE human's hand as a horizontal, scrollable strip of CardUI widgets
## pinned to the bottom-left (away from the bottom-right Pass button). Unlimited hand
## size; the strip scrolls when it overflows.
##
## Interaction (Corin's model): tap a card to SELECT it — it highlights and lifts
## slightly. Tap the SAME card again to PLAY it. Right-click anywhere deselects.
## (No separate zoom/Play buttons.) A HAND toggle collapses the strip so it never
## permanently covers the board.
##
## Reads Player.hand (Array of ActionCardData); owns NO rules. Playing emits
## `play_card(card, index)`, which BoardView routes to the effect system (Piece 5b).

signal play_card(card, index)

const CARD_SIZE := Vector2(162, 238)
const STRIP_H := 252

var _strip_root: Control
var _scroll: ScrollContainer
var _strip: HBoxContainer
var _toggle_btn: Button
var _count_lbl: Label

var _player = null
var _shown_color: StringName = &""
var _strip_visible: bool = true
var _can_play: bool = false
var _selected_index: int = -1
var _card_widgets: Array = []   # CardUI per hand index
# Which card TYPES are playable in the current context (0=Recruitment,1=Movement,
# 2=Attack). Empty = none playable. Set via show_for().
var _playable_types: Array = []


func _ready() -> void:
	# Above the recruitment panel (20) so cards are playable DURING recruitment too,
	# but below target pickers (26) and the hand-off cover (28). The strip is anchored
	# bottom-left and the recruitment panel is centred, so they don't visually clash.
	layer = 21
	_build_ui()
	visible = false


func _build_ui() -> void:
	_strip_root = Control.new()
	_strip_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_strip_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip_root)

	# HAND toggle + count, on a row ABOVE the strip so cards never cover them.
	_toggle_btn = Button.new()
	_toggle_btn.text = "HAND ▾"
	_toggle_btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_toggle_btn.position = Vector2(16, -(STRIP_H + 50))
	_toggle_btn.custom_minimum_size = Vector2(110, 38)
	_toggle_btn.add_theme_font_size_override("font_size", 16)
	_toggle_btn.pressed.connect(_on_toggle)
	_strip_root.add_child(_toggle_btn)

	_count_lbl = Label.new()
	_count_lbl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_count_lbl.position = Vector2(138, -(STRIP_H + 42))
	_count_lbl.add_theme_font_size_override("font_size", 14)
	_count_lbl.modulate = Color(1, 1, 1, 0.7)
	_strip_root.add_child(_count_lbl)

	# Scrollable card strip. Left-anchored, limited width so it stays clear of the
	# bottom-right Pass button area.
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_scroll.position = Vector2(16, -(STRIP_H + 4))
	_scroll.custom_minimum_size = Vector2(900, STRIP_H)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_strip_root.add_child(_scroll)

	_strip = HBoxContainer.new()
	_strip.add_theme_constant_override("separation", 10)
	_scroll.add_child(_strip)


# ---------------------------------------------------------------------------
#  Public API
# ---------------------------------------------------------------------------

## `playable_types` = the card types playable right now (e.g. [0] in Recruitment,
## [1] during an Action turn). Cards of other types are shown but dimmed + not
## selectable.
func show_for(color: StringName, player, can_play: bool, playable_types: Array = []) -> void:
	_shown_color = color
	_player = player
	_can_play = can_play
	_playable_types = playable_types
	_selected_index = -1
	visible = true
	_rebuild_strip()


func _is_playable(card) -> bool:
	return _can_play and card != null and int(card.card_type) in _playable_types


func hide_hand() -> void:
	visible = false
	_selected_index = -1


func _rebuild_strip() -> void:
	for c in _strip.get_children():
		c.queue_free()
	_card_widgets.clear()
	if _player == null:
		_count_lbl.text = ""
		return
	var hand: Array = _player.hand
	_count_lbl.text = "%d card%s" % [hand.size(), "" if hand.size() == 1 else "s"]
	for i in range(hand.size()):
		var cu := CardUI.new(hand[i], CARD_SIZE)
		cu.set_playable(_is_playable(hand[i]))   # dim if not playable in this context
		cu.tapped.connect(_on_card_tapped.bind(i))
		_strip.add_child(cu)
		_card_widgets.append(cu)
	_scroll.visible = _strip_visible


func _on_toggle() -> void:
	_strip_visible = not _strip_visible
	_scroll.visible = _strip_visible
	_toggle_btn.text = "HAND ▾" if _strip_visible else "HAND ▴"


# ---------------------------------------------------------------------------
#  Select -> confirm-play interaction
# ---------------------------------------------------------------------------

func _on_card_tapped(card, index: int) -> void:
	if not _is_playable(card):
		return   # non-playable in this context: ignore taps (it's shown dimmed)
	if index == _selected_index:
		# Second tap on the selected card = play it.
		_play_selected()
		return
	_select(index)


func _select(index: int) -> void:
	_selected_index = index
	for i in range(_card_widgets.size()):
		_card_widgets[i].set_selected(i == index)


func _deselect() -> void:
	_selected_index = -1
	for cu in _card_widgets:
		cu.set_selected(false)


func _play_selected() -> void:
	if _selected_index < 0 or _player == null:
		return
	if not _can_play:
		return
	var idx := _selected_index
	if idx >= _player.hand.size():
		_deselect()
		return
	var card = _player.hand[idx]
	_deselect()
	if card != null:
		play_card.emit(card, idx)


## Deselect on click-away: a left-click that lands OUTSIDE every card drops the
## selection. The card's own gui_input fires first (select / play), so by the time
## this sees a click on a card, that card was already handled and we leave it. We do
## NOT consume the event, so a click-away still reaches the board normally.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _selected_index < 0:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if not _click_is_on_a_card(event.position):
			_deselect()


func _click_is_on_a_card(global_pos: Vector2) -> bool:
	for cu in _card_widgets:
		if is_instance_valid(cu) and cu.get_global_rect().has_point(global_pos):
			return true
	return false

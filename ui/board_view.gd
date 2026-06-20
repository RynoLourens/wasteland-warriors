extends Node2D
class_name BoardView
## Section E — Greybox board & interaction (the FIRST visual section).
##
## This node OWNS no rules. It renders GameState and turns clicks into intents,
## following the strict one-directional flow the build plan demands:
##
##     input (click) -> ask logic "is this legal?" -> ActionResolver mutates
##     GameState + emits EventBus signals -> THIS layer hears the signal and
##     redraws.  The visual layer NEVER mutates the board itself.
##
## Everything is grey shapes: Polygon2D hexes, rectangle unit tokens, labels.
## Art arrives in Section G; the point here is to watch the proven engine play.

# --- Hex geometry (flat-top, axial -> pixel). Pure presentation; the engine
#     never sees pixels (HexCoord is axial-only by design). ---
const HEX_SIZE := 56.0                      # centre-to-corner radius in px
const HEX_W := HEX_SIZE * 2.0               # flat-top width  = 2 * size
const HEX_H := sqrt(3.0) * HEX_SIZE         # flat-top height = sqrt(3) * size

# Greybox palette ----------------------------------------------------------
const COL_CENTER := Color(0.32, 0.30, 0.36)
const COL_ROOM := Color(0.42, 0.42, 0.46)
const COL_CORRIDOR := Color(0.30, 0.34, 0.40)
const COL_RALLY := Color(0.26, 0.36, 0.30)
const COL_EDGE := Color(0.12, 0.12, 0.14)
const COL_EXIT := Color(0.78, 0.74, 0.55)          # open-edge markers
const COL_HILITE := Color(0.30, 0.70, 0.95, 0.55)  # reachable tint
const COL_SUPPORT := Color(0.96, 0.62, 0.16, 0.50) # eligible Ranged support-fire glow
const COL_ACTIVATE := Color(0.95, 0.78, 0.25, 0.85)
const COL_STAGED := Color(0.98, 0.85, 0.20)        # staged-to-move unit outline/badge
const TOKEN_HIT_PAD := 8.0                          # padding on unit-token click targets
const PLAYER_COLORS := {
	&"green": Color(0.35, 0.78, 0.40),
	&"blue": Color(0.35, 0.55, 0.92),
	&"red": Color(0.90, 0.40, 0.40),
	&"guardian": Color(0.70, 0.45, 0.85),
}

# Runtime state (presentation only) ----------------------------------------
var _hex_nodes: Dictionary = {}     # hexkey(String) -> Polygon2D
var _hilites: Dictionary = {}       # hexkey -> Polygon2D (reachable overlay)
var _overlays: Dictionary = {}      # hexkey -> Node2D (tokens/labels per cell)
var _unit_rects: Dictionary = {}    # hexkey -> [{unit, owner, rect}] for click hit-test
var _token_rects: Dictionary = {}   # hexkey -> [{data, rect}] for env/func hover tooltips
var _reveal_order: Array = []       # Array of hexkey, centre-out (for animation)
var _revealing := false
var _reveal_tween: Tween = null     # master cadence tween (killed on skip)

# Interaction (the click-driven Move-and-Attack flow) ----------------------
var _human_color: StringName = &"green"   # whose turn we're driving by hand
var _selected_activate: HexCoord = null   # the space being activated
var _reachable_keys: Dictionary = {}      # hexkey -> true, currently legal dests
var _staged_moves: Array = []             # [{from: HexCoord, unit}] chosen so far

# Section F HUD / hotseat hand-off -----------------------------------------
var _hud: GameHUD = null
var _recruit_panel: RecruitmentPanel = null
var _hand_panel: HandPanel = null
var _combat_readout: CombatReadout = null
var _win_screen: WinScreen = null

# Zoom / pan (Fix G). scale = _fit_scale * _zoom; position = band - center*scale + pan.
var _fit_scale: float = 1.0
var _board_center: Vector2 = Vector2.ZERO
var _band_center: Vector2 = Vector2.ZERO
var _zoom: float = 1.6
const _min_zoom := 1.0
const _max_zoom := 4.0
const _zoom_step := 1.12
var _pan: Vector2 = Vector2.ZERO
var _panning: bool = false             # middle-mouse drag
var _pan_last: Vector2 = Vector2.ZERO
var _lmb_down: bool = false            # left button held (may become a drag-pan)
var _lmb_dragged: bool = false         # the current left-hold has moved -> panning
var _lmb_start: Vector2 = Vector2.ZERO
const _key_pan_speed := 700.0          # px/sec for arrow / WASD panning
var _human_count: int = 0                 # how many seats are humans (hand-off gate)
var _last_handoff_human: StringName = &""  # the human currently behind the device
var _handoff_blocking: bool = false       # a cover is up; suppress action panels
var _active_human: StringName = &""        # the human whose intent we're collecting
var _my_action_turn: bool = false          # true while the active human owes an ACTION intent
var _last_illegal_reason: String = ""      # reason from the last rejected move (re-prompt)

@onready var _hex_root: Node2D = $HexRoot
@onready var _overlay_root: Node2D = $OverlayRoot
@onready var _hilite_root: Node2D = $HiliteRoot
@onready var _status: Label = $UILayer/StatusLabel
@onready var _skip_btn: Button = $UILayer/SkipButton


func _ready() -> void:
	# Listen to the engine, never poke it from here except through resolvers.
	var bus := _bus()
	if bus != null:
		bus.unit_moved.connect(_on_unit_moved)
		bus.token_flipped.connect(_on_token_flipped)
		bus.control_changed.connect(_on_control_changed)
		bus.combat_resolved.connect(_on_combat_resolved)
		bus.guardian_spawned.connect(_on_guardian_spawned)
		bus.old_tech_captured.connect(_on_old_tech_captured)
	if _skip_btn != null:
		_skip_btn.pressed.connect(_skip_reveal)

	# Section F HUD: phase/turn banner + hotseat hand-off cover, on its own layer.
	_hud = GameHUD.new()
	add_child(_hud)
	_hud.handoff_confirmed.connect(_on_handoff_confirmed)

	# Recruitment panel (Piece 3) — raised when a human owes a recruitment intent.
	_recruit_panel = RecruitmentPanel.new()
	add_child(_recruit_panel)
	_recruit_panel.choice_made.connect(_on_recruitment_choice)
	_recruit_panel.view_map_requested.connect(_on_view_map_requested)
	# Action-phase Pass button lives on the HUD.
	_hud.pass_pressed.connect(_on_pass_pressed)

	# Card hand (Piece 5) — shows the active human's hand; tap-to-zoom + play.
	_hand_panel = HandPanel.new()
	add_child(_hand_panel)
	_hand_panel.play_card.connect(_on_play_card)

	# Combat readout + win screen (Piece 6).
	_combat_readout = CombatReadout.new()
	add_child(_combat_readout)
	_win_screen = WinScreen.new()
	add_child(_win_screen)

	# Fix H: provide the per-round combat-card window to the controller.
	if _controller_match_active():
		GameController.combat_round_provider = _combat_round_provider
		# Interactive hit assignment: human defenders choose which Unit takes a hit.
		GameController.combat_assign_provider = _combat_assign_provider
		# Ranged support fire: human picks which Ranged Units fire INTO a combat (Ch.11).
		GameController.support_fire_provider = _support_fire_provider

	# Section F: GameController (autoload) owns match setup + the round-loop
	# coroutine. If a match is already running (started from the SetupScreen), just
	# render it. Otherwise fall back to a standalone demo match so BoardView still
	# runs on its own (handy in the editor) — Section E behaviour, demo-seeded.
	if GameState.players.is_empty():
		var seed := int(Time.get_unix_time_from_system())
		GameState.setup_match([
			{"color": &"green", "is_ai": false},
			{"color": &"blue", "is_ai": true},
			{"color": &"red", "is_ai": true},
		], seed)
		_seed_demo_units()
		_human_color = &"green"

	# When the controller is driving, listen for phase/turn changes so the banner
	# and hand-off cover react. (Standalone demo has no controller signals.)
	if _controller_match_active():
		# Retire the old top-left StatusLabel — the HUD banner + action bar replace it.
		if _status != null:
			_status.visible = false
		_human_count = GameController.human_colors.size()
		GameController.phase_changed.connect(_on_phase_changed)
		GameController.seat_turn_began.connect(_on_seat_turn_began)
		GameController.seat_passed.connect(_on_seat_passed)
		GameController.pass_state_reset.connect(_on_pass_state_reset)
		GameController.action_resolved.connect(_on_action_resolved)
		GameController.recruitment_resolved.connect(_on_recruitment_resolved)
		GameController.round_completed.connect(_on_round_completed)
		GameController.game_over.connect(_on_game_over)
		# Connect to each HumanAgent's await signals — the correct, race-free hook
		# for raising the human's panel (the agent has, by then, entered its waiting
		# state, so submit() resolves it). Pieces 3/4 raise real panels here.
		for hcolor in GameController.human_colors:
			var ha = GameController.human_agent_for(hcolor)
			if ha != null:
				ha.awaiting_recruitment.connect(_on_awaiting_recruitment)
				ha.awaiting_action.connect(_on_awaiting_action)

	_build_board_nodes()
	_start_reveal()


# ---------------------------------------------------------------------------
#  Board construction
# ---------------------------------------------------------------------------

## Axial (q, r) -> pixel centre for flat-top hexes (Red Blob Games model).
func _hex_to_pixel(q: int, r: int) -> Vector2:
	var x := HEX_SIZE * 1.5 * float(q)
	var y := HEX_H * (float(r) + float(q) / 2.0)
	return Vector2(x, y)


## Six corner offsets for a flat-top hex of HEX_SIZE.
func _hex_corners() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(6):
		var ang := deg_to_rad(60.0 * float(i))
		pts.append(Vector2(HEX_SIZE * cos(ang), HEX_SIZE * sin(ang)))
	return pts


func _build_board_nodes() -> void:
	# Clear any prior render.
	for child in _hex_root.get_children():
		child.queue_free()
	for child in _overlay_root.get_children():
		child.queue_free()
	for child in _hilite_root.get_children():
		child.queue_free()
	_hex_nodes.clear()
	_overlays.clear()
	_hilites.clear()
	_reveal_order.clear()

	var corners := _hex_corners()

	# Build hexes in spiral (centre-out) order so the reveal animation is free.
	var ordered_coords := _board_coords_center_out()
	for coord in ordered_coords:
		var cell: HexCell = GameState.get_cell(coord)
		if cell == null:
			continue
		var pos := _hex_to_pixel(coord.q, coord.r)

		var poly := Polygon2D.new()
		poly.polygon = corners
		poly.color = _tile_color(coord, cell)
		poly.position = pos
		_hex_root.add_child(poly)
		_hex_nodes[coord.key()] = poly

		# Edge outline + open-exit markers (so a tester can see connectivity).
		_draw_cell_edges(poly, cell, corners)

		# Per-cell overlay layer (units, tokens, old tech, coord label).
		var ov := Node2D.new()
		ov.position = pos
		_overlay_root.add_child(ov)
		_overlays[coord.key()] = ov
		_redraw_cell_overlay(coord)

		_reveal_order.append(coord.key())

	_center_camera_on_board(ordered_coords)


## Board coords sorted centre-first by ring, for spiral reveal. We read the
## board's actual keys (the generator may add rally fixtures on ring 3).
func _board_coords_center_out() -> Array:
	var coords := []
	for k in GameState.board.keys():
		coords.append(HexCoord.from_key(k))
	var ctr: HexCoord = GameState.center
	if ctr == null:
		ctr = HexCoord.new(0, 0)
	coords.sort_custom(func(a, b): return a.distance_to(ctr) < b.distance_to(ctr))
	return coords


func _tile_color(coord: HexCoord, cell: HexCell) -> Color:
	# Rally zones get their own tint regardless of tile type.
	for color in GameState.rally_zones.keys():
		var rz: HexCoord = GameState.rally_zones[color]
		if rz != null and rz.equals(coord):
			return COL_RALLY
	match cell.tile_type:
		HexCell.TileType.CENTER:
			return COL_CENTER
		HexCell.TileType.CORRIDOR:
			return COL_CORRIDOR
		_:
			return COL_ROOM


func _draw_cell_edges(poly: Polygon2D, cell: HexCell, corners: PackedVector2Array) -> void:
	# Outline.
	var outline := Line2D.new()
	outline.width = 2.0
	outline.default_color = COL_EDGE
	outline.closed = true
	for c in corners:
		outline.add_point(c)
	poly.add_child(outline)

	# Mark each OPEN edge with a thick bar on the edge that FACES the neighbour in
	# that logical direction. The logic's DIRECTIONS (0=E,1=NE,2=NW,3=W,4=SW,5=SE)
	# do NOT line up with "corners dir..dir+1", so we pick the hex edge whose midpoint
	# points toward the neighbour's pixel offset. This is what makes the yellow bars
	# actually correspond to where a Unit can move.
	for dir in range(6):
		if not cell.has_exit(dir):
			continue
		# Pixel direction toward this neighbour (relative to this hex centre).
		var d: Vector2i = HexCoord.DIRECTIONS[dir]
		var ndir: Vector2 = _hex_to_pixel(d.x, d.y).normalized()
		# Find the boundary edge (corner i -> i+1) whose midpoint normal best matches.
		var best_i := 0
		var best_dot := -2.0
		for i in range(6):
			var mid := corners[i].lerp(corners[(i + 1) % 6], 0.5)
			var dot := mid.normalized().dot(ndir)
			if dot > best_dot:
				best_dot = dot
				best_i = i
		var a := corners[best_i]
		var b := corners[(best_i + 1) % 6]
		var bar := Line2D.new()
		bar.width = 6.0
		bar.default_color = COL_EXIT
		bar.add_point(a.lerp(b, 0.2))
		bar.add_point(a.lerp(b, 0.8))
		poly.add_child(bar)


func _center_camera_on_board(coords: Array) -> void:
	if coords.is_empty():
		return
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for coord in coords:
		var p := _hex_to_pixel(coord.q, coord.r)
		min_p.x = min(min_p.x, p.x)
		min_p.y = min(min_p.y, p.y)
		max_p.x = max(max_p.x, p.x)
		max_p.y = max(max_p.y, p.y)
	# Full pixel extent INCLUDING each hex's half-size (min/max above are centres).
	var board_w := (max_p.x - min_p.x) + HEX_W
	var board_h := (max_p.y - min_p.y) + HEX_H
	var board_center := (min_p + max_p) * 0.5

	# Reserve top space for the banner+hint and bottom for the hand strip, then compute
	# the scale that FITS the board in what's left — this becomes the min-zoom floor.
	var vp := get_viewport_rect().size
	var top_reserve := 120.0 if _controller_match_active() else 16.0
	var bottom_reserve := 270.0 if _controller_match_active() else 16.0
	var avail_w := vp.x - 40.0
	var avail_h := vp.y - top_reserve - bottom_reserve
	_fit_scale = min(avail_w / board_w, avail_h / board_h)
	_board_center = board_center
	_band_center = Vector2(vp.x * 0.5, top_reserve + (vp.y - top_reserve - bottom_reserve) * 0.5)
	# Default to a comfortably larger view than bare fit (but cap at 1.0 raw), and
	# reset any pan.
	_zoom = clampf(1.6, 1.0, _max_zoom)
	_pan = Vector2.ZERO
	_apply_view()


## Apply the current zoom (× the fit floor) and pan to the node transform, then
## centre the board in the available band.
func _apply_view() -> void:
	var s: float = _fit_scale * _zoom
	scale = Vector2(s, s)
	position = _band_center - _board_center * s + _pan


## Zoom by `factor` keeping the board point under `screen_pos` stationary.
func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var old_s: float = _fit_scale * _zoom
	if old_s <= 0.0:
		return
	# Board-local point currently under the cursor.
	var world := (screen_pos - position) / old_s
	_zoom = clampf(_zoom * factor, _min_zoom, _max_zoom)
	var new_s: float = _fit_scale * _zoom
	# Solve pan so that band - center*new_s + pan + new_s*world == screen_pos.
	_pan = screen_pos - new_s * world - (_band_center - _board_center * new_s)
	_apply_view()


# ---------------------------------------------------------------------------
#  Map-generation reveal (animated, skippable) — Section E step 2
# ---------------------------------------------------------------------------

func _start_reveal() -> void:
	_revealing = true
	if _skip_btn != null:
		_skip_btn.visible = true
	# Hide everything, then pop hexes in centre-out order on a short cadence.
	for k in _reveal_order:
		_hex_nodes[k].scale = Vector2.ZERO
		if _overlays.has(k):
			(_overlays[k] as Node2D).visible = false

	_reveal_tween = create_tween()
	var step := 0.04
	var i := 0
	for k in _reveal_order:
		var node: Polygon2D = _hex_nodes[k]
		var ov: Node2D = _overlays.get(k)
		_reveal_tween.tween_callback(func(): _pop_hex(node, ov)).set_delay(step if i > 0 else 0.0)
		i += 1
	_reveal_tween.tween_callback(_finish_reveal)


func _pop_hex(node: Polygon2D, ov: Node2D) -> void:
	if not is_instance_valid(node):
		return
	var t := create_tween()
	t.tween_property(node, "scale", Vector2.ONE, 0.18) \
		.from(Vector2.ZERO).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if ov != null:
		ov.visible = true


func _skip_reveal() -> void:
	_finish_reveal()


func _finish_reveal() -> void:
	if not _revealing:
		return
	_revealing = false
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()
		_reveal_tween = null
	for k in _reveal_order:
		var node: Polygon2D = _hex_nodes[k]
		if is_instance_valid(node):
			node.scale = Vector2.ONE
		if _overlays.has(k):
			(_overlays[k] as Node2D).visible = true
	if _skip_btn != null:
		_skip_btn.visible = false
	# Section F: now that the board is revealed and our EventBus handlers are live,
	# let the controller start driving rounds (if a real match is running). In the
	# standalone demo fallback there is no controller match, so just prompt.
	if _controller_match_active():
		_set_status("")   # the HUD banner now reports turn/phase; clear the old label
		GameController.begin()
	else:
		_set_status("%s's turn — click a space to Activate." % str(_human_color))


## True when GameController is driving a real match (started from SetupScreen),
## as opposed to BoardView's standalone editor-demo fallback.
func _controller_match_active() -> bool:
	var gc = get_tree().root.get_node_or_null("GameController")
	return gc != null and gc.agents != null and not gc.agents.is_empty()


# ---------------------------------------------------------------------------
#  Section F — controller signal handlers (banner + hotseat hand-off)
# ---------------------------------------------------------------------------

func _on_phase_changed(phase: int) -> void:
	if _hud != null:
		_hud.set_phase(phase)


## Each seat's turn (human or AI). Update the banner; for a human seat in a 2+-human
## game, raise the hand-off cover first so the previous player's hidden info isn't
## seen across the device pass. AI seats just update the banner and act instantly.
var _pending_human_phase: int = -1        # phase the active human still owes an intent for


func _on_seat_passed(color: StringName) -> void:
	if _hud != null:
		_hud.mark_passed(color)


func _on_pass_state_reset() -> void:
	if _hud != null:
		_hud.reset_passed()


func _on_seat_turn_began(color: StringName, phase: int) -> void:
	if _hud != null:
		_hud.show_turn(color, phase)
	# Drive the on-board click flow for whichever human is active.
	if GameController.is_human(color):
		_human_color = color
		_maybe_handoff(color, phase)


## A human's recruitment intent is awaited — raise the recruitment panel (Piece 3).
## Until then, auto-advance once any hand-off cover is cleared.
func _on_awaiting_recruitment(color: StringName) -> void:
	_pending_human_phase = GameState.Phase.RECRUITMENT
	if not _handoff_blocking:
		_serve_human(color)


## A human's action intent is awaited — raise the action panel (Piece 4).
func _on_awaiting_action(color: StringName) -> void:
	_pending_human_phase = GameState.Phase.ACTION
	if not _handoff_blocking:
		_serve_human(color)


func _maybe_handoff(color: StringName, phase: int = -1) -> void:
	# Cover only matters with 2+ humans (nothing to hide in solo-vs-AI).
	if _human_count < 2:
		_last_handoff_human = color
		return
	# Same human still holding the device (e.g. consecutive Action sub-turns) — no
	# need to pass again.
	if color == _last_handoff_human:
		return
	_handoff_blocking = true
	if _hand_panel != null:
		_hand_panel.hide_hand()   # never reveal a hand behind the device-pass cover
	if _hud != null:
		_hud.show_handoff(color, phase)


func _on_handoff_confirmed(color: StringName) -> void:
	_last_handoff_human = color
	_handoff_blocking = false
	# The device is now in front of `color`; serve whatever intent they owe.
	if _pending_human_phase >= 0:
		_serve_human(color)


## Serve the active human their pending decision. Recruitment raises the Recruitment
## panel (Piece 3); Action opens the on-board click flow + Pass button (Piece 4).
func _serve_human(color: StringName) -> void:
	var phase := _pending_human_phase
	_pending_human_phase = -1
	_active_human = color
	_human_color = color
	var p = GameState.get_player(color)
	# Show this human's hand. Playable card types depend on the phase:
	#   Recruitment -> Recruitment cards (type 0); Action -> Movement cards (type 1).
	# Attack cards (type 2) are never played from the hand — only in combat windows.
	if _hand_panel != null:
		var playable: Array = [0] if phase == GameState.Phase.RECRUITMENT else [1]
		_hand_panel.show_for(color, p, true, playable)
	if phase == GameState.Phase.RECRUITMENT:
		_recruit_card_played = false   # fresh turn: one card may be played
		_recruit_panel.open_for(color, p)
		return
	# ACTION phase — hand control to the board click flow.
	_begin_action_turn(color)


## Open the active human's Action turn: enable board input, show the Pass button.
func _begin_action_turn(color: StringName) -> void:
	_my_action_turn = true
	_cancel_selection()
	var hint := "%s — tap a space to Activate it, then move Units in. Or Pass." % str(color).to_upper()
	if _last_illegal_reason != "":
		hint = "Illegal: %s  —  try again, or Pass." % _last_illegal_reason
		_last_illegal_reason = ""
	if _hud != null:
		_hud.set_action_bar(true, hint)


## The Recruitment panel produced an intent — hand it to the active human's agent.
## Player tapped "VIEW MAP" during Recruitment: hide the panel so the board is visible,
## and arm a one-shot so the NEXT board click/right-click brings the panel back rather
## than acting on the board.
func _on_view_map_requested() -> void:
	if _recruit_panel != null:
		_recruit_panel.hide_panel()
	_map_peeking = true
	_set_status("Viewing map — tap anywhere on the board to return to Recruitment.")


func _end_map_peek() -> void:
	_map_peeking = false
	if _recruit_panel != null:
		_recruit_panel.show_panel()


func _on_recruitment_choice(intent: Dictionary) -> void:
	if _hand_panel != null:
		_hand_panel.hide_hand()
	var agent = GameController.human_agent_for(_active_human)
	if agent != null:
		agent.submit(intent)


var _pending_card = null            # a played card awaiting a target pick
var _pending_card_index: int = -1
var _pending_card_need: String = ""  # "controlled_space" | "player"
var _recruit_panel_suspended := false  # recruitment panel hidden while targeting a card
var _map_peeking := false              # recruitment panel hidden so the player can view the board
var _recruit_card_played := false      # a card already played this Recruitment turn (limit 1)


## A card was played. Resolve its effect via CardEffects. If the card needs a target,
## enter a pick mode; otherwise apply immediately, discard, and refresh the hand.
func _on_play_card(card, index: int) -> void:
	var p = GameState.get_player(_active_human)
	if p == null or card == null:
		return
	# Recruitment phase: at most ONE card may be played per turn (rulebook). Block a
	# second play (including while the first is still awaiting its on-board target).
	if GameState.current_phase == GameState.Phase.RECRUITMENT \
			and (_recruit_card_played or _pending_card != null):
		if _hud != null:
			_hud.set_action_hint("Only one card may be played during Recruitment.")
		return
	var unit_db: Dictionary = GameController.unit_db if _controller_match_active() else {}
	var res: Dictionary = CardEffects.resolve(GameState, _active_human, card, unit_db)
	if not res.get("ok", false):
		_hud.set_action_hint("Can't play: %s" % res.get("reason", "?"))
		return
	var needs: String = res.get("needs", "")
	if needs != "":
		# Hold the card; collect a target, then resolve_targeted and discard.
		_pending_card = card
		_pending_card_index = index
		_pending_card_need = needs
		_enter_card_target_mode(needs, str(res.get("reason", "Pick a target.")))
		return
	# Immediate effect — consume the card now.
	_consume_card(p, index, card)
	_hud.set_action_hint(str(res.get("reason", "Card played.")))
	_redraw_all_cells()
	_maybe_end_action_after_card(card)


## Playing a MOVEMENT card during the Action phase USES your action (rulebook). End
## the action turn after such a card resolves. Recruitment cards don't end the
## recruitment step (you still choose Deploy/Recruit/Punish).
func _maybe_end_action_after_card(card) -> void:
	if card == null:
		return
	if _my_action_turn and int(card.card_type) == 1:   # MOVEMENT
		_my_action_turn = false
		if _hud != null:
			_hud.set_action_bar(false)
		if _hand_panel != null:
			_hand_panel.hide_hand()
		_cancel_selection()
		var agent = GameController.human_agent_for(_active_human)
		if agent != null:
			agent.submit({"type": "card", "hand_index": -1})


func _consume_card(p, index: int, card) -> void:
	# Remove the exact card by identity (hand may have duplicates).
	for i in range(p.hand.size()):
		if is_same(p.hand[i], card):
			p.hand.remove_at(i)
			break
	GameState.discard_action_card(card)
	# Recruitment allows only one card per turn — record that it's now spent.
	if GameState.current_phase == GameState.Phase.RECRUITMENT:
		_recruit_card_played = true
	# Re-show the hand preserving the current phase's playable types.
	if _hand_panel != null:
		var phase := GameState.current_phase
		var playable: Array = [0] if phase == GameState.Phase.RECRUITMENT else [1]
		_hand_panel.show_for(_active_human, p, true, playable)


# --- Card targeting ---------------------------------------------------------

func _enter_card_target_mode(need: String, prompt: String) -> void:
	_cancel_selection()
	# If a recruitment-phase card needs an on-board target, the Recruitment panel is
	# covering the board — tuck it away so the player can click a space, then restore
	# it once the card resolves (they still owe their Recruitment action).
	if _recruit_panel != null and _recruit_panel.visible \
			and (need == "controlled_space" or need == "special_unit"):
		_recruit_panel.visible = false
		_recruit_panel_suspended = true
	if need == "controlled_space":
		# Highlight every space the active player controls; next click picks one.
		_clear_hilites()
		var any := false
		for k in GameState.board.keys():
			var coord: HexCoord = HexCoord.from_key(k)
			if GameState.player_controls(_active_human, coord):
				_add_hilite(coord)
				any = true
		if not any:
			_abort_card_target("You control no spaces — card not played.")
			return
		_hud.set_action_hint(prompt + "  (right-click to cancel)")
	elif need == "player":
		_show_player_picker(prompt)
	elif need == "special_unit":
		_show_special_unit_picker(prompt)


func _resolve_card_with_target(target) -> void:
	if _pending_card == null:
		return
	var p = GameState.get_player(_active_human)
	var unit_db: Dictionary = GameController.unit_db if _controller_match_active() else {}
	var res: Dictionary = CardEffects.resolve_targeted(
		GameState, _active_human, _pending_card, unit_db, target)
	if not res.get("ok", false):
		_hud.set_action_hint("Can't apply: %s — pick again or right-click to cancel." % res.get("reason", "?"))
		return
	var played_card = _pending_card
	_consume_card(p, _pending_card_index, _pending_card)
	_clear_card_target_state()
	_clear_hilites()
	_hud.set_action_hint(str(res.get("reason", "Card played.")))
	_redraw_all_cells()
	_maybe_end_action_after_card(played_card)


func _abort_card_target(msg: String) -> void:
	_clear_card_target_state()
	_clear_hilites()
	if _hud != null:
		_hud.set_action_hint(msg)


func _clear_card_target_state() -> void:
	_pending_card = null
	_pending_card_index = -1
	_pending_card_need = ""
	# Restore the Recruitment panel if we tucked it away to collect the target.
	if _recruit_panel_suspended:
		_recruit_panel_suspended = false
		if _recruit_panel != null:
			var p = GameState.get_player(_active_human)
			if p != null and GameState.current_phase == GameState.Phase.RECRUITMENT:
				_recruit_panel.open_for(_active_human, p)


const UNIT_DISPLAY := {
	&"warrior": "Warrior", &"scout": "Scout", &"heavy": "Heavy", &"gunner": "Gunner",
	&"berserker": "Berserker", &"manstopper": "Manstopper",
	&"infiltrator": "Infiltrator", &"sapperteur": "Sapperteur",
}
# Regular Units ("Units"): Warrior, Scout, Gunner, Heavy.
const REGULAR_UNIT_IDS := [&"warrior", &"scout", &"gunner", &"heavy"]
# Special Units: Berserker, Manstopper, Infiltrator, Sapperteur.
const SPECIAL_UNIT_IDS := [&"berserker", &"manstopper", &"infiltrator", &"sapperteur"]


## Supply unit picker for Deploy Unit (action_03): choose which REGULAR Unit to place
## into the already-picked controlled `space`.
func _show_supply_unit_picker(space: HexCoord) -> void:
	_show_unit_picker_overlay("Deploy which Unit?", REGULAR_UNIT_IDS,
		func(uid): _resolve_card_with_target({"space": space, "unit_id": uid}))


## Special unit picker for Deploy Special Unit (action_04). Target is the chosen id.
func _show_special_unit_picker(prompt: String) -> void:
	_show_unit_picker_overlay(prompt, SPECIAL_UNIT_IDS,
		func(uid): _resolve_card_with_target(uid))


## Shared modal: a grid of unit buttons. `on_pick` is called with the chosen id.
func _show_unit_picker_overlay(title_text: String, ids: Array, on_pick: Callable) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 26
	layer.name = "UnitPicker"
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.08, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-220, -200)
	box.add_theme_constant_override("separation", 10)
	layer.add_child(box)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for uid in ids:
		var b := Button.new()
		b.text = str(UNIT_DISPLAY.get(uid, str(uid)))
		b.custom_minimum_size = Vector2(210, 48)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(func():
			layer.queue_free()
			on_pick.call(uid))
		grid.add_child(b)
	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.custom_minimum_size = Vector2(430, 46)
	cancel.pressed.connect(func():
		layer.queue_free()
		_abort_card_target("Card cancelled."))
	box.add_child(cancel)
	add_child(layer)


## A tiny overlay with one button per player (for Sabotage Bag / Force Discard).
func _show_player_picker(prompt: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 26
	layer.name = "PlayerPicker"
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.08, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.position = Vector2(-180, -150)
	col.add_theme_constant_override("separation", 14)
	layer.add_child(col)
	var title := Label.new()
	title.text = prompt
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	for c in GameState.turn_order:
		var b := Button.new()
		b.text = str(c).to_upper()
		b.custom_minimum_size = Vector2(300, 54)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(func():
			layer.queue_free()
			_resolve_card_with_target(c))
		col.add_child(b)
	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.custom_minimum_size = Vector2(300, 48)
	cancel.pressed.connect(func():
		layer.queue_free()
		_abort_card_target("Card cancelled."))
	col.add_child(cancel)
	add_child(layer)


## A move_attack resolved. On illegal, stash the reason — the controller re-asks
## this same human (re-firing awaiting_action), and _begin_action_turn surfaces it.
## Combat readout (the event log) is wired in Piece 6.
func _on_action_resolved(_color: StringName, result: Dictionary) -> void:
	# The combat readout is driven by the EventBus combat_resolved signal (which fires
	# for every combat, incl. Guardian), so we only stash the illegal reason here.
	if not result.get("ok", false):
		_last_illegal_reason = str(result.get("reason", "illegal move"))
		return
	# Announce any Environment/Function token that resolved on arrival so a flipped
	# token / room hazard isn't silent.
	var token_log: Dictionary = result.get("token_log", {})
	var resolved: Array = token_log.get("resolved", [])
	if not resolved.is_empty():
		var parts := []
		for entry in resolved:
			parts.append(str(entry.get("summary", "")))
		var msg := "Explored: " + " · ".join(parts)
		_set_status(msg)
		# Also push to the action-hint panel, which persists through the turn (the
		# status label is overwritten by the next seat's prompt almost immediately).
		if _hud != null:
			_hud.set_action_hint(msg)
	# Token effects can spawn Guardians, add/kill Units, flip tokens — none of which
	# emit a per-cell signal — so refresh the whole board after any move resolves so the
	# visual + the cached hit-rects match the authoritative state (e.g. a Unit killed by
	# Turrets actually disappears instead of lingering with stale "Health 0/1").
	_redraw_all_cells()


## Recruitment mutates cells directly (Deploy adds Units, etc.) WITHOUT an EventBus
## signal, so the board wouldn't otherwise refresh. Redraw after each recruitment so
## newly-deployed Units appear immediately.
func _on_recruitment_resolved(_color: StringName, _summary: Dictionary) -> void:
	_redraw_all_cells()


## Cleanup (heals, clears activations, recomputes Control) runs inside the guardian
## phase without per-cell signals. Refresh the whole board between rounds.
## A Guardian spawned (centre entry, Guardian phase, or env-token). It's on the board
## in data but fires no per-cell redraw, so refresh everything to make it visible.
func _on_guardian_spawned(_guardian, _coord) -> void:
	_redraw_all_cells()


## Old Tech dropped where a Guardian died — refresh so the OT badge appears.
func _on_old_tech_captured(_player, _coord) -> void:
	_redraw_all_cells()


func _on_round_completed(_round_number: int) -> void:
	_redraw_all_cells()


func _redraw_all_cells() -> void:
	for k in GameState.board.keys():
		_redraw_cell_overlay(HexCoord.from_key(k))


func _on_game_over(winner) -> void:
	_my_action_turn = false
	if _hud != null:
		_hud.set_action_bar(false)
	if _hand_panel != null:
		_hand_panel.hide_hand()
	if _win_screen != null:
		_win_screen.show_winner(winner)


# ---------------------------------------------------------------------------
#  Per-cell overlay: greybox units, tokens, Old Tech, coord label
# ---------------------------------------------------------------------------

func _redraw_cell_overlay(coord: HexCoord) -> void:
	var ov: Node2D = _overlays.get(coord.key())
	if ov == null:
		return
	for child in ov.get_children():
		child.queue_free()
	var cell: HexCell = GameState.get_cell(coord)
	if cell == null:
		return

	# Faint coord label (top of hex) — handy while debugging the greybox.
	var clabel := Label.new()
	clabel.text = "%d,%d" % [coord.q, coord.r]
	clabel.add_theme_font_size_override("font_size", 11)
	clabel.modulate = Color(1, 1, 1, 0.35)
	clabel.position = Vector2(-HEX_SIZE * 0.5, -HEX_H * 0.5 + 2)
	ov.add_child(clabel)

	# Units as labelled rectangles, laid out in a small centred grid per cell. We
	# record each unit's local rect so clicks can resolve to an individual unit
	# (for deselect). Staged-to-move units get a bright outline.
	if not _unit_rects.has(coord.key()):
		_unit_rects[coord.key()] = []
	# Flatten all units (with their owner colour) so we can centre the whole grid.
	var flat := []
	for owner in cell.units.keys():
		var col: Color = PLAYER_COLORS.get(owner, Color(0.6, 0.6, 0.6))
		for unit in cell.units[owner]:
			flat.append({"unit": unit, "owner": owner, "col": col})
	var rect_list: Array = []
	var total: int = flat.size()
	for slot in range(total):
		var e = flat[slot]
		var staged := _is_unit_staged(coord, e["unit"])
		var r := _add_unit_rect(ov, e["col"], _unit_label(e["unit"]), slot, total, staged)
		rect_list.append({"unit": e["unit"], "owner": e["owner"], "rect": r})
	_unit_rects[coord.key()] = rect_list

	# Count badge: how many units here are staged to move into the activated space.
	var staged_here := _staged_count_from(coord)
	if staged_here > 0:
		var badge := Label.new()
		badge.text = "%d→" % staged_here
		badge.add_theme_font_size_override("font_size", 13)
		badge.modulate = COL_STAGED
		badge.position = Vector2(HEX_SIZE * 0.30, -HEX_H * 0.5 + 2)
		ov.add_child(badge)

	# Old Tech count — a styled gold pill at the TOP-CENTRE of the hex, clear of the
	# unit stack (centre) and the token chips / name labels (lower-left). High contrast
	# so the objective tokens are obvious.
	if cell.old_tech > 0:
		var ot := Label.new()
		ot.text = "★ OT×%d" % cell.old_tech
		ot.add_theme_font_size_override("font_size", 14)
		ot.modulate = Color(0.10, 0.10, 0.06)
		var otsb := StyleBoxFlat.new()
		otsb.bg_color = Color(0.95, 0.82, 0.30, 0.97)
		otsb.set_corner_radius_all(8)
		otsb.content_margin_left = 7
		otsb.content_margin_right = 7
		otsb.content_margin_top = 1
		otsb.content_margin_bottom = 1
		ot.add_theme_stylebox_override("normal", otsb)
		ot.position = Vector2(-22, -HEX_H * 0.5 + 6)
		ov.add_child(ot)

	# Environment / Function tokens. Face-DOWN: a generic "?" chip tinted by kind so
	# you can see a space has an unexplored token. Face-UP: the effect's short name.
	_token_rects[coord.key()] = []
	var tok_i := 0
	for t in cell.tokens:
		var kind: String = t.get("kind", "")
		if kind != "env" and kind != "func":
			continue
		var face_up: bool = t.get("face_up", false)
		var data = t.get("data")
		var chip := Label.new()
		chip.add_theme_font_size_override("font_size", 11)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 5
		sb.content_margin_right = 5
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		if face_up:
			chip.text = _token_short_name(data)
			sb.bg_color = Color(0.12, 0.13, 0.16, 0.92)
			chip.modulate = _token_kind_color(kind, data)
		else:
			chip.text = "?"
			sb.bg_color = _token_kind_color(kind, data)
			sb.bg_color.a = 0.85
			chip.modulate = Color(1, 1, 1, 0.95)
		chip.add_theme_stylebox_override("normal", sb)
		var chip_pos := Vector2(-HEX_SIZE * 0.5 + 4, HEX_H * 0.5 - 20 - tok_i * 16)
		chip.position = chip_pos
		ov.add_child(chip)
		# Record an overlay-local hit-rect so hover can show the effect text (a bit
		# wider than the glyph so it's easy to land on).
		_token_rects[coord.key()].append({
			"data": t.get("data"),
			"face_up": t.get("face_up", false),
			"kind": kind,
			"rect": Rect2(chip_pos, Vector2(76, 18)),
		})
		tok_i += 1

	# Sticky Bomb markers (card-placed): a small bomb badge tinted by the placer.
	for t in cell.tokens:
		if t.get("kind", "") == "sticky_bomb":
			var owner_col: Color = PLAYER_COLORS.get(t.get("owner", &""), Color(0.9, 0.6, 0.2))
			var bomb := Label.new()
			bomb.text = "✸ BOMB"
			bomb.add_theme_font_size_override("font_size", 12)
			bomb.modulate = owner_col
			bomb.position = Vector2(-22, -HEX_H * 0.5 + 30)
			ov.add_child(bomb)

	# Activation / Control token markers per owner.
	_draw_token_markers(ov, cell)


## Tint for an env/func token chip: blue = corridor env, orange = room env,
## yellow = function (matching the physical token colours).
func _token_kind_color(kind: String, data) -> Color:
	if kind == "func":
		return Color(0.92, 0.86, 0.30)
	var category := ""
	if data != null and "category" in data:
		category = str(data.category)
	if category == "Corridor":
		return Color(0.36, 0.62, 0.95)
	return Color(0.95, 0.62, 0.28)


## Short label for a face-up token (the effect's display name, trimmed).
func _token_short_name(data) -> String:
	if data == null:
		return "?"
	var nm := ""
	if "display_name" in data and str(data.display_name) != "":
		nm = str(data.display_name)
	elif "effect_id" in data:
		nm = str(data.effect_id).trim_prefix("env_").trim_prefix("func_").capitalize()
	if nm.length() > 14:
		nm = nm.substr(0, 13) + "…"
	return nm


## Draws one unit token (centred grid). Returns its Rect2 (overlay-local) for
## click hit-testing. `slot` is the unit's index, `total` the count in the cell.
func _add_unit_rect(ov: Node2D, col: Color, label_text: String, slot: int, total: int, staged: bool) -> Rect2:
	var w := 26.0
	var h := 18.0
	var gap := 3.0
	var per_row := 3
	var rows: int = int(ceil(float(total) / float(per_row)))
	var row: int = slot / per_row
	# How many tokens are on THIS row (last row may be short) — used to centre it.
	var in_this_row: int = per_row
	if row == rows - 1:
		var rem: int = total % per_row
		in_this_row = rem if rem != 0 else per_row
	var col_in_row: int = slot % per_row
	# Centre the row horizontally and the rows block vertically around (0,0).
	var row_w := float(in_this_row) * w + float(in_this_row - 1) * gap
	var cx := -row_w * 0.5 + float(col_in_row) * (w + gap)
	var block_h := float(rows) * h + float(rows - 1) * gap
	var cy := -block_h * 0.5 + float(row) * (h + gap)
	var pos := Vector2(cx, cy)

	var rect := ColorRect.new()
	rect.color = col
	rect.size = Vector2(w, h)
	rect.position = pos
	ov.add_child(rect)

	# Bright outline when this unit is staged to move.
	if staged:
		var outline := Line2D.new()
		outline.width = 2.5
		outline.default_color = COL_STAGED
		outline.closed = true
		outline.add_point(pos)
		outline.add_point(pos + Vector2(w, 0))
		outline.add_point(pos + Vector2(w, h))
		outline.add_point(pos + Vector2(0, h))
		ov.add_child(outline)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.modulate = Color(0, 0, 0, 0.9)
	lbl.position = pos + Vector2(2, 1)
	ov.add_child(lbl)

	return Rect2(pos, Vector2(w, h))


func _draw_token_markers(ov: Node2D, cell: HexCell) -> void:
	var i := 0
	for owner in cell.token_state.keys():
		var st: int = cell.get_token_state(owner)
		if st == HexCell.TokenState.NONE:
			continue
		var marker := Polygon2D.new()
		var col: Color = PLAYER_COLORS.get(owner, Color.WHITE)
		# Diamond = control (face-down), filled triangle = activation (face-up).
		if st == HexCell.TokenState.ACTIVE:
			marker.color = col
			marker.polygon = PackedVector2Array([
				Vector2(0, -7), Vector2(7, 6), Vector2(-7, 6)])
		else:
			marker.color = Color(col.r, col.g, col.b, 0.5)
			marker.polygon = PackedVector2Array([
				Vector2(0, -6), Vector2(6, 0), Vector2(0, 6), Vector2(-6, 0)])
		marker.position = Vector2(-HEX_SIZE * 0.55 + float(i) * 10.0, -HEX_H * 0.5 + 14)
		ov.add_child(marker)
		i += 1


func _unit_label(unit) -> String:
	# Units on cells are dicts {data: UnitData, damage}. Guardians may be bare
	# resources under the &"guardian" owner. Handle both.
	var data = unit.get("data") if unit is Dictionary else unit
	if data != null and data is Resource and "display_name" in data \
			and str(data.display_name) != "":
		return str(data.display_name).substr(0, 3)
	return "U"


# ---------------------------------------------------------------------------
#  Input -> intent -> ActionResolver -> EventBus -> redraw  (one direction)
# ---------------------------------------------------------------------------

## Keyboard panning: arrow keys / WASD nudge the board each frame.
func _process(delta: float) -> void:
	if _revealing:
		return
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		dir.y += 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		dir.y -= 1.0
	if dir != Vector2.ZERO:
		_pan += dir * _key_pan_speed * delta
		_apply_view()


## Hover tooltips: on mouse motion, show the stats of the unit under the cursor.
## Runs in _input (before GUI) but never consumes the event.
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion):
		return
	if _hud == null or _revealing:
		return
	var gp := get_global_mouse_position()
	var coord: HexCoord = _pixel_to_hex(gp)
	if coord == null or GameState.get_cell(coord) == null:
		_hud.hide_tooltip()
		return
	var unit = _unit_at_point(coord, gp)
	if unit != null:
		_hud.show_tooltip(_unit_tooltip_text(coord, unit), event.position)
		return
	# Not over a unit — maybe over an Environment/Function token chip. Show its effect.
	var tok = _token_at_point(coord, gp)
	if tok != null:
		_hud.show_tooltip(_token_tooltip_text(tok), event.position)
		return
	_hud.hide_tooltip()


## Token chip under a global point, in cell `coord`, or null. Same overlay-local basis
## as _unit_at_point so the rects line up with what was drawn.
func _token_at_point(coord: HexCoord, global_pos: Vector2):
	var entries: Array = _token_rects.get(coord.key(), [])
	if entries.is_empty():
		return null
	var sx: float = scale.x if scale.x != 0.0 else 1.0
	var sy: float = scale.y if scale.y != 0.0 else 1.0
	var board_local := Vector2((global_pos.x - position.x) / sx, (global_pos.y - position.y) / sy)
	var local := board_local - _hex_to_pixel(coord.q, coord.r)
	for e in entries:
		var r: Rect2 = e["rect"]
		if r.grow(TOKEN_HIT_PAD).has_point(local):
			return e
	return null


## Tooltip text for a token chip entry {data, face_up, kind}. Face-up shows the full
## rules text; face-down stays a mystery ("Unexplored …").
func _token_tooltip_text(tok: Dictionary) -> String:
	var data = tok.get("data")
	var kind: String = tok.get("kind", "")
	var label := "Function" if kind == "func" else "Environment"
	if not tok.get("face_up", false):
		return "Unexplored %s token\n(move a Unit here to reveal it)" % label
	if data == null:
		return label
	var nm := str(data.display_name) if "display_name" in data and str(data.display_name) != "" else label
	var body := str(data.text) if "text" in data and str(data.text) != "" else ""
	return "%s — %s\n%s" % [label, nm, body] if body != "" else "%s — %s" % [label, nm]


## Build the stat block for a unit dict {data, damage} sitting on `coord`.
func _unit_tooltip_text(coord: HexCoord, unit) -> String:
	var data = unit.get("data") if unit is Dictionary else unit
	if data == null:
		return "Unit"
	var dmg: int = int(unit.get("damage", 0)) if unit is Dictionary else 0
	var name_s := str(data.display_name) if "display_name" in data else "Unit"
	var mv: int = int(data.move) if "move" in data else 1
	var atk: int = int(data.attack) if "attack" in data else 1
	var base_def: int = int(data.defense) if "defense" in data else 1
	var eff_def: int = _effective_defense_for(coord, unit)
	# Health = how many more hits this Unit can take before dying = effective Defense
	# minus damage already on it. Effective Defense shifts with board control / buffs,
	# so Health moves with it. A Unit dies when damage reaches its effective Defense.
	var hp: int = int(max(eff_def - dmg, 0))
	return "%s\nMove %d   Attack %d   Defense %d\nHealth %d/%d" \
		% [name_s, mv, atk, eff_def, hp, eff_def]


## Effective Defense of a unit here = base + controlled-ground/drone (+1, capped) +
## stacking round buffs (Defensive Stance), mirroring the combat resolver's rule.
func _effective_defense_for(coord: HexCoord, unit) -> int:
	var data = unit.get("data") if unit is Dictionary else unit
	if data == null:
		return 1
	var base_def: int = int(data.defense) if "defense" in data else 1
	var bonus := 0
	var cell: HexCell = GameState.get_cell(coord)
	# Owner of this unit (search the cell's owners for the one holding this dict).
	var owner := &""
	if cell != null:
		for o in cell.units.keys():
			for u in cell.units[o]:
				if is_same(u, unit):
					owner = o
					break
	# Controlled-ground +1 (the resolver caps drones+control at +1 ground bonus).
	if owner != &"" and cell != null and cell.get_token_state(owner) == HexCell.TokenState.CONTROL:
		bonus += 1
	# Stacking round buff (Defensive Stance).
	if owner != &"" and GameState.has_method("extra_defense_for"):
		bonus += GameState.extra_defense_for(owner)
	return base_def + bonus


func _unhandled_input(event: InputEvent) -> void:
	if _revealing:
		return
	# --- Zoom (scroll wheel), always available ---
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(get_global_mouse_position(), _zoom_step)
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(get_global_mouse_position(), 1.0 / _zoom_step)
			return
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = true
			_pan_last = event.position
			return

	# --- Middle-drag pan ---
	if event is InputEventMouseButton and not event.pressed \
			and event.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = false
		return

	# --- Left-press: remember start, may become a drag-pan ---
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_lmb_down = true
		_lmb_dragged = false
		_pan_last = event.position
		_lmb_start = event.position
		# fall through: actual click handled on RELEASE (so a drag doesn't also click)
		return

	# --- Motion while a button is held -> pan ---
	if event is InputEventMouseMotion and (_panning or _lmb_down):
		var delta: Vector2 = event.position - _pan_last
		if _lmb_down and not _lmb_dragged:
			# Only start panning once the cursor moves past a small threshold, so a
			# normal click isn't mistaken for a drag.
			if event.position.distance_to(_lmb_start) > 6.0:
				_lmb_dragged = true
		if _panning or _lmb_dragged:
			_pan += delta
			_pan_last = event.position
			_apply_view()
		return

	# --- Left-release: if it wasn't a drag, perform the board click ---
	if event is InputEventMouseButton and not event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var was_drag := _lmb_dragged
		_lmb_down = false
		_lmb_dragged = false
		if was_drag:
			return   # it was a pan, not a click
		# Map-peek: while viewing the board during Recruitment, ANY click (that isn't a
		# pan) ends the peek and restores the recruitment panel. The board state is
		# unchanged — this is a look-only mode.
		if _map_peeking:
			_end_map_peek()
			return
		# A pending on-board card target (Deploy Unit, Sticky Bomb, etc.) accepts a
		# board click in ANY phase the card was legally played in — including
		# Recruitment — so long as the device isn't behind a hand-off cover. This is
		# checked BEFORE the Action-turn gate so recruitment-phase cards resolve at
		# play time, not at the start of the next phase.
		var targeting_card := _pending_card != null and _pending_card_need == "controlled_space"
		if _controller_match_active() and _handoff_blocking:
			return
		# Outside card-targeting, the board only accepts clicks during the active
		# human's ACTION turn (not recruitment or AI turns).
		if _controller_match_active() and not targeting_card and not _my_action_turn:
			return
		var coord: HexCoord = _pixel_to_hex(event.position)
		if coord == null or GameState.get_cell(coord) == null:
			return
		# Card targeting takes priority over the normal Activate flow.
		if targeting_card:
			if not GameState.player_controls(_active_human, coord):
				_hud.set_action_hint("Pick a space you CONTROL (highlighted), or right-click to cancel.")
				return
			# Deploy Unit (action_03) also needs WHICH Unit — pick it now, then deploy.
			if _pending_card.effect_id == &"action_03":
				_show_supply_unit_picker(coord)
			else:
				_resolve_card_with_target(coord)
			return
		_on_hex_clicked(coord)
		return

	# --- Right-click: cancel a pending card target / selection ---
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_RIGHT:
		if _pending_card != null:
			_abort_card_target("Card cancelled.")
			return
		if not _my_action_turn:
			return
		var had_selection := _selected_activate != null
		_cancel_selection()
		if _hud != null:
			if had_selection:
				_hud.set_action_hint("Cancelled. Tap a space to Activate it, or Pass.")
			else:
				_hud.set_action_hint("Tap a space to Activate it, then move Units in. Or Pass.")


## Pixel -> nearest axial hex by rounding cube coords (Red Blob Games).
func _pixel_to_hex(global_pos: Vector2) -> HexCoord:
	# Undo the node transform (position AND scale) to get board-local pixels.
	var sx: float = scale.x if scale.x != 0.0 else 1.0
	var sy: float = scale.y if scale.y != 0.0 else 1.0
	var local := Vector2((global_pos.x - position.x) / sx, (global_pos.y - position.y) / sy)
	var q := (2.0 / 3.0 * local.x) / HEX_SIZE
	var r := (-1.0 / 3.0 * local.x + sqrt(3.0) / 3.0 * local.y) / HEX_SIZE
	return _cube_round(q, r)


func _cube_round(qf: float, rf: float) -> HexCoord:
	var sf := -qf - rf
	var rq := roundf(qf)
	var rr := roundf(rf)
	var rs := roundf(sf)
	var dq := absf(rq - qf)
	var dr := absf(rr - rf)
	var ds := absf(rs - sf)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return HexCoord.new(int(rq), int(rr))


func _on_hex_clicked(coord: HexCoord) -> void:
	if _selected_activate == null:
		_begin_activation(coord)
		return

	# Mid-action. A staged unit token is drawn near its cell's centre but can sit
	# physically closer to a NEIGHBOUR's centre, so the rounded-hex `coord` is
	# unreliable for token hits. Scan every staged source cell for a token under
	# the actual click point first; if one is hit, deselect just that unit.
	var global_pos := get_global_mouse_position()
	var hit_info := _staged_token_at_point(global_pos)
	if not hit_info.is_empty():
		_unstage_unit(hit_info["coord"], hit_info["unit"])
		return

	# Otherwise cell-level behaviour, keyed off the rounded hex.
	if coord.equals(_selected_activate):
		_commit_action()
	elif _reachable_keys.has(coord.key()):
		_stage_all_from(coord)
	else:
		_set_status("%s can't reach the activated space. Click a highlighted space, the activation space to confirm, or right-click to cancel." % coord)


func _begin_activation(coord: HexCoord) -> void:
	var cell: HexCell = GameState.get_cell(coord)
	if cell == null:
		return
	if cell.has_faceup_activation(_human_color):
		_set_status("Already activated there. Pick another space.")
		return
	_selected_activate = coord
	_staged_moves.clear()
	# Units already standing on the activated space are auto-included (they don't
	# move, but they take part in the action / combat there).
	for unit in cell.units_for(_human_color):
		_staged_moves.append({"from": coord, "unit": unit})
	_compute_and_show_reachable(coord)
	_set_status("Activated. Tap a highlighted space to pull its Units in; tap the space again to confirm. Right-click cancels.")


## Highlight every space from which one of the human's units could legally
## reach the activation target. The logic layer answers; we only tint.
func _compute_and_show_reachable(activate: HexCoord) -> void:
	_clear_hilites()
	_reachable_keys.clear()
	for k in GameState.board.keys():
		var src: HexCoord = HexCoord.from_key(k)
		if src.equals(activate):
			continue
		var cell: HexCell = GameState.get_cell(src)
		if cell == null:
			continue
		# You cannot move Units OUT of a space you have face-up activated, so such a
		# space must not be offered as a pull source (the engine rejects it anyway).
		if cell.has_faceup_activation(_human_color):
			continue
		var units: Array = cell.units_for(_human_color)
		if units.is_empty():
			continue
		# This source contributes if ANY of its units can reach the target.
		var can_reach := false
		for unit in units:
			if _unit_can_reach(_human_color, src, unit, activate):
				can_reach = true
				break
		if can_reach:
			_reachable_keys[k] = true
			_add_hilite(src)


func _unit_can_reach(color: StringName, from: HexCoord, unit, dest: HexCoord) -> bool:
	# A "unit" on a cell is the dict {data: UnitData, damage: int}. GameState's
	# reachable_for wants the bare UnitData, so unwrap .data here.
	var data = unit.get("data") if unit is Dictionary else unit
	var reachable: Array = GameState.reachable_for(color, from, data)
	for h in reachable:
		if h is HexCoord and h.equals(dest):
			return true
	return false


# --- Staging model: clicking a source stages ALL its reachable units; click an
#     individual staged unit token to drop just that one. ---

func _stage_all_from(coord: HexCoord) -> void:
	var cell: HexCell = GameState.get_cell(coord)
	if cell == null:
		return
	var units: Array = cell.units_for(_human_color)
	if units.is_empty():
		return
	var added := 0
	for unit in units:
		if _is_unit_staged(coord, unit):
			continue
		if _unit_can_reach(_human_color, coord, unit, _selected_activate):
			_staged_moves.append({"from": coord, "unit": unit})
			added += 1
	_redraw_cell_overlay(coord)   # show outlines + count badge
	var total := _staged_count_from(coord)
	if added == 0:
		_set_status("All %d reachable unit(s) from %s already staged. Tap a highlighted token to drop it, or click the activation space to confirm." % [total, coord])
	else:
		_set_status("Staged all %d unit(s) from %s. Tap a highlighted token to drop one, or click the activation space to confirm." % [total, coord])


func _unstage_unit(coord: HexCoord, unit) -> void:
	for i in range(_staged_moves.size() - 1, -1, -1):
		var m = _staged_moves[i]
		if m.get("from") != null and m["from"].equals(coord) and is_same(m["unit"], unit):
			_staged_moves.remove_at(i)
			break
	_redraw_cell_overlay(coord)
	_set_status("Dropped a unit from %s (%d still staged there). Click activation space to confirm." \
		% [coord, _staged_count_from(coord)])


func _is_unit_staged(coord: HexCoord, unit) -> bool:
	# IMPORTANT: compare unit dicts by OBJECT IDENTITY (is_same), not ==. Two
	# identical Units (e.g. two freshly-deployed Warriors) are dicts with equal
	# CONTENTS, so == treats them as the same entry — which caused the second
	# Warrior to be seen as "already staged" and silently skipped, so only one ever
	# moved. is_same() distinguishes the two distinct dict instances.
	for m in _staged_moves:
		if m.get("from") != null and m["from"].equals(coord) and is_same(m["unit"], unit):
			return true
	return false


func _staged_count_from(coord: HexCoord) -> int:
	# Count staged units that ACTUALLY move (i.e. not the auto-included units that
	# are already standing on the activation space).
	var n := 0
	for m in _staged_moves:
		var from_c = m.get("from")
		if from_c != null and from_c.equals(coord) \
				and not from_c.equals(_selected_activate):
			n += 1
	return n


## Which unit (if any) sits under a global click point, within cell `coord`.
## The stored rects are in OVERLAY-LOCAL space (offsets from the hex centre).
## We compute the click in that same basis the SAME way _pixel_to_hex does
## (BoardView-local = global - this node's position), then subtract the hex
## centre. Using that explicit chain avoids any to_local() transform mismatch.
func _unit_at_point(coord: HexCoord, global_pos: Vector2):
	var entries: Array = _unit_rects.get(coord.key(), [])
	if entries.is_empty():
		return null
	# Undo position AND scale to reach board-local pixels (overlay rects are stored
	# unscaled, in board space).
	var sx: float = scale.x if scale.x != 0.0 else 1.0
	var sy: float = scale.y if scale.y != 0.0 else 1.0
	var board_local := Vector2((global_pos.x - position.x) / sx, (global_pos.y - position.y) / sy)
	var hex_center := _hex_to_pixel(coord.q, coord.r)   # overlay origin in that space
	var local := board_local - hex_center               # overlay-local click point
	# Pad the hit-rect so deselect taps are forgiving (tokens are small and sit
	# near cell borders). grow() expands the rect on all sides.
	for e in entries:
		var r: Rect2 = e["rect"]
		if r.grow(TOKEN_HIT_PAD).has_point(local):
			return e["unit"]
	return null


## Scan every cell that currently has staged-to-move units for a unit token
## under `global_pos`. Independent of hex rounding, so a token drawn near a cell
## border is still hittable. Returns {coord, unit} or {} if nothing hit.
func _staged_token_at_point(global_pos: Vector2) -> Dictionary:
	# Collect the distinct source coords that have staged movers.
	var seen := {}
	for m in _staged_moves:
		var from_c = m.get("from")
		if from_c == null or from_c.equals(_selected_activate):
			continue   # units on the activation space don't move / can't deselect
		seen[from_c.key()] = from_c
	for k in seen.keys():
		var coord: HexCoord = seen[k]
		var hit = _unit_at_point(coord, global_pos)
		if hit != null and _is_unit_staged(coord, hit):
			return {"coord": coord, "unit": hit}
	return {}


func _commit_action() -> void:
	if _selected_activate == null:
		return
	# Old Tech carry choice: if any staged unit is leaving a space this player CONTROLS
	# that holds Old Tech, let the player pick WHICH units carry a token out (one each),
	# capped by the Old Tech available at each source. If there's nothing to choose, this
	# returns immediately and we commit with auto-carry.
	var eligible := _carry_eligible_units()
	if not eligible.is_empty():
		_prompt_old_tech_carriers(eligible)
		return
	_finish_commit([])


## Build the move intent (with optional explicit `carriers`) and submit/resolve it.
func _finish_commit(carriers: Array) -> void:
	if _selected_activate == null:
		return
	var intent := {
		"type": "move_attack",
		"activate": _selected_activate,
		"moves": _staged_moves.duplicate(),
		"carry_old_tech": true,
	}
	if not carriers.is_empty():
		intent["carriers"] = carriers
	if _controller_match_active():
		# Just submit the move. If it lands in combat, the controller defers and runs
		# the INTERACTIVE per-round combat (Fix H), prompting for an Attack card each
		# round via _combat_round_provider — no pre-combat window needed.
		_submit_action_intent(intent)
		return
	# Standalone demo fallback (no controller): resolve directly, as in Section E.
	var result: Dictionary = ActionResolver.resolve_move_attack(GameState, _human_color, intent)
	if not result.get("ok", false):
		_set_status("Illegal: %s" % result.get("reason", "?"))
		return
	var log: Array = result.get("combat_log", [])
	if not log.is_empty():
		_set_status("Move resolved with combat (%d events). See readout." % log.size())
	else:
		_set_status("Move resolved. Activate another space, or pass.")
	_cancel_selection()


## Staged units that COULD carry an Old Tech token out: their source space is one the
## player Controls and it has Old Tech. Returns [{unit, from, name}]. (We don't cap by
## OT count here — the picker enforces the cap per source at confirm time.)
func _carry_eligible_units() -> Array:
	var out := []
	for m in _staged_moves:
		var from_c = m.get("from")
		if from_c == null or from_c.equals(_selected_activate):
			continue   # units already on the activation space don't "leave"
		var cell: HexCell = GameState.get_cell(from_c)
		if cell == null or cell.old_tech <= 0:
			continue
		if not GameState.player_controls(_human_color, from_c):
			continue
		out.append({"unit": m["unit"], "from": from_c, "name": _unit_label(m["unit"])})
	return out


## Modal: a checklist of eligible units; the player ticks which ones carry an Old Tech
## token out. Capped per source space by that space's Old Tech count. Confirm builds the
## carriers list and calls _finish_commit.
func _prompt_old_tech_carriers(eligible: Array) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.08, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-260, -200)
	panel.custom_minimum_size = Vector2(520, 400)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.13, 0.17, 1.0)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var title := Label.new()
	title.text = "Carry Old Tech?"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := Label.new()
	sub.text = "Tick the Units that should carry an Old Tech token out (one each)."
	sub.add_theme_font_size_override("font_size", 15)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.modulate = Color(1, 1, 1, 0.8)
	col.add_child(sub)
	var checks := []   # [{box: CheckBox, entry}]
	for e in eligible:
		var cb := CheckBox.new()
		cb.text = "%s  (from %s)" % [str(e["name"]), str(e["from"])]
		cb.add_theme_font_size_override("font_size", 18)
		col.add_child(cb)
		checks.append({"box": cb, "entry": e})
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	var confirm := Button.new()
	confirm.text = "CONFIRM"
	confirm.custom_minimum_size = Vector2(200, 50)
	confirm.add_theme_font_size_override("font_size", 20)
	var none_btn := Button.new()
	none_btn.text = "CARRY NONE"
	none_btn.custom_minimum_size = Vector2(180, 50)
	none_btn.add_theme_font_size_override("font_size", 18)
	row.add_child(confirm)
	row.add_child(none_btn)
	col.add_child(row)

	var close_and := func(carriers: Array):
		layer.queue_free()
		_finish_commit(carriers)
	confirm.pressed.connect(func():
		# Build carriers, capping per source space by its Old Tech count.
		var picked := []
		var used := {}   # source key -> count taken
		for c in checks:
			if not c["box"].button_pressed:
				continue
			var fk: String = c["entry"]["from"].key()
			var cell: HexCell = GameState.get_cell(c["entry"]["from"])
			var cap: int = cell.old_tech if cell != null else 0
			if int(used.get(fk, 0)) < cap:
				picked.append(c["entry"]["unit"])
				used[fk] = int(used.get(fk, 0)) + 1
		close_and.call(picked))
	none_btn.pressed.connect(func(): close_and.call([]))


# ---------------------------------------------------------------------------
#  Fix H — per-round combat card window
# ---------------------------------------------------------------------------

var _combat_pick_result: Dictionary = {}
var _combat_pick_done: bool = false


## Called by GameController BEFORE each combat round. For each HUMAN side in the
## fight that holds ATTACK cards, raise a window letting them play ONE card this
## round, then return the merged round modifiers
## { extra_defense:{side->int}, reroll_misses:{side->int}, extra_rounds:int, cancel_round:bool }.
func _combat_round_provider(round_index: int, sides: Array, _combatants, coord) -> Dictionary:
	var mods := {"extra_defense": {}, "reroll_misses": {}, "extra_rounds": 0, "cancel_round": false}
	for side in sides:
		if not (side in human_colors_list()):
			continue
		var p = GameState.get_player(side)
		if p == null:
			continue
		var cards := _attack_cards_for(p)
		if cards.is_empty():
			continue
		var chosen = await _ask_combat_card(side, round_index, cards)
		if chosen == null:
			continue   # skipped
		_apply_combat_card_to_mods(side, p, chosen, mods)
	return mods


func human_colors_list() -> Array:
	return GameController.human_colors if _controller_match_active() else []


func _attack_cards_for(p) -> Array:
	var out: Array = []
	for i in range(p.hand.size()):
		var c = p.hand[i]
		if c != null and int(c.card_type) == 2:
			out.append({"card": c, "index": i})
	return out


## Apply a chosen combat card's effect into this round's `mods` and consume it.
func _apply_combat_card_to_mods(side: StringName, p, chosen: Dictionary, mods: Dictionary) -> void:
	var c = chosen["card"]
	match c.effect_id:
		&"action_15":   # Extra Attack
			mods["extra_rounds"] = int(mods["extra_rounds"]) + 1
		&"action_14":   # Cancel Attack — skip this round
			mods["cancel_round"] = true
		&"action_10":   # Re-roll two dice
			var rr: Dictionary = mods["reroll_misses"]
			rr[side] = int(rr.get(side, 0)) + 2
		&"action_13":   # Defensive Stance — +1 def this round
			var ed: Dictionary = mods["extra_defense"]
			ed[side] = int(ed.get(side, 0)) + 1
	# Consume the card by identity.
	for i in range(p.hand.size()):
		if is_same(p.hand[i], c):
			p.hand.remove_at(i)
			break
	GameState.discard_action_card(c)


## Raise a modal for `side` to play ONE attack card this round (or Skip). Awaits the
## tap; returns the chosen {card,index} or null. Resolves via _combat_pick signal.
func _ask_combat_card(side: StringName, round_index: int, cards: Array):
	_combat_pick_done = false
	_combat_pick_result = {}
	var layer := CanvasLayer.new()
	layer.layer = 27
	layer.name = "CombatRoundWindow"
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.08, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.position = Vector2(-280, -240)
	col.add_theme_constant_override("separation", 12)
	layer.add_child(col)
	var title := Label.new()
	title.text = "%s — Combat round %d: play a card?" % [str(side).to_upper(), round_index + 1]
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size = Vector2(560, 0)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	for entry in cards:
		var c = entry["card"]
		var b := Button.new()
		b.text = "%s — %s" % [str(c.card_name), str(c.text)]
		b.custom_minimum_size = Vector2(560, 54)
		b.add_theme_font_size_override("font_size", 15)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.pressed.connect(func():
			layer.queue_free()
			_combat_pick_result = entry
			_combat_pick_done = true)
		col.add_child(b)
	var skip := Button.new()
	skip.text = "SKIP (no card)"
	skip.custom_minimum_size = Vector2(560, 50)
	skip.add_theme_font_size_override("font_size", 18)
	skip.pressed.connect(func():
		layer.queue_free()
		_combat_pick_result = {}
		_combat_pick_done = true)
	col.add_child(skip)
	add_child(layer)
	# Await the tap.
	while not _combat_pick_done:
		await get_tree().process_frame
	if _combat_pick_result.is_empty():
		return null
	return _combat_pick_result


## Interactive hit assignment (#6): ask the human DEFENDER which live Unit absorbs
## this hit. Called by the resolver (via GameController.combat_assign_provider) only
## when there are 2+ valid targets. `targets` is an Array of CombatResolver.Combatant;
## returns the chosen Combatant. Awaits the tap using the same latch as the card modal.
func _combat_assign_provider(targets: Array, defender_side: StringName):
	if targets.is_empty():
		return null
	_combat_pick_done = false
	_combat_pick_result = {}
	var layer := CanvasLayer.new()
	layer.layer = 27
	layer.name = "AssignHitWindow"
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.08, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.position = Vector2(-280, -200)
	col.add_theme_constant_override("separation", 12)
	layer.add_child(col)
	var title := Label.new()
	title.text = "%s — assign the hit to which Unit?" % str(defender_side).to_upper()
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size = Vector2(560, 0)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	for t in targets:
		var uid = t.data.get("id")
		var dmg: int = t.damage()
		var def: int = t.defense()
		var remaining: int = def - dmg
		var b := Button.new()
		b.text = "%s   (%d/%d dmg · %d hit%s left)" % [
			UNIT_DISPLAY.get(uid, str(uid).capitalize()), dmg, def,
			remaining, "" if remaining == 1 else "s"]
		b.custom_minimum_size = Vector2(560, 54)
		b.add_theme_font_size_override("font_size", 16)
		var picked = t
		b.pressed.connect(func():
			layer.queue_free()
			_combat_pick_result = {"combatant": picked}
			_combat_pick_done = true)
		col.add_child(b)
	add_child(layer)
	while not _combat_pick_done:
		await get_tree().process_frame
	return _combat_pick_result.get("combatant", null)


## Ranged SUPPORT FIRE prompt (Ch.11). `eligible` is [{coord,unit}]. The eligible shooter
## spaces glow faintly on the board; a modal lists each as a toggle, with FIRE / NONE.
## Returns the chosen subset of `eligible`. Mirrors the combat-card modal latch pattern.
func _support_fire_provider(color: StringName, combat_coord, eligible: Array) -> Array:
	if eligible.is_empty():
		return []
	# Faint glow on every eligible shooter space.
	for e in eligible:
		if e.get("coord") is HexCoord:
			_add_hilite_colored(e["coord"], COL_SUPPORT)
	var chosen_flags: Array = []
	for _e in eligible:
		chosen_flags.append(false)
	_combat_pick_done = false
	_combat_pick_result = {}
	var layer := CanvasLayer.new()
	layer.layer = 27
	layer.name = "SupportFireWindow"
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.08, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var col_box := VBoxContainer.new()
	col_box.set_anchors_preset(Control.PRESET_CENTER)
	col_box.position = Vector2(-300, -260)
	col_box.add_theme_constant_override("separation", 10)
	layer.add_child(col_box)
	var title := Label.new()
	title.text = "%s — fire with any Ranged Units? This Activates their space." % str(color).to_upper()
	title.add_theme_font_size_override("font_size", 21)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size = Vector2(600, 0)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col_box.add_child(title)
	# One toggle per eligible shooter.
	for i in range(eligible.size()):
		var entry = eligible[i]
		var u = entry["unit"]
		var d = u.get("data")
		var uid = d.id if d != null else &"?"
		var rng_v: int = (d.range if d != null else 0)
		var c: HexCoord = entry["coord"]
		var b := Button.new()
		b.toggle_mode = true
		b.text = "%s  (Range %d)  @ (%d,%d)" % [
			UNIT_DISPLAY.get(uid, str(uid).capitalize()), rng_v, c.q, c.r]
		b.custom_minimum_size = Vector2(600, 48)
		b.add_theme_font_size_override("font_size", 16)
		var idx := i
		b.toggled.connect(func(pressed): chosen_flags[idx] = pressed)
		col_box.add_child(b)
	var fire := Button.new()
	fire.text = "FIRE selected"
	fire.custom_minimum_size = Vector2(600, 50)
	fire.add_theme_font_size_override("font_size", 18)
	fire.pressed.connect(func():
		layer.queue_free()
		_combat_pick_result = {"go": true}
		_combat_pick_done = true)
	col_box.add_child(fire)
	var none := Button.new()
	none.text = "NONE (skip)"
	none.custom_minimum_size = Vector2(600, 46)
	none.add_theme_font_size_override("font_size", 17)
	none.pressed.connect(func():
		layer.queue_free()
		_combat_pick_result = {"go": false}
		_combat_pick_done = true)
	col_box.add_child(none)
	add_child(layer)
	while not _combat_pick_done:
		await get_tree().process_frame
	_clear_hilites()
	var out: Array = []
	if _combat_pick_result.get("go", false):
		for i in range(eligible.size()):
			if chosen_flags[i]:
				out.append(eligible[i])
	return out


## Finalise an action intent: end the turn, hide UI, submit to our HumanAgent
## (the GameController is the single path into the engine).
func _submit_action_intent(intent: Dictionary) -> void:
	_my_action_turn = false
	if _hud != null:
		_hud.set_action_bar(false)
	if _hand_panel != null:
		_hand_panel.hide_hand()
	var agent = GameController.human_agent_for(_active_human)
	if agent != null:
		agent.submit(intent)


## The active human tapped Pass — end their Action turn (submit a pass intent).
func _on_pass_pressed() -> void:
	if not _my_action_turn:
		return
	_my_action_turn = false
	if _hud != null:
		_hud.set_action_bar(false)
	if _hand_panel != null:
		_hand_panel.hide_hand()
	_cancel_selection()
	var agent = GameController.human_agent_for(_active_human)
	if agent != null:
		agent.submit({"type": "pass"})


func _cancel_selection() -> void:
	# Remember which cells carried staged units so we can clear their outlines.
	var dirty := {}
	for m in _staged_moves:
		var from_c = m.get("from")
		if from_c != null:
			dirty[from_c.key()] = from_c
	_selected_activate = null
	_staged_moves.clear()
	_reachable_keys.clear()
	_clear_hilites()
	# Redraw the affected cells now that nothing is staged (drops outlines/badges).
	for k in dirty.keys():
		_redraw_cell_overlay(dirty[k])


# --- highlight overlay helpers ---

func _add_hilite(coord: HexCoord) -> void:
	var poly := Polygon2D.new()
	poly.polygon = _hex_corners()
	poly.color = COL_HILITE
	poly.position = _hex_to_pixel(coord.q, coord.r)
	_hilite_root.add_child(poly)
	_hilites[coord.key()] = poly


func _clear_hilites() -> void:
	for child in _hilite_root.get_children():
		child.queue_free()
	_hilites.clear()


## Like _add_hilite but with an explicit colour (used for the Ranged support-fire glow).
func _add_hilite_colored(coord: HexCoord, col: Color) -> void:
	var poly := Polygon2D.new()
	poly.polygon = _hex_corners()
	poly.color = col
	poly.position = _hex_to_pixel(coord.q, coord.r)
	_hilite_root.add_child(poly)
	_hilites[coord.key()] = poly


# ---------------------------------------------------------------------------
#  EventBus handlers — the ONLY way visuals change after a logic mutation
# ---------------------------------------------------------------------------

func _on_unit_moved(_unit, from_coord, to_coord) -> void:
	if from_coord is HexCoord:
		_redraw_cell_overlay(from_coord)
	if to_coord is HexCoord:
		_redraw_cell_overlay(to_coord)


func _on_token_flipped(coord, _player, _new_state) -> void:
	if coord is HexCoord:
		_redraw_cell_overlay(coord)


func _on_control_changed(coord, _player) -> void:
	if coord is HexCoord:
		_redraw_cell_overlay(coord)


func _on_combat_resolved(event_log) -> void:
	# Refresh every cell so deaths show.
	for k in GameState.board.keys():
		_redraw_cell_overlay(HexCoord.from_key(k))
	# Section F Piece 6: show the plain text/number readout of the resolver's log.
	# (Section G replaces this static list with animated playback.)
	if event_log is Array and not event_log.is_empty() and _combat_readout != null:
		_combat_readout.show_log(event_log)


# ---------------------------------------------------------------------------
#  Demo seeding so the greybox has something to push around (pre-Section-F)
# ---------------------------------------------------------------------------

func _seed_demo_units() -> void:
	# Drop a few real Units near each player's rally zone so a tester can try a
	# Move-and-Attack immediately. Pure presentation convenience — real placement
	# is the Recruitment phase (Section F). Units are stored exactly as the engine
	# expects: dicts {data: UnitData, damage: int}, drawn from the seeded bag and
	# mapped through the unit_db (id -> UnitData) loaded from the .tres files.
	var unit_db := _load_unit_db()
	for color in GameState.rally_zones.keys():
		var rz: HexCoord = GameState.rally_zones[color]
		if rz == null:
			continue
		var p = GameState.get_player(color)
		if p == null:
			continue
		var cell: HexCell = GameState.get_cell(rz)
		if cell == null:
			continue
		# Draw 3 from the seeded bag; Cowards just don't reach the board.
		var drawn: Array = p.draw_from_bag(3, GameState.rng)
		for unit_id in drawn:
			if unit_id == Player.COWARD:
				p.bag.append(unit_id)   # Cowards go back, like Deploy does.
				continue
			var data = unit_db.get(unit_id, null)
			if data == null:
				continue
			cell.add_unit(color, {"data": data, "damage": 0})


## Load every Unit .tres into an id -> UnitData map (the engine's unit_db shape).
func _load_unit_db() -> Dictionary:
	var db := {}
	var dir := DirAccess.open("res://data/units")
	if dir == null:
		return db
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var res = load("res://data/units/" + fname)
			if res != null and "id" in res:
				db[res.id] = res
		fname = dir.get_next()
	dir.list_dir_end()
	return db


# ---------------------------------------------------------------------------
#  Small helpers
# ---------------------------------------------------------------------------

func _set_status(text: String) -> void:
	# Under the controller, the top StatusLabel is retired (it overflowed across the
	# banner) — route all interaction feedback to the action-bar hint instead.
	if _controller_match_active():
		if _hud != null and _my_action_turn and text != "":
			_hud.set_action_hint(text)
		return
	if _status != null:
		_status.text = text


func _bus() -> Node:
	return get_tree().root.get_node_or_null("EventBus")

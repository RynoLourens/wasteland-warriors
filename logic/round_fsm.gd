extends RefCounted
class_name RoundFSM
## The round state machine (Section D, steps 1-2, 7) — the piece that makes
## "the game works headlessly" (Milestone M4).
##
## States cycle Recruitment -> Action -> Guardian -> (repeat) until a victory
## condition fires. Each phase is its own method that decides when it is done and
## hands control back; this beats one giant match statement and keeps each phase
## independently testable.
##
## CRITICAL architecture rules baked in here:
##   * Turn order is driven by GameState.turn_order, NEVER by UI button state.
##   * Every player CHOICE is obtained from that player's Agent (the same intent
##     API the UI and the AI use) — the FSM only validates + applies. No back door.
##   * The FSM is the ONLY thing that advances phases and mutates phase state.
##
## Headless usage:
##   var fsm := RoundFSM.new(game_state, agents_by_color, unit_db, guardian_pool)
##   var result := fsm.play_until_victory(max_rounds)
## `agents_by_color`: { &"green": Agent, ... }. `unit_db`: { &"warrior": UnitData }.
## `guardian_pool`: Array[GuardianData].

const Phase := GameState.Phase
const GUARDIAN_OWNER := &"guardian"
const FACILITY := &"facility"   ## the "Facility wins" tie-break sentinel winner

var state                       ## the live GameState (autoload or a fresh instance)
var agents: Dictionary = {}     ## color -> Agent
var unit_db: Dictionary = {}    ## unit id -> UnitData (for Deploy/Recruit instancing)
var guardians: GuardianManager

var first_player_index: int = 0 ## index into state.turn_order holding the First Player token
var round_number: int = 0
var winner: StringName = &""    ## set when victory fires (&"" while ongoing)


func _init(_state, _agents: Dictionary, _unit_db: Dictionary = {}, guardian_pool: Array = [], guardian_seed: int = 0) -> void:
	state = _state
	agents = _agents
	unit_db = _unit_db
	guardians = GuardianManager.new(guardian_pool, guardian_seed)


# ---------------------------------------------------------------------------
#  Top-level driver
# ---------------------------------------------------------------------------

## Play whole rounds until someone wins (or max_rounds is hit, a safety valve so a
## degenerate scripted test can't loop forever). Returns:
##   {"winner": StringName, "rounds": int, "reason": String}
func play_until_victory(max_rounds: int = 200) -> Dictionary:
	for _r in range(max_rounds):
		round_number += 1
		run_recruitment_phase()
		run_action_phase()
		var v := run_guardian_phase()   # includes the victory check
		if v != &"":
			winner = v
			return {"winner": winner, "rounds": round_number, "reason": "victory"}
	return {"winner": &"", "rounds": round_number, "reason": "max_rounds"}


# ---------------------------------------------------------------------------
#  Phase 1 — Recruitment
# ---------------------------------------------------------------------------

func run_recruitment_phase() -> void:
	state.current_phase = Phase.RECRUITMENT
	_emit("phase_changed", [Phase.RECRUITMENT])
	for color in _turn_order_from_first():
		var p = state.get_player(color)
		if p == null:
			continue
		# 0. Medical Machine: place any Units saved last combat into the Rally Zone for free.
		ArtefactEffects.apply_pending_redeploys(state, color, {"unit_db": unit_db})
		# 1. Draw an Action card (from a shared deck if present; harmless no-op if not).
		_draw_action_card(p)
		# 2. Ask the player's agent what to do.
		var intent: Dictionary = agents[color].decide_recruitment(state, color)
		# 2a. Optional Recruitment card (data-driven; logged, effect applied in F+).
		var card_idx: int = intent.get("play_recruitment_card", -1)
		if card_idx >= 0 and card_idx < p.hand.size():
			p.hand.remove_at(card_idx)
		# 3. Resolve the chosen recruitment action.
		_apply_recruitment_choice(p, color, intent)


func _apply_recruitment_choice(p, color: StringName, intent: Dictionary) -> void:
	match intent.get("choice", "deploy"):
		"deploy":
			var deployed: Array = p.deploy(state.rng)
			_place_deployed_units(p, color, deployed)
		"recruit":
			var ids: Array = intent.get("recruit_ids", [])
			ids = _apply_leader_recruit_passive(p, ids)
			p.recruit(ids)
		"punish":
			p.punish_cowards(state.rng)
		"control_room_spawn":
			# Guardian Control Room FUNCTION (Ch.13): spawn 1 Guardian in a face-up Control
			# Room you Control, instead of the normal Recruitment action.
			_recruit_control_room_spawn(p, color, intent)
		"hub_deploy":
			# Teleporter Hub FUNCTION (Ch.13): Deploy your drawn Units into the Hub space
			# (which you Control) instead of your Rally Zone, and Activate it.
			_recruit_hub_deploy(p, color, intent)
		"artefact_place_special":
			# Ancient Artifact (Ch.13): discard a face-down Artifact to place 1 Special Unit
			# from the supply into a space you Control.
			_recruit_artefact_place_special(p, color, intent)


## Guardian Control Room: spawn 1 Guardian into a face-up `func_guardian_control_room`
## room the player Controls. `intent.room` (HexCoord) names the room.
func _recruit_control_room_spawn(_p, color: StringName, intent: Dictionary) -> bool:
	var room = intent.get("room")
	if not (room is HexCoord):
		return false
	var cell: HexCell = state.get_cell(room)
	if cell == null:
		return false
	if not cell.has_token_effect(&"func_guardian_control_room", true):
		return false
	if not _player_controls(color, room):
		return false
	return guardians.spawn_into_cell(state, room) != null


## Teleporter Hub: Deploy this player's drawn Units into the Hub space (Controlled) and
## Activate it, instead of the Rally Zone. `intent.room` (HexCoord) names the Hub.
func _recruit_hub_deploy(p, color: StringName, intent: Dictionary) -> bool:
	var room = intent.get("room")
	if not (room is HexCoord):
		return false
	var cell: HexCell = state.get_cell(room)
	if cell == null or not cell.has_token_effect(&"func_teleporter_hub", true):
		return false
	if not _player_controls(color, room):
		return false
	var deployed: Array = p.deploy(state.rng)
	for unit_id in deployed:
		var data = unit_db.get(unit_id, null)
		cell.add_unit(color, {"data": data, "damage": 0})
	# Activate the Hub space (rulebook).
	cell.set_token_state(color, HexCell.TokenState.ACTIVE)
	if state.has_method("note_activation"):
		state.note_activation(color, room)
	return true


## Ancient Artifact: discard a face-down Artifact to place one Special Unit (from supply)
## into a Controlled space. `intent.special_id` (StringName) + `intent.space` (HexCoord).
func _recruit_artefact_place_special(p, color: StringName, intent: Dictionary) -> bool:
	var special_id = intent.get("special_id")
	var space = intent.get("space")
	if special_id == null or not (space is HexCoord):
		return false
	if p.artefacts.is_empty():
		return false
	if not _player_controls(color, space):
		return false
	if not (special_id in [&"berserker", &"manstopper", &"infiltrator", &"sapperteur"]):
		return false
	var cell: HexCell = state.get_cell(space)
	var data = unit_db.get(special_id, null)
	if cell == null or data == null:
		return false
	# Discard one face-down Artifact (any) to pay the cost.
	p.artefacts.pop_back()
	cell.add_unit(color, {"data": data, "damage": 0})
	return true


## Control check that tolerates a bare GameState OR a Player-only test double.
func _player_controls(color: StringName, coord: HexCoord) -> bool:
	if state.has_method("player_controls"):
		return state.player_controls(color, coord)
	var p = state.get_player(color)
	return p != null and p.controls(coord)


## Place freshly-deployed Units onto the player's Rally Zone cell as live unit
## dicts {data, damage}. Cowards never reach here (deploy returns them to the bag).
func _place_deployed_units(p, color: StringName, deployed: Array) -> void:
	if p.rally_zone == null:
		return
	var cell: HexCell = state.get_cell(p.rally_zone)
	if cell == null:
		return
	for unit_id in deployed:
		var data = unit_db.get(unit_id, null)
		cell.add_unit(color, {"data": data, "damage": 0})


## Leader passive hook: Lady Seraph recruits 5 Units / 3 Special instead of 3/2.
## We dispatch on the leader's passive_effect_id (flag-driven, no name hardcoding).
func _apply_leader_recruit_passive(p, ids: Array) -> Array:
	if p.leader == null:
		return ids
	# Only the seraph_recruit passive changes counts in v1; others are no-ops here.
	if p.leader.passive_effect_id == &"seraph_recruit_bonus":
		# Caller already chose the ids; the bonus simply permits a larger list, so
		# nothing to truncate. (Validation of list length lives in the UI/AI which
		# know the per-leader cap.) Documented seam for Section F.
		pass
	return ids


# ---------------------------------------------------------------------------
#  Phase 2 — Action (one action per player, in turn order, until all Pass)
# ---------------------------------------------------------------------------

func run_action_phase() -> void:
	state.current_phase = Phase.ACTION
	_emit("phase_changed", [Phase.ACTION])
	var passed := {}            # color -> true once it has Passed
	var order := _turn_order_from_first()
	var safety := 0
	var safety_cap := 1000      # guards against an agent that never passes
	while passed.size() < order.size() and safety < safety_cap:
		for color in order:
			if passed.has(color):
				continue
			var intent: Dictionary = agents[color].decide_action(state, color)
			match intent.get("type", "pass"):
				"pass":
					passed[color] = true
					_emit("turn_passed", [color])
				"card":
					var idx: int = intent.get("hand_index", -1)
					var p = state.get_player(color)
					if p != null and idx >= 0 and idx < p.hand.size():
						p.hand.remove_at(idx)   # Movement-card effect wired in Section F
				"move_attack":
					ActionResolver.resolve_move_attack(state, color, intent)
				"ranged_attack":
					ActionResolver.resolve_ranged_attack(state, color, intent)
				_:
					passed[color] = true
			safety += 1
			if passed.size() >= order.size():
				break


# ---------------------------------------------------------------------------
#  Phase 3 — Guardian (victory check -> spawn/move -> cleanup)
# ---------------------------------------------------------------------------

## Returns the winner color (or FACILITY) if victory fired this phase, else &"".
func run_guardian_phase() -> StringName:
	state.current_phase = Phase.GUARDIAN
	_emit("phase_changed", [Phase.GUARDIAN])

	# Step 1 — Victory check.
	var v := check_victory()
	if v != &"":
		return v

	# Central-Chamber spawn (the locked rule): EVERY Guardian phase spawn 1 in the
	# centre (bag draw, may fizzle), or 2 once the centre has ever been breached.
	var breached: bool = state.center_breached if "center_breached" in state else false
	guardians.spawn_into_center(state, 2 if breached else 1)

	# Step 2 — Move every Guardian (spawn already done above, so do_spawn=false).
	guardians.run_guardian_movement(state, false)

	# Step 3 — Cleanup.
	run_cleanup()

	# A Guardian attack during movement can't grant victory (Old Tech must be in a
	# Rally Zone), so no second victory check is needed here.
	return &""


## Old Tech sitting in a Rally Zone counts toward victory. We tally each player's
## Old Tech in their OWN rally-zone cell (authoritative), not the cached counter,
## so carrying tokens home is what actually wins.
func check_victory() -> StringName:
	var winners := []
	for p in state.players:
		var got := _old_tech_in_rally(p)
		p.old_tech_count = got   # keep the cached counter honest for the UI
		if got >= 3:
			winners.append(p)
	if winners.is_empty():
		return &""
	if winners.size() == 1:
		_emit_victory(winners[0].color)
		return winners[0].color
	# Tie-break 1: fewest Cowards in the bag.
	winners.sort_custom(func(a, b): return a.coward_count() < b.coward_count())
	if winners[0].coward_count() < winners[1].coward_count():
		_emit_victory(winners[0].color)
		return winners[0].color
	# Tie-break 2: still tied -> the Facility wins (everybody loses).
	_emit_victory(FACILITY)
	return FACILITY


func _old_tech_in_rally(p) -> int:
	if p.rally_zone == null:
		return 0
	var cell: HexCell = state.get_cell(p.rally_zone)
	return cell.old_tech if cell != null else 0



# ---------------------------------------------------------------------------
#  Cleanup
# ---------------------------------------------------------------------------

## Cleanup (rulebook Ch.10 step 3):
##   * Remove all face-up Activation tokens.
##   * Remove all Damage tokens (every surviving Unit heals fully).
##   * Place a face-down Control token in each space where a player's Units are the
##     ONLY force present (no enemy Units, no Guardians).
##   * Pass the First Player token clockwise.
func run_cleanup() -> void:
	# 0. Expire round-scoped card buffs (Defensive Stance / Extra Move / Move Through
	#    Enemies) — they last "until the end of the round" (Piece 5b). Also clear any
	#    unspent Extra Recruitment grants.
	if state.has_method("clear_round_buffs"):
		state.clear_round_buffs()
	if state.has_method("clear_extra_recruitment"):
		state.clear_extra_recruitment()

	# 1. Recompute Control from scratch each round: clear last round's first.
	for p in state.players:
		p.control_set.clear()

	# Dehydration (Ch.13): a dehydrated player keeps their LAST Activation token face-up
	# into the next round. Gather those keep-coords (by hexkey) before the board loop so
	# the Activation-removal step can spare them.
	var dehydration_keep: Dictionary = {}   # color -> hexkey to keep ACTIVE
	for p in state.players:
		var col: StringName = p.color
		if state.has_method("dehydration_keep_coord"):
			var keep = state.dehydration_keep_coord(col)
			if keep != null:
				dehydration_keep[col] = keep.key()

	for k in state.board.keys():
		var cell: HexCell = state.board[k]
		var coord := HexCoord.from_key(k)

		# Remove face-up Activation tokens (keep face-down Control; we recompute it).
		# EXCEPTION (Dehydration): leave a dehydrated player's recorded last Activation
		# token face-up — it persists into the next round (Ch.13).
		for owner in cell.token_state.keys():
			if cell.get_token_state(owner) == HexCell.TokenState.ACTIVE:
				if dehydration_keep.get(owner, "") == k:
					continue   # dehydrated: keep this one face-up
				cell.set_token_state(owner, HexCell.TokenState.NONE)

		# Discard spent Environment tokens: a face-up env token that has done its job
		# is removed at the Cleanup AFTER it flipped (so it's visible the round it
		# resolved, then gone). Persistent ones (Darkness / Tough Terrain / Teleporter)
		# and Function tokens stay; sticky bombs are handled by combat, not here.
		var kept_tokens := []
		for t in cell.tokens:
			var kind: String = t.get("kind", "")
			var face_up: bool = t.get("face_up", false)
			if kind == "env" and face_up and not _env_persists(t):
				continue   # discard the spent one-shot environment token
			kept_tokens.append(t)
		cell.tokens = kept_tokens

		# Heal everyone fully.
		for owner in cell.units.keys():
			for u in cell.units[owner]:
				u["damage"] = 0

		# Determine sole occupant (ignoring Control tokens, which don't count as a
		# "force"). A space with Guardians is never controllable.
		var occupants := []
		var has_guardian := false
		for owner in cell.units.keys():
			if cell.units[owner].is_empty():
				continue
			if owner == GUARDIAN_OWNER:
				has_guardian = true
			else:
				occupants.append(owner)
		if not has_guardian and occupants.size() == 1:
			var sole: StringName = occupants[0]
			# If this is the dehydrated player's kept Activation token, leave it ACTIVE —
			# do NOT convert it to Control this round.
			if dehydration_keep.get(sole, "") == k and cell.get_token_state(sole) == HexCell.TokenState.ACTIVE:
				pass
			else:
				cell.set_token_state(sole, HexCell.TokenState.CONTROL)
				var p = state.get_player(sole)
				if p != null:
					p.mark_control(coord)
					_emit("control_changed", [coord, sole])
		else:
			# No sole occupant -> ensure no stale Control token lingers here.
			for owner in cell.token_state.keys().duplicate():
				if cell.get_token_state(owner) == HexCell.TokenState.CONTROL:
					cell.set_token_state(owner, HexCell.TokenState.NONE)

	# 4. Pass the First Player token clockwise (next in turn order).
	if not state.turn_order.is_empty():
		first_player_index = (first_player_index + 1) % state.turn_order.size()

	# 5. Reset Dehydration + last-activation tracking for the new round (the keep, if any,
	#    has now been honoured above).
	if state.has_method("clear_dehydration"):
		state.clear_dehydration()
	# 6. Reset Sunstone Fragments marks (round-scoped Artifact effect).
	if state.has_method("clear_sunstone_marks"):
		state.clear_sunstone_marks()


## True if a flipped Environment token stays in its room (Darkness / Tough Terrain /
## Teleporter Node). These are read by movement/combat each round, so Cleanup keeps
## them; every other env token is a spent one-shot and is discarded.
const PERSISTENT_ENV := [&"env_darkness", &"env_tough_terrain", &"env_teleporter_node"]

func _env_persists(token: Dictionary) -> bool:
	var data = token.get("data")
	if data == null:
		return false
	# Prefer the explicit schema flag if present; fall back to the id list.
	if "persists_in_room" in data and bool(data.persists_in_room):
		return true
	return data.get("effect_id") in PERSISTENT_ENV


# ---------------------------------------------------------------------------
#  Turn-order helpers
# ---------------------------------------------------------------------------

## turn_order rotated so it starts at the current First Player. ALWAYS the source
## of truth for who acts when — never UI state.
func _turn_order_from_first() -> Array:
	var order: Array = state.turn_order
	if order.is_empty():
		return []
	var out := []
	for i in range(order.size()):
		out.append(order[(first_player_index + i) % order.size()])
	return out


# ---------------------------------------------------------------------------
#  Misc
# ---------------------------------------------------------------------------

## Draw one Action card into the player's hand from a shared deck if GameState
## exposes one; otherwise a harmless no-op (headless rules tests don't need cards).
func _draw_action_card(p) -> void:
	if state.has_method("draw_action_card"):
		var card = state.draw_action_card()
		if card != null:
			p.hand.append(card)


func _emit_victory(color: StringName) -> void:
	# Reuse turn_passed as a generic "game over" notice would be wrong; victory has
	# no dedicated signal in the v1 EventBus, so the FSM just records the winner and
	# the driver returns it. (Section F adds a game_over screen reading fsm.winner.)
	winner = color


func _emit(signal_name: String, args: Array) -> void:
	var bus = null
	if state != null and state.has_method("get_tree") and state.get_tree() != null:
		bus = state.get_tree().root.get_node_or_null("EventBus")
	if bus == null:
		return
	match args.size():
		0: bus.emit_signal(signal_name)
		1: bus.emit_signal(signal_name, args[0])
		2: bus.emit_signal(signal_name, args[0], args[1])
		3: bus.emit_signal(signal_name, args[0], args[1], args[2])

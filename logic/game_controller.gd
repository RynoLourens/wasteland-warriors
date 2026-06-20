extends Node
## Section F — the interactive round driver.
##
## NOTE: registered as the `GameController` AUTOLOAD in project.godot, so it must
## NOT also declare `class_name GameController` (the singleton name and a global
## class of the same name collide — "hides an autoload singleton"). Reach it
## everywhere via the autoload global `GameController`.
##
## The headless RoundFSM (Section D) runs a whole game in one blocking call, which
## is perfect for GUT but useless for a UI: a human seat must PAUSE the flow until a
## tap arrives. GameController is the interactive counterpart. It runs the exact same
## phase order (Recruitment -> Action -> Guardian/Cleanup) as a COROUTINE, awaiting
## the HumanAgent on human seats and resolving PassAgent (AI) seats instantly.
##
## It is deliberately thin: every rule still lives in the logic layer. Recruitment
## mechanics are Player methods; movement/combat go through ActionResolver; Guardian
## movement, cleanup, and the victory check are delegated to an internal RoundFSM
## instance so that tested code stays the single source of truth. The controller
## only sequences phases and routes agent intents — it owns NO rules.
##
## Signals let the UI raise the right panel and banners without the controller
## knowing anything about scenes.

signal match_started(turn_order)
signal phase_changed(phase)              ## GameState.Phase value
signal seat_turn_began(color, phase)     ## a seat is about to act (human or AI)
signal seat_passed(color)                ## a seat passed (ended its Action phase)
signal pass_state_reset()                ## new round (Recruitment) — clear passed markers
signal recruitment_resolved(color, summary)
signal action_resolved(color, result)    ## result dict from ActionResolver (has combat_log)
signal round_completed(round_number)
signal game_over(winner)                 ## StringName color, or RoundFSM.FACILITY

const Phase := GameState.Phase
const GUARDIAN_OWNER := &"guardian"

var state                                ## the live GameState (autoload)
var agents: Dictionary = {}              ## color -> Agent (HumanAgent or PassAgent)
var unit_db: Dictionary = {}             ## unit id -> UnitData
var human_colors: Array = []             ## colors driven by a HumanAgent (for hand-off)

var _fsm: RoundFSM                        ## internal: cleanup / guardian / victory mechanics
var _guardian_pool: Array = []           ## static GuardianData list (for env-Guardian spawns)
var _artefact_deck: Array = []           ## ArtefactData pool drawn by Artifact tokens/functions
var _running := false
var winner: StringName = &""

## The UI sets this (BoardView) to provide each combat ROUND's human card plays.
## Signature: func(round_index:int, sides:Array, combatants:Dictionary, coord) -> Dictionary
## returning { extra_defense, reroll_misses, extra_rounds, cancel_round }. If unset,
## combat runs with no card input (the round_provider returns {}).
var combat_round_provider: Callable = Callable()

## The UI sets this (BoardView) to let a HUMAN defender choose which Unit absorbs a
## hit. Signature: func(targets:Array, defender_side:StringName) -> Combatant (may
## await a tap). Only called when the defender is human AND there are 2+ live targets.
## If unset, the resolver uses its default minimise-losses policy.
var combat_assign_provider: Callable = Callable()


# ---------------------------------------------------------------------------
#  Setup
# ---------------------------------------------------------------------------

## Start a fresh match. `seats` is an ordered Array of
##   { "color": StringName, "is_ai": bool }
## (turn order = array order). Builds GameState, loads the unit + token data,
## constructs an Agent per seat, then kicks off the round loop coroutine.
func start_match(seats: Array, seed: int) -> void:
	state = GameState
	unit_db = _load_unit_db()

	# 1. Headless model (board, rally zones, players, bags) — Section B/D.
	state.setup_match(seats, seed)

	# 2. Seed the real environment/function tokens face-down (the greybox used
	#    empty pools). Done AFTER setup_match so we reseed onto the built board.
	MapGenerator.seed_tokens(state.board, _token_pools(), seed, _rally_skip_keys())

	# 2b. Setup rule 7: each player starts with one Warrior + one Scout in their
	#     Rally Zone (from the supply, NOT from the bag).
	_place_starting_units(seats)

	# 3. One Agent per seat. Humans get a HumanAgent (awaits taps); everyone else a
	#    PassAgent placeholder (Section H swaps in HeuristicAgent here).
	agents.clear()
	human_colors.clear()
	for spec in seats:
		var color: StringName = spec.get("color")
		if spec.get("is_ai", true):
			agents[color] = PassAgent.new()
		else:
			agents[color] = HumanAgent.new()
			human_colors.append(color)

	# 4. Internal FSM reused for the non-agent mechanics (guardian move, cleanup,
	#    victory). Guardian pool from the .tres set.
	_guardian_pool = _load_guardian_pool()
	_artefact_deck = _load_artefact_deck()
	_fsm = RoundFSM.new(state, agents, unit_db, _guardian_pool, seed)

	winner = &""
	_running = false   # not running until begin() is called by the view
	emit_signal("match_started", state.turn_order.duplicate())


## Kick off the round-loop coroutine. Called by BoardView AFTER it has connected to
## the controller's signals and finished the board reveal, so no phase fires before
## the UI is listening. Idempotent: a second call while running is a no-op.
func begin() -> void:
	if _running or _fsm == null:
		return
	_running = true
	_run_game()


func human_agent_for(color: StringName) -> HumanAgent:
	var a = agents.get(color, null)
	return a if a is HumanAgent else null


func is_human(color: StringName) -> bool:
	return color in human_colors


# ---------------------------------------------------------------------------
#  The round loop (coroutine)
# ---------------------------------------------------------------------------

func _run_game() -> void:
	var max_rounds := 200
	for _r in range(max_rounds):
		if not _running:
			return
		_fsm.round_number += 1
		await _recruitment_phase()
		await _action_phase()
		var v: StringName = await _guardian_phase()   # victory + spawn + (interactive) combat + cleanup
		emit_signal("round_completed", _fsm.round_number)
		if v != &"":
			winner = v
			_running = false
			emit_signal("game_over", winner)
			return
	# Safety valve (degenerate game). Treat as Facility win so the UI can resolve.
	winner = RoundFSM.FACILITY
	_running = false
	emit_signal("game_over", winner)


# --- Phase 1: Recruitment (mirrors RoundFSM.run_recruitment_phase, but awaits) ---
func _recruitment_phase() -> void:
	state.current_phase = Phase.RECRUITMENT
	emit_signal("phase_changed", Phase.RECRUITMENT)
	# A new round opens with Recruitment — clear last round's PASSED markers here so
	# they're gone before anyone acts, not only when the Action phase starts.
	emit_signal("pass_state_reset")
	for color in _turn_order_from_first():
		if not _running:
			return
		var p = state.get_player(color)
		if p == null:
			continue
		_draw_action_card(p)
		# A seat takes its recruitment decision, then one MORE for each Extra
		# Recruitment (action_09) granted to it this round.
		var keep_going := true
		while keep_going:
			if not _running:
				return
			emit_signal("seat_turn_began", color, Phase.RECRUITMENT)
			var intent: Dictionary = await agents[color].decide_recruitment(state, color)
			var card_idx: int = intent.get("play_recruitment_card", -1)
			if card_idx >= 0 and card_idx < p.hand.size():
				p.hand.remove_at(card_idx)
			var summary := _apply_recruitment_choice(p, color, intent)
			emit_signal("recruitment_resolved", color, summary)
			keep_going = state.has_method("take_extra_recruitment") and state.take_extra_recruitment(color)


func _apply_recruitment_choice(p, color: StringName, intent: Dictionary) -> Dictionary:
	match intent.get("choice", "deploy"):
		"recruit":
			var ids: Array = intent.get("recruit_ids", [])
			p.recruit(ids)
			return {"choice": "recruit", "added": ids.size()}
		"punish":
			var removed: int = p.punish_cowards(state.rng)
			return {"choice": "punish", "cowards_removed": removed}
		_:
			var deployed: Array = p.deploy(state.rng)
			_place_deployed_units(p, color, deployed)
			return {"choice": "deploy", "deployed": deployed.size()}


## Setup rule 7: one Warrior + one Scout from the supply into each Rally Zone.
## These come from the SUPPLY, so they never touch the player's bag.
func _place_starting_units(seats: Array) -> void:
	for spec in seats:
		var color: StringName = spec.get("color")
		var p = state.get_player(color)
		if p == null or p.rally_zone == null:
			continue
		var cell: HexCell = state.get_cell(p.rally_zone)
		if cell == null:
			continue
		for unit_id in [&"warrior", &"scout"]:
			var data = unit_db.get(unit_id, null)
			if data != null:
				cell.add_unit(color, {"data": data, "damage": 0})


func _place_deployed_units(p, color: StringName, deployed: Array) -> void:
	if p.rally_zone == null:
		return
	var cell: HexCell = state.get_cell(p.rally_zone)
	if cell == null:
		return
	for unit_id in deployed:
		var data = unit_db.get(unit_id, null)
		cell.add_unit(color, {"data": data, "damage": 0})


# --- Phase 2: Action (mirrors RoundFSM.run_action_phase, but awaits humans) ---
func _action_phase() -> void:
	state.current_phase = Phase.ACTION
	emit_signal("phase_changed", Phase.ACTION)
	emit_signal("pass_state_reset")
	var passed := {}
	var order := _turn_order_from_first()
	var safety := 0
	var safety_cap := 1000
	while passed.size() < order.size() and safety < safety_cap:
		for color in order:
			if not _running:
				return
			if passed.has(color):
				continue
			# One TURN for this seat. A turn ends on Pass, Card, or a LEGAL
			# move_attack; an illegal move_attack re-asks the SAME seat (the human
			# corrects without losing their turn). AI agents only ever propose legal
			# intents, so this inner loop runs once for them.
			var turn_done := false
			while not turn_done:
				if not _running:
					return
				safety += 1
				if safety >= safety_cap:
					break
				emit_signal("seat_turn_began", color, Phase.ACTION)
				var intent: Dictionary = await agents[color].decide_action(state, color)
				match intent.get("type", "pass"):
					"pass":
						passed[color] = true
						turn_done = true
						emit_signal("seat_passed", color)
					"card":
						var idx: int = intent.get("hand_index", -1)
						var p = state.get_player(color)
						if p != null and idx >= 0 and idx < p.hand.size():
							p.hand.remove_at(idx)
						turn_done = true
					"move_attack":
						# Human seats defer combat so they can play a card each round;
						# AI seats resolve inline. Either way, _do_move_attack handles it.
						var as_human: bool = color in human_colors
						var move_intent := intent.duplicate()
						move_intent["defer_combat"] = as_human
						move_intent["token_deps"] = _token_deps_for_effects(color)
						var result: Dictionary = ActionResolver.resolve_move_attack(state, color, move_intent)
						emit_signal("action_resolved", color, result)
						if result.get("ok", false) and result.get("combat_pending", false):
							await run_interactive_combat(result.get("combat_coord"), result.get("entering_side"))
						# Central Chamber: the instant a player's Unit enters the centre,
						# spawn 1 Guardian there (bag draw, may fizzle) and fight it now.
						# From then on the breach flag makes the Guardian phase spawn 2.
						if result.get("ok", false):
							await _handle_center_entry(color, result.get("dest_coord"))
						turn_done = result.get("ok", false)   # illegal -> re-ask
					"ranged_attack":
						# One-sided ranged fire (Ch.11): immediate, no deferred combat window.
						var r_result: Dictionary = ActionResolver.resolve_ranged_attack(state, color, intent)
						emit_signal("action_resolved", color, r_result)
						turn_done = r_result.get("ok", false)   # illegal -> re-ask
					_:
						passed[color] = true
						turn_done = true
						emit_signal("seat_passed", color)
			if passed.size() >= order.size():
				break


# ---------------------------------------------------------------------------
#  Interactive per-round combat (Fix H)
# ---------------------------------------------------------------------------

## Run combat at `coord` interactively: the human(s) involved may play one ATTACK
## card per round (Defensive Stance / Re-roll / Cancel / Extra Attack). Uses the
## tested CombatResolver building blocks via ActionResolver; the per-round card
## window is supplied by `combat_round_provider` (set by the UI). Awaits humans.
func run_interactive_combat(coord, entering_side) -> void:
	if coord == null:
		return
	var cell: HexCell = state.get_cell(coord)
	if cell == null:
		return
	var ctx := ActionResolver.build_combat_context(state, cell, entering_side, {})
	if ctx.is_empty():
		return
	var resolver := CombatResolver.new()
	# Wrap the UI provider so the resolver only sees a (round_index, sides, combatants)
	# Callable; we add `coord` and a safe default of {}.
	var provider := func(round_index, sides, combatants):
		if combat_round_provider.is_valid():
			return await combat_round_provider.call(round_index, sides, combatants, coord)
		return {}
	# Async hit-assignment: only ask a HUMAN defender; AI/empty seats fall back to
	# the resolver's default minimise-losses policy (returns null -> default used).
	if combat_assign_provider.is_valid():
		ctx["async_assign_policy"] = func(targets, defender_side):
			if defender_side in human_colors:
				return await combat_assign_provider.call(targets, defender_side)
			return null
	# Snapshot Guardians present BEFORE combat so we can detect deaths after pruning —
	# the interactive path doesn't go through GuardianManager._guardian_attack, so this
	# is where dead Guardians must be returned to the bag and drop their Old Tech.
	var guardians_before: Array = cell.units_for(GUARDIAN_OWNER).duplicate()
	var log: Array = await resolver.resolve_interactive(ctx, provider)
	ActionResolver.finish_combat(state, cell, log)
	_handle_guardian_deaths(coord, cell, guardians_before)


## After an interactive combat, any Guardian that was present but is now gone (pruned
## by finish_combat) has died: return it to the bag and drop an Old Tech token where it
## fell (rulebook Ch.11). Done here because finish_combat is generic and has no bag.
func _handle_guardian_deaths(coord, cell: HexCell, guardians_before: Array) -> void:
	if guardians_before.is_empty() or _fsm == null or _fsm.guardians == null:
		return
	var still_here: Array = cell.units_for(GUARDIAN_OWNER)
	for g in guardians_before:
		var alive := false
		for s in still_here:
			if is_same(s, g):
				alive = true
				break
		if not alive:
			# finish_combat already dropped the Old Tech for this death; here we ONLY
			# return the Guardian token to the bag (drop_old_tech=false avoids doubling).
			_fsm.guardians.on_guardian_death(state, g, coord, false)


## When a player's Unit enters the Central Chamber: spawn 1 Guardian there (bag draw,
## may fizzle to Scrap), mark the centre BREACHED (so the Guardian phase spawns 2
## from now on), and immediately fight the spawned Guardian if one appeared.
func _handle_center_entry(color: StringName, dest_coord) -> void:
	if dest_coord == null or state.center == null:
		return
	if not dest_coord.equals(state.center):
		return
	var center_cell: HexCell = state.get_cell(state.center)
	if center_cell == null or center_cell.units_for(color).is_empty():
		return
	state.center_breached = true
	var spawned: Array = _fsm.guardians.spawn_into_center(state, 1)
	if not spawned.is_empty():
		await run_interactive_combat(state.center, color)


# --- Phase 3: Guardian + Cleanup ---
## Mirrors RoundFSM.run_guardian_phase (victory -> spawn -> move -> cleanup) but
## INTERLEAVES interactive per-round combat for any guardian-vs-player fights that
## happened during movement, so a defending human can play Attack cards. The tested
## FSM helpers (check_victory / spawns / cleanup) stay the source of truth.
func _guardian_phase() -> StringName:
	state.current_phase = Phase.GUARDIAN
	_fsm._emit("phase_changed", [Phase.GUARDIAN])

	# Step 1 — Victory check (before movement, exactly as the FSM does).
	var v := _fsm.check_victory()
	if v != &"":
		return v

	# Step 2 — Per-phase Central-Chamber spawn (the new rule): EVERY Guardian phase
	# spawn 1 in the centre (bag draw, may fizzle), or 2 once the centre has ever
	# been breached. If the spawn lands on a player's Units, fight immediately.
	var spawn_count: int = 2 if state.center_breached else 1
	var spawned: Array = _fsm.guardians.spawn_into_center(state, spawn_count)
	if not spawned.is_empty():
		var center_cell: HexCell = state.get_cell(state.center)
		if center_cell != null and _center_has_player(center_cell):
			await run_interactive_combat(state.center, GUARDIAN_OWNER)

	# Step 3 — Move every Guardian (NO built-in spawn — we just did it), deferring
	# their combats so a defending human can play a card each round.
	_fsm.guardians.defer_combats = true
	_fsm.guardians.pending_combats = []
	_fsm.guardians.run_guardian_movement(state, false)
	for pc in _fsm.guardians.pending_combats:
		await run_interactive_combat(pc.get("coord"), GUARDIAN_OWNER)
	_fsm.guardians.defer_combats = false
	_fsm.guardians.pending_combats = []

	# Step 4 — Cleanup.
	_fsm.run_cleanup()
	return &""


func _center_has_player(center_cell: HexCell) -> bool:
	for owner in center_cell.units.keys():
		if owner != GUARDIAN_OWNER and not center_cell.units[owner].is_empty():
			return true
	return false


# ---------------------------------------------------------------------------
#  Helpers (turn order, data loading)
# ---------------------------------------------------------------------------

func _turn_order_from_first() -> Array:
	return _fsm._turn_order_from_first()


func _draw_action_card(p) -> void:
	if state.has_method("draw_action_card"):
		var card = state.draw_action_card()
		if card != null:
			p.hand.append(card)


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


func _load_guardian_pool() -> Array:
	var pool := []
	var dir := DirAccess.open("res://data/guardians")
	if dir == null:
		return pool
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var res = load("res://data/guardians/" + fname)
			if res != null:
				pool.append(res)
		fname = dir.get_next()
	dir.list_dir_end()
	return pool


## Environment + function token pools loaded from data/tokens, bucketed by where
## they seed. We read each token's own flags to bucket it; unknown -> room_env.
func _token_pools() -> Dictionary:
	var pools := {"corridor_env": [], "room_env": [], "func": []}
	var dir := DirAccess.open("res://data/tokens")
	if dir == null:
		return pools
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var res = load("res://data/tokens/" + fname)
			if res != null:
				_bucket_token(res, pools)
		fname = dir.get_next()
	dir.list_dir_end()
	return pools


## Rally Zone hexkeys as a skip-set so seed_tokens never tokenises a Rally Zone.
func _rally_skip_keys() -> Dictionary:
	var out := {}
	for color in state.rally_zones.keys():
		var rz = state.rally_zones[color]
		if rz != null:
			out[rz.key()] = true
	return out


## Rich dependency bundle for TokenEffects (environment/function resolution): seeded
## rng, the unit db (Gang Press), the live Guardian pool (env Guardian / Control Room),
## and Action-card draw callbacks. Passed into each move_attack intent.
func _token_deps_for_effects(color: StringName = &"") -> Dictionary:
	var deps := {
		"rng": state.rng,
		"unit_db": unit_db,
		"guardian_pool": _guardian_pool,
	}
	if state.has_method("draw_action_card"):
		deps["draw_action"] = Callable(state, "draw_action_card")
	if state.has_method("discard_action_card"):
		deps["discard_action"] = Callable(state, "discard_action_card")
	# Artifact draw: pull a random Artifact card into the acting player's face-down pile.
	if color != &"":
		deps["draw_artefact"] = func():
			return _draw_artefact_for(color)
	return deps


## Draw one random Artifact card into `color`'s face-down Artifact pile (Ancient
## Artifact token / Function flip). Reproducible via the seeded state rng.
func _draw_artefact_for(color: StringName) -> String:
	if _artefact_deck.is_empty():
		return ""
	var p = state.get_player(color)
	if p == null:
		return ""
	var card = _artefact_deck[state.rng.randi_range(0, _artefact_deck.size() - 1)]
	p.artefacts.append(card)
	return str(card.display_name) if "display_name" in card else "Artifact"


## Load the Artifact card pool from data/artefacts.
func _load_artefact_deck() -> Array:
	var pool := []
	var dir := DirAccess.open("res://data/artefacts")
	if dir == null:
		return pool
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var res = load("res://data/artefacts/" + fname)
			if res != null:
				pool.append(res)
		fname = dir.get_next()
	dir.list_dir_end()
	return pool


func _bucket_token(res, pools: Dictionary) -> void:
	# Bucket by the real .tres schema: FunctionTokenData -> func pool; an
	# EnvironmentTokenData seeds by its "category" ("Room" / "Corridor").
	if res is FunctionTokenData:
		pools["func"].append(res)
	elif res is EnvironmentTokenData:
		if str(res.category) == "Corridor":
			pools["corridor_env"].append(res)
		else:
			pools["room_env"].append(res)

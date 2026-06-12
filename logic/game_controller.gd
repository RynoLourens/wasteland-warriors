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
var _running := false
var winner: StringName = &""


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
	MapGenerator.seed_tokens(state.board, _token_pools(), seed)

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
	_fsm = RoundFSM.new(state, agents, unit_db, _load_guardian_pool(), seed)

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
		var v := _guardian_phase()             # victory check + spawn + cleanup
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
					"card":
						var idx: int = intent.get("hand_index", -1)
						var p = state.get_player(color)
						if p != null and idx >= 0 and idx < p.hand.size():
							p.hand.remove_at(idx)
						turn_done = true
					"move_attack":
						var result: Dictionary = ActionResolver.resolve_move_attack(state, color, intent)
						emit_signal("action_resolved", color, result)
						turn_done = result.get("ok", false)   # illegal -> re-ask
					_:
						passed[color] = true
						turn_done = true
			if passed.size() >= order.size():
				break


# --- Phase 3: Guardian + Cleanup (delegate wholesale to the tested FSM) ---
func _guardian_phase() -> StringName:
	# RoundFSM.run_guardian_phase touches no agents, so we can call it directly and
	# keep the tested guardian/cleanup/victory code as the single source of truth.
	return _fsm.run_guardian_phase()


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

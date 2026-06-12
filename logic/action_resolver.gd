extends RefCounted
class_name ActionResolver
## Move-and-Attack resolution (Section D, step 4) — pure logic, scene-free.
##
## Validates and applies ONE Move-and-Attack intent against the live GameState:
##   1. Activate a space      — place a face-up Activation token; never two of the
##                              same colour; face-down Control tokens don't count.
##   2. Move units in         — pull units from MULTIPLE source spaces into the
##                              activated space, each within its Move budget, never
##                              through enemies (unless Infiltrator), never OUT of a
##                              space you have face-up-activated, stopping on Tough
##                              Terrain. Old Tech is carried only if you Control the
##                              source (one token per unit leaving).
##   3. Resolve Environment-on-the-way (face up tokens on the path's destination).
##   4. Attack                — if the destination holds enemy Units or Guardians,
##                              call the CombatResolver and apply the outcome.
##
## DESIGN: this is the single place that mutates board unit positions for player
## actions, so the rules live here, not in the UI. It returns a small result
## Dictionary {ok, reason, combat_log} so the FSM / UI / AI all learn the outcome
## the same way. It emits EventBus signals so the visual layer (Section E) can react.

const GUARDIAN_OWNER := &"guardian"   ## reserved owner colour for Guardians on a cell


## Apply a validated move_attack intent. `state` is the live GameState autoload (or
## any object exposing board/get_cell/get_player + rng). Returns:
##   {"ok": bool, "reason": String, "combat_log": Array}
static func resolve_move_attack(state, color: StringName, intent: Dictionary) -> Dictionary:
	var activate: HexCoord = intent.get("activate")
	if activate == null:
		return _fail("no activation target")
	var dest: HexCell = state.get_cell(activate)
	if dest == null:
		return _fail("activation target not on board")

	# --- 1. Activate (legality) ---
	if dest.has_faceup_activation(color):
		return _fail("already have a face-up activation token here")

	var moves: Array = intent.get("moves", [])
	var carry: bool = intent.get("carry_old_tech", false)

	# --- 2. Validate every move BEFORE mutating anything (atomic action). ---
	var plan := []   # Array of {from_cell, unit, source_coord}
	for m in moves:
		var from_coord: HexCoord = m.get("from")
		var unit = m.get("unit")
		if from_coord == null or unit == null:
			return _fail("malformed move entry")
		var from_cell: HexCell = state.get_cell(from_coord)
		if from_cell == null:
			return _fail("source space not on board")
		# You cannot move OUT of a space you have face-up-activated (Control is fine).
		if from_cell.has_faceup_activation(color):
			return _fail("cannot move units out of your own activated space")
		# The unit must actually be there and belong to you.
		if not _unit_in_cell(from_cell, color, unit):
			return _fail("unit not present in source space")
		# Reachability: destination must be within this unit's Move from the source.
		# Use the STATE's reachable_for so round-scoped card buffs (Extra Move, Move
		# Through Enemies) are honoured — the same query the UI highlights with, so
		# "lit up but rejected" can't happen.
		if not from_coord.equals(activate):
			if not _reachable_via_state(state, from_coord, activate, color, unit):
				return _fail("destination out of range for a unit")
		plan.append({"from_cell": from_cell, "unit": unit, "source_coord": from_coord})

	# --- 2b. Place the face-up Activation token. ---
	dest.set_token_state(color, HexCell.TokenState.ACTIVE)
	_emit(state, "token_flipped", [activate, color, HexCell.TokenState.ACTIVE])

	# --- 2c. Execute the validated moves. ---
	var p = state.get_player(color)
	for step in plan:
		var from_cell: HexCell = step["from_cell"]
		var unit = step["unit"]
		var source_coord: HexCoord = step["source_coord"]
		if source_coord.equals(activate):
			continue   # unit already standing on the activated space; no movement
		from_cell.remove_unit(color, unit)
		dest.add_unit(color, unit)
		_emit(state, "unit_moved", [unit, source_coord, activate])
		# Old Tech carrying: you must CONTROL the source space, one token per unit.
		if carry and from_cell.old_tech > 0 and p != null and p.controls(source_coord):
			from_cell.old_tech -= 1
			dest.old_tech += 1

	# --- 3. Environment-on-arrival: flip & resolve face-down env tokens on dest. ---
	_resolve_environment_on_arrival(state, dest)

	# --- 4. Attack: if enemies / Guardians are now sharing the space, fight. ---
	# The entering player may have declared combat cards (Re-roll / Cancel / Extra
	# Attack) for this fight; pass them through to the resolver context.
	var combat_log: Array = []
	if _has_other_forces(dest, color):
		combat_log = _resolve_combat(state, dest, color, intent.get("combat_cards", {}))

	# --- 4b. Rally Zone / Central Chamber side effects after the dust settles. ---
	_after_move_effects(state, color, dest)

	return {"ok": true, "reason": "", "combat_log": combat_log}


# ---------------------------------------------------------------------------
#  Combat hand-off
# ---------------------------------------------------------------------------

## Build the CombatResolver context from everyone present in `cell` and run it.
## `combat_cards` (optional) = { "extra_combat_rounds": int, "cancelled_rounds": int,
##   "reroll_misses": { side -> int } } declared by the entering player's cards.
static func _resolve_combat(state, cell: HexCell, entering_side: StringName, combat_cards: Dictionary = {}) -> Array:
	var sides: Array = []
	var units_by_owner: Dictionary = {}
	for owner in cell.units.keys():
		if cell.units[owner].is_empty():
			continue
		sides.append(owner)
		units_by_owner[owner] = cell.units[owner]
	if sides.size() < 2:
		return []

	var combatants := CombatResolver.combatants_from_units(units_by_owner)

	# Controller of the space (face-down Control token) grants +1 ground Defense.
	var controller: StringName = &""
	for owner in cell.token_state.keys():
		if cell.get_token_state(owner) == HexCell.TokenState.CONTROL:
			controller = owner
			break

	# Round-scoped Defensive Stance (+1 def to a player's units this round) flows in
	# as the resolver's stacking extra_defense, keyed by side.
	var extra_def := {}
	for owner in sides:
		if state.has_method("extra_defense_for"):
			var bonus: int = state.extra_defense_for(owner)
			if bonus != 0:
				extra_def[owner] = bonus

	var resolver := CombatResolver.new()
	var ctx := {
		"sides": sides,
		"combatants": combatants,
		"controller": controller,
		"extra_defense": extra_def,
		"entering_side": entering_side,
		"rng": state.rng,
		# Section F combat-card modifiers (default 0/{} so non-card combats are
		# identical to before).
		"extra_combat_rounds": int(combat_cards.get("extra_combat_rounds", 0)),
		"cancelled_rounds": int(combat_cards.get("cancelled_rounds", 0)),
		"reroll_misses": combat_cards.get("reroll_misses", {}),
	}
	var log: Array = resolver.resolve(ctx)

	# Apply deaths: the resolver mutated each combatant's live cell dict in place
	# (damage persists on the dict), so prune any unit whose damage >= its
	# effective defense out of the cell.
	_prune_dead(cell)
	_emit(state, "combat_resolved", [log])
	return log


## Remove dead units from the cell. Death is checked against EFFECTIVE Defense
## (base + controlled-ground bonus), matching the resolver's own death rule, so a
## controlled unit doesn't die one hit early.
static func _prune_dead(cell: HexCell) -> void:
	var controller := &""
	for owner in cell.token_state.keys():
		if cell.get_token_state(owner) == HexCell.TokenState.CONTROL:
			controller = owner
			break
	var has_drone := false
	for owner in cell.units.keys():
		for u in cell.units[owner]:
			if u["data"] != null and u["data"].get("grants_ground_defense"):
				has_drone = true
	for owner in cell.units.keys():
		var survivors := []
		for u in cell.units[owner]:
			var base_def: int = u["data"].defense if u["data"] != null else 1
			var bonus := 0
			if owner == controller or has_drone:
				bonus = 1   # control / drone don't stack with each other (rulebook note)
			if u.get("damage", 0) < base_def + bonus:
				survivors.append(u)
		if survivors.is_empty():
			cell.units.erase(owner)
		else:
			cell.units[owner] = survivors


# ---------------------------------------------------------------------------
#  Movement helpers
# ---------------------------------------------------------------------------

## Reachability that honours round buffs by going through GameState.reachable_for
## (which folds in Extra Move / Move Through Enemies). Falls back to a raw board
## query if `state` lacks the method (pure headless tests with a bare board).
static func _reachable_via_state(state, from_coord: HexCoord, dest: HexCoord, owner: StringName, unit) -> bool:
	var data = unit.get("data")
	if state != null and state.has_method("reachable_for"):
		for c in state.reachable_for(owner, from_coord, data):
			if c is HexCoord and c.equals(dest):
				return true
		return false
	return _reachable(state.board, from_coord, dest, owner, unit)


static func _reachable(board: Dictionary, from_coord: HexCoord, dest: HexCoord, owner: StringName, unit) -> bool:
	var data = unit.get("data")
	var abilities := {
		"move": data.move if data != null else 1,
		"moves_through_enemies": data.moves_through_enemies if data != null else false,
		"can_blink": false,
		"owner": owner,
	}
	for c in HexGraph.reachable(board, from_coord, abilities):
		if c.equals(dest):
			return true
	return false


static func _unit_in_cell(cell: HexCell, owner: StringName, unit) -> bool:
	return cell.units_for(owner).has(unit)


## Any force present that isn't `me` — enemy players OR Guardians.
static func _has_other_forces(cell: HexCell, me: StringName) -> bool:
	for owner in cell.units.keys():
		if owner != me and not cell.units[owner].is_empty():
			return true
	return false


# ---------------------------------------------------------------------------
#  Environment-on-arrival
# ---------------------------------------------------------------------------

## When units arrive on a space, its face-DOWN Environment tokens flip face-up and
## resolve. Section D keeps the data-driven flip + flag; the concrete per-effect
## damage hooks are wired with the real .tres pools in Section E/F. We flip here so
## teleporters / tough-terrain / shield-drone auras become active immediately.
static func _resolve_environment_on_arrival(state, cell: HexCell) -> void:
	for t in cell.tokens:
		if not t.get("face_up", false):
			t["face_up"] = true
			_emit(state, "token_flipped", [cell.coord, &"environment", HexCell.TokenState.NONE])


# ---------------------------------------------------------------------------
#  Post-move effects (Central Chamber spawn handled by GuardianManager via FSM)
# ---------------------------------------------------------------------------

static func _after_move_effects(_state, _color: StringName, _cell: HexCell) -> void:
	# Central-Chamber "stop here -> spawn 2 Guardians" is handled by the FSM/
	# GuardianManager (it owns the Guardian bag). We only flag arrival; the FSM
	# inspects board state in the Guardian phase. Nothing to mutate here yet.
	pass


# ---------------------------------------------------------------------------
#  Small utilities
# ---------------------------------------------------------------------------

static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "combat_log": []}


## Emit on the EventBus autoload. EventBus has no class_name; it's reached through
## the scene tree singleton. We resolve it via the passed-in `state` (which is the
## GameState autoload and can find its sibling) to stay testable, and no-op if the
## tree isn't available (pure unit tests that don't care about signals).
static func _emit(state, signal_name: String, args: Array) -> void:
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

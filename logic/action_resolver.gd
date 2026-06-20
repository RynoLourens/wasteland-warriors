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
	# Optional explicit carrier list: the specific unit dicts the player chose to carry
	# an Old Tech token out. When present, ONLY these units carry (one token each). When
	# absent, fall back to auto-carry (every moving unit carries if OT is available) so
	# tests and the AI keep their prior behaviour.
	var carriers: Array = intent.get("carriers", [])
	var use_explicit_carriers: bool = not carriers.is_empty()

	# --- 2. Validate every move BEFORE mutating anything (atomic action). ---
	# Manstopper rule (Ch.14): it has Move 2 but must spend 1 Move to set up its weapon
	# before Attacking. So when the activated space is an ATTACK (already holds enemy
	# Units or Guardians), a unit flagged `extra_setup_move` reaches with Move-1.
	var dest_is_attack: bool = _has_other_forces(dest, color)
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
			if not _reachable_via_state(state, from_coord, activate, color, unit, dest_is_attack):
				return _fail("destination out of range for a unit")
		plan.append({"from_cell": from_cell, "unit": unit, "source_coord": from_coord})

	# --- 2b. Place the face-up Activation token. ---
	dest.set_token_state(color, HexCell.TokenState.ACTIVE)
	# Remember this as the player's most-recent Activation, so a Dehydration env token
	# resolved this round can spare it from being flipped down at Cleanup (Ch.13).
	if state.has_method("note_activation"):
		state.note_activation(color, activate)
	_emit(state, "token_flipped", [activate, color, HexCell.TokenState.ACTIVE])

	# --- 2c. Execute the validated moves. ---
	var p = state.get_player(color)
	var moved_in := 0   # units that actually MOVED into dest (not already standing there)
	for step in plan:
		var from_cell: HexCell = step["from_cell"]
		var unit = step["unit"]
		var source_coord: HexCoord = step["source_coord"]
		if source_coord.equals(activate):
			continue   # unit already standing on the activated space; no movement
		from_cell.remove_unit(color, unit)
		dest.add_unit(color, unit)
		moved_in += 1
		_emit(state, "unit_moved", [unit, source_coord, activate])
		# Resolve tokens on the cells this Unit PASSED THROUGH (rulebook Ch.11: env and
		# function tokens flip "when a Unit moves through" a space, not only on a stop).
		# We reconstruct the unit's path and resolve each INTERMEDIATE cell (excluding the
		# source it left and the destination, which step 3 below handles).
		_resolve_passthrough_tokens(state, color, source_coord, activate, unit, intent)
		# Old Tech carrying: you must CONTROL the source space, one token per unit.
		# With an explicit carrier list, only chosen units carry; otherwise auto-carry.
		var this_carries := carry
		if use_explicit_carriers:
			this_carries = false
			for cu in carriers:
				if is_same(cu, unit):
					this_carries = true
					break
		if this_carries and from_cell.old_tech > 0 and p != null and p.controls(source_coord):
			from_cell.old_tech -= 1
			dest.old_tech += 1

	# --- 2d. Sapperteur (Ch.14): "When it stops in a space, you may place a Sticky Bomb
	# token there." Any Sapperteur that MOVED into dest this action drops one bomb. We add
	# at most one bomb per action (a space holds one), and only if one isn't already here.
	if moved_in > 0:
		_maybe_place_sapperteur_bomb(state, color, dest)

	# --- 3. Environment/Function-on-arrival: flip & RESOLVE face-down tokens on dest. ---
	# Tokens flip only when a Unit actually MOVED into the space this action (rulebook:
	# "moves through or stops in"). Activating an empty space with no movers must NOT
	# flip its token. `moved_in` counts units this action pulled from a DIFFERENT space.
	var token_log: Dictionary = {"resolved": [], "damage": {}}
	if moved_in > 0:
		token_log = _resolve_environment_on_arrival(state, color, dest, intent)

	# --- 4. Attack: if enemies / Guardians are now sharing the space, fight. ---
	# When intent.defer_combat is set (live game with a human who may play cards each
	# round), DON'T resolve here — return combat_pending so GameController runs the
	# interactive per-round combat. Default (tests/AI) resolves synchronously inline.
	var has_fight := _has_other_forces(dest, color)
	if has_fight and intent.get("defer_combat", false):
		_after_move_effects(state, color, dest)
		# Surface the eligible Ranged support shooters so the UI can prompt the human to
		# fire some IN before combat (Ch.11). The controller passes the chosen subset to
		# run_interactive_combat.
		var eligible: Array = eligible_ranged_shooters(state, color, activate, {})
		return {"ok": true, "reason": "", "combat_log": [], "combat_pending": true,
			"combat_coord": activate, "entering_side": color, "dest_coord": activate,
			"eligible_shooters": eligible, "token_log": token_log}

	# Sync (AI / headless / tests) path: gather Ranged support shooters now. An explicit
	# `support_shooters` list (tests) takes precedence; otherwise `auto_support_fire` (AI /
	# FSM) fires ALL eligible. Activate every shooter's space, then resolve with their dice.
	var combat_log: Array = []
	if has_fight:
		var shooters: Array = intent.get("support_shooters", [])
		if shooters.is_empty() and intent.get("auto_support_fire", false):
			shooters = eligible_ranged_shooters(state, color, activate, {})
		activate_shooter_spaces(state, color, shooters)
		combat_log = _resolve_combat(state, dest, color, intent.get("combat_cards", {}), shooters)

	# --- 4b. Rally Zone / Central Chamber side effects after the dust settles. ---
	_after_move_effects(state, color, dest)

	return {"ok": true, "reason": "", "combat_log": combat_log, "dest_coord": activate,
		"token_log": token_log}

# ---------------------------------------------------------------------------
#  Combat hand-off
# ---------------------------------------------------------------------------

## Build the CombatResolver context from everyone present in `cell`. Returns {} if
## fewer than two forces are present (no fight). `combat_cards` (optional) =
## { "extra_combat_rounds": int, "cancelled_rounds": int, "reroll_misses": {side->int} }.
## Shared by the sync (`_resolve_combat`) AND interactive (GameController) paths so the
## combat setup is identical either way.
static func build_combat_context(state, cell: HexCell, entering_side: StringName, combat_cards: Dictionary = {}, support_shooters: Array = []) -> Dictionary:
	var sides: Array = []
	var units_by_owner: Dictionary = {}
	for owner in cell.units.keys():
		if cell.units[owner].is_empty():
			continue
		sides.append(owner)
		units_by_owner[owner] = cell.units[owner]
	if sides.size() < 2:
		return {}

	var combatants := CombatResolver.combatants_from_units(units_by_owner)

	# Controller of the space (face-down Control token) grants +1 ground Defense.
	var controller: StringName = &""
	for owner in cell.token_state.keys():
		if cell.get_token_state(owner) == HexCell.TokenState.CONTROL:
			controller = owner
			break

	# Round-scoped Defensive Stance (+1 def this round) flows in as stacking extra_def.
	var extra_def := {}
	for owner in sides:
		if state.has_method("extra_defense_for"):
			var bonus: int = state.extra_defense_for(owner)
			if bonus != 0:
				extra_def[owner] = bonus

	# Shield Drones FUNCTION token (Ch.13): +1 Defense to the controller's Units.
	# A Function needs Control to use; stacks on controlled-ground / Siyana via extra_defense.
	if controller != &"" and cell.has_token_effect(&"func_shield_drones", true):
		extra_def[controller] = int(extra_def.get(controller, 0)) + 1

	# Defensive Turrets FUNCTION token (Ch.13): +1 Range-1 Attack die per Unit, controller only.
	var extra_attack_dice := {}
	if controller != &"" and cell.has_token_effect(&"func_defensive_turrets", true):
		var n_def: int = cell.units_for(controller).size()
		if n_def > 0:
			extra_attack_dice[controller] = n_def

	# Placed Sticky Bomb tokens (Ch.11 + Sapperteur/Action card): a bomb owned by a side
	# OTHER than the one entering rolls 2 Attack dice at the entering side, before combat.
	# (The resolver's unit-flag sticky-bomb path is for a Sapperteur standing here; this
	# covers bombs LEFT on the space, which persist after the Sapperteur moves on.)
	# Sunstone Fragments (Artifact): if THIS space is marked, ranged attackers (units with
	# Range, incl. Guardians) can only HIT on a 6 this round.
	var sunstone_active := false
	if state.has_method("is_sunstone_marked"):
		sunstone_active = state.is_sunstone_marked(cell.coord)

	var sticky_bomb_count := 0
	if entering_side != &"":
		for t in cell.tokens:
			if t.get("kind", "") == "sticky_bomb" and t.get("owner", &"") != entering_side:
				sticky_bomb_count += 1

	# Darkness ENVIRONMENT token (Ch.13): all Units here get -1 Attack. Applies to
	# EVERY side in the space (drained across each side's dice pool by the resolver).
	var space_attack_penalty := 0
	if cell.has_token_effect(&"env_darkness", true):
		space_attack_penalty = 1

	# Ranged SUPPORT FIRE (Ch.11): remote Ranged Units firing INTO this combat for the
	# entering side. They are NOT in `combatants`/`sides` (so the defender can never hit
	# them); they only add dice. Build them as Combatants via the same helper, keyed under
	# the entering side, and hand them to the resolver as a separate pool.
	var shooter_combatants: Array = []
	if not support_shooters.is_empty() and entering_side != &"":
		var shooter_units: Array = []
		for sh in support_shooters:
			shooter_units.append(sh["unit"])
		shooter_combatants = CombatResolver.combatants_from_units({entering_side: shooter_units})[entering_side]

	return {
		"support_shooters": shooter_combatants,
		"support_side": entering_side if not shooter_combatants.is_empty() else &"",
		"extra_attack_dice": extra_attack_dice,
		"space_attack_penalty": space_attack_penalty,
		"sticky_bomb_count": sticky_bomb_count,
		"sunstone_active": sunstone_active,
		"sides": sides,
		"combatants": combatants,
		"controller": controller,
		"extra_defense": extra_def,
		"entering_side": entering_side,
		"rng": state.rng,
		"extra_combat_rounds": int(combat_cards.get("extra_combat_rounds", 0)),
		"cancelled_rounds": int(combat_cards.get("cancelled_rounds", 0)),
		"reroll_misses": combat_cards.get("reroll_misses", {}),
	}


## Prune dead units from `cell` and emit combat_resolved. Call after ANY combat
## (sync or interactive) once the resolver has stamped damage onto the cell dicts.
## ALSO drops an Old Tech token for every Guardian that died here (rulebook Ch.11) and
## emits `old_tech_captured`, so Old Tech appears regardless of which combat path ran —
## the bag-return is handled by the caller that owns the GuardianManager.
static func finish_combat(state, cell: HexCell, log: Array) -> void:
	var guardians_before: int = cell.units_for(GUARDIAN_OWNER).size()
	var dead_by_owner: Dictionary = _prune_dead(cell)
	var guardians_after: int = cell.units_for(GUARDIAN_OWNER).size()
	var died: int = guardians_before - guardians_after
	for _i in range(died):
		cell.old_tech += 1
		_emit(state, "old_tech_captured", [GUARDIAN_OWNER, cell.coord])
	# Medical Machine artifact: a player holding it may save ONE just-killed Unit (yours or
	# an enemy's) for a free redeploy next Recruitment. We arm it for any holder, choosing
	# the first dead Unit available (UI can later let them pick which).
	for owner in dead_by_owner.keys():
		for victim in dead_by_owner[owner]:
			if ArtefactEffects.arm_medical_machine(state, owner, victim):
				break   # one save per Medical Machine
	_emit(state, "combat_resolved", [log])


## Synchronous combat (headless/AI path; unchanged behaviour). Builds the context,
## runs the sync resolver, prunes + emits. Interactive combat lives in GameController.
static func _resolve_combat(state, cell: HexCell, entering_side: StringName, combat_cards: Dictionary = {}, support_shooters: Array = []) -> Array:
	var ctx := build_combat_context(state, cell, entering_side, combat_cards, support_shooters)
	if ctx.is_empty():
		return []
	var resolver := CombatResolver.new()
	var log: Array = resolver.resolve(ctx)
	finish_combat(state, cell, log)
	return log


## Remove dead units from the cell. Death is checked against EFFECTIVE Defense
## (base + controlled-ground bonus), matching the resolver's own death rule, so a
## controlled unit doesn't die one hit early.
static func _prune_dead(cell: HexCell) -> Dictionary:
	var controller := &""
	for owner in cell.token_state.keys():
		if cell.get_token_state(owner) == HexCell.TokenState.CONTROL:
			controller = owner
			break
	# +1 per Shield Drone present in the space (drones grant ground defense to the
	# whole space). Count them — multiple drones each add +1.
	var drone_bonus := 0
	for owner in cell.units.keys():
		for u in cell.units[owner]:
			if u["data"] != null and u["data"].get("grants_ground_defense"):
				drone_bonus += 1
	var dead_by_owner: Dictionary = {}
	for owner in cell.units.keys():
		var survivors := []
		var dead := []
		for u in cell.units[owner]:
			var base_def: int = u["data"].defense if u["data"] != null else 1
			# Controlled ground (+1) and Shield Drone(s) (+1 each) DO STACK — a unit on
			# its controlled space with a drone present is base + 1 + 1. Must match the
			# CombatResolver's _ground_defense_bonus, or cleanup kills a unit a hit early.
			var bonus := drone_bonus
			if owner == controller and controller != &"":
				bonus += 1
			if u.get("damage", 0) < base_def + bonus:
				survivors.append(u)
			else:
				dead.append(u)
		if not dead.is_empty() and owner != GUARDIAN_OWNER:
			dead_by_owner[owner] = dead
		if survivors.is_empty():
			cell.units.erase(owner)
		else:
			cell.units[owner] = survivors
	return dead_by_owner


# ---------------------------------------------------------------------------
#  Movement helpers
# ---------------------------------------------------------------------------

## Reachability that honours round buffs by going through GameState.reachable_for
## (which folds in Extra Move / Move Through Enemies). Falls back to a raw board
## query if `state` lacks the method (pure headless tests with a bare board).
static func _reachable_via_state(state, from_coord: HexCoord, dest: HexCoord, owner: StringName, unit, is_attack: bool = false) -> bool:
	var data = unit.get("data")
	# Manstopper setup cost: when this move is an Attack, a unit that must "set up"
	# (extra_setup_move) loses 1 Move. We enforce it by requiring the destination to be
	# within (Move-1) of the source — computed with a raw HexGraph query using the
	# reduced budget, since reachable_for reads the unit's printed Move directly.
	if is_attack and data != null and data.get("extra_setup_move"):
		var reduced: int = int(max(0, (data.move if data != null else 1) - 1))
		var abilities := {
			"move": reduced,
			"moves_through_enemies": data.moves_through_enemies if data != null else false,
			"can_blink": false,
			"owner": owner,
		}
		# Fold in any round-scoped Extra Move buff so cards still help a Manstopper.
		if state != null and state.has_method("extra_move_for"):
			abilities["move"] += int(state.extra_move_for(owner, from_coord))
		for c in HexGraph.reachable(state.board, from_coord, abilities):
			if c is HexCoord and c.equals(dest):
				return true
		return false
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


## Sapperteur unit ability: if one of `color`'s units in `cell` carries places_sticky_bomb
## and the cell doesn't already hold a Sticky Bomb of theirs, drop one (face-up). Mirrors
## the Action-card placement shape so the combat sticky-bomb sub-round picks it up.
static func _maybe_place_sapperteur_bomb(state, color: StringName, cell: HexCell) -> void:
	var has_sapperteur := false
	for u in cell.units_for(color):
		var d = u.get("data")
		if d != null and d.get("places_sticky_bomb"):
			has_sapperteur = true
			break
	if not has_sapperteur:
		return
	for t in cell.tokens:
		if t.get("kind", "") == "sticky_bomb" and t.get("owner", &"") == color:
			return   # already a bomb of theirs here; one per space
	cell.tokens.append({"data": null, "face_up": true, "kind": "sticky_bomb", "owner": color})
	_emit(state, "token_flipped", [cell.coord, color, HexCell.TokenState.NONE])


## Any force present that isn't `me` — enemy players OR Guardians.
static func _has_other_forces(cell: HexCell, me: StringName) -> bool:
	for owner in cell.units.keys():
		if owner != me and not cell.units[owner].is_empty():
			return true
	return false


# ---------------------------------------------------------------------------
#  Ranged support fire (Ch.11)
# ---------------------------------------------------------------------------

## List `color`'s Ranged Units eligible to fire INTO a combat at `combat_coord` from afar.
## Returns an Array of { "coord": HexCoord, "unit": <unit dict> }. A shooter qualifies when:
##   * its Unit has Range >= 1,
##   * hex distance from its space to the combat space <= its Range (no line of sight),
##   * its space is NOT activated by `color` (no face-up Activation token of theirs),
##   * its space has NO enemy Units,
##   * (Manstopper / extra_setup_move) it moved <= 1 space this Activation — looked up in
##     `moved_this_activation` (unit dict -> spaces moved); absent = moved 0 = eligible.
## The combat space itself is skipped, so any Unit that just moved into the fight (and is
## therefore a melee participant) is never offered as a remote shooter.
static func eligible_ranged_shooters(state, color: StringName, combat_coord: HexCoord, moved_this_activation: Dictionary = {}) -> Array:
	var out: Array = []
	if combat_coord == null:
		return out
	for k in state.board.keys():
		var coord: HexCoord = HexCoord.from_key(k)
		if coord.equals(combat_coord):
			continue
		var cell: HexCell = state.board[k]
		if cell == null:
			continue
		if cell.has_faceup_activation(color):
			continue
		if cell.has_enemy_units(color):
			continue
		var dist: int = coord.distance_to(combat_coord)
		for u in cell.units_for(color):
			var d = u.get("data")
			var rng_v: int = (d.range if d != null else 0)
			if rng_v < 1:
				continue
			if dist > rng_v:
				continue
			# Manstopper setup gate: only if it has moved <= 1 space this Activation.
			if d != null and d.extra_setup_move:
				var moved: int = _moved_steps(moved_this_activation, u)
				if moved > 1:
					continue
			out.append({"coord": coord, "unit": u})
	return out


## Steps a specific unit dict moved this Activation, per `moved_this_activation` (matched by
## identity). 0 if absent (didn't move). The dict can't key on a Dictionary, so it stores
## entries as { "unit": <dict>, "steps": int } and we identity-match here.
static func _moved_steps(moved_this_activation: Dictionary, unit) -> int:
	var entries: Array = moved_this_activation.get("entries", [])
	for e in entries:
		if is_same(e.get("unit"), unit):
			return int(e.get("steps", 0))
	return 0


## Activate the space of every Ranged support shooter that fired (Ch.11 step 7): place a
## face-up Activation token of `color` there (deduped), record it for Dehydration, and emit.
## Runs even if the combat is one-sided/empty, so firing always costs the Activation.
static func activate_shooter_spaces(state, color: StringName, support_shooters: Array) -> void:
	var done: Dictionary = {}
	for sh in support_shooters:
		var coord: HexCoord = sh.get("coord")
		if coord == null:
			continue
		var key: String = coord.key()
		if done.has(key):
			continue
		done[key] = true
		var cell: HexCell = state.get_cell(coord)
		if cell == null:
			continue
		cell.set_token_state(color, HexCell.TokenState.ACTIVE)
		if state.has_method("note_activation"):
			state.note_activation(color, coord)
		_emit(state, "token_flipped", [coord, color, HexCell.TokenState.ACTIVE])


# ---------------------------------------------------------------------------
#  Environment-on-arrival
# ---------------------------------------------------------------------------

## When units arrive on a space, its face-DOWN Environment and Function tokens flip
## face-up and RESOLVE (Ch.11/Ch.13) via TokenEffects. `intent.token_deps` (set by
## GameController) supplies unit_db / guardian_pool / draw callbacks; we fall back to a
## minimal deps from `state` so headless tests / the FSM still resolve dice/coward/bag.
## Returns the TokenEffects log so the caller/UI can announce what happened.
## Flip & resolve tokens on cells a Unit PASSED THROUGH (between source and dest,
## exclusive). Uses HexGraph.find_path for the unit's actual route. Degrades safely if
## no path is found (e.g. teleporter hops — those have no walked corridor).
static func _resolve_passthrough_tokens(state, color: StringName, source_coord: HexCoord, dest_coord: HexCoord, unit, intent: Dictionary) -> void:
	var data = unit.get("data") if unit is Dictionary else unit
	var abilities := {
		"move": 99,
		"moves_through_enemies": data.moves_through_enemies if data != null else false,
		"can_blink": false,
		"owner": color,
	}
	var path: Array = HexGraph.find_path(state.board, source_coord, dest_coord, abilities)
	if path.size() <= 2:
		return   # adjacent move or no path: no intermediate cells to resolve
	var deps: Dictionary = intent.get("token_deps", {})
	if deps.is_empty():
		deps = _default_token_deps(state)
	# Skip index 0 (source) and the last (dest); resolve everything between.
	for i in range(1, path.size() - 1):
		var mid: HexCell = state.get_cell(path[i])
		if mid != null:
			TokenEffects.resolve_on_passthrough(state, mid, color, deps)


static func _resolve_environment_on_arrival(state, color: StringName, cell: HexCell, intent: Dictionary) -> Dictionary:
	var deps: Dictionary = intent.get("token_deps", {})
	if deps.is_empty():
		deps = _default_token_deps(state)
	return TokenEffects.resolve_cell(state, cell, color, deps)


## Minimal deps from `state` alone: seeded rng + Action-card draw/discard. No unit_db
## or guardian_pool, so Gang Press / env-Guardian degrade to no-ops in pure headless
## tests unless the caller injects richer deps.
static func _default_token_deps(state) -> Dictionary:
	var deps := {"rng": state.rng if "rng" in state else null}
	if state.has_method("draw_action_card"):
		deps["draw_action"] = Callable(state, "draw_action_card")
	if state.has_method("discard_action_card"):
		deps["discard_action"] = Callable(state, "discard_action_card")
	return deps


# ---------------------------------------------------------------------------
#  Post-move effects (Central Chamber spawn handled by GuardianManager via FSM)
# ---------------------------------------------------------------------------

static func _after_move_effects(state, color: StringName, cell: HexCell) -> void:
	# Central-Chamber breach flag: once ANY player's Unit is on the centre, the
	# Guardian phase spawns 2 (not 1) from then on. The live controller ALSO does an
	# immediate centre-entry spawn; here we just set the persistent flag so BOTH the
	# headless FSM and the live game agree on the breach state.
	if state != null and "center" in state and state.center != null and "center_breached" in state:
		if cell != null and cell.coord != null and cell.coord.equals(state.center):
			if not cell.units_for(color).is_empty():
				state.center_breached = true


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

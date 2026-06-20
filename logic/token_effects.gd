extends RefCounted
class_name TokenEffects
## Environment & Function token resolution (rulebook Ch.11 + Ch.13).
##
## The board seeds Environment (blue corridor / orange room) and Function (yellow
## room) tokens FACE DOWN. Until this module existed, ActionResolver flipped them
## face-up but resolved NOTHING — so exploration had no risk and no reward. This is
## the single place a token's rules text becomes a mutation, mirroring the pattern
## of CardEffects: dispatch on `effect_id`, never on token display names.
##
## DESIGN — dependency injection for testability:
##   The damage effects roll dice; the spawn effects need a Guardian pool; the draw
##   effects need the Action/Artefact decks. Rather than reach into autoloads (which
##   would make this untestable headless), the caller passes a `deps` Dictionary:
##     {
##       "rng":            RandomNumberGenerator,   # seeded; REQUIRED for dice/spawn
##       "unit_db":        { id -> UnitData },       # for Gang Press warriors
##       "guardian_pool":  Array of GuardianData,    # for env Guardian / Control Room
##       "draw_action":    Callable() -> card,       # Supplies / Schematics
##       "discard_action": Callable(card) -> void,   # Schematics discard
##       "draw_artefact":  Callable() -> void,       # on any Function flip (Ch.11)
##     }
##   Every dep is OPTIONAL: a missing dep degrades that one effect to a no-op rather
##   than crashing, so headless rules tests can supply only what they assert on.
##
## RETURN: a small log Dictionary per call so the UI/AI/tests learn what happened:
##   { "resolved": [ {effect_id, summary, ...}, ... ], "damage": {color -> hits} }

const GUARDIAN_OWNER := &"guardian"
const COWARD := &"coward"
const WARRIOR := &"warrior"

## Effects that LEAVE their token in the room (persist face-up; their effect is read
## later by combat/movement, not applied as a one-shot here).
const PERSISTENT := [&"env_teleporter_node", &"env_tough_terrain", &"env_darkness"]


# ---------------------------------------------------------------------------
#  Public entry point
# ---------------------------------------------------------------------------

## Resolve every face-DOWN token on `cell` for the `color` whose Unit(s) just arrived
## (or passed through). Flips each token face-up, then dispatches its effect. Returns
## the log described above. `state` is GameState (for board/center/spawn/draw access).
##
## Ch.11 ordering rules honoured:
##   * Environment tokens flip & resolve whenever a Unit moves THROUGH or STOPS on the
##     space — callers invoke this on arrival AND (for tough terrain / teleporters)
##     mid-path via resolve_on_passthrough().
##   * A Function token is flipped ONLY if a Unit is present and there is NO unresolved
##     Environment token in the same space; using its Function additionally needs
##     Control (checked by the function effects themselves).
static func resolve_cell(state, cell: HexCell, color: StringName, deps: Dictionary = {}) -> Dictionary:
	var log := {"resolved": [], "damage": {}}
	if cell == null:
		return log

	# 1. Environment tokens first (flip face-down -> face-up, resolve one-shots).
	for t in cell.tokens:
		if t.get("kind", "") != "env":
			continue
		if not t.get("face_up", false):
			t["face_up"] = true
			_emit(state, "token_flipped", [cell.coord, &"environment", HexCell.TokenState.NONE])
			_resolve_env(state, cell, color, t, deps, log)
		# Darkness / Tough Terrain / Teleporter persist; they're not "unresolved" but
		# they also don't gate the Function flip. Only a one-shot env that hasn't been
		# dealt with would, and we just dealt with them all, so none remain unresolved.
	# (After the loop every env token is face-up & resolved, so the Function may flip.)

	# 2. Function token: flip only if a Unit of `color` is here AND no env token blocks
	#    it. We flip at most one per visit (a room holds exactly one Function token).
	if not cell.units_for(color).is_empty():
		for t in cell.tokens:
			if t.get("kind", "") != "func":
				continue
			if not t.get("face_up", false):
				t["face_up"] = true
				_emit(state, "token_flipped", [cell.coord, &"function", HexCell.TokenState.NONE])
				# Ch.11: "Whenever you flip a Function token, draw an Artefact card."
				_call(deps.get("draw_artefact"), [])
				_resolve_func(state, cell, color, t, deps, log)
			# A Function's ongoing benefit (Shield Drones +1 Def, Defensive Turrets die)
			# is read in combat via flags; flipping it is what activates it.
			break
	return log


## Entry for tokens encountered MID-PATH (a Unit moving THROUGH the space, not
## stopping). Per Ch.11 Environment tokens resolve on pass-through; Corin's ruling also
## flips a FUNCTION token when a Unit passes through its space (draws an Artefact). The
## function's ONGOING benefit still needs the Unit present + Control to USE, but the
## flip + Artefact happen on pass-through.
static func resolve_on_passthrough(state, cell: HexCell, color: StringName, deps: Dictionary = {}) -> Dictionary:
	var log := {"resolved": [], "damage": {}}
	if cell == null:
		return log
	# Function tokens flip on pass-through too (draw an Artefact on the flip).
	for t in cell.tokens:
		if t.get("kind", "") == "func" and not t.get("face_up", false):
			t["face_up"] = true
			_emit(state, "token_flipped", [cell.coord, &"function", HexCell.TokenState.NONE])
			_call(deps.get("draw_artefact"), [])
			_resolve_func(state, cell, color, t, deps, log)
	for t in cell.tokens:
		if t.get("kind", "") != "env":
			continue
		if not t.get("face_up", false):
			t["face_up"] = true
			_emit(state, "token_flipped", [cell.coord, &"environment", HexCell.TokenState.NONE])
			_resolve_env(state, cell, color, t, deps, log)
	return log


# ---------------------------------------------------------------------------
#  Environment effects (Ch.13)
# ---------------------------------------------------------------------------

static func _resolve_env(state, cell: HexCell, color: StringName, token: Dictionary, deps: Dictionary, log: Dictionary) -> void:
	var data = token.get("data")
	if data == null:
		return
	var eid: StringName = data.get("effect_id")
	match eid:
		# --- Room (orange) ---
		&"env_guardian":
			# Spawn 1 Guardian in THIS space and fight it immediately. We place the
			# Guardian on the cell; the caller resolves the ensuing combat (it shares
			# the space now, so the normal combat path triggers).
			var g = _spawn_guardian_here(state, cell, deps)
			_record(log, eid, "Guardian appeared — fight it!" if g != null else "No Guardian to spawn (bag empty).")
		&"env_turrets":
			var h := _roll_attack_against(state, cell, color, 3, deps)
			_record(log, eid, "Turrets fired 3 dice (%d hit)." % h, {"hits": h})
			_accumulate_damage(log, color, h)
		&"env_falling_debris":
			# 1 Attack die against EACH of your Units in the space.
			var n := cell.units_for(color).size()
			var total := _roll_attack_per_unit(state, cell, color, 1, deps)
			_record(log, eid, "Falling debris hit %d of %d Unit(s)." % [total, n], {"hits": total})
			_accumulate_damage(log, color, total)
		&"env_gang_press_survivors":
			var added := _place_supply_units(state, cell, color, WARRIOR, 2, deps)
			_record(log, eid, "Gained %d Warrior(s)." % added, {"added": added})
		&"env_dehydration":
			# At end of round, do not flip the last Activation token you placed. Flag it
			# on the player; Cleanup reads the flag. We just set it; Cleanup honours it.
			if state.has_method("set_dehydration"):
				state.set_dehydration(color)
			_record(log, eid, "Dehydration: your last Activation token stays face-up at Cleanup.")
		&"env_schematics":
			var kept := _draw_and_discard(deps, color, 3, 1, state)
			_record(log, eid, "Drew 3 Action cards, discarded 1 (kept %d)." % kept, {"kept": kept})

		# --- Corridor (blue) ---
		&"env_troubling_tales":
			var p = state.get_player(color)
			if p != null:
				p.bag.append(COWARD)
			_record(log, eid, "A Coward joined your bag.")
		&"env_supplies":
			var c = _call(deps.get("draw_action"), [])
			if c != null:
				var pl = state.get_player(color)
				if pl != null:
					pl.hand.append(c)
			_record(log, eid, "Drew 1 Action card.")
		&"env_local_fauna":
			var h2 := _roll_attack_against(state, cell, color, 1, deps)
			_record(log, eid, "Local fauna attacked (%d hit)." % h2, {"hits": h2})
			_accumulate_damage(log, color, h2)
		&"env_teleporter_node":
			# Persists. Movement code (HexGraph) reads it; nothing to apply now.
			_record(log, eid, "Teleporter Node active.")
		&"env_darkness":
			# Persists. Combat reads -1 Attack for Units here; nothing to apply now.
			_record(log, eid, "Darkness: Units here have -1 Attack.")
		&"env_tough_terrain":
			# Persists. HexGraph stops movement on it; nothing to apply now.
			_record(log, eid, "Tough Terrain: movement stops here.")
		&"env_ancient_artifact":
			# Draw one Artifact card face down in front of you. The callback returns the
			# drawn card's name so we can announce exactly what was found.
			var art = _call(deps.get("draw_artefact"), [])
			var art_name := str(art) if art != null and str(art) != "" else ""
			if art_name != "":
				_record(log, eid, "Found an Artifact: %s (face-down in front of you)." % art_name)
			else:
				_record(log, eid, "Drew an Artifact card.")
		&"env_dead_silence":
			_record(log, eid, "Dead silence — nothing happens.")
		_:
			_record(log, eid, "Unknown environment effect (no-op).")


# ---------------------------------------------------------------------------
#  Function effects (Ch.13). Using a Function needs CONTROL of the space.
# ---------------------------------------------------------------------------

static func _resolve_func(state, cell: HexCell, color: StringName, token: Dictionary, deps: Dictionary, log: Dictionary) -> void:
	var data = token.get("data")
	if data == null:
		return
	var eid: StringName = data.get("effect_id")
	# Most Functions are USED during Recruitment and/or require Control; flipping always
	# happens (and always draws an Artefact). We record availability; the actual "use"
	# is gated on Control where the rules demand it.
	var controlled := false
	if state.has_method("player_controls"):
		controlled = state.player_controls(color, cell.coord)
	match eid:
		&"func_shield_drones":
			# Ongoing: each Unit here gets +1 Defense (combat reads grants_ground_defense
			# via the token being face-up). Activated by the flip; no one-shot.
			_record(log, eid, "Shield Drones online: +1 Defense to Units here.")
		&"func_defensive_turrets":
			# Ongoing: each Unit here gets 1 extra Range-1 Attack die in combat (read via
			# flag on the face-up token). Activated by the flip.
			_record(log, eid, "Defensive Turrets online: +1 Attack die (Range 1) here.")
		&"func_guardian_control_room":
			# During Recruitment you MAY spawn a Guardian here under your control instead
			# of your normal Recruitment action — gated on Control. We flag availability.
			_record(log, eid, "Guardian Control Room available%s." %
				("" if controlled else " (Control the space to use it)"), {"controlled": controlled})
		&"func_teleporter_hub":
			# During Recruitment you MAY Deploy into this space instead of your Rally
			# Zone (and Activate it) — gated on Control. We flag availability.
			_record(log, eid, "Teleporter Hub available%s." %
				("" if controlled else " (Control the space to use it)"), {"controlled": controlled})
		_:
			_record(log, eid, "Unknown function (no-op).")


# ---------------------------------------------------------------------------
#  Ground-defense bonus (control + Shield Drones) — env damage respects it too
# ---------------------------------------------------------------------------

## +1 if `color` Controls the space (face-down Control token) AND +1 per Shield Drone
## present — these STACK, matching CombatResolver._ground_defense_bonus and
## ActionResolver._prune_dead. Room-hazard dice now use base + this bonus (Corin ruling
## 2026-06-18: controlled ground / drones DO protect against environmental damage).
static func _ground_defense_bonus(cell: HexCell, color: StringName) -> int:
	var bonus := 0
	if cell.get_token_state(color) == HexCell.TokenState.CONTROL:
		bonus += 1
	for owner in cell.units.keys():
		for u in cell.units[owner]:
			if u["data"] != null and u["data"].get("grants_ground_defense"):
				bonus += 1
	return bonus


# ---------------------------------------------------------------------------
#  Dice / damage (one-sided environmental attacks)
# ---------------------------------------------------------------------------

## Roll `dice` Attack dice ONCE against `color`'s Units in `cell`, assign hits
## minimise-losses (stack onto the unit closest to dying), apply damage, prune the
## dead. Returns total hits rolled. 4/5/6 = hit; 6 = crit (roll one more, chains).
static func _roll_attack_against(state, cell: HexCell, color: StringName, dice: int, deps: Dictionary) -> int:
	var rng = deps.get("rng")
	var hits := _roll_hits(rng, dice)
	if hits > 0:
		_apply_hits_minimise(cell, color, hits)
	return hits


## Roll `dice` dice against EACH Unit separately (Falling Debris semantics). Each Unit
## takes its own roll; returns total hits across all Units.
static func _roll_attack_per_unit(state, cell: HexCell, color: StringName, dice: int, deps: Dictionary) -> int:
	var rng = deps.get("rng")
	var arr: Array = cell.units_for(color)
	var total := 0
	# Snapshot the unit list — applying damage may prune entries.
	var targets := arr.duplicate()
	for u in targets:
		var h := _roll_hits(rng, dice)
		if h > 0:
			u["damage"] = int(u.get("damage", 0)) + h
			total += h
	_prune_dead_for(cell, color)
	return total


## Core dice roller: `dice` dice, 4/5/6 = hit, each 6 crits (one extra die, chains).
## Bounded by a guard so a pathological rng can't hang. Mirrors the CombatResolver's
## hit rule so environmental and combat dice behave identically.
static func _roll_hits(rng, dice: int) -> int:
	if rng == null or dice <= 0:
		return 0
	var hits := 0
	var pending := dice
	var guard := 0
	while pending > 0 and guard < 10000:
		var next := 0
		for _i in range(pending):
			guard += 1
			var face: int = rng.randi_range(1, 6)
			if face >= 4:
				hits += 1
			if face == 6:
				next += 1   # each 6 crits -> one extra die
		pending = next
	return hits


## Assign `hits` to `color`'s Units minimise-losses: pour onto the unit nearest death
## (highest current damage, lowest remaining) so each kill is "paid for" before the
## next Unit is touched. Then prune the dead.
static func _apply_hits_minimise(cell: HexCell, color: StringName, hits: int) -> void:
	var arr: Array = cell.units_for(color)
	var bonus := _ground_defense_bonus(cell, color)
	var remaining := hits
	while remaining > 0 and not arr.is_empty():
		# Find the unit closest to dying (smallest remaining HP), tie-break by order.
		# Effective HP = base Defense + controlled-ground / Shield-Drone bonus.
		var best_i := -1
		var best_remaining := 1 << 30
		for i in range(arr.size()):
			var u = arr[i]
			var def: int = (u["data"].defense if u["data"] != null else 1) + bonus
			var rem: int = def - int(u.get("damage", 0))
			if rem > 0 and rem < best_remaining:
				best_remaining = rem
				best_i = i
		if best_i == -1:
			break
		var unit = arr[best_i]
		var def2: int = (unit["data"].defense if unit["data"] != null else 1) + bonus
		var need: int = def2 - int(unit.get("damage", 0))
		var apply: int = min(need, remaining)
		unit["damage"] = int(unit.get("damage", 0)) + apply
		remaining -= apply
	_prune_dead_for(cell, color)


## Remove `color`'s Units whose damage >= their EFFECTIVE Defense (base + controlled-
## ground / Shield-Drone bonus). Per Corin's ruling (2026-06-18) environmental attacks
## DO respect that +1 — controlled ground and drones protect against room hazards too,
## matching combat's death rule (CombatResolver._ground_defense_bonus).
static func _prune_dead_for(cell: HexCell, color: StringName) -> void:
	if not cell.units.has(color):
		return
	var bonus := _ground_defense_bonus(cell, color)
	var survivors := []
	for u in cell.units[color]:
		var def: int = (u["data"].defense if u["data"] != null else 1) + bonus
		if int(u.get("damage", 0)) < def:
			survivors.append(u)
	if survivors.is_empty():
		cell.units.erase(color)
	else:
		cell.units[color] = survivors


# ---------------------------------------------------------------------------
#  Spawns / placement / draws
# ---------------------------------------------------------------------------

## Place one Guardian from the pool onto `cell` under the guardian owner. Returns the
## spawned unit-dict or null if no Guardian is available. Uses the deps rng to pick.
static func _spawn_guardian_here(state, cell: HexCell, deps: Dictionary):
	var pool: Array = deps.get("guardian_pool", [])
	var rng = deps.get("rng")
	if pool.is_empty() or rng == null:
		return null
	var gdata = pool[rng.randi_range(0, pool.size() - 1)]
	var unit := {"data": gdata, "damage": 0}
	cell.add_unit(GUARDIAN_OWNER, unit)
	_emit(state, "guardian_spawned", [gdata, cell.coord])
	return unit


## Place `n` supply Units of `unit_id` onto `cell` under `color`'s control. Returns the
## number actually placed (0 if the unit isn't in the db).
static func _place_supply_units(state, cell: HexCell, color: StringName, unit_id: StringName, n: int, deps: Dictionary) -> int:
	var db: Dictionary = deps.get("unit_db", {})
	var data = db.get(unit_id, null)
	if data == null:
		return 0
	for _i in range(n):
		cell.add_unit(color, {"data": data, "damage": 0})
	return n


## Draw `draw_n` Action cards, keep all but `discard_n`, append kept to the player's
## hand, send discards to the discard pile. Returns the number kept. Degrades to a
## no-op if no draw_action dep is provided.
static func _draw_and_discard(deps: Dictionary, color: StringName, draw_n: int, discard_n: int, state) -> int:
	var draw = deps.get("draw_action")
	if draw == null or not (draw is Callable) or not draw.is_valid():
		return 0
	var drawn := []
	for _i in range(draw_n):
		var c = draw.call()
		if c != null:
			drawn.append(c)
	# Discard the first `discard_n` (UI would let the player choose; headless keeps it
	# deterministic — the UI layer can swap in a chooser later).
	var p = state.get_player(color)
	var discarded := 0
	while discarded < discard_n and not drawn.is_empty():
		var c2 = drawn.pop_front()
		_call(deps.get("discard_action"), [c2])
		discarded += 1
	if p != null:
		for c3 in drawn:
			p.hand.append(c3)
	return drawn.size()


# ---------------------------------------------------------------------------
#  Small utilities
# ---------------------------------------------------------------------------

static func _accumulate_damage(log: Dictionary, color: StringName, hits: int) -> void:
	if hits <= 0:
		return
	var d: Dictionary = log["damage"]
	d[color] = int(d.get(color, 0)) + hits


static func _record(log: Dictionary, eid: StringName, summary: String, extra: Dictionary = {}) -> void:
	var entry := {"effect_id": eid, "summary": summary}
	for k in extra.keys():
		entry[k] = extra[k]
	log["resolved"].append(entry)


## Call an optional Callable dep safely. Returns the call result, or null if the dep is
## missing/invalid. Keeps every dep optional so headless tests supply only what they need.
static func _call(cb, args: Array):
	if cb == null or not (cb is Callable) or not cb.is_valid():
		return null
	match args.size():
		0: return cb.call()
		1: return cb.call(args[0])
		2: return cb.call(args[0], args[1])
	return null


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

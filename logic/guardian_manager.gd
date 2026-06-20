extends RefCounted
class_name GuardianManager
## Guardian bag, spawning, and automated movement (Section D, steps 5-6 + Ch.11).
##
## Holds the Guardian-phase state that GameState/FSM doesn't: the Guardian BAG and
## the live list of Guardians on the board. Pure logic, scene-free, seeded.
##
## BAG (rulebook Ch.11): 8 Guardians + 4 Scrap.
##   * Spawning draws one token. A Guardian goes to the Central Chamber; Scrap goes
##     straight back into the bag (so a spawn can "fizzle").
##   * When a Guardian dies it returns to the bag and drops an Old Tech token where
##     it died.
##   * [CHANGE] If the bag has NO Guardians left to draw, SKIP further spawn draws
##     until a Guardian is killed (which returns one to the bag). We implement this
##     by checking guardian-count-in-bag before drawing, not by drawing-and-praying.
##
## Guardians live on their cell under the reserved owner key &"guardian", in the
## same {data, damage} unit shape every other unit uses, so the CombatResolver and
## ActionResolver treat them uniformly.

const GUARDIAN_OWNER := &"guardian"
const SCRAP := &"scrap"

## The bag as a multiset Array. Guardian entries are GuardianData resources; Scrap
## entries are the SCRAP StringName.
var bag: Array = []
var rng := RandomNumberGenerator.new()

## Fix H: when true, guardian-vs-player combats are NOT resolved inline. The cells
## where a guardian made contact are collected in `pending_combats` (Array of
## {coord}) for the caller (GameController) to run INTERACTIVELY. Default false keeps
## the sync (GUT-tested) behaviour: combat resolves inline as before.
var defer_combats: bool = false
var pending_combats: Array = []


## Build the bag from the 8 Guardian resources + 4 Scrap. `guardian_pool` is an
## Array of GuardianData (the .tres). Headless rules tests may pass a small pool;
## the live game passes all 8.
func _init(guardian_pool: Array = [], seed: int = 0) -> void:
	rng.seed = seed
	bag.clear()
	for g in guardian_pool:
		bag.append(g)
	for _i in range(4):
		bag.append(SCRAP)


func guardians_in_bag() -> int:
	var n := 0
	for e in bag:
		if e is Resource:
			n += 1
	return n


# ---------------------------------------------------------------------------
#  Spawning
# ---------------------------------------------------------------------------

## Spawn `count` Guardians into the Central Chamber, honouring the bag rules.
## Returns the Array of spawned guardian unit-dicts (may be shorter than `count`
## if the bag fizzles on Scrap or runs out of Guardians). Mutates the center cell.
func spawn_into_center(state, count: int) -> Array:
	var center_cell: HexCell = state.get_cell(state.center)
	var spawned := []
	for _i in range(count):
		# Skip-if-empty: no Guardians in the bag -> no more spawns this phase.
		if guardians_in_bag() == 0:
			break
		var token = _draw()
		# Scrap entries are the SCRAP StringName; Guardians are Resources. Compare by
		# TYPE, not value: `resource == StringName` THROWS in Godot 4 ("Invalid
		# operands Object and StringName"), so never use == across those types.
		if not (token is Resource):
			bag.append(SCRAP)   # Scrap goes straight back in; this draw fizzles
			continue
		# A Guardian: place it on the center cell.
		var unit := {"data": token, "damage": 0}
		center_cell.add_unit(GUARDIAN_OWNER, unit)
		spawned.append(unit)
		_emit(state, "guardian_spawned", [token, state.center])
	return spawned


## Spawn one Guardian into an arbitrary `coord` (Guardian Control Room, Ch.13). Draws
## from the same bag with the same skip-if-empty rule; Scrap fizzles the draw. Returns
## the spawned unit dict, or null if none was placed.
func spawn_into_cell(state, coord: HexCoord):
	var cell: HexCell = state.get_cell(coord)
	if cell == null or guardians_in_bag() == 0:
		return null
	var token = _draw()
	if not (token is Resource):
		bag.append(SCRAP)
		return null
	var unit := {"data": token, "damage": 0}
	cell.add_unit(GUARDIAN_OWNER, unit)
	_emit(state, "guardian_spawned", [token, coord])
	return unit


func _draw():
	var idx := rng.randi_range(0, bag.size() - 1)
	var token = bag[idx]
	bag.remove_at(idx)
	return token


## A Guardian died on `coord`: return its token to the bag, and (unless suppressed)
## drop an Old Tech token there. `drop_old_tech` is false when the caller already
## dropped it via ActionResolver.finish_combat (the interactive combat path), so Old
## Tech isn't doubled.
func on_guardian_death(state, guardian_unit: Dictionary, coord: HexCoord, drop_old_tech: bool = true) -> void:
	bag.append(guardian_unit["data"])
	if not drop_old_tech:
		return
	var cell: HexCell = state.get_cell(coord)
	if cell != null:
		cell.old_tech += 1
		_emit(state, "old_tech_captured", [GUARDIAN_OWNER, coord])


# ---------------------------------------------------------------------------
#  Guardian-phase orchestration
# ---------------------------------------------------------------------------

## The full Guardian-phase movement step (rulebook Ch.10 step 2):
##   * If any player has reached the Central Chamber, spawn 1 Guardian there.
##   * Then move EVERY Guardian: roll one die per green Move, one die at a time,
##     each die picks a direction; if it moves into a space with Units it Attacks
##     them and STOPS.
## `do_spawn` controls the built-in per-phase spawn. The interactive controller does
## its own spawn (1, or 2 once the centre is breached — the new rule) and passes
## false; the headless FSM keeps the original spawn-if-anyone-reached behaviour.
func run_guardian_movement(state, do_spawn: bool = true) -> void:
	if do_spawn and _anyone_reached_center(state):
		spawn_into_center(state, 1)
	for entry in _all_guardian_locations(state):
		_move_one_guardian(state, entry["coord"], entry["unit"])


## Has any player a unit on the Central Chamber? (Triggers the per-round +1 spawn.)
func _anyone_reached_center(state) -> bool:
	var center_cell: HexCell = state.get_cell(state.center)
	if center_cell == null:
		return false
	for owner in center_cell.units.keys():
		if owner != GUARDIAN_OWNER and not center_cell.units[owner].is_empty():
			return true
	return false


## Move one Guardian up to its green Move, one doorway step at a time in a RANDOM
## direction (rulebook Ch.10: "roll a die per green Move and move it in the indicated
## direction, one die at a time"); attack-and-stop on contact. Direction is the seeded
## rng among the cell's valid doorway exits, so Guardians wander rather than hunt.
func _move_one_guardian(state, from_coord: HexCoord, unit: Dictionary) -> void:
	var data = unit["data"]
	var steps: int = data.move if data != null else 1
	var cur: HexCoord = from_coord
	# If the Guardian already SHARES its space with player Units, it fights there and
	# does NOT move (you can't move out of a space holding enemies — same rule as
	# players). The Ox's move-through is handled via moves_through_enemies.
	var start_cell: HexCell = state.get_cell(cur)
	var moves_through: bool = data != null and data.get("moves_through_enemies")
	if start_cell != null and _has_player_units(start_cell) and not moves_through:
		_guardian_attack(state, start_cell, cur)
		return
	for _i in range(steps):
		var cell: HexCell = state.get_cell(cur)
		# Guardian movement uses Blink-style adjacency only if it can pass walls.
		var can_blink: bool = data != null and data.get("moves_through_walls")
		var next = _step_random(state, cur, can_blink)   # random doorway step; may be null
		if next == null:
			break   # nowhere to go
		# Move the guardian one step.
		cell.remove_unit(GUARDIAN_OWNER, unit)
		var next_cell: HexCell = state.get_cell(next)
		next_cell.add_unit(GUARDIAN_OWNER, unit)
		_emit(state, "unit_moved", [unit, cur, next])
		cur = next
		# If the space now holds player Units, attack. The Ox (attacks_on_move) rolls its
		# dice at them and KEEPS MOVING (ploughing through); every other Guardian STOPS.
		if _has_player_units(next_cell):
			var attacks_through: bool = data != null and data.get("attacks_on_move")
			if attacks_through:
				_guardian_attack(state, next_cell, next)
				# The Ox may have been the only force and survived; if the cell still holds
				# the Ox, continue moving. If the Ox died (unlikely on its own turn) the
				# guardian was pruned from the cell — stop.
				if not next_cell.units_for(GUARDIAN_OWNER).has(unit):
					break
				# Continue the loop (do NOT break) so the Ox keeps stepping.
			else:
				_guardian_attack(state, next_cell, next)
				break

	# Arachnid (range >= 2): AFTER it moves, it Attacks one space within Range (Ch.12).
	# "Shoots around corners" => no line of sight; range is hex distance. This fires in
	# ADDITION to any melee it triggered above (it shoots even if it didn't stop on Units).
	var rng_v: int = data.range if data != null else 1
	if rng_v >= 2:
		_arachnid_ranged_attack(state, cur, unit, rng_v)


## Pick a RANDOM next hex one doorway step from `from_coord` (rulebook: the die roll
## chooses a direction). We roll among the cell's valid doorway exits via the seeded
## rng; if the cell has no exits the Guardian stays put (returns null). Deterministic
## for a given seed because it draws from the same rng stream.
func _step_random(state, from_coord: HexCoord, can_blink: bool):
	var one_step := {
		"move": 1, "moves_through_enemies": true, "can_blink": can_blink,
		"owner": GUARDIAN_OWNER,
	}
	var neighbours: Array = HexGraph.reachable(state.board, from_coord, one_step)
	if neighbours.is_empty():
		return null
	# Sort for determinism, then pick one at random from the seeded rng.
	neighbours.sort_custom(func(a, b): return a.key() < b.key())
	var idx: int = rng.randi_range(0, neighbours.size() - 1)
	return neighbours[idx]


## Arachnid's after-move ranged attack (Ch.12). From `from_coord`, find every board space
## within `rng_v` hex distance that holds player Units. If none, nothing happens. If several,
## roll the seeded rng to choose ONE. Roll the Arachnid's Attack dice at that space; if it
## holds Units from multiple players, divide the hits EVENLY across those players, rounded UP.
func _arachnid_ranged_attack(state, from_coord: HexCoord, unit: Dictionary, rng_v: int) -> void:
	var data = unit["data"]
	# Candidate target spaces: any cell within range holding player Units (not the Arachnid's
	# own space — it's a ranged shot at a DIFFERENT space).
	var targets: Array = []
	for k in state.board.keys():
		var coord: HexCoord = HexCoord.from_key(k)
		if coord.equals(from_coord):
			continue
		if from_coord.distance_to(coord) > rng_v:
			continue
		var cell: HexCell = state.board[k]
		if cell != null and _has_player_units(cell):
			targets.append(coord)
	if targets.is_empty():
		return
	# Choose one deterministically-at-random (sort for stability, then seeded pick).
	targets.sort_custom(func(a, b): return a.key() < b.key())
	var pick: HexCoord = targets[rng.randi_range(0, targets.size() - 1)]
	var target_cell: HexCell = state.get_cell(pick)
	if target_cell == null:
		return
	# Which players have Units there?
	var player_sides: Array = []
	for owner in target_cell.units.keys():
		if owner != GUARDIAN_OWNER and not target_cell.units[owner].is_empty():
			player_sides.append(owner)
	if player_sides.is_empty():
		return
	# Roll the Arachnid's Attack dice ONCE (its attack_dice; 4/5/6 hit, 6 crit-chains).
	var dice: int = data.attack_dice if data != null else 1
	var total_hits: int = _roll_guardian_dice(dice, data)
	if total_hits <= 0:
		_emit(state, "guardian_ranged_attack", [pick, 0])
		return
	# Divide hits evenly across the players present, rounded UP (Ch.12). Each player's
	# defender assigns its own share minimise-losses; prune the dead.
	var n: int = player_sides.size()
	var per: int = int(ceil(float(total_hits) / float(n)))
	for side in player_sides:
		_apply_hits_to_side(target_cell, side, per)
	_prune_dead_and_handle_guardians(state, target_cell, pick)
	_emit(state, "guardian_ranged_attack", [pick, total_hits])


## Roll `dice` Attack dice with this Guardian's crit/hit profile (4/5/6 hit, crit_face grants
## a bonus die that chains; hit_only_on overrides the hit floor). Mirrors CombatResolver's
## rule so guardian ranged dice behave identically. Bounded against a pathological rng.
func _roll_guardian_dice(dice: int, data) -> int:
	if dice <= 0:
		return 0
	var crit_face: int = 6
	if data != null and int(data.get("crit_on")) > 0:
		crit_face = int(data.get("crit_on"))
	var hit_floor: int = 4
	if data != null and int(data.get("hit_only_on")) > 0:
		hit_floor = int(data.get("hit_only_on"))
	var hits: int = 0
	var pending: int = dice
	var guard: int = 0
	while pending > 0 and guard < 10000:
		pending -= 1
		guard += 1
		var face: int = rng.randi_range(1, 6)
		if face >= hit_floor:
			hits += 1
		if face >= crit_face:
			pending += 1
	return hits


## Assign `hits` to `side`'s Units in `cell`, minimise-losses (stack onto the unit nearest
## death), against EFFECTIVE Defense (base + controlled-ground/drone). Writes damage onto the
## live unit dicts; pruning is done by the caller.
func _apply_hits_to_side(cell: HexCell, side: StringName, hits: int) -> void:
	var bonus: int = _ground_defense_bonus(cell, side)
	var remaining: int = hits
	while remaining > 0:
		var arr: Array = cell.units_for(side)
		var best_i: int = -1
		var best_remaining: int = 1 << 30
		for i in range(arr.size()):
			var u = arr[i]
			var def: int = (u["data"].defense if u["data"] != null else 1) + bonus
			var rem: int = def - int(u.get("damage", 0))
			if rem > 0 and rem < best_remaining:
				best_remaining = rem
				best_i = i
		if best_i == -1:
			break
		var unit_dict = arr[best_i]
		var def2: int = (unit_dict["data"].defense if unit_dict["data"] != null else 1) + bonus
		var need: int = def2 - int(unit_dict.get("damage", 0))
		var apply: int = int(min(need, remaining))
		unit_dict["damage"] = int(unit_dict.get("damage", 0)) + apply
		remaining -= apply


## Ground-defense bonus for `side` on `cell`: +1 controlled-ground, +1 per Shield Drone
## (stack), matching CombatResolver._ground_defense_bonus and ActionResolver._prune_dead.
func _ground_defense_bonus(cell: HexCell, side: StringName) -> int:
	var bonus: int = 0
	if cell.get_token_state(side) == HexCell.TokenState.CONTROL:
		bonus += 1
	for owner in cell.units.keys():
		for u in cell.units[owner]:
			if u["data"] != null and u["data"].get("grants_ground_defense"):
				bonus += 1
	return bonus


## Guardian attacks the player Units in `cell`: a one-side combat where the
## Guardian is the entering side. Reuses the CombatResolver.
func _guardian_attack(state, cell: HexCell, coord: HexCoord) -> void:
	var sides: Array = []
	var units_by_owner: Dictionary = {}
	for owner in cell.units.keys():
		if cell.units[owner].is_empty():
			continue
		sides.append(owner)
		units_by_owner[owner] = cell.units[owner]
	if sides.size() < 2:
		return
	# Fix H: hand the fight to the caller for interactive per-round resolution. The
	# guardian still STOPPED here (movement already ended on contact); only the
	# resolution is deferred, so behaviour is otherwise unchanged.
	if defer_combats:
		pending_combats.append({"coord": coord})
		return
	# Build the FULL combat context (control +1, Shield Drones, Darkness, Sunstone) the same
	# way the player and interactive-guardian paths do, so a defender's footing matters here
	# too. build_combat_context reads `cell` directly, so the Guardian (entering side) and the
	# players are all picked up.
	var ctx: Dictionary = ActionResolver.build_combat_context(state, cell, GUARDIAN_OWNER, {})
	if ctx.is_empty():
		return
	var resolver := CombatResolver.new()
	var log: Array = resolver.resolve(ctx)
	# Prune dead. A dead Guardian returns to the bag and drops Old Tech here.
	_prune_dead_and_handle_guardians(state, cell, coord)
	_emit(state, "combat_resolved", [log])


func _prune_dead_and_handle_guardians(state, cell: HexCell, coord: HexCoord) -> void:
	for owner in cell.units.keys():
		var survivors := []
		var dead := []
		# Guardians get no ground bonus; players get controlled-ground / Shield-Drone +1.
		var bonus: int = 0 if owner == GUARDIAN_OWNER else _ground_defense_bonus(cell, owner)
		for u in cell.units[owner]:
			var base_def: int = (u["data"].defense if u["data"] != null else 1) + bonus
			if u.get("damage", 0) < base_def:
				survivors.append(u)
			else:
				dead.append(u)
		if owner == GUARDIAN_OWNER:
			for d in dead:
				on_guardian_death(state, d, coord)
		if survivors.is_empty():
			cell.units.erase(owner)
		else:
			cell.units[owner] = survivors


# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------

func _has_player_units(cell: HexCell) -> bool:
	for owner in cell.units.keys():
		if owner != GUARDIAN_OWNER and not cell.units[owner].is_empty():
			return true
	return false


func _all_guardian_locations(state) -> Array:
	var out := []
	for k in state.board.keys():
		var cell: HexCell = state.board[k]
		for u in cell.units_for(GUARDIAN_OWNER):
			out.append({"coord": HexCoord.from_key(k), "unit": u})
	return out


func _emit(state, signal_name: String, args: Array) -> void:
	var bus = null
	if state != null and state.has_method("get_tree") and state.get_tree() != null:
		bus = state.get_tree().root.get_node_or_null("EventBus")
	if bus == null:
		return
	if not bus.has_signal(signal_name):
		return
	match args.size():
		0: bus.emit_signal(signal_name)
		1: bus.emit_signal(signal_name, args[0])
		2: bus.emit_signal(signal_name, args[0], args[1])
		3: bus.emit_signal(signal_name, args[0], args[1], args[2])

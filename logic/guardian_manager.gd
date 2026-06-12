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


func _draw():
	var idx := rng.randi_range(0, bag.size() - 1)
	var token = bag[idx]
	bag.remove_at(idx)
	return token


## A Guardian died on `coord`: return its token to the bag and drop Old Tech there.
func on_guardian_death(state, guardian_unit: Dictionary, coord: HexCoord) -> void:
	bag.append(guardian_unit["data"])
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
func run_guardian_movement(state) -> void:
	if _anyone_reached_center(state):
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


## Move one Guardian up to its green Move, one doorway step at a time toward the
## nearest enemy Units; attack-and-stop on contact. Automated targeting: head for
## the closest player unit by doorway distance (deterministic tie-break by hexkey).
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
		var next = _step_toward_prey(state, cur, can_blink)   # may be null; untyped on purpose
		if next == null:
			break   # nowhere to go
		# Move the guardian one step.
		cell.remove_unit(GUARDIAN_OWNER, unit)
		var next_cell: HexCell = state.get_cell(next)
		next_cell.add_unit(GUARDIAN_OWNER, unit)
		_emit(state, "unit_moved", [unit, cur, next])
		cur = next
		# If the space now holds player Units, attack and STOP.
		if _has_player_units(next_cell):
			_guardian_attack(state, next_cell, next)
			break


## Choose the next hex one step toward the nearest player unit. Returns null if
## the Guardian can't reach any prey.
func _step_toward_prey(state, from_coord: HexCoord, can_blink: bool):
	var abilities := {
		"move": 99, "moves_through_enemies": true, "can_blink": can_blink,
		"owner": GUARDIAN_OWNER,
	}
	# Find the closest player-occupied hex by doorway distance.
	var best_target = null
	var best_dist := 1 << 30
	for k in state.board.keys():
		var c: HexCell = state.board[k]
		if not _has_player_units(c):
			continue
		var goal: HexCoord = HexCoord.from_key(k)
		var d := HexGraph.path_distance(state.board, from_coord, goal, abilities)
		if d > 0 and (d < best_dist or (d == best_dist and (best_target == null or k < best_target.key()))):
			best_dist = d
			best_target = goal
	if best_target == null:
		return null
	# Take the first step on a shortest path toward that target: pick the immediate
	# neighbour that MINIMISES remaining doorway distance to best_target, with a
	# deterministic hexkey tie-break so a seed reproduces exactly.
	var one_step := {
		"move": 1, "moves_through_enemies": true, "can_blink": can_blink,
		"owner": GUARDIAN_OWNER,
	}
	var neighbours := HexGraph.reachable(state.board, from_coord, one_step)
	var chosen = null
	var chosen_remaining := 1 << 30
	for n in neighbours:
		var nd := HexGraph.path_distance(state.board, n, best_target, abilities)
		if nd < 0:
			continue
		if nd < chosen_remaining or (nd == chosen_remaining and (chosen == null or n.key() < chosen.key())):
			chosen = n
			chosen_remaining = nd
	return chosen


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
	var combatants := CombatResolver.combatants_from_units(units_by_owner)
	var resolver := CombatResolver.new()
	var log: Array = resolver.resolve({
		"sides": sides,
		"combatants": combatants,
		"controller": &"",
		"extra_defense": {},
		"entering_side": GUARDIAN_OWNER,
		"rng": state.rng,
	})
	# Prune dead. A dead Guardian returns to the bag and drops Old Tech here.
	_prune_dead_and_handle_guardians(state, cell, coord)
	_emit(state, "combat_resolved", [log])


func _prune_dead_and_handle_guardians(state, cell: HexCell, coord: HexCoord) -> void:
	for owner in cell.units.keys():
		var survivors := []
		var dead := []
		for u in cell.units[owner]:
			var base_def: int = u["data"].defense if u["data"] != null else 1
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
	match args.size():
		0: bus.emit_signal(signal_name)
		1: bus.emit_signal(signal_name, args[0])
		2: bus.emit_signal(signal_name, args[0], args[1])
		3: bus.emit_signal(signal_name, args[0], args[1], args[2])

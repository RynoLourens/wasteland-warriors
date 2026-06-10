extends RefCounted
class_name HexGraph
## Movement over the board as a graph with DYNAMIC edges (Section B, step 4).
##
## Movement in Wasteland Warriors is not plain hex distance — the legal moves
## depend on unit abilities and board state, so we treat it as a reachability
## search where each edge is enabled/disabled per query:
##   * You can only move between two tiles if BOTH share an open exit (a real
##     doorway) — UNLESS the unit can Blink (crosses walls) or both tiles are
##     Teleporters (adjacent to all other teleporters).
##   * You cannot move THROUGH a tile containing enemy units (it blocks
##     pass-through) — unless the unit can move_through_enemies (Infiltrator).
##   * Tough Terrain STOPS movement: you may enter it but not continue past it
##     in the same move.
##   * "Distance" is the number of doorway steps, bounded by the unit's Move.
##
## This class is pure logic: give it a board, a unit's abilities, and a start
## hex, and it returns the set of reachable hexes. No scenes, fully testable.

const TELEPORTER_EFFECT := &"teleporter_node"   ## env effect id flagging a teleporter
const TOUGH_TERRAIN_EFFECT := &"tough_terrain"  ## env effect id that stops movement


## Reachable hexes for a unit moving from `start`, given its Move budget and
## ability flags. Returns Array of HexCoord (excluding `start`).
##
## `unit_abilities` is a small Dictionary so we don't depend on the UnitData
## class here:
##   {
##     "move": int,                       # blue Move number
##     "moves_through_enemies": bool,     # Infiltrator
##     "can_blink": bool,                 # crosses walls (ignores open-exit need)
##     "owner": StringName,               # whose unit (to know which units are enemies)
##   }
static func reachable(board: Dictionary, start: HexCoord, unit_abilities: Dictionary) -> Array:
	var move_budget: int = unit_abilities.get("move", 1)
	var owner: StringName = unit_abilities.get("owner", &"")
	var through_enemies: bool = unit_abilities.get("moves_through_enemies", false)
	var can_blink: bool = unit_abilities.get("can_blink", false)

	# Precompute teleporter hexes once.
	var teleporters := _teleporter_hexes(board)

	# Dijkstra/BFS over doorway steps up to move_budget.
	var best := {start.key(): 0}        # hexkey -> steps used
	var frontier := [start]
	var result := []

	while not frontier.is_empty():
		var cur: HexCoord = frontier.pop_front()
		var cur_key := cur.key()
		var steps_here: int = best[cur_key]
		if steps_here >= move_budget:
			continue

		# Tough Terrain stops movement: you can land on it, but not move FURTHER
		# from it in the same activation. So we don't expand out of it.
		if not cur.equals(start) and _cell_has_effect(board, cur, TOUGH_TERRAIN_EFFECT):
			continue

		var nbrs := _adjacent(board, cur, teleporters, can_blink)
		for n in nbrs:
			var n_key: String = n.key()
			if not board.has(n_key):
				continue
			var ncell: HexCell = board[n_key]

			# Enemy-occupied tiles block pass-through. You may move INTO one only
			# if it's your destination (handled by the activation/combat rules,
			# not here) — for pure movement reachability, an enemy tile is a wall
			# unless the unit can move through enemies.
			var enemy_here: bool = ncell.has_enemy_units(owner)
			if enemy_here and not through_enemies:
				continue

			var new_steps := steps_here + 1
			if not best.has(n_key) or new_steps < best[n_key]:
				best[n_key] = new_steps
				result.append(n)
				if new_steps < move_budget:
					frontier.append(n)

	# Dedupe (a hex can be appended via two paths before best[] settles).
	return _dedupe(result, start)


## Doorway distance between two hexes for this unit (number of steps), or -1 if
## unreachable within a large cap. Useful for AI scoring later.
static func path_distance(board: Dictionary, start: HexCoord, goal: HexCoord, unit_abilities: Dictionary) -> int:
	var owner: StringName = unit_abilities.get("owner", &"")
	var through_enemies: bool = unit_abilities.get("moves_through_enemies", false)
	var can_blink: bool = unit_abilities.get("can_blink", false)
	var teleporters := _teleporter_hexes(board)

	var dist := {start.key(): 0}
	var queue := [start]
	while not queue.is_empty():
		var cur: HexCoord = queue.pop_front()
		if cur.equals(goal):
			return dist[cur.key()]
		for n in _adjacent(board, cur, teleporters, can_blink):
			var nk: String = n.key()
			if not board.has(nk) or dist.has(nk):
				continue
			var ncell: HexCell = board[nk]
			if ncell.has_enemy_units(owner) and not through_enemies and not n.equals(goal):
				continue
			dist[nk] = dist[cur.key()] + 1
			queue.append(n)
	return -1


# --- Adjacency (the dynamic-edge core) ----------------------------------------

## Hexes one doorway-step from `cur`: open-exit neighbours (both sides open),
## plus all other teleporters if `cur` is a teleporter, plus all neighbours if
## the unit can Blink (walls ignored). Only returns coords that are on the board.
static func _adjacent(board: Dictionary, cur: HexCoord, teleporters: Array, can_blink: bool) -> Array:
	var out := []
	var cur_key := cur.key()
	if not board.has(cur_key):
		return out
	var cell: HexCell = board[cur_key]

	for dir in range(6):
		var n: HexCoord = cur.neighbor(dir)
		if not board.has(n.key()):
			continue
		if can_blink:
			out.append(n)  # walls ignored
			continue
		# Normal: need a matched doorway (both tiles open on the shared edge).
		var ncell: HexCell = board[n.key()]
		if cell.has_exit(dir) and ncell.has_exit(HexCoord.opposite_dir(dir)):
			out.append(n)

	# Teleporter network: a teleporter is adjacent to every OTHER teleporter.
	if _coord_in(teleporters, cur):
		for t in teleporters:
			if not t.equals(cur):
				out.append(t)

	return out


# --- Helpers ------------------------------------------------------------------

static func _teleporter_hexes(board: Dictionary) -> Array:
	var out := []
	for k in board.keys():
		var cell: HexCell = board[k]
		if cell.has_token_effect(TELEPORTER_EFFECT, true):
			out.append(HexCoord.from_key(k))
	return out


static func _cell_has_effect(board: Dictionary, coord: HexCoord, effect_id: StringName) -> bool:
	if not board.has(coord.key()):
		return false
	var cell: HexCell = board[coord.key()]
	return cell.has_token_effect(effect_id, true)


static func _coord_in(arr: Array, c: HexCoord) -> bool:
	for x in arr:
		if x.equals(c):
			return true
	return false


static func _dedupe(arr: Array, exclude: HexCoord) -> Array:
	var seen := {}
	var out := []
	for c in arr:
		var k: String = c.key()
		if k == exclude.key() or seen.has(k):
			continue
		seen[k] = true
		out.append(c)
	return out

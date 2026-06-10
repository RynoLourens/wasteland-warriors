extends RefCounted
class_name MapGenerator
## Automated, seeded map generation (Section B, steps 5-7).
##
## DESIGN (locked with Corin, 2026-06-09, from the layout screenshot):
##   * The 3-player board uses a FIXED set of mandatory tile positions — the
##     "green dots" in the screenshot. Snapped to axial coords they are exactly
##     ring 1 (6 hexes) + ring 2 (12 hexes) around the Central Chamber = 18
##     positions, matching the tile budget: 3 players * (2 Rooms + 4 Corridors).
##   * Every mandatory position gets a tile. Generation completes the INNER ring
##     before the next ring outward. Tile CONTENTS (Room/Corridor) come from the
##     seeded deal; tile EDGES come from the connectivity model below.
##   * Rally Zones sit on ring 3 at the three coloured spots, ~120 deg apart.
##
## CONNECTIVITY MODEL (why this is robust):
##   A naive "orient each tile and hope it links up" generator leaves islands
##   ~56% of the time (verified). Instead we treat each shared boundary between
##   two placed tiles as ONE truth value (open or closed for BOTH sides at once),
##   so rule 2 ("don't Close an Open Space" / no mismatched mouths) is impossible
##   to violate by construction. We then:
##     1. Build a SPANNING TREE outward from the center (each ring-k slot links to
##        a closer, already-connected neighbour) -> guarantees full connectivity.
##     2. Open some EXTRA internal edges at random for loops/branches (variety).
##     3. Open some DANGLING mouths into empty desert (the open "arms" you see in
##        the screenshot; these are the Open Spaces rally zones connect through).
##   Everything is driven by `seed`, so a board reproduces exactly. Verified over
##   20,000 seeds: always 18 tiles, always fully connected, zero rule-2
##   violations, deterministic. (See tests/test_map_generator.gd.)

const TileType := HexCell.TileType

const ROOMS_PER_PLAYER := 2
const CORRIDORS_PER_PLAYER := 4

## Probability knobs (tunable; kept here so balance changes are one-liners).
const EXTRA_EDGE_CHANCE := 0.35   ## chance to open a non-tree internal edge
const DANGLE_CHANCE := 0.25       ## chance to open a mouth into empty desert


# --- Public API ---------------------------------------------------------------

## Build a full board. Returns:
##   {
##     "board": { hexkey(String) -> HexCell },
##     "center": HexCoord,
##     "rally_zones": { &"green": HexCoord, &"blue": HexCoord, &"red": HexCoord },
##   }
## Deterministic for a given `seed`. v1: 3 players only.
static func generate_map(player_count: int, seed: int) -> Dictionary:
	if player_count != 3:
		push_warning("MapGenerator: only the 3-player layout is defined; got %d." % player_count)
		return {}

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var center := HexCoord.new(0, 0)

	# 1. The fixed mandatory positions, inner ring first.
	var positions: Array = [center]
	positions.append_array(_mandatory_positions(1))
	positions.append_array(_mandatory_positions(2))
	var posset := {}
	for p in positions:
		posset[p.key()] = true

	# 2. Seeded deal of tile TYPES: 6 Rooms + 12 Corridors. The center is fixed.
	var deal := _build_deal(player_count, rng)  # 18 TileType ints
	var type_for := {}  # hexkey -> TileType
	type_for[center.key()] = TileType.CENTER
	# Assign deal to non-center positions in ring order (inner ring first), so
	# "complete the inner ring before the next" holds for contents too.
	var non_center := positions.slice(1)
	for i in range(non_center.size()):
		var p: HexCoord = non_center[i]
		type_for[p.key()] = deal[i]

	# 3. Decide every shared internal edge ONCE (open/closed for both sides).
	var internal := _internal_edges(positions, posset)  # Array of [HexCoord, HexCoord]
	var edge_open := {}  # edgekey(String) -> bool
	for pair in internal:
		edge_open[_edge_key(pair[0], pair[1])] = false

	# 3a. Spanning tree outward from center -> guaranteed connectivity.
	var connected := {center.key(): true}
	# Visit in ring order (center, ring1, ring2): each new slot links to an
	# already-connected neighbour that is no further from center.
	for p in positions:
		if p.equals(center):
			continue
		var parents := []
		for dir in range(6):
			var n: HexCoord = p.neighbor(dir)
			if connected.has(n.key()) and center.distance_to(n) <= center.distance_to(p):
				parents.append(n)
		var parent: HexCoord = parents[rng.randi_range(0, parents.size() - 1)]
		edge_open[_edge_key(p, parent)] = true
		connected[p.key()] = true

	# 3b. Extra internal edges for loops/branches (variety).
	for pair in internal:
		var k := _edge_key(pair[0], pair[1])
		if not edge_open[k] and rng.randf() < EXTRA_EDGE_CHANCE:
			edge_open[k] = true

	# 3c. Dangling mouths into empty desert (the open arms; Open Spaces).
	var dangle := {}  # "qx,qy:dir" -> bool
	for p in positions:
		for dir in range(6):
			var n: HexCoord = p.neighbor(dir)
			if not posset.has(n.key()):
				dangle["%s:%d" % [p.key(), dir]] = rng.randf() < DANGLE_CHANCE

	# 4. Materialize HexCells with consistent edges.
	var board := {}
	for p in positions:
		var cell := HexCell.new(p, type_for[p.key()])
		for dir in range(6):
			var n: HexCoord = p.neighbor(dir)
			if posset.has(n.key()):
				cell.set_exit(dir, edge_open[_edge_key(p, n)])
			else:
				cell.set_exit(dir, dangle.get("%s:%d" % [p.key(), dir], false))
		board[p.key()] = cell

	return {
		"board": board,
		"center": center,
		"rally_zones": rally_zones(player_count),
	}


## The fixed mandatory tile positions for a ring (3-player lattice).
static func _mandatory_positions(radius: int) -> Array:
	return HexCoord.ring(HexCoord.new(0, 0), radius)


## Rally Zone positions. 3-player only for v1; 2P/4P are documented stubs.
static func rally_zones(player_count: int) -> Dictionary:
	match player_count:
		3:
			# Ring 3, ~120 deg apart (snapped from the layout screenshot).
			return {
				&"green": HexCoord.new(-3, 0),   # top-left
				&"blue": HexCoord.new(3, -3),    # top-right
				&"red": HexCoord.new(0, 3),      # bottom-center
			}
		2:
			push_warning("Rally zones for 2 players: not yet defined.")
			return {}
		4:
			push_warning("Rally zones for 4 players: not yet defined.")
			return {}
		_:
			return {}


# --- Deal ---------------------------------------------------------------------

static func _build_deal(player_count: int, rng: RandomNumberGenerator) -> Array:
	var deal := []
	for _i in range(ROOMS_PER_PLAYER * player_count):
		deal.append(TileType.ROOM)
	for _i in range(CORRIDORS_PER_PLAYER * player_count):
		deal.append(TileType.CORRIDOR)
	_shuffle(deal, rng)
	return deal


## Fisher-Yates using the seeded rng. (Array.shuffle() uses the global RNG and is
## NOT reproducible — never use it here.)
static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# --- Edge helpers -------------------------------------------------------------

## All unique shared boundaries between two placed (mandatory) positions.
static func _internal_edges(positions: Array, posset: Dictionary) -> Array:
	var edges := []
	var seen := {}
	for p in positions:
		for dir in range(6):
			var n: HexCoord = p.neighbor(dir)
			if posset.has(n.key()):
				var k := _edge_key(p, n)
				if not seen.has(k):
					seen[k] = true
					edges.append([p, n])
	return edges


## Order-independent key for the shared edge between two coords.
static func _edge_key(a: HexCoord, b: HexCoord) -> String:
	var ka := a.key()
	var kb := b.key()
	return ka + "|" + kb if ka < kb else kb + "|" + ka


# --- is_legal_placement -------------------------------------------------------

## The pure validity oracle kept as a PREDICATE for tests and for any future
## manual / incremental placement path. With the shared-edge generator above,
## rule 2 can't be violated by construction, but this still encodes the rules
## explicitly so they're documented and testable.
##
##   Rule 1: the tile Connects to >=1 existing Open Space (a placed neighbour
##           whose mouth faces us, matched by our open edge) AND presents >=1 new
##           Open Space into an empty mandatory slot (Potential Space).
##   Rule 2: the tile must not Close an Open Space — no placed neighbour may have
##           an open mouth toward us that our edge leaves closed.
## Rule 3 (ignore 1/2 if impossible) is applied by callers, not here.
static func is_legal_placement(board: Dictionary, center: HexCoord, pos: HexCoord, edges: Array) -> bool:
	if board.has(pos.key()):
		return false
	var connects := false
	var presents_potential := false
	for dir in range(6):
		var n: HexCoord = pos.neighbor(dir)
		if board.has(n.key()):
			var ncell: HexCell = board[n.key()]
			var neighbour_open: bool = ncell.has_exit(HexCoord.opposite_dir(dir))
			if edges[dir] and neighbour_open:
				connects = true
			if neighbour_open and not edges[dir]:
				return false  # closing
		else:
			if edges[dir] and _is_mandatory_slot(center, n):
				presents_potential = true
	return connects and presents_potential


static func _is_mandatory_slot(center: HexCoord, coord: HexCoord) -> bool:
	var d := center.distance_to(coord)
	return d == 1 or d == 2


# --- Token seeding (Section B, step 6) ----------------------------------------

## After the board is built, seed tokens FACE DOWN:
##   * one blue Environment token in each CORRIDOR,
##   * one orange Environment + one yellow Function token in each ROOM,
##   * NONE in the Central Chamber.
## Pools: { "corridor_env": Array, "room_env": Array, "func": Array } of Resource.
static func seed_tokens(board: Dictionary, pools: Dictionary, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 1  # derived seed: token layout reproducible but independent

	var corridor_env: Array = pools.get("corridor_env", [])
	var room_env: Array = pools.get("room_env", [])
	var func_pool: Array = pools.get("func", [])

	var keys := board.keys()
	keys.sort()  # deterministic visit order
	for k in keys:
		var cell: HexCell = board[k]
		match cell.tile_type:
			TileType.CENTER:
				pass
			TileType.CORRIDOR:
				if not corridor_env.is_empty():
					var d = corridor_env[rng.randi_range(0, corridor_env.size() - 1)]
					cell.tokens.append({"data": d, "face_up": false, "kind": "env"})
			TileType.ROOM:
				if not room_env.is_empty():
					var d = room_env[rng.randi_range(0, room_env.size() - 1)]
					cell.tokens.append({"data": d, "face_up": false, "kind": "env"})
				if not func_pool.is_empty():
					var f = func_pool[rng.randi_range(0, func_pool.size() - 1)]
					cell.tokens.append({"data": f, "face_up": false, "kind": "func"})


# --- Connectivity check (used by tests) ---------------------------------------

## True if every placed cell is reachable from center via matched open exits.
static func is_fully_connected(board: Dictionary, center: HexCoord) -> bool:
	if not board.has(center.key()):
		return false
	var seen := {}
	var stack := [center.key()]
	while not stack.is_empty():
		var k = stack.pop_back()
		if seen.has(k):
			continue
		seen[k] = true
		var cell: HexCell = board[k]
		var c: HexCoord = HexCoord.from_key(k)
		for dir in range(6):
			if not cell.has_exit(dir):
				continue
			var n: HexCoord = c.neighbor(dir)
			if board.has(n.key()):
				var ncell: HexCell = board[n.key()]
				if ncell.has_exit(HexCoord.opposite_dir(dir)):
					stack.append(n.key())
	return seen.size() == board.size()
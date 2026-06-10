extends GutTest
## Map generation (Section B, steps 5-7). The headline test: generate many
## boards across seeds and assert EVERY one is legal, fully connected, the right
## size, and reproducible. Mirrors the Python verification run over 20k seeds.

const TileType := HexCell.TileType

# Keep the per-run seed count modest so the suite stays fast in the editor; the
# exhaustive 20k-seed sweep was run offline in Python. Bump locally if desired.
const SEED_COUNT := 1000


func test_board_size_is_lattice_19_plus_3_rally_fixtures() -> void:
	# Two contracts: the random builder produces the 19-cell lattice (center + 18),
	# and 3 Rally Zone FIXTURES are added on top -> 22 total board cells.
	var map := MapGenerator.generate_map(3, 12345)
	assert_eq(map.board.size(), 22, "1 center + 18 lattice + 3 rally fixtures")
	var center: HexCoord = map.center
	var lattice := 0
	for k in map.board.keys():
		if center.distance_to(HexCoord.from_key(k)) <= 2:
			lattice += 1
	assert_eq(lattice, 19, "the seeded lattice is exactly 19 cells (center + 18)")


func test_tile_budget_six_rooms_twelve_corridors() -> void:
	var map := MapGenerator.generate_map(3, 999)
	var rooms := 0
	var corridors := 0
	var centers := 0
	for k in map.board.keys():
		match map.board[k].tile_type:
			TileType.ROOM: rooms += 1
			TileType.CORRIDOR: corridors += 1
			TileType.CENTER: centers += 1
	assert_eq(centers, 1, "exactly one Central Chamber")
	# 6 lattice Rooms (2/player) + 3 Rally Zone Rooms = 9.
	assert_eq(rooms, 9, "6 lattice Rooms + 3 Rally Zone Rooms")
	assert_eq(corridors, 12, "12 Corridors (4 per player x3)")


func test_positions_are_the_mandatory_lattice() -> void:
	# Every placed tile must sit on rings 1-2 (the green-dot lattice) or be one of
	# the 3 ring-3 Rally Zone cells, plus the center; nothing else off-lattice.
	var map := MapGenerator.generate_map(3, 7)
	var center: HexCoord = map.center
	var rz := MapGenerator.rally_zones(3)
	var rz_keys := {}
	for color in rz.keys():
		rz_keys[rz[color].key()] = true
	for k in map.board.keys():
		var c := HexCoord.from_key(k)
		var d := center.distance_to(c)
		assert_true(d <= 2 or rz_keys.has(k),
			"tile %s within ring 2, or is a rally zone" % c)
	# And all 18 mandatory positions are filled.
	for radius in [1, 2]:
		for pos in HexCoord.ring(center, radius):
			assert_true(map.board.has(pos.key()),
				"mandatory slot %s is filled" % pos)
	# And all 3 rally-zone cells exist on the board.
	for color in rz.keys():
		assert_true(map.board.has(rz[color].key()),
			"rally zone %s is a real board cell" % color)


func test_every_board_is_fully_connected_and_legal() -> void:
	# The big one. Across many seeds, every board must be fully connected and
	# free of rule-2 (mismatched-mouth) violations.
	var center := HexCoord.new(0, 0)
	var failures := 0
	for s in range(SEED_COUNT):
		var map := MapGenerator.generate_map(3, s)
		if map.board.size() != 22:
			failures += 1
			continue
		if not MapGenerator.is_fully_connected(map.board, center):
			failures += 1
			continue
		if _has_rule2_violation(map.board):
			failures += 1
	assert_eq(failures, 0,
		"all %d seeded boards are legal & fully connected" % SEED_COUNT)


func test_generation_is_deterministic() -> void:
	var a := MapGenerator.generate_map(3, 555)
	var b := MapGenerator.generate_map(3, 555)
	assert_true(_boards_equal(a.board, b.board),
		"same seed produces an identical board")


func test_different_seeds_differ() -> void:
	var a := MapGenerator.generate_map(3, 1)
	var b := MapGenerator.generate_map(3, 2)
	assert_false(_boards_equal(a.board, b.board),
		"different seeds produce different boards")


func test_rally_zones_three_players() -> void:
	var rz := MapGenerator.rally_zones(3)
	assert_eq(rz.size(), 3, "three rally zones")
	assert_true(rz.has(&"green") and rz.has(&"blue") and rz.has(&"red"),
		"green/blue/red zones present")
	# All on ring 3, ~120 deg apart.
	var center := HexCoord.new(0, 0)
	for color in rz.keys():
		assert_eq(center.distance_to(rz[color]), 3,
			"%s rally zone on ring 3" % color)


func test_2p_4p_rally_zones_stubbed() -> void:
	assert_eq(MapGenerator.rally_zones(2).size(), 0, "2P not yet defined")
	assert_eq(MapGenerator.rally_zones(4).size(), 0, "4P not yet defined")


func test_center_has_no_tokens_after_seeding() -> void:
	var map := MapGenerator.generate_map(3, 88)
	# Use small non-empty pools so room/corridor cells DO get tokens, proving
	# the center is skipped specifically.
	var env_room := load("res://data/tokens/env_room_schematics.tres")
	var env_corr := load("res://data/tokens/env_corridor_supplies.tres")
	var fn := load("res://data/tokens/func_shield_drones.tres")
	var pools := {
		"corridor_env": [env_corr],
		"room_env": [env_room],
		"func": [fn],
	}
	MapGenerator.seed_tokens(map.board, pools, 88)
	var center_cell: HexCell = map.board[map.center.key()]
	assert_eq(center_cell.tokens.size(), 0, "Central Chamber never seeded")
	# Spot-check a room got 2 tokens and a corridor got 1.
	var room_ok := false
	var corr_ok := false
	for k in map.board.keys():
		var cell: HexCell = map.board[k]
		if cell.tile_type == TileType.ROOM and cell.tokens.size() == 2:
			room_ok = true
		if cell.tile_type == TileType.CORRIDOR and cell.tokens.size() == 1:
			corr_ok = true
	assert_true(room_ok, "a Room received env + function tokens")
	assert_true(corr_ok, "a Corridor received one env token")


func test_seeded_tokens_are_face_down() -> void:
	var map := MapGenerator.generate_map(3, 5)
	var env_corr := load("res://data/tokens/env_corridor_supplies.tres")
	MapGenerator.seed_tokens(map.board, {"corridor_env": [env_corr], "room_env": [], "func": []}, 5)
	for k in map.board.keys():
		for t in map.board[k].tokens:
			assert_false(t.face_up, "seeded tokens start face-down")


# --- is_legal_placement predicate (unit-level) ---

func test_is_legal_placement_rejects_occupied() -> void:
	var center := HexCoord.new(0, 0)
	var board := {center.key(): HexCell.new(center, TileType.CENTER)}
	board[center.key()].edges = [true, true, true, true, true, true]
	var edges := [true, false, false, false, false, false]
	assert_false(MapGenerator.is_legal_placement(board, center, center, edges),
		"can't place on an occupied hex")


func test_is_legal_placement_requires_connection_and_potential() -> void:
	var center := HexCoord.new(0, 0)
	var cc := HexCell.new(center, TileType.CENTER)
	cc.edges = [true, true, true, true, true, true]
	var board := {center.key(): cc}
	var pos := center.neighbor(0)  # E of center
	# Tile that opens back toward center (dir 3 = W) AND outward toward a
	# mandatory ring-2 slot -> legal.
	var edges := [false, false, false, true, false, false]  # open W (toward center)
	# also open an edge toward a ring-2 mandatory empty slot:
	edges[0] = true  # open E toward ring-2 slot (2,0)
	assert_true(MapGenerator.is_legal_placement(board, center, pos, edges),
		"connects to center + presents a potential space")


func test_is_legal_placement_rejects_closing() -> void:
	# Neighbour has an open mouth toward us, but our edge is closed -> Closing.
	var center := HexCoord.new(0, 0)
	var cc := HexCell.new(center, TileType.CENTER)
	cc.edges = [true, true, true, true, true, true]  # center opens everywhere
	var board := {center.key(): cc}
	var pos := center.neighbor(0)  # E of center; center opens W-toward-us? center dir 0 (E) faces pos
	# center's edge toward pos is dir 0 (open). Our edge back is dir 3 (W).
	# Leave dir 3 CLOSED -> we close the center's open mouth -> illegal.
	var edges := [true, false, false, false, false, false]
	assert_false(MapGenerator.is_legal_placement(board, center, pos, edges),
		"closing a neighbour's open mouth is illegal (rule 2)")


# --- helpers ---

func _has_rule2_violation(board: Dictionary) -> bool:
	# A violation is two PLACED adjacent tiles whose shared edge disagrees
	# (one open, one closed). Dangling mouths into empty desert are fine.
	for k in board.keys():
		var c := HexCoord.from_key(k)
		var cell: HexCell = board[k]
		for dir in range(6):
			var n := c.neighbor(dir)
			if board.has(n.key()):
				var ncell: HexCell = board[n.key()]
				if cell.has_exit(dir) != ncell.has_exit(HexCoord.opposite_dir(dir)):
					return true
	return false


func _boards_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a.keys():
		if not b.has(k):
			return false
		var ca: HexCell = a[k]
		var cb: HexCell = b[k]
		if ca.tile_type != cb.tile_type:
			return false
		if ca.edges != cb.edges:
			return false
	return true

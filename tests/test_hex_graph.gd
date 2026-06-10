extends GutTest
## Movement graph with dynamic edges (Section B, step 4).

const TileType := HexCell.TileType


# Build a straight corridor of `n` cells from center going East (dir 0), each
# fully connected to the next via matched open exits.
func _line_board(n: int) -> Dictionary:
	var board := {}
	var prev: HexCoord = null
	var c := HexCoord.new(0, 0)
	for i in range(n):
		var cell := HexCell.new(c, TileType.CORRIDOR)
		if prev != null:
			# open West toward prev
			cell.set_exit(3, true)
			board[prev.key()].set_exit(0, true)  # prev opens East toward this
		board[c.key()] = cell
		prev = c
		c = c.neighbor(0)
	return board


func _abilities(move: int, owner := &"green", through := false, blink := false) -> Dictionary:
	return {"move": move, "owner": owner, "moves_through_enemies": through, "can_blink": blink}


func test_reachable_respects_move_budget() -> void:
	var board := _line_board(5)
	var start := HexCoord.new(0, 0)
	var r := HexGraph.reachable(board, start, _abilities(2))
	# Move 2 reaches the next two cells East, not the 3rd/4th.
	assert_eq(r.size(), 2, "move 2 reaches exactly 2 cells down a corridor")


func test_reachable_needs_open_doorways() -> void:
	# Two adjacent cells with NO matched exit -> not reachable.
	var a := HexCoord.new(0, 0)
	var b := a.neighbor(0)
	var board := {
		a.key(): HexCell.new(a, TileType.ROOM),
		b.key(): HexCell.new(b, TileType.ROOM),
	}
	# no exits opened
	var r := HexGraph.reachable(board, a, _abilities(3))
	assert_eq(r.size(), 0, "no doorway means no movement")


func test_blink_ignores_walls() -> void:
	var a := HexCoord.new(0, 0)
	var b := a.neighbor(0)
	var board := {
		a.key(): HexCell.new(a, TileType.ROOM),
		b.key(): HexCell.new(b, TileType.ROOM),
	}
	# still no exits, but Blink crosses walls
	var r := HexGraph.reachable(board, a, _abilities(1, &"green", false, true))
	assert_eq(r.size(), 1, "blink reaches the walled neighbour")


func test_enemy_units_block_passthrough() -> void:
	var board := _line_board(4)  # cells at (0,0),(1,0),(2,0),(3,0)
	# Enemy at (2,0): the unit CAN reach (1,0) but the enemy blocks pass-through,
	# so (2,0) and (3,0) beyond it stay unreachable by pure movement.
	var enemy := HexCoord.new(2, 0)
	board[enemy.key()].add_unit(&"red", {"data": null, "damage": 0})
	var start := HexCoord.new(0, 0)
	var r := HexGraph.reachable(board, start, _abilities(3, &"green"))
	var keys := {}
	for c in r:
		keys[c.key()] = true
	assert_true(keys.has(HexCoord.new(1, 0).key()), "(1,0) is reachable")
	assert_false(keys.has(HexCoord.new(2, 0).key()), "(2,0) enemy cell not a movement dest")
	assert_false(keys.has(HexCoord.new(3, 0).key()), "(3,0) blocked behind the enemy")


func test_infiltrator_moves_through_enemies() -> void:
	var board := _line_board(4)
	var mid := HexCoord.new(1, 0)
	board[mid.key()].add_unit(&"red", {"data": null, "damage": 0})
	var start := HexCoord.new(0, 0)
	var r := HexGraph.reachable(board, start, _abilities(3, &"green", true))
	# With move-through-enemies, cells beyond the enemy become reachable.
	var reached_far := false
	for c in r:
		if c.equals(HexCoord.new(2, 0)) or c.equals(HexCoord.new(3, 0)):
			reached_far = true
	assert_true(reached_far, "infiltrator reaches cells past the enemy")


func test_path_distance_along_corridor() -> void:
	var board := _line_board(5)
	var start := HexCoord.new(0, 0)
	var goal := HexCoord.new(3, 0)
	assert_eq(HexGraph.path_distance(board, start, goal, _abilities(99)), 3,
		"3 doorway steps to the 4th cell")


func test_path_distance_unreachable() -> void:
	var a := HexCoord.new(0, 0)
	var b := HexCoord.new(5, 0)  # not even on the board
	var board := {a.key(): HexCell.new(a, TileType.ROOM)}
	assert_eq(HexGraph.path_distance(board, a, b, _abilities(99)), -1,
		"unreachable goal returns -1")

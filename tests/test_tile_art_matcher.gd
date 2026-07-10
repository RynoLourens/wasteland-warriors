extends GutTest
## WP1 — TileArtMatcher: exit-true tile face selection (pure logic, no scenes).
## The FACE_DOORS table was derived by pixel-sampling + visual verification of
## every face PNG; these tests pin the matcher's behaviour on top of it.


## Every axial neighbour direction must land exactly on one of the six hex edge
## midpoints in pixel space — the shared angle model of matcher and board view.
func test_direction_angles_land_on_edge_midpoints() -> void:
	for dir in range(6):
		var d: Vector2i = HexCoord.DIRECTIONS[dir]
		var px := Vector2(1.5 * float(d.x), sqrt(3.0) * (float(d.y) + float(d.x) / 2.0))
		var ang := fposmod(rad_to_deg(px.angle()), 360.0)
		assert_true(TileArtMatcher.angle_index(ang) >= 0,
				"dir %d angle %.1f not on an edge midpoint" % [dir, ang])


func test_face_doors_table_is_valid() -> void:
	for face in TileArtMatcher.FACE_DOORS.keys():
		var doors: Array = TileArtMatcher.FACE_DOORS[face]
		assert_between(doors.size(), 1, 6, "face %s has %d doors" % [face, doors.size()])
		for a in doors:
			assert_true(TileArtMatcher.angle_index(float(a)) >= 0,
					"face %s door angle %s off-grid" % [face, str(a)])


func test_mask_rotation() -> void:
	# Doors at {90, 210, 330} rotated one step clockwise land on {150, 270, 30}.
	var m: int = TileArtMatcher.mask_from_angles([90.0, 210.0, 330.0])
	var want: int = TileArtMatcher.mask_from_angles([150.0, 270.0, 30.0])
	assert_eq(TileArtMatcher.rotate_mask(m, 1), want)
	# Six steps = identity.
	assert_eq(TileArtMatcher.rotate_mask(m, 6), m)


func test_rotation_finds_exact_match() -> void:
	# room_03 has doors {90,150,270}; exits {150,210,330} are that set rotated
	# by 60 deg, so SOME face+rotation must match with zero patches.
	var res: Dictionary = TileArtMatcher.pick("room", [150.0, 210.0, 330.0], 0, 1)
	assert_eq(res["missing_doors"].size(), 0, "missing: %s" % str(res["missing_doors"]))
	assert_eq(res["extra_doors"].size(), 0, "extra: %s" % str(res["extra_doors"]))


func test_pick_is_deterministic() -> void:
	var first: Dictionary = TileArtMatcher.pick("corridor", [30.0, 270.0], 2, -3)
	for i in range(5):
		var again: Dictionary = TileArtMatcher.pick("corridor", [30.0, 270.0], 2, -3)
		assert_eq(again["face"], first["face"])
		assert_eq(again["rotation_deg"], first["rotation_deg"])


func test_center_never_rotates() -> void:
	var res: Dictionary = TileArtMatcher.pick("center", [30.0, 90.0, 150.0], 0, 0)
	assert_eq(res["face"], "center")
	assert_eq(res["rotation_deg"], 0.0)
	# The centre face paints all six doors; the three closed edges need walls.
	assert_eq(res["missing_doors"].size(), 0)
	assert_eq(res["extra_doors"].size(), 3)


## Real boards: over many seeds the face pool must cover every generated cell
## with at most 2 patch strips (python pre-validation says worst case is 1 for
## any exit set the pools see, 2 only for a 6-exit corridor).
func test_face_pool_covers_generated_boards() -> void:
	for seed_i in range(50):
		var gen: Dictionary = MapGenerator.generate_map(3, 1000 + seed_i)
		var board: Dictionary = gen["board"]
		for key in board.keys():
			var cell: HexCell = board[key]
			var coord: HexCoord = HexCoord.from_key(key)
			var tt := "room"
			match cell.tile_type:
				HexCell.TileType.CENTER:
					tt = "center"
				HexCell.TileType.CORRIDOR:
					tt = "corridor"
				_:
					tt = "room"
			var res: Dictionary = TileArtMatcher.pick(tt, _exit_angles(cell), coord.q, coord.r)
			if tt == "center":
				# The centre face is fixed and paints all six doors; closed
				# edges become wall patches (any count is fine — see
				# test_center_never_rotates). Only a MISSING door would be
				# a real defect.
				assert_eq(res["missing_doors"].size(), 0,
						"seed %d centre missing doors: %s" % [seed_i, str(res["missing_doors"])])
				continue
			var patches: int = res["missing_doors"].size() + res["extra_doors"].size()
			assert_true(patches <= 2,
					"seed %d cell %s (%s): %d patches" % [seed_i, key, tt, patches])


## Same pixel-angle derivation the board view uses, headless.
func _exit_angles(cell: HexCell) -> Array:
	var out: Array = []
	for dir in range(6):
		if not cell.has_exit(dir):
			continue
		var d: Vector2i = HexCoord.DIRECTIONS[dir]
		var px := Vector2(1.5 * float(d.x), sqrt(3.0) * (float(d.y) + float(d.x) / 2.0))
		out.append(fposmod(rad_to_deg(px.angle()), 360.0))
	return out

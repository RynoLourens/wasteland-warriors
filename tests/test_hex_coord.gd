extends GutTest
## HexCoord math (Section B, step 1).


func test_axial_to_cube_invariant() -> void:
	# q + r + s == 0 must always hold.
	for q in range(-3, 4):
		for r in range(-3, 4):
			var h := HexCoord.new(q, r)
			assert_eq(h.q + h.r + h.s(), 0, "cube invariant for (%d,%d)" % [q, r])


func test_neighbors_are_distance_one() -> void:
	var c := HexCoord.new(0, 0)
	for dir in range(6):
		var n := c.neighbor(dir)
		assert_eq(c.distance_to(n), 1, "neighbor %d is distance 1" % dir)


func test_opposite_direction() -> void:
	assert_eq(HexCoord.opposite_dir(0), 3)
	assert_eq(HexCoord.opposite_dir(2), 5)
	assert_eq(HexCoord.opposite_dir(5), 2)
	# Going dir then opposite returns to start.
	var c := HexCoord.new(2, -1)
	for dir in range(6):
		var there := c.neighbor(dir)
		var back := there.neighbor(HexCoord.opposite_dir(dir))
		assert_true(back.equals(c), "dir %d then opposite returns home" % dir)


func test_distance_symmetry_and_zero() -> void:
	var a := HexCoord.new(1, -2)
	var b := HexCoord.new(-1, 1)
	assert_eq(a.distance_to(b), b.distance_to(a), "distance is symmetric")
	assert_eq(a.distance_to(a), 0, "distance to self is 0")


func test_ring_sizes() -> void:
	var center := HexCoord.new(0, 0)
	assert_eq(HexCoord.ring(center, 0).size(), 1, "ring 0 = 1 hex (center)")
	assert_eq(HexCoord.ring(center, 1).size(), 6, "ring 1 = 6 hexes")
	assert_eq(HexCoord.ring(center, 2).size(), 12, "ring 2 = 12 hexes")
	assert_eq(HexCoord.ring(center, 3).size(), 18, "ring 3 = 18 hexes")


func test_ring_members_have_correct_distance() -> void:
	var center := HexCoord.new(0, 0)
	for radius in range(1, 4):
		for h in HexCoord.ring(center, radius):
			assert_eq(center.distance_to(h), radius,
				"ring %d member %s at correct distance" % [radius, h])


func test_key_roundtrip() -> void:
	var h := HexCoord.new(-2, 3)
	var h2 := HexCoord.from_key(h.key())
	assert_true(h.equals(h2), "key roundtrip preserves coords")


func test_spiral_count() -> void:
	var center := HexCoord.new(0, 0)
	# spiral to radius 2 = 1 + 6 + 12 = 19
	assert_eq(HexCoord.spiral(center, 2).size(), 19, "spiral radius 2 = 19 hexes")

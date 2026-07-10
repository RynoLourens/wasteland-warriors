class_name TileArtMatcher
## WP1 (exit-true tiles): pure-logic matcher that picks the tile face + rotation
## whose PAINTED doorways best match a cell's REAL exits, in pixel-angle space.
##
## Why pixel angles: HexCoord.DIRECTIONS indices do not map cleanly onto pixel
## edges (board_view resolves logical dir -> pixel edge by best-dot matching).
## For a flat-top hex in y-down pixel space the six edge midpoints sit at
## 30/90/150/210/270/330 degrees, and every axial neighbour offset lands exactly
## on one of them - so both a face's doors and a cell's exits are sets drawn
## from the same six angles, encoded here as 6-bit masks (bit i = 30 + 60*i).
##
## All static, no scene deps - testable headless (tests/test_tile_art_matcher.gd).

const EDGE_ANGLES := [30.0, 90.0, 150.0, 210.0, 270.0, 330.0]
const ANGLE_SNAP := 5.0

## Which edge-midpoint angles (deg, y-down pixel space) have a painted doorway.
## Derived by pixel-sampling every face at the 6 edge midpoints (doorway = grey,
## low saturation; rock = orange, high saturation) then visually verifying every
## face; corridor_01's inner plaza is walled off from its lower-right edge, so it
## really has only 2 exits. Derivation 2026-07-10, OPUS-BUILD-GUIDE WP1.
const FACE_DOORS := {
	"room_01": [30.0, 90.0, 210.0, 270.0],
	"room_03": [90.0, 150.0, 270.0],
	"room_04": [30.0, 90.0, 270.0],
	"room_05": [30.0, 90.0],
	"room_06": [30.0, 270.0],
	"room_07": [30.0, 150.0, 210.0, 270.0, 330.0],
	"room_09": [30.0, 270.0, 330.0],
	"room_10": [90.0, 210.0, 270.0, 330.0],
	"corridor_01": [210.0, 270.0],
	"corridor_02": [30.0, 90.0, 270.0],
	"corridor_03": [90.0, 150.0, 270.0],
	"corridor_04": [210.0, 270.0, 330.0],
	"corridor_05": [210.0, 330.0],
	"corridor_06": [90.0, 270.0],
	"corridor_07": [90.0, 150.0, 270.0, 330.0],
	"corridor_08": [90.0, 210.0, 270.0, 330.0],
	"corridor_09": [30.0, 210.0, 270.0, 330.0],
	"center": [30.0, 90.0, 150.0, 210.0, 270.0, 330.0],
}

# Face pools per tile_type, in a FIXED order (deterministic tie-breaking).
const ROOM_FACES := ["room_01", "room_03", "room_04", "room_05", "room_06",
		"room_07", "room_09", "room_10"]
const CORRIDOR_FACES := ["corridor_01", "corridor_02", "corridor_03",
		"corridor_04", "corridor_05", "corridor_06", "corridor_07",
		"corridor_08", "corridor_09"]


## Snap an angle (deg) to its edge index 0..5, or -1 if it is not on a midpoint.
static func angle_index(angle_deg: float) -> int:
	var a := fposmod(angle_deg, 360.0)
	for i in range(6):
		var diff: float = absf(a - EDGE_ANGLES[i])
		if diff <= ANGLE_SNAP or diff >= 360.0 - ANGLE_SNAP:
			return i
	return -1


static func mask_from_angles(angles: Array) -> int:
	var m := 0
	for a in angles:
		var i := angle_index(float(a))
		if i >= 0:
			m |= 1 << i
	return m


## Rotate a 6-bit edge mask by k*60 deg clockwise (y-down: +60 deg per step).
static func rotate_mask(m: int, k: int) -> int:
	var kk: int = ((k % 6) + 6) % 6
	return ((m << kk) | (m >> (6 - kk))) & 63


static func _bit_count(m: int) -> int:
	var n := 0
	for i in range(6):
		if m & (1 << i):
			n += 1
	return n


static func _angles_from_mask(m: int) -> Array:
	var out: Array = []
	for i in range(6):
		if m & (1 << i):
			out.append(EDGE_ANGLES[i])
	return out


## Pick the best (face, rotation) for a cell.
##   tile_type: "room" / "corridor" / "center"
##   exit_angles: pixel angles (deg) of the cell's OPEN edges
##   q, r: axial coord, used only for the deterministic tie-break
## Returns {face: String, rotation_deg: float, missing_doors: Array, extra_doors: Array}
##   missing_doors: exit angles the art has no doorway for (needs a door patch)
##   extra_doors:   painted doorways with no real exit (needs a wall patch)
## Angles in the result are in WORLD space (post-rotation).
static func pick(tile_type: String, exit_angles: Array, q: int, r: int) -> Dictionary:
	var exits := mask_from_angles(exit_angles)
	# The Central Chamber is unique: never rotated, doors fixed.
	if tile_type == "center":
		var cdoors: int = mask_from_angles(FACE_DOORS["center"])
		return {
			"face": "center",
			"rotation_deg": 0.0,
			"missing_doors": _angles_from_mask(exits & ~cdoors),
			"extra_doors": _angles_from_mask(cdoors & ~exits),
		}
	var pool: Array = CORRIDOR_FACES if tile_type == "corridor" else ROOM_FACES
	var best: Array = []      # candidates tied on the best score
	var best_diff := 99
	for face in pool:
		var dm: int = mask_from_angles(FACE_DOORS[face])
		for k in range(6):
			var diff: int = _bit_count(rotate_mask(dm, k) ^ exits)
			if diff < best_diff:
				best_diff = diff
				best = [[face, k]]
			elif diff == best_diff:
				best.append([face, k])
	# Deterministic per-cell tie-break so a given board renders identically
	# across redraws while different cells still vary.
	var idx: int = abs(q * 7 + r * 13) % best.size()
	var face_name: String = best[idx][0]
	var k_rot: int = best[idx][1]
	var doors_rotated: int = rotate_mask(mask_from_angles(FACE_DOORS[face_name]), k_rot)
	return {
		"face": face_name,
		"rotation_deg": float(k_rot) * 60.0,
		"missing_doors": _angles_from_mask(exits & ~doors_rotated),
		"extra_doors": _angles_from_mask(doors_rotated & ~exits),
	}

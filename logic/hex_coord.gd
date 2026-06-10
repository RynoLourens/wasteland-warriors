extends RefCounted
class_name HexCoord
## Cube/axial hex coordinate helper (Section B, step 1).
##
## We store axial (q, r) and derive the cube s = -q - r on demand. All board
## math — neighbours, distance, rings, direction — lives here so the rest of
## the engine never touches pixels or "every-other-row-is-offset" math. This is
## the Red Blob Games model (https://www.redblobgames.com/grids/hexagons/).
##
## Direction indices 0..5 are FIXED and shared with tile edge math: a tile's
## "exits" are a 6-bool array indexed by these same directions, so direction i
## of a tile lines up with neighbour i. Keep this ordering stable forever.

var q: int
var r: int


func _init(_q: int = 0, _r: int = 0) -> void:
	q = _q
	r = _r


## Cube s-coordinate (q + r + s == 0 always holds).
func s() -> int:
	return -q - r


# --- Direction vectors (axial). Index = direction 0..5. ---
# Order chosen for flat-top hexes going clockwise from "East". The OPPOSITE of
# direction i is direction (i + 3) % 6 — used constantly for "do two tiles'
# exits face each other?".
const DIRECTIONS := [
	Vector2i(1, 0),   # 0 E
	Vector2i(1, -1),  # 1 NE
	Vector2i(0, -1),  # 2 NW
	Vector2i(-1, 0),  # 3 W
	Vector2i(-1, 1),  # 4 SW
	Vector2i(0, 1),   # 5 SE
]


static func opposite_dir(dir: int) -> int:
	return (dir + 3) % 6


## Neighbour in a given direction (0..5).
func neighbor(dir: int) -> HexCoord:
	var d: Vector2i = DIRECTIONS[dir]
	return HexCoord.new(q + d.x, r + d.y)


## All six neighbours, in direction order.
func neighbors() -> Array:
	var out := []
	for dir in range(6):
		out.append(neighbor(dir))
	return out


## Cube distance (number of steps between two hexes).
func distance_to(other: HexCoord) -> int:
	return (abs(q - other.q) + abs(r - other.r) + abs(s() - other.s())) / 2


func equals(other: HexCoord) -> bool:
	return other != null and q == other.q and r == other.r


## A stable, hashable key so HexCoord can index a Dictionary. (Object identity
## won't work for that — two HexCoords with the same q,r are "equal" to us but
## are different objects, so we key on this string instead.)
func key() -> String:
	return "%d,%d" % [q, r]


static func from_key(k: String) -> HexCoord:
	var parts := k.split(",")
	return HexCoord.new(int(parts[0]), int(parts[1]))


func duplicate_coord() -> HexCoord:
	return HexCoord.new(q, r)


func _to_string() -> String:
	return "Hex(%d,%d)" % [q, r]


# --- Ring / spiral math (drives the ring-by-ring map builder) ---

## The N hexes that form ring `radius` around `center` (radius 0 = just center).
## Ring k has exactly 6*k hexes (radius 0 returns the single center).
static func ring(center: HexCoord, radius: int) -> Array:
	var results := []
	if radius == 0:
		results.append(center.duplicate_coord())
		return results
	# Start at the hex `radius` steps in direction 4 (SW), then walk the 6 sides.
	var cube_q := center.q + HexCoord.DIRECTIONS[4].x * radius
	var cube_r := center.r + HexCoord.DIRECTIONS[4].y * radius
	var cur := HexCoord.new(cube_q, cube_r)
	for side in range(6):
		for _step in range(radius):
			results.append(cur.duplicate_coord())
			cur = cur.neighbor(side)
	return results


## All hexes from ring 0 out to `radius` inclusive, center-first (a spiral).
static func spiral(center: HexCoord, radius: int) -> Array:
	var results := [center.duplicate_coord()]
	for k in range(1, radius + 1):
		results.append_array(ring(center, k))
	return results

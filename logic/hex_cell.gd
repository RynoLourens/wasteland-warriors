extends RefCounted
class_name HexCell
## One placed tile on the board (Section B, step 2).
##
## A cell knows its tile type, which of its six edges are OPEN (exits), what
## Units sit on it (keyed by owner colour), which Environment/Function tokens
## are present and whether they are face-up, the explicit Activation-token state
## per player, and any Old Tech sitting on it.
##
## CRITICAL design rule from the plan: the face-up / face-down distinction and
## the "(face-down tokens don't count)" caveats are encoded EXPLICITLY here via
## TokenState — never inferred from other state. That is exactly where bugs hide.

enum TileType { CENTER, ROOM, CORRIDOR }

# Re-declared here for readability; mirrors GameState.TokenState. NONE = no
# activation token, ACTIVE = face-up Activation token (blocks re-activation,
# locks units in), CONTROL = face-down Control token (does NOT count for the
# "two face-up tokens" / "can't move out" rules, but grants +1 Defense).
enum TokenState { NONE, ACTIVE, CONTROL }

var coord: HexCoord
var tile_type: int = TileType.ROOM

## edges[dir] == true means there is an OPEN exit on that edge (dir 0..5,
## matching HexCoord.DIRECTIONS). The CENTER tile and standard tiles all have
## their exits described this way so is_legal_placement can reason purely about
## edges meeting edges.
var edges: Array = [false, false, false, false, false, false]

## Units present, keyed by owner colour (StringName) -> Array of unit instances
## (each unit is a small Dictionary {data: UnitData, damage: int}).
var units: Dictionary = {}

## Activation token state per player: owner(StringName) -> TokenState.
## Absent key == TokenState.NONE.
var token_state: Dictionary = {}

## Environment/Function tokens seeded on this cell.
## Each entry: {data: Resource, face_up: bool, kind: "env"|"func"}.
var tokens: Array = []

## Number of Old Tech tokens currently sitting on this cell.
var old_tech: int = 0


func _init(_coord: HexCoord, _tile_type: int = TileType.ROOM) -> void:
	coord = _coord
	tile_type = _tile_type
	edges = [false, false, false, false, false, false]
	units = {}
	token_state = {}
	tokens = []
	old_tech = 0


# --- Edges / connectivity ---

func has_exit(dir: int) -> bool:
	return edges[dir] == true


func set_exit(dir: int, open: bool = true) -> void:
	edges[dir] = open


func open_exit_count() -> int:
	var n := 0
	for e in edges:
		if e:
			n += 1
	return n


# --- Units ---

func units_for(owner: StringName) -> Array:
	return units.get(owner, [])


func add_unit(owner: StringName, unit) -> void:
	if not units.has(owner):
		units[owner] = []
	units[owner].append(unit)


func remove_unit(owner: StringName, unit) -> bool:
	if units.has(owner):
		var arr: Array = units[owner]
		var idx := arr.find(unit)
		if idx != -1:
			arr.remove_at(idx)
			if arr.is_empty():
				units.erase(owner)
			return true
	return false


## True if any owner OTHER than `me` has units here (blocks pass-through).
func has_enemy_units(me: StringName) -> bool:
	for owner in units.keys():
		if owner != me and not units[owner].is_empty():
			return true
	return false


func is_empty_of_units() -> bool:
	for owner in units.keys():
		if not units[owner].is_empty():
			return false
	return true


# --- Activation / control tokens (explicit state) ---

func get_token_state(owner: StringName) -> int:
	return token_state.get(owner, TokenState.NONE)


func set_token_state(owner: StringName, state: int) -> void:
	if state == TokenState.NONE:
		token_state.erase(owner)
	else:
		token_state[owner] = state


## A player may not place a second FACE-UP activation token here. Face-down
## CONTROL tokens explicitly do not count toward this rule.
func has_faceup_activation(owner: StringName) -> bool:
	return get_token_state(owner) == TokenState.ACTIVE


## Controlling a space (a face-down Control token of your colour) grants +1
## Defense to your units here.
func grants_control_defense(owner: StringName) -> bool:
	return get_token_state(owner) == TokenState.CONTROL


# --- Tokens (environment / function) ---

func has_token_effect(effect_id: StringName, must_be_face_up: bool = true) -> bool:
	for t in tokens:
		if must_be_face_up and not t.get("face_up", false):
			continue
		var data = t.get("data")
		if data != null and data.get("effect_id") == effect_id:
			return true
	return false

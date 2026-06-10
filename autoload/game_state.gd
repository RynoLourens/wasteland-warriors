extends Node
## GameState — the authoritative, headless board model.
##
## Section B: composes HexCoord / HexCell / Player / MapGenerator / HexGraph
## into a runnable game model with NO scene loaded — that is what makes it
## unit-testable with GUT. The visual layer (Section E+) only ever reads this
## and listens to EventBus; it never contains rules.

## Token state per player per hex. Encoded explicitly — never inferred.
## (face-down CONTROL tokens behave differently from ACTIVE ones.)
enum TokenState { NONE, ACTIVE, CONTROL }

## Round phase order: Recruitment -> Action -> Guardian -> (repeat).
enum Phase { RECRUITMENT, ACTION, GUARDIAN }

# --- Authoritative headless state (Section B) ---
var board: Dictionary = {}             # hexkey(String) -> HexCell
var center: HexCoord = null
var rally_zones: Dictionary = {}       # color(StringName) -> HexCoord
var players: Array = []                # Player models
var turn_order: Array = []             # Array of color StringNames
var current_phase: int = Phase.RECRUITMENT
var match_seed: int = 0
var rng := RandomNumberGenerator.new() # seeded for reproducibility


func _ready() -> void:
	# Nothing auto-runs; a match starts explicitly via setup_match() so the
	# autoload stays inert (and unit-testable) until a game begins.
	pass


## Start a fresh, fully-headless match. No scenes touched. `player_specs` is an
## Array of { "color": StringName, "is_ai": bool } in turn order.
func setup_match(player_specs: Array, seed: int) -> void:
	match_seed = seed
	rng.seed = seed

	# 1. Build the board + rally zones from the seeded generator.
	var map := MapGenerator.generate_map(player_specs.size(), seed)
	board = map.get("board", {})
	center = map.get("center", null)
	rally_zones = map.get("rally_zones", {})

	# 2. Seed tokens face-down. An empty pool seeds nothing, which is fine for
	# headless rules tests; Section E/F wires the real .tres pools in.
	MapGenerator.seed_tokens(board, _token_pools(), seed)

	# 3. Build players, each with a starting bag and their rally zone.
	players.clear()
	turn_order.clear()
	for spec in player_specs:
		var color: StringName = spec.get("color")
		var p := Player.new(color, spec.get("is_ai", true))
		p.load_starting_bag()
		p.rally_zone = rally_zones.get(color, null)
		players.append(p)
		turn_order.append(color)

	current_phase = Phase.RECRUITMENT


func get_cell(coord: HexCoord) -> HexCell:
	return board.get(coord.key(), null)


func get_player(color: StringName) -> Player:
	for p in players:
		if p.color == color:
			return p
	return null


## Reachable hexes for one of a player's units sitting at `from`.
func reachable_for(color: StringName, from: HexCoord, unit_data) -> Array:
	var abilities := {
		"move": unit_data.move if unit_data != null else 1,
		"moves_through_enemies": unit_data.moves_through_enemies if unit_data != null else false,
		"can_blink": false,
		"owner": color,
	}
	return HexGraph.reachable(board, from, abilities)


## Token pools for seeding. Empty by default; Section E/F wires the real .tres
## resources in. Single source for seed_tokens().
func _token_pools() -> Dictionary:
	return {"corridor_env": [], "room_env": [], "func": []}

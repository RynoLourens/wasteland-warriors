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

# --- Shared Action-card deck (Section F). One deck for the table; players draw 1
# per Recruitment. Draw pile + discard; reshuffle discard when the pile empties. ---
var action_deck: Array = []            # Array of ActionCardData (draw pile, top = back)
var action_discard: Array = []         # Array of ActionCardData (played/discarded)
# Independent stream so card order is reproducible but doesn't perturb map/combat rng.
var deck_rng := RandomNumberGenerator.new()

# --- Round-scoped card buffs (Section F, Piece 5b). Keyed by player color; CLEARED
# each round during Cleanup. "until the end of the round" cards write here and the
# movement/combat queries read them, so no per-unit flags leak across rounds. ---
#   { color: { "extra_defense": int, "extra_move": int, "move_through_enemies": bool } }
var round_buffs: Dictionary = {}


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

	# 4. Build + shuffle the shared Action-card deck (seeded, independent stream).
	_build_action_deck(seed)

	center_breached = false
	current_phase = Phase.RECRUITMENT


# ---------------------------------------------------------------------------
#  Action-card deck
# ---------------------------------------------------------------------------

## Load every card .tres into the draw pile and shuffle it with a derived seed.
func _build_action_deck(seed: int) -> void:
	action_deck.clear()
	action_discard.clear()
	deck_rng.seed = seed + 7   # derived: reproducible, independent of map/combat rng
	var dir := DirAccess.open("res://data/cards")
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var res = load("res://data/cards/" + fname)
			if res != null:
				action_deck.append(res)
		fname = dir.get_next()
	dir.list_dir_end()
	action_deck.sort_custom(func(a, b): return str(a.id) < str(b.id))  # deterministic pre-shuffle order
	_shuffle_deck()


func _shuffle_deck() -> void:
	# Fisher-Yates with the seeded deck_rng (Array.shuffle uses the global rng).
	for i in range(action_deck.size() - 1, 0, -1):
		var j: int = deck_rng.randi_range(0, i)
		var tmp = action_deck[i]
		action_deck[i] = action_deck[j]
		action_deck[j] = tmp


## Draw the top card. If the draw pile is empty, reshuffle the discard back in.
## Returns an ActionCardData, or null if there are genuinely no cards at all.
func draw_action_card():
	if action_deck.is_empty():
		if action_discard.is_empty():
			return null
		action_deck = action_discard.duplicate()
		action_discard.clear()
		_shuffle_deck()
	if action_deck.is_empty():
		return null
	return action_deck.pop_back()


## Send a played/discarded card to the discard pile (reshuffled in when needed).
func discard_action_card(card) -> void:
	if card != null:
		action_discard.append(card)


func get_cell(coord: HexCoord) -> HexCell:
	return board.get(coord.key(), null)


func get_player(color: StringName) -> Player:
	for p in players:
		if p.color == color:
			return p
	return null


## Does `color` control `coord`? A space is controlled if the player holds a
## face-down Control token there, OR it is the player's own Rally Zone — which is
## ALWAYS theirs UNLESS an enemy is the sole occupant (rulebook). This is the
## authoritative control test for card targeting / Old-Tech carry.
func player_controls(color: StringName, coord: HexCoord) -> bool:
	var cell: HexCell = get_cell(coord)
	if cell == null:
		return false
	# 1. Explicit Control token on the cell.
	if cell.get_token_state(color) == TokenState.CONTROL:
		return true
	# 1b. The Player's own control_set still records this space as controlled even
	# when the cell's per-player token slot was overwritten by a face-up ACTIVATION
	# token this turn (activating a space you control must NOT forfeit control).
	var p := get_player(color)
	if p != null and p.controls(coord):
		return true
	# 2. Own Rally Zone, unless an enemy solely occupies it.
	var rz: HexCoord = rally_zones.get(color, null)
	if rz != null and rz.equals(coord):
		var mine := not cell.units_for(color).is_empty()
		var enemy := false
		for owner in cell.units.keys():
			if owner != color and not cell.units[owner].is_empty():
				enemy = true
		# Yours by default; only lost if an enemy is present and you are not.
		if enemy and not mine:
			return false
		return true
	return false


## Reachable hexes for one of a player's units sitting at `from`. Folds in any
## round-scoped card buffs for `color` — Extra Move / Move Through Enemies are
## PER-SPACE (the card buffs "Units in a space you control"), so they apply only
## when `from` is one of the buffed spaces.
func reachable_for(color: StringName, from: HexCoord, unit_data) -> Array:
	var base_move: int = unit_data.move if unit_data != null else 1
	var base_mte: bool = unit_data.moves_through_enemies if unit_data != null else false
	var buff: Dictionary = round_buffs.get(color, {})
	var fk := from.key()
	var move_spaces: Dictionary = buff.get("extra_move_spaces", {})
	var mte_spaces: Dictionary = buff.get("mte_spaces", {})
	var em: int = int(move_spaces.get(fk, 0))
	var mte: bool = mte_spaces.has(fk)
	var abilities := {
		"move": base_move + em,
		"moves_through_enemies": base_mte or mte,
		"can_blink": false,
		"owner": color,
	}
	return HexGraph.reachable(board, from, abilities)


# ---------------------------------------------------------------------------
#  Round-scoped card buffs (Piece 5b)
# ---------------------------------------------------------------------------

## Ensure a buff bucket exists for `color` and return it (mutable).
func _buff_bucket(color: StringName) -> Dictionary:
	if not round_buffs.has(color):
		round_buffs[color] = {
			"extra_defense": 0,
			"extra_move_spaces": {},   # hexkey -> extra move amount
			"mte_spaces": {},          # hexkey -> true (move through enemies)
		}
	return round_buffs[color]


## Player-wide +Defense (Defensive Stance — "all your Units").
func add_extra_defense(color: StringName, amount: int) -> void:
	var b := _buff_bucket(color)
	b["extra_defense"] = int(b.get("extra_defense", 0)) + amount


## Per-space +Move (Extra Move — "Units in a space you control").
func add_extra_move_space(color: StringName, coord: HexCoord, amount: int) -> void:
	var b := _buff_bucket(color)
	var spaces: Dictionary = b["extra_move_spaces"]
	spaces[coord.key()] = int(spaces.get(coord.key(), 0)) + amount


## Per-space Move Through Enemies (— "Units in a space you control").
func grant_move_through_enemies_space(color: StringName, coord: HexCoord) -> void:
	var b := _buff_bucket(color)
	b["mte_spaces"][coord.key()] = true


func extra_defense_for(color: StringName) -> int:
	return int(round_buffs.get(color, {}).get("extra_defense", 0))


## Clear all round buffs (called from Cleanup each round).
func clear_round_buffs() -> void:
	round_buffs.clear()


# --- Extra Recruitment (action_09): grant one more recruitment decision this round.
# Pending count per color; the recruitment flow drains it. Cleared each round. ---
var _extra_recruitment: Dictionary = {}   # color -> int

## True once ANY player has ever moved a Unit into the Central Chamber. After this,
## the Guardian phase spawns 2 (not 1) per phase. Persists for the whole match.
var center_breached: bool = false

func grant_extra_recruitment(color: StringName) -> void:
	_extra_recruitment[color] = int(_extra_recruitment.get(color, 0)) + 1

func take_extra_recruitment(color: StringName) -> bool:
	var n: int = int(_extra_recruitment.get(color, 0))
	if n <= 0:
		return false
	_extra_recruitment[color] = n - 1
	return true

func clear_extra_recruitment() -> void:
	_extra_recruitment.clear()


## Token pools for seeding. Empty by default; Section E/F wires the real .tres
## resources in. Single source for seed_tokens().
func _token_pools() -> Dictionary:
	return {"corridor_env": [], "room_env": [], "func": []}

extends RefCounted
class_name Player
## A player's full state (Section B, step 3).
##
## The bag is modelled as SAMPLING WITHOUT REPLACEMENT driven by a seeded RNG —
## NOT a "reshuffle the whole bag on every draw" model. Reproducibility from a
## seed is a hard requirement (bug reports, "same deal" rematches, AI-vs-AI
## balance sims), so every random act goes through the injected RNG.

const COWARD := &"coward"   ## bag entries that are Cowards (not real units)

var color: StringName              ## &"green" / &"blue" / &"red"
var is_ai: bool = true             ## AI fills empty seats by default
var leader = null                  ## LeaderData resource (or null)
var rally_zone: HexCoord = null

## The bag: an Array of StringName entries. Real units carry their unit id
## (e.g. &"warrior"); Cowards are COWARD. We draw without replacement.
var bag: Array = []

## Action cards in hand (unlimited size; persist across rounds).
var hand: Array = []

## Face-down Artifact cards drawn from the Artifact Deck (Ancient Artifact token /
## Function flips). Held face-down; may be discarded during Recruitment to place a
## Special Unit in a controlled space (rulebook). v1 just tracks them.
var artefacts: Array = []

## Unit ids queued for a FREE redeploy next Recruitment (Medical Machine artifact).
var pending_redeploys: Array = []

var old_tech_count: int = 0

## Set of hex keys this player currently Controls (face-down token of theirs).
## Kept as a Dictionary used as a set: key(String) -> true.
var control_set: Dictionary = {}


func _init(_color: StringName, _is_ai: bool = true) -> void:
	color = _color
	is_ai = _is_ai
	bag = []
	hand = []
	control_set = {}


## Standard starting bag (rulebook Ch.4, with the reviewed change):
## 6 Cowards + 6 Warriors.
func load_starting_bag() -> void:
	bag.clear()
	for _i in range(6):
		bag.append(COWARD)
	for _i in range(6):
		bag.append(&"warrior")


func bag_size() -> int:
	return bag.size()


func count_in_bag(entry: StringName) -> int:
	var n := 0
	for e in bag:
		if e == entry:
			n += 1
	return n


func coward_count() -> int:
	return count_in_bag(COWARD)


## Draw `n` entries WITHOUT replacement using the seeded rng. Returns the drawn
## entries; they are REMOVED from the bag. Caller decides what to do with them
## (Deploy returns Cowards to the bag; Punish removes Cowards to supply; etc.).
func draw_from_bag(n: int, rng: RandomNumberGenerator) -> Array:
	var drawn := []
	var to_take: int = min(n, bag.size())
	for _i in range(to_take):
		var idx := rng.randi_range(0, bag.size() - 1)
		drawn.append(bag[idx])
		bag.remove_at(idx)
	return drawn


## Put entries back into the bag (e.g. Deploy returns drawn Cowards;
## Punish returns drawn Units).
func return_to_bag(entries: Array) -> void:
	bag.append_array(entries)


# --- Recruitment actions (Ch.7). These mutate bag state; the GameState/FSM
# decides legality and which units actually get placed in the rally zone. ---

## Deploy: draw 3, Units go to rally zone (returned here as the "deployed"
## list), Cowards go back to the bag.
func deploy(rng: RandomNumberGenerator) -> Array:
	var drawn := draw_from_bag(3, rng)
	var deployed := []
	var cowards := []
	for e in drawn:
		if e == COWARD:
			cowards.append(e)
		else:
			deployed.append(e)
	return_to_bag(cowards)
	return deployed


## Recruit: add 3 Units (or 2 Special) from supply into the bag. The caller
## passes the chosen unit ids (length validated by the FSM / Leader rules —
## Lady Seraph recruits 5/3 instead of 3/2).
func recruit(unit_ids: Array) -> void:
	bag.append_array(unit_ids)


## Punish Cowards: draw 5, remove Cowards to supply, return Units to bag.
## Returns how many Cowards were removed.
func punish_cowards(rng: RandomNumberGenerator) -> int:
	var drawn := draw_from_bag(5, rng)
	var removed := 0
	var units_back := []
	for e in drawn:
		if e == COWARD:
			removed += 1
		else:
			units_back.append(e)
	return_to_bag(units_back)
	return removed


# --- Control set helpers ---

func mark_control(coord: HexCoord) -> void:
	control_set[coord.key()] = true


func clear_control(coord: HexCoord) -> void:
	control_set.erase(coord.key())


func controls(coord: HexCoord) -> bool:
	return control_set.has(coord.key())


func has_won() -> bool:
	return old_tech_count >= 3

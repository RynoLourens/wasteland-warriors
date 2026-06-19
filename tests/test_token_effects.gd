extends GutTest
## TokenEffects — environment & function token resolution (rulebook Ch.11 + Ch.13).
##
## These tests assert the EFFECTS that were missing until Section F's punch-list:
## tokens used to flip face-up but resolve nothing. We build minimal cells/tokens by
## hand (no .tres load) and inject a `deps` bundle with a seeded rng so the dice
## effects are reproducible. We assert the deterministic, non-luck outcomes exactly
## (coward added, card drawn, units placed, persistent records, function flip + gate)
## and the dice effects structurally (damage recorded, dead units pruned).

const GUARDIAN_OWNER := &"guardian"


# --- builders ----------------------------------------------------------------

func _unit(id: StringName, defense: int = 1) -> Dictionary:
	var d := UnitData.new()
	d.id = id
	d.display_name = str(id).capitalize()
	d.move = 1
	d.attack = 1
	d.defense = defense
	return {"data": d, "damage": 0}


func _env(effect_id: StringName, category: String = "Room") -> EnvironmentTokenData:
	var t := EnvironmentTokenData.new()
	t.id = effect_id
	t.effect_id = effect_id
	t.category = category
	return t


func _func(effect_id: StringName) -> FunctionTokenData:
	var t := FunctionTokenData.new()
	t.id = effect_id
	t.effect_id = effect_id
	return t


func _cell_with(tokens: Array) -> HexCell:
	var c := HexCell.new(HexCoord.new(0, 0), HexCell.TileType.ROOM)
	for entry in tokens:
		c.tokens.append(entry)   # entry: {data, face_up, kind}
	return c


## A tiny stand-in "state" exposing only what TokenEffects touches: a player with a
## bag/hand, get_player, and player_controls. No board/scene — pure and headless.
class FakeState:
	var rng := RandomNumberGenerator.new()
	var players := {}          # color -> FakePlayer
	var controlled := {}       # "color|hexkey" -> true
	var center = null

	func get_player(color):
		return players.get(color, null)

	func player_controls(color, coord) -> bool:
		return controlled.has(str(color) + "|" + coord.key())


class FakePlayer:
	var color: StringName
	var bag: Array = []
	var hand: Array = []
	func _init(_c): color = _c


func _state(color: StringName = &"green") -> FakeState:
	var s := FakeState.new()
	s.rng.seed = 42
	s.players[color] = FakePlayer.new(color)
	return s


# --- environment: deterministic (non-dice) effects ---------------------------

func test_troubling_tales_adds_a_coward_to_bag() -> void:
	var s := _state()
	var cell := _cell_with([{"data": _env(&"env_troubling_tales", "Corridor"), "face_up": false, "kind": "env"}])
	cell.add_unit(&"green", _unit(&"warrior"))
	TokenEffects.resolve_cell(s, cell, &"green", {"rng": s.rng})
	assert_eq(s.get_player(&"green").bag.count(&"coward"), 1, "Troubling Tales adds 1 Coward")
	assert_true(cell.tokens[0]["face_up"], "token is now face-up")


func test_supplies_draws_one_action_card() -> void:
	var s := _state()
	var drawn_card := UnitData.new()   # any object stands in for a card here
	var deps := {
		"rng": s.rng,
		"draw_action": func(): return drawn_card,
	}
	var cell := _cell_with([{"data": _env(&"env_supplies", "Corridor"), "face_up": false, "kind": "env"}])
	cell.add_unit(&"green", _unit(&"warrior"))
	TokenEffects.resolve_cell(s, cell, &"green", deps)
	assert_eq(s.get_player(&"green").hand.size(), 1, "Supplies draws 1 Action card into hand")


func test_gang_press_places_two_warriors() -> void:
	var s := _state()
	var wdata := UnitData.new(); wdata.id = &"warrior"; wdata.defense = 1
	var deps := {"rng": s.rng, "unit_db": {&"warrior": wdata}}
	var cell := _cell_with([{"data": _env(&"env_gang_press_survivors", "Room"), "face_up": false, "kind": "env"}])
	cell.add_unit(&"green", _unit(&"warrior"))   # one already present
	TokenEffects.resolve_cell(s, cell, &"green", deps)
	assert_eq(cell.units_for(&"green").size(), 3, "1 present + 2 Gang Press warriors = 3")


func test_dead_silence_does_nothing() -> void:
	var s := _state()
	var cell := _cell_with([{"data": _env(&"env_dead_silence", "Corridor"), "face_up": false, "kind": "env"}])
	cell.add_unit(&"green", _unit(&"warrior"))
	TokenEffects.resolve_cell(s, cell, &"green", {"rng": s.rng})
	assert_eq(cell.units_for(&"green").size(), 1, "no units lost or gained")
	assert_true(cell.tokens[0]["face_up"], "still flips face-up")


func test_persistent_tokens_record_but_dont_remove() -> void:
	# Darkness / Tough Terrain / Teleporter persist; resolution should flip them and
	# leave them on the cell (movement/combat read them later).
	for eid in [&"env_darkness", &"env_tough_terrain", &"env_teleporter_node"]:
		var s := _state()
		var cell := _cell_with([{"data": _env(eid, "Corridor"), "face_up": false, "kind": "env"}])
		cell.add_unit(&"green", _unit(&"warrior"))
		var log: Dictionary = TokenEffects.resolve_cell(s, cell, &"green", {"rng": s.rng})
		assert_true(cell.tokens[0]["face_up"], "%s flipped" % eid)
		assert_eq(cell.tokens.size(), 1, "%s stays in the room" % eid)
		assert_eq(log["resolved"].size(), 1, "%s recorded one resolution" % eid)


# --- environment: dice (damage) effects --------------------------------------

func test_falling_debris_can_kill_a_one_defense_unit() -> void:
	# Use forced outcome by seeding until we get a hit; structurally assert that when
	# damage is recorded, the dead unit is pruned. We loop a few seeds to find a hit.
	var killed_somewhere := false
	for s_idx in range(50):
		var s := _state()
		s.rng.seed = s_idx
		var cell := _cell_with([{"data": _env(&"env_falling_debris", "Room"), "face_up": false, "kind": "env"}])
		cell.add_unit(&"green", _unit(&"warrior", 1))   # Defense 1 dies on 1 hit
		var log: Dictionary = TokenEffects.resolve_cell(s, cell, &"green", {"rng": s.rng})
		var dmg: int = int(log["damage"].get(&"green", 0))
		if dmg >= 1:
			killed_somewhere = true
			assert_true(cell.units_for(&"green").is_empty(),
				"a Defense-1 Unit that took >=1 hit is pruned (seed %d)" % s_idx)
			break
	assert_true(killed_somewhere, "at least one seed produced a Falling Debris hit")


func test_turrets_roll_three_dice_and_record_damage() -> void:
	# Turrets roll 3 dice once. Over many seeds, SOME produce hits. Assert the damage
	# log is populated and never negative, and survivors are consistent with damage.
	var any_damage := false
	for s_idx in range(30):
		var s := _state()
		s.rng.seed = s_idx
		var cell := _cell_with([{"data": _env(&"env_turrets", "Room"), "face_up": false, "kind": "env"}])
		# Two tough Units (Defense 3) so a few hits don't always wipe them.
		cell.add_unit(&"green", _unit(&"heavy", 3))
		cell.add_unit(&"green", _unit(&"heavy", 3))
		var log: Dictionary = TokenEffects.resolve_cell(s, cell, &"green", {"rng": s.rng})
		var dmg: int = int(log["damage"].get(&"green", 0))
		assert_true(dmg >= 0, "damage is never negative")
		if dmg > 0:
			any_damage = true
	assert_true(any_damage, "Turrets dealt damage on at least one seed")


func test_env_guardian_spawns_a_guardian_into_the_cell() -> void:
	var s := _state()
	var gpool := [_make_guardian(&"cutter")]
	var deps := {"rng": s.rng, "guardian_pool": gpool}
	var cell := _cell_with([{"data": _env(&"env_guardian", "Room"), "face_up": false, "kind": "env"}])
	cell.add_unit(&"green", _unit(&"warrior"))
	TokenEffects.resolve_cell(s, cell, &"green", deps)
	assert_eq(cell.units_for(GUARDIAN_OWNER).size(), 1, "env Guardian spawned into the space")


func _make_guardian(id: StringName) -> GuardianData:
	var g := GuardianData.new()
	g.id = id
	g.display_name = str(id).capitalize()
	g.move = 1; g.attack = 1; g.defense = 1; g.attack_dice = 1
	return g


# --- function tokens ---------------------------------------------------------

func test_function_flips_only_when_unit_present_and_draws_artefact() -> void:
	var s := _state()
	var artefact_draws := [0]
	var deps := {
		"rng": s.rng,
		"draw_artefact": func(): artefact_draws[0] += 1,
	}
	var cell := _cell_with([{"data": _func(&"func_shield_drones"), "face_up": false, "kind": "func"}])
	# No unit present yet -> Function must NOT flip.
	TokenEffects.resolve_cell(s, cell, &"green", deps)
	assert_false(cell.tokens[0]["face_up"], "Function does not flip with no Unit present")
	assert_eq(artefact_draws[0], 0, "no Artefact drawn yet")
	# Now a Unit arrives -> Function flips AND an Artefact is drawn.
	cell.add_unit(&"green", _unit(&"warrior"))
	TokenEffects.resolve_cell(s, cell, &"green", deps)
	assert_true(cell.tokens[0]["face_up"], "Function flips once a Unit is present")
	assert_eq(artefact_draws[0], 1, "flipping a Function draws exactly one Artefact")


func test_guardian_control_room_reports_control_gate() -> void:
	var s := _state()
	var cell := _cell_with([{"data": _func(&"func_guardian_control_room"), "face_up": false, "kind": "func"}])
	cell.add_unit(&"green", _unit(&"warrior"))
	# Not controlled -> availability recorded as not-usable.
	var log: Dictionary = TokenEffects.resolve_cell(s, cell, &"green", {"rng": s.rng})
	var entry := _find(log["resolved"], &"func_guardian_control_room")
	assert_false(entry.get("controlled", true), "Control gate is false when not controlled")

func _find(arr: Array, eid: StringName) -> Dictionary:
	for e in arr:
		if e.get("effect_id") == eid:
			return e
	return {}

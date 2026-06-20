extends GutTest
## Section G — rules-audit fixes (Darkness, env +1 Defense, Manstopper setup, Dehydration,
## placed Sticky Bombs, and the 5 Artifacts). Pure-logic, headless, seeded.

const GUARDIAN_OWNER := &"guardian"


# --- builders ----------------------------------------------------------------

func _unit(id: StringName, defense := 1, attack := 1, rng_val := 0) -> Dictionary:
	var d := UnitData.new()
	d.id = id
	d.display_name = str(id).capitalize()
	d.move = 1
	d.attack = attack
	d.defense = defense
	d.range = rng_val
	return {"data": d, "damage": 0}


func _env(effect_id: StringName) -> EnvironmentTokenData:
	var t := EnvironmentTokenData.new()
	t.id = effect_id
	t.effect_id = effect_id
	return t


func _cell(coord := Vector2i(0, 0)) -> HexCell:
	return HexCell.new(HexCoord.new(coord.x, coord.y), HexCell.TileType.ROOM)


# --- FakeState reused for token/artefact tests -------------------------------

class FakePlayer:
	var color: StringName
	var bag: Array = []
	var hand: Array = []
	var artefacts: Array = []
	var pending_redeploys: Array = []
	var rally_zone = null
	func _init(c): color = c


class FakeState:
	var rng := RandomNumberGenerator.new()
	var board := {}
	var players := {}
	var center = null
	var sunstone := {}
	func get_player(c): return players.get(c, null)
	func get_cell(coord):
		return board.get(coord.key(), null) if coord != null else null
	func add_sunstone_mark(coord): sunstone[coord.key()] = true
	func is_sunstone_marked(coord): return sunstone.has(coord.key())


# =============================================================================
#  Step 1 — Darkness -1 Attack
# =============================================================================

func test_darkness_reduces_each_sides_dice():
	# Two warriors (attack 2) vs one warrior; with Darkness, each side rolls 1 fewer die.
	var resolver := CombatResolver.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var ctx := {
		"sides": [&"green", &"red"],
		"combatants": CombatResolver.combatants_from_units({
			&"green": [_unit(&"warrior", 9, 2)],
			&"red": [_unit(&"warrior", 9, 2)],
		}),
		"controller": &"",
		"extra_defense": {},
		"entering_side": &"green",
		"rng": rng,
		"space_attack_penalty": 1,
	}
	var log := resolver.resolve(ctx)
	# Count attack dice rolled by green this combat — with penalty 1 against attack 2 it's 1.
	var green_attack_dice := 0
	for e in log:
		if e.get("event") == "die" and e.get("phase") == "attack" and e.get("side") == &"green":
			green_attack_dice += 1
	# At least the first round shows the reduction (1 die, not 2), modulo crit cascades.
	assert_true(green_attack_dice >= 1, "green rolled attack dice")
	# Re-run with NO penalty and assert strictly more base dice in round one.
	rng.seed = 42
	ctx["space_attack_penalty"] = 0
	var log2 := resolver.resolve(ctx)
	var green2 := 0
	for e in log2:
		if e.get("event") == "die" and e.get("phase") == "attack" and e.get("side") == &"green":
			green2 += 1
	assert_gt(green2, green_attack_dice, "no-Darkness rolls more dice than Darkness")


# =============================================================================
#  Step 2 — Environmental damage respects controlled-ground / drone +1
# =============================================================================

func test_env_damage_respects_control_bonus():
	# A warrior (defense 1) on a controlled space should survive 1 hit (effective def 2).
	var cell := _cell()
	cell.add_unit(&"green", _unit(&"warrior", 1))
	cell.set_token_state(&"green", HexCell.TokenState.CONTROL)
	# Force 1 hit by applying damage directly through the prune path.
	cell.units[&"green"][0]["damage"] = 1
	# Use TokenEffects pruning helper indirectly via Local Fauna? Simpler: call prune.
	# Effective defense = base 1 + control 1 = 2, so 1 damage does NOT kill.
	TokenEffects._prune_dead_for(cell, &"green")
	assert_eq(cell.units_for(&"green").size(), 1, "controlled unit survives 1 hit")
	# Without control, 1 damage kills (base defense 1).
	var cell2 := _cell()
	cell2.add_unit(&"green", _unit(&"warrior", 1))
	cell2.units[&"green"][0]["damage"] = 1
	TokenEffects._prune_dead_for(cell2, &"green")
	assert_eq(cell2.units_for(&"green").size(), 0, "uncontrolled unit dies at base defense")


# =============================================================================
#  Step 7 — placed Sticky Bomb triggers on the entering side
# =============================================================================

func test_placed_sticky_bomb_hits_entrant():
	# A red bomb sits on the space; green enters with a fragile warrior. The bomb rolls
	# PLACED_BOMB_DICE at green before combat. With a seed that hits, green takes damage.
	var resolver := CombatResolver.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ctx := {
		"sides": [&"green", &"red"],
		"combatants": CombatResolver.combatants_from_units({
			&"green": [_unit(&"warrior", 9, 1)],
			&"red": [_unit(&"warrior", 9, 1)],
		}),
		"controller": &"",
		"extra_defense": {},
		"entering_side": &"green",
		"rng": rng,
		"sticky_bomb_count": 1,
	}
	var log := resolver.resolve(ctx)
	var saw_placed_bomb := false
	for e in log:
		if e.get("event") == "sticky_bomb" and e.get("side") == &"placed":
			saw_placed_bomb = true
	assert_true(saw_placed_bomb, "a placed sticky bomb rolled at the entrant")


# =============================================================================
#  Step 4 — Artifacts
# =============================================================================

func test_jam_gobbar_removes_up_to_5_cowards():
	var st := FakeState.new()
	var p := FakePlayer.new(&"green")
	for _i in range(8): p.bag.append(&"coward")
	p.bag.append(&"warrior")
	st.players[&"green"] = p
	var card := ArtefactData.new(); card.effect_id = &"the_jam_gobbar"
	p.artefacts.append(card)
	var res := ArtefactEffects.resolve(st, &"green", card, -1)
	assert_true(res.ok, "jam gobbar resolved")
	assert_eq(p.bag.count(&"coward"), 3, "removed exactly 5 cowards")
	assert_eq(p.bag.count(&"warrior"), 1, "warrior untouched")
	assert_eq(p.artefacts.size(), 0, "card discarded")


func test_sunstone_marks_space_and_forces_six():
	var st := FakeState.new()
	var p := FakePlayer.new(&"green")
	st.players[&"green"] = p
	var cell := _cell(Vector2i(1, 0))
	cell.add_unit(&"green", _unit(&"warrior"))
	st.board[cell.coord.key()] = cell
	var card := ArtefactData.new(); card.effect_id = &"sunstone_fragments"
	p.artefacts.append(card)
	var res := ArtefactEffects.resolve_targeted(st, &"green", card, -1, {"space": cell.coord})
	assert_true(res.ok, "sunstone targeted ok")
	assert_true(st.is_sunstone_marked(cell.coord), "space marked")
	assert_eq(p.artefacts.size(), 0, "card discarded")


func test_psychic_control_belt_steals_adjacent_enemy():
	var st := FakeState.new()
	var p := FakePlayer.new(&"green")
	st.players[&"green"] = p
	var src := _cell(Vector2i(0, 0))
	src.add_unit(&"green", _unit(&"warrior"))
	var enemy_cell := _cell(Vector2i(1, 0))   # distance 1 from (0,0)
	var enemy_unit := _unit(&"heavy")
	enemy_cell.add_unit(&"red", enemy_unit)
	st.board[src.coord.key()] = src
	st.board[enemy_cell.coord.key()] = enemy_cell
	var card := ArtefactData.new(); card.effect_id = &"psychic_control_belt"
	p.artefacts.append(card)
	var res := ArtefactEffects.resolve_targeted(st, &"green", card, -1, {
		"source": src.coord, "enemy_coord": enemy_cell.coord, "enemy_unit": enemy_unit,
	})
	assert_true(res.ok, "psychic steal ok: " + str(res.reason))
	assert_eq(enemy_cell.units_for(&"red").size(), 0, "enemy lost the unit")
	assert_eq(src.units_for(&"green").size(), 2, "green gained the stolen unit")


func test_medical_machine_arms_and_redeploys():
	var st := FakeState.new()
	var p := FakePlayer.new(&"green")
	var rz := _cell(Vector2i(2, 0))
	p.rally_zone = rz.coord
	st.board[rz.coord.key()] = rz
	st.players[&"green"] = p
	var card := ArtefactData.new(); card.effect_id = &"medical_machine"
	p.artefacts.append(card)
	var killed := _unit(&"scout")
	assert_true(ArtefactEffects.arm_medical_machine(st, &"green", killed), "armed")
	assert_eq(p.artefacts.size(), 0, "medical machine discarded on arm")
	assert_eq(p.pending_redeploys.size(), 1, "one redeploy queued")
	var db := {&"scout": killed["data"]}
	var placed := ArtefactEffects.apply_pending_redeploys(st, &"green", {"unit_db": db})
	assert_eq(placed, 1, "redeployed one unit")
	assert_eq(rz.units_for(&"green").size(), 1, "scout placed in rally zone")
	assert_eq(p.pending_redeploys.size(), 0, "queue cleared")


# =============================================================================
#  Sunstone Fragments — ranged-only (Range >= 1) hit-floor, melee unaffected
# =============================================================================

func _sunstone_hits(attacker_range: int, seed: int) -> int:
	# One attacker (attack 5 dice) vs an indestructible defender, on a Sunstone space.
	# Returns hits scored by the attacker. With a ranged attacker, only 6s count.
	var resolver := CombatResolver.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var atk := _unit(&"attacker", 99, 5, attacker_range)
	var ctx := {
		"sides": [&"green", &"red"],
		"combatants": CombatResolver.combatants_from_units({
			&"green": [atk],
			&"red": [_unit(&"rock", 999, 0)],
		}),
		"controller": &"",
		"extra_defense": {},
		"entering_side": &"green",
		"rng": rng,
		"sunstone_active": true,
	}
	var log := resolver.resolve(ctx)
	var hits := 0
	for e in log:
		if e.get("event") == "die" and e.get("side") == &"green" and e.get("hit"):
			hits += 1
	return hits


func test_sunstone_limits_ranged_not_melee():
	# For the SAME seed, a melee attacker (Range 0) scores >= a ranged attacker (Range 1),
	# because Sunstone forces the ranged attacker to need 6s. Average over a few seeds to
	# avoid a flukey tie.
	var melee_total := 0
	var ranged_total := 0
	for seed in [1, 2, 3, 4, 5, 6, 7, 8]:
		melee_total += _sunstone_hits(0, seed)
		ranged_total += _sunstone_hits(1, seed)
	assert_gt(melee_total, ranged_total,
		"melee (unaffected) out-hits ranged (limited to 6s) under Sunstone")

# =============================================================================
#  Ranged SUPPORT FIRE (Ch.11) — shooters add dice into a melee, take no return fire
# =============================================================================

func test_eligible_ranged_shooters_filters_correctly():
	var st := FakeState.new()
	# Combat at C = (0,0): green melee vs red.
	var combat := _cell(Vector2i(0, 0))
	combat.add_unit(&"green", _unit(&"warrior", 1, 2, 0))
	combat.add_unit(&"red", _unit(&"warrior", 1, 2, 0))
	st.board[combat.coord.key()] = combat
	# Valid: a green Gunner (Range 1) adjacent, unactivated, no enemy.
	var ok_cell := _cell(Vector2i(1, 0))
	ok_cell.add_unit(&"green", _unit(&"gunner", 1, 1, 1))
	st.board[ok_cell.coord.key()] = ok_cell
	# Out of range: Gunner (Range 1) two spaces away.
	var far := _cell(Vector2i(2, 0))
	far.add_unit(&"green", _unit(&"gunner", 1, 1, 1))
	st.board[far.coord.key()] = far
	# Activated space: excluded.
	var act := _cell(Vector2i(0, 1))
	act.add_unit(&"green", _unit(&"gunner", 1, 1, 1))
	act.set_token_state(&"green", HexCell.TokenState.ACTIVE)
	st.board[act.coord.key()] = act
	# Enemy co-located: excluded.
	var enemied := _cell(Vector2i(-1, 1))   # distance 1 from (0,0)
	enemied.add_unit(&"green", _unit(&"gunner", 1, 1, 1))
	enemied.add_unit(&"red", _unit(&"warrior", 1, 1, 0))
	st.board[enemied.coord.key()] = enemied
	# Melee (Range 0) adjacent: excluded.
	var melee := _cell(Vector2i(0, -1))
	melee.add_unit(&"green", _unit(&"warrior", 1, 2, 0))
	st.board[melee.coord.key()] = melee

	var elig := ActionResolver.eligible_ranged_shooters(st, &"green", combat.coord, {})
	assert_eq(elig.size(), 1, "exactly one eligible shooter")
	assert_true(elig[0]["coord"].equals(ok_cell.coord), "the adjacent in-range Gunner")


func test_manstopper_shooter_excluded_if_moved_more_than_one():
	var st := FakeState.new()
	var combat := _cell(Vector2i(0, 0))
	combat.add_unit(&"green", _unit(&"warrior", 1, 2, 0))
	combat.add_unit(&"red", _unit(&"warrior", 1, 2, 0))
	st.board[combat.coord.key()] = combat
	var mcell := _cell(Vector2i(1, 0))
	var manstopper := _unit(&"manstopper", 1, 2, 1)
	manstopper["data"].extra_setup_move = true
	mcell.add_unit(&"green", manstopper)
	st.board[mcell.coord.key()] = mcell
	# Moved 2 this activation -> excluded.
	var moved2 := {"entries": [{"unit": manstopper, "steps": 2}]}
	assert_eq(ActionResolver.eligible_ranged_shooters(st, &"green", combat.coord, moved2).size(),
		0, "manstopper that moved 2 is excluded")
	# Moved 1 (or absent) -> eligible.
	var moved1 := {"entries": [{"unit": manstopper, "steps": 1}]}
	assert_eq(ActionResolver.eligible_ranged_shooters(st, &"green", combat.coord, moved1).size(),
		1, "manstopper that moved 1 is eligible")
	assert_eq(ActionResolver.eligible_ranged_shooters(st, &"green", combat.coord, {}).size(),
		1, "manstopper that didn't move is eligible")


func _support_ctx(seed: int, shooter_attack: int, sunstone: bool, darkness: bool) -> Array:
	# Green warrior (tanky) vs red warrior (tanky), plus a green Gunner shooter firing IN.
	var resolver := CombatResolver.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var shooter := _unit(&"gunner", 9, shooter_attack, 1)
	var shooter_combatants: Array = CombatResolver.combatants_from_units({&"green": [shooter]})[&"green"]
	var ctx := {
		"sides": [&"green", &"red"],
		"combatants": CombatResolver.combatants_from_units({
			&"green": [_unit(&"warrior", 99, 1)],
			&"red": [_unit(&"warrior", 99, 1)],
		}),
		"controller": &"",
		"extra_defense": {},
		"entering_side": &"green",
		"rng": rng,
		"support_shooters": shooter_combatants,
		"support_side": &"green",
		"sunstone_active": sunstone,
		"space_attack_penalty": (1 if darkness else 0),
	}
	return [resolver.resolve(ctx), shooter]


func test_support_shooters_add_dice_and_take_no_return_fire():
	var pair := _support_ctx(11, 6, false, false)
	var log: Array = pair[0]
	var shooter = pair[1]
	# Shooter dice appear in the log under the entering side.
	var shooter_dice := 0
	for e in log:
		if e.get("event") == "die" and e.get("side") == &"green" and e.get("unit") == &"gunner":
			shooter_dice += 1
	assert_gt(shooter_dice, 0, "shooter contributed attack dice")
	# Shooter never takes damage (never in the combat cell; never targeted).
	assert_eq(shooter.get("damage", 0), 0, "support shooter takes no return fire")


func test_support_shooters_respect_sunstone():
	# Same seed: a Gunner shooter scores fewer hits when the combat space is Sunstone-marked
	# (ranged -> hit only on 6). Average over seeds.
	var marked := 0
	var unmarked := 0
	for seed in [1, 2, 3, 4, 5, 6, 7, 8]:
		var u: Array = _support_ctx(seed, 6, false, false)[0]
		var m: Array = _support_ctx(seed, 6, true, false)[0]
		for e in u:
			if e.get("event") == "die" and e.get("unit") == &"gunner" and e.get("hit"):
				unmarked += 1
		for e in m:
			if e.get("event") == "die" and e.get("unit") == &"gunner" and e.get("hit"):
				marked += 1
	assert_gt(unmarked, marked, "Sunstone limits support shooters to 6s")


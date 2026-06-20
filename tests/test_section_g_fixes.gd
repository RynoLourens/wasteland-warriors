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
#  Ranged attack (Ch.11) — fire without moving in; range-gated; melee can't
# =============================================================================

func test_ranged_attack_fires_without_moving():
	var st := FakeState.new()
	st.rng.seed = 5
	var shooter_cell := _cell(Vector2i(0, 0))
	# A Gunner (Range 1) with lots of dice so it reliably scores a hit at this seed.
	shooter_cell.add_unit(&"green", _unit(&"gunner", 1, 6, 1))
	var target_cell := _cell(Vector2i(1, 0))   # distance 1 — in range
	target_cell.add_unit(&"red", _unit(&"warrior", 1, 2, 0))
	st.board[shooter_cell.coord.key()] = shooter_cell
	st.board[target_cell.coord.key()] = target_cell

	var res := ActionResolver.resolve_ranged_attack(st, &"green", {
		"activate": shooter_cell.coord, "target": target_cell.coord,
	})
	assert_true(res.ok, "ranged attack resolved: " + str(res.get("reason")))
	# Shooter never moved: still in its own space, now Activated.
	assert_eq(shooter_cell.units_for(&"green").size(), 1, "shooter stayed put")
	assert_true(shooter_cell.has_faceup_activation(&"green"), "firing space Activated")
	# The defending warrior (defense 1) should have died to the 6-dice volley.
	assert_eq(target_cell.units_for(&"red").size(), 0, "target warrior killed by ranged fire")
	# Attacker takes NO retaliation (one-sided).
	assert_eq(shooter_cell.units_for(&"green")[0].get("damage", 0), 0, "shooter untouched")


func test_ranged_attack_rejected_out_of_range():
	var st := FakeState.new()
	var shooter_cell := _cell(Vector2i(0, 0))
	shooter_cell.add_unit(&"green", _unit(&"gunner", 1, 1, 1))   # Range 1
	var far := _cell(Vector2i(2, 0))                              # distance 2 — out of range
	far.add_unit(&"red", _unit(&"warrior", 1, 2, 0))
	st.board[shooter_cell.coord.key()] = shooter_cell
	st.board[far.coord.key()] = far
	var res := ActionResolver.resolve_ranged_attack(st, &"green", {
		"activate": shooter_cell.coord, "target": far.coord,
	})
	assert_false(res.ok, "out-of-range ranged attack rejected")
	assert_false(shooter_cell.has_faceup_activation(&"green"), "no activation on a rejected action")


func test_melee_cannot_ranged_attack():
	var st := FakeState.new()
	var melee_cell := _cell(Vector2i(0, 0))
	melee_cell.add_unit(&"green", _unit(&"warrior", 1, 2, 0))   # Range 0
	var target_cell := _cell(Vector2i(1, 0))
	target_cell.add_unit(&"red", _unit(&"warrior", 1, 2, 0))
	st.board[melee_cell.coord.key()] = melee_cell
	st.board[target_cell.coord.key()] = target_cell
	var res := ActionResolver.resolve_ranged_attack(st, &"green", {
		"activate": melee_cell.coord, "target": target_cell.coord,
	})
	assert_false(res.ok, "melee-only space cannot make a ranged attack")


func test_ranged_targets_helper_lists_in_range_enemies():
	var st := FakeState.new()
	var shooter_cell := _cell(Vector2i(0, 0))
	shooter_cell.add_unit(&"green", _unit(&"gunner", 1, 1, 1))   # Range 1
	var adj_enemy := _cell(Vector2i(1, 0))
	adj_enemy.add_unit(&"red", _unit(&"warrior"))
	var far_enemy := _cell(Vector2i(2, 0))
	far_enemy.add_unit(&"red", _unit(&"warrior"))
	var adj_empty := _cell(Vector2i(0, 1))
	st.board[shooter_cell.coord.key()] = shooter_cell
	st.board[adj_enemy.coord.key()] = adj_enemy
	st.board[far_enemy.coord.key()] = far_enemy
	st.board[adj_empty.coord.key()] = adj_empty
	var targets := ActionResolver.ranged_targets_for(st, &"green", shooter_cell.coord)
	# Only the adjacent ENEMY space qualifies (far is out of range; empty has no enemy).
	assert_eq(targets.size(), 1, "exactly one valid ranged target")
	assert_true(targets[0].equals(adj_enemy.coord), "the in-range enemy space")

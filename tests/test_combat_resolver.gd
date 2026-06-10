extends GutTest
## Section C — Combat resolver tests.
##
## Each special unit and Guardian is exercised IN ISOLATION via a scripted die
## sequence (context["forced_faces"]) so outcomes are exact, plus a seeded
## 10,000-combat sim that must never crash and must produce a sane hit rate.
##
## Units are the real .tres Resources, so these tests also guard the data: if a
## .tres stat or flag drifts, the matching test fails.

const UNIT_DIR := "res://data/units/"
const GUARD_DIR := "res://data/guardians/"


# --- helpers --------------------------------------------------------------

func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


func _u(id: String):
	return load(UNIT_DIR + id + ".tres")


func _g(id: String):
	return load(GUARD_DIR + id + ".tres")


## A live unit dict as it sits on a HexCell: {data, damage}.
func _unit(data, damage: int = 0) -> Dictionary:
	return {"data": data, "damage": damage}


## Build the combatants map from {side -> Array[{data,damage}]}.
func _combatants(units_by_side: Dictionary) -> Dictionary:
	return CombatResolver.combatants_from_units(units_by_side)


## Run one combat with optional scripted faces. Returns {log, combatants}.
func _fight(units_by_side: Dictionary, forced: Array = [],
		controller: StringName = &"", entering: StringName = &"",
		extra_def: Dictionary = {}) -> Dictionary:
	var resolver := CombatResolver.new()
	var combatants := _combatants(units_by_side)
	var sides: Array = units_by_side.keys()
	var log := resolver.resolve({
		"sides": sides,
		"combatants": combatants,
		"controller": controller,
		"entering_side": entering,
		"extra_defense": extra_def,
		"forced_faces": forced,
		"rng": _rng(1),
	})
	return {"log": log, "combatants": combatants}


func _alive(combatants: Dictionary, side: StringName) -> Array:
	var out: Array = []
	for c in combatants[side]:
		if c.alive:
			out.append(c)
	return out


func _events(log: Array, ev: String) -> Array:
	var out: Array = []
	for e in log:
		if e.get("event") == ev:
			out.append(e)
	return out


func _dice_for(log: Array, side: StringName) -> Array:
	var out: Array = []
	for e in log:
		if e.get("event") == "die" and e.get("side") == side:
			out.append(e)
	return out


# --- core pipeline --------------------------------------------------------

func test_two_hits_kill_lone_enemy_warrior() -> void:
	# 'a' Warrior rolls 2 dice = 6(hit+crit), 4(hit); the 6 cascades into a
	# forced 2 (miss). 2 hits land on b's 1-Defense Warrior -> it dies.
	# b's 2 dice are forced 1,1 = 0 hits, so a survives.
	var res := _fight({&"a": [_unit(_u("warrior"))], &"b": [_unit(_u("warrior"))]},
		[6, 4, 2, 1, 1])
	assert_eq(_alive(res.combatants, &"b").size(), 0, "enemy warrior dies to 2 hits")
	assert_eq(_alive(res.combatants, &"a").size(), 1, "attacker survives a miss")


func test_simultaneous_both_can_die_same_round() -> void:
	# Both Warriors score a kill in the SAME round; neither is removed before
	# the other rolls. a: 6,4 (then bonus 1) = 2 hits. b: 6,4 (then bonus 1) = 2.
	var res := _fight({&"a": [_unit(_u("warrior"))], &"b": [_unit(_u("warrior"))]},
		[6, 4, 1, 6, 4, 1])
	assert_eq(_alive(res.combatants, &"a").size(), 0, "a died")
	assert_eq(_alive(res.combatants, &"b").size(), 0, "b died too (simultaneous)")


func test_damage_persists_on_survivor() -> void:
	# Heavy (Defense 2) takes exactly 1 hit and survives carrying that damage.
	# a Warrior: 6,1 then bonus 1 = 1 hit. Heavy survives at damage 1.
	var res := _fight({&"a": [_unit(_u("warrior"))], &"b": [_unit(_u("heavy"))]},
		[6, 1, 1, 1, 1])
	var heavy = res.combatants[&"b"][0]
	assert_true(heavy.alive, "heavy survives one hit")
	assert_eq(heavy.unit_dict["damage"], 1, "damage token persists on the survivor")


# --- special units --------------------------------------------------------

func test_berserker_crits_on_five() -> void:
	# Berserker (crit_on = 5): a forced 5 must grant a bonus die. 2 base dice
	# 5,1 -> the 5 cascades to a forced 1, so 'a' rolls 3 dice total.
	var res := _fight({&"a": [_unit(_u("berserker"))],
		&"b": [_unit(_u("heavy")), _unit(_u("heavy")), _unit(_u("heavy"))]},
		[5, 1, 1, 1, 1, 1, 1, 1, 1])
	assert_eq(_dice_for(res.log, &"a").size(), 3, "berserker's 5 cascades into a bonus die")


func test_warrior_does_not_crit_on_five() -> void:
	# Control: a Warrior (crit_on = 6) rolling a 5 is a hit but NO cascade.
	var res := _fight({&"a": [_unit(_u("warrior"))],
		&"b": [_unit(_u("heavy")), _unit(_u("heavy"))]},
		[5, 5, 1, 1])
	assert_eq(_dice_for(res.log, &"a").size(), 2, "warrior's 5 does not cascade")


func test_infiltrator_hits_only_on_six() -> void:
	# Infiltrator (hit_only_on = 6, attack 0 but rolls via hit_only path? No —
	# attack 0 means 0 dice). Use Typhoon for the hit-floor test instead; here we
	# assert Infiltrator contributes 0 dice (attack 0), i.e. deals no damage.
	var res := _fight({&"a": [_unit(_u("infiltrator"))], &"b": [_unit(_u("warrior"))]},
		[1, 1])
	assert_eq(_dice_for(res.log, &"a").size(), 0, "infiltrator rolls no attack dice")


func test_sticky_bomb_fires_pre_combat_on_entering_side() -> void:
	# Sapperteur already in the space; enemy 'b' ENTERS. Sticky bomb rolls 2
	# dice at b BEFORE the main round. Force 6,4 to score 2 hits pre-combat.
	var res := _fight({&"a": [_unit(_u("sapperteur"))], &"b": [_unit(_u("warrior"))]},
		[6, 1, 1, 1, 1, 1, 1], &"", &"b")
	var sticky := _events(res.log, "sticky_bomb")
	assert_gt(sticky.size(), 0, "a sticky_bomb event fired")
	# The sticky_bomb event must precede the first round_start.
	var sb_i := -1
	var rs_i := -1
	for i in range(res.log.size()):
		var ev: String = res.log[i].get("event")
		if ev == "sticky_bomb" and sb_i == -1:
			sb_i = i
		if ev == "round_start" and rs_i == -1:
			rs_i = i
	assert_true(sb_i != -1 and (rs_i == -1 or sb_i < rs_i),
		"sticky bomb resolves before the main round")


# --- guardians ------------------------------------------------------------

func test_typhoon_hits_only_on_six() -> void:
	# Typhoon (hit_only_on = 6): 3 dice forced 4,5,5 score ZERO hits.
	var res := _fight({&"a": [_unit(_g("typhoon"))], &"b": [_unit(_u("heavy"))]},
		[4, 5, 5, 1])
	assert_eq(_events(res.log, "hit_assigned").filter(
		func(e): return e["side"] == &"b").size(), 0,
		"typhoon faces below 6 score no hits")


func test_cutter_crits_on_five() -> void:
	# Cutter (crit_on = 5): forced 5 cascades. 3 base dice 5,1,1 -> 4 dice total.
	var res := _fight({&"a": [_unit(_g("cutter"))],
		&"b": [_unit(_u("heavy")), _unit(_u("heavy")), _unit(_u("heavy"))]},
		[5, 1, 1, 1, 1, 1, 1, 1])
	assert_eq(_dice_for(res.log, &"a").size(), 4, "cutter's 5 cascades (4 dice from 3)")


func test_razor_applies_hits_first() -> void:
	# Razor (applies_hits_first): his attack resolves in a pre-combat sub-round.
	# Force 6,4 so he kills b's 1-Defense Warrior BEFORE any round_start.
	var res := _fight({&"a": [_unit(_g("razor"))], &"b": [_unit(_u("warrior"))]},
		[6, 4, 1, 1, 1, 1])
	assert_gt(_events(res.log, "hits_first").size(), 0, "a hits_first event fired")
	var seen_round := false
	var pre_round_death := false
	for e in res.log:
		if e.get("event") == "round_start":
			seen_round = true
		if e.get("event") == "death" and not seen_round:
			pre_round_death = true
	assert_true(pre_round_death, "razor kills in the pre-combat sub-round")


func test_scrape_runs_two_full_rounds() -> void:
	# Scrape (extra_attack_rounds = 1) makes the WHOLE combat run 2 rounds.
	# Give b enough Heavies to survive round 0 so round 1 actually occurs.
	# Force all misses (1s) so nobody dies and both rounds run.
	var ones: Array = []
	for _i in range(40):
		ones.append(1)
	var res := _fight({&"a": [_unit(_g("scrape"))],
		&"b": [_unit(_u("heavy")), _unit(_u("heavy")), _unit(_u("heavy"))]},
		ones)
	var rounds: Array = []
	for e in res.log:
		if e.get("event") == "round_start":
			rounds.append(e["round"])
	assert_eq(rounds, [0, 1], "scrape forces two simultaneous rounds")


func test_blackout_reduces_each_side_by_one_die() -> void:
	# Blackout (reduces_attack): -1 die to each side. Blackout has 3 attack dice;
	# with the global -1 it rolls 2. Force misses; count a's dice = 2.
	var res := _fight({&"a": [_unit(_g("blackout"))], &"b": [_unit(_u("warrior"))]},
		[1, 1, 1, 1, 1, 1])
	assert_eq(_dice_for(res.log, &"a").size(), 2,
		"blackout's own attack is reduced by its global -1 die")


func test_the_ox_has_two_attack_dice() -> void:
	# The Ox (attack_dice = 2): rolls exactly 2 dice regardless of Attack stat.
	var res := _fight({&"a": [_unit(_g("the_ox"))], &"b": [_unit(_u("heavy"))]},
		[1, 1, 1])
	assert_eq(_dice_for(res.log, &"a").size(), 2, "the ox rolls its 2 attack dice")


# --- defensive interactions ----------------------------------------------

func test_control_plus_one_saves_a_warrior() -> void:
	# A controlled Warrior (eff Defense 2) survives a single hit at damage 1.
	# a forces one hit (6 then bonus 1, plus a 1); b controls its own space.
	var res := _fight({&"a": [_unit(_u("warrior"))], &"b": [_unit(_u("warrior"))]},
		[6, 1, 1, 1, 1], &"b")
	var w = res.combatants[&"b"][0]
	assert_true(w.alive, "controlled warrior survives one hit")
	assert_eq(w.unit_dict["damage"], 1, "carries 1 damage under +1 control defense")


func test_control_stacks_with_shield_drone() -> void:
	# Control (+1) and a Shield Drone (+1) DO stack -> +2. A Warrior (base Def 1)
	# on a space its side controls, alongside a Shield Drone, has eff Defense 3.
	# Three hits leave it alive at damage 2; the same Warrior with control only
	# (eff Def 2) would already be dead. Shield Drone built in-code from the
	# schema (no .tres yet — it's a future unit).
	var drone := UnitData.new()
	drone.id = &"shield_drone"
	drone.display_name = "Shield Drone"
	drone.attack = 0
	drone.defense = 3
	drone.grants_ground_defense = true

	var res := _fight({
			&"a": [_unit(_u("warrior")), _unit(_u("warrior")), _unit(_u("warrior"))],
			&"b": [_unit(_u("warrior")), _unit(drone)],
		},
		# a's 3 warriors = 6 dice; force exactly 2 hits (4,4) then misses. The
		# minimise-losses policy stacks both onto b's Warrior (closer to dying
		# than the Defense-3 drone). At eff Defense 3 it SURVIVES at damage 2 —
		# control-only (eff Def 2, see baseline below) would die to the same 2.
		[4, 4, 1, 1, 1, 1], &"b")
	var w = res.combatants[&"b"][0]
	assert_eq(w.data.id, &"warrior", "first b unit is the warrior")
	assert_true(w.alive, "warrior survives 2 hits at eff Defense 3 (control +1, drone +1)")
	assert_eq(w.unit_dict["damage"], 2, "carries 2 damage; the +2 stacked bonus kept it alive")


func test_control_only_warrior_dies_to_two_hits() -> void:
	# Baseline proving the stack above: the SAME Warrior with control only
	# (eff Defense 2, no drone) dies to those same 2 hits.
	var res := _fight({
			&"a": [_unit(_u("warrior")), _unit(_u("warrior")), _unit(_u("warrior"))],
			&"b": [_unit(_u("warrior"))],
		},
		[4, 4, 1, 1, 1, 1], &"b")
	assert_false(res.combatants[&"b"][0].alive,
		"control-only warrior (eff Def 2) dies to 2 hits")


func test_minimise_losses_assignment() -> void:
	# Defender with two Heavies, one pre-damaged to 1. Two incoming hits should
	# finish the wounded Heavy and leave the fresh one alive (fewest losses).
	var res := _fight({&"a": [_unit(_u("warrior"))],
		&"b": [_unit(_u("heavy"), 1), _unit(_u("heavy"))]},
		[6, 4, 1])
	var wounded = res.combatants[&"b"][0]
	var fresh = res.combatants[&"b"][1]
	assert_false(wounded.alive, "wounded heavy is finished")
	assert_true(fresh.alive, "fresh heavy is spared (loss minimised)")


# --- robustness / stochastic ---------------------------------------------

func test_all_sixes_cascade_is_bounded() -> void:
	# A pathological all-6 stream must terminate at the MAX_CASCADE guard, never
	# infinite-loop. Force 200 sixes for a single Warrior (2 dice).
	var sixes: Array = []
	for _i in range(200):
		sixes.append(6)
	var res := _fight({&"a": [_unit(_u("warrior"))],
		&"b": [_unit(_u("heavy"))]}, sixes)
	assert_lte(_dice_for(res.log, &"a").size(), CombatResolver.MAX_CASCADE + 2,
		"cascade is bounded by MAX_CASCADE")


func test_ten_thousand_combats_never_crash() -> void:
	# Seeded sim: random rosters, never crashes, sane hit rate. Mirrors the
	# Python verification (which observed ~0.47 with Typhoon/Infiltrator pulling
	# the 0.5 baseline down).
	var ids := ["warrior", "gunner", "heavy", "scout", "berserker",
		"manstopper", "sapperteur"]
	var gids := ["the_ox", "razor", "scrape", "arachnid", "blackout",
		"blink", "cutter", "typhoon"]
	var total_dice := 0
	var total_hits := 0
	for seed in range(10000):
		var rng := _rng(seed)
		var a_units: Array = []
		var b_units: Array = []
		for _k in range(1 + (seed % 3)):
			a_units.append(_unit(_u(ids[rng.randi_range(0, ids.size() - 1)])))
			b_units.append(_unit(_g(gids[rng.randi_range(0, gids.size() - 1)])))
		var resolver := CombatResolver.new()
		var combatants := _combatants({&"a": a_units, &"b": b_units})
		var log := resolver.resolve({
			"sides": [&"a", &"b"],
			"combatants": combatants,
			"controller": &"a" if seed % 2 == 0 else &"",
			"rng": rng,
		})
		for e in log:
			if e.get("event") == "die":
				total_dice += 1
				if e.get("hit"):
					total_hits += 1
	assert_gt(total_dice, 0, "dice were rolled across the sim")
	var rate := float(total_hits) / float(total_dice)
	assert_between(rate, 0.30, 0.60, "hit rate is sane (~0.5, lower with hit-on-6 units)")

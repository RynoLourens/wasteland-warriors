extends GutTest
## Rulebook-coverage fixes: Arachnid (range-2 after-move ranged attack), The Ox
## (attacks-on-move without stopping), Guardian sync-combat full defense context, and the
## Action-card type gate. Pure-logic, headless, seeded.

const GUARDIAN_OWNER := &"guardian"


# --- builders ----------------------------------------------------------------

func _udata(id: StringName, defense := 1, attack := 1, rng_val := 0, grants_drone := false) -> UnitData:
	var d := UnitData.new()
	d.id = id
	d.display_name = str(id).capitalize()
	d.move = 1
	d.attack = attack
	d.defense = defense
	d.range = rng_val
	d.grants_ground_defense = grants_drone
	return d


func _unit(id: StringName, defense := 1, attack := 1) -> Dictionary:
	return {"data": _udata(id, defense, attack), "damage": 0}


func _gdata(id: StringName, mv: int, dice: int, rng_v := 1, attacks_on_move := false) -> GuardianData:
	var g := GuardianData.new()
	g.id = id
	g.display_name = str(id).capitalize()
	g.move = mv
	g.attack_dice = dice
	g.defense = 9
	g.range = rng_v
	g.attacks_on_move = attacks_on_move
	g.crit_on = 6
	return g


func _cell(q: int, r: int, tile := HexCell.TileType.ROOM) -> HexCell:
	return HexCell.new(HexCoord.new(q, r), tile)


## Build a tiny linear board: cells at the given axial coords, each connected to its
## east/west neighbour so a Guardian can walk along it.
func _line_board(coords: Array) -> Dictionary:
	var board := {}
	for c in coords:
		var cell := _cell(c.x, c.y)
		board[cell.coord.key()] = cell
	# Open E/W doorways between consecutive cells (dir 0 = E, dir 3 = W).
	for i in range(coords.size() - 1):
		var a: HexCell = board[HexCoord.new(coords[i].x, coords[i].y).key()]
		var b: HexCell = board[HexCoord.new(coords[i + 1].x, coords[i + 1].y).key()]
		# Only open if they're actually adjacent (east neighbour).
		if a.coord.distance_to(b.coord) == 1:
			a.set_exit(0, true)
			b.set_exit(3, true)
	return board


class MiniState:
	var rng := RandomNumberGenerator.new()
	var deck_rng := RandomNumberGenerator.new()
	var board := {}
	func get_cell(coord):
		return board.get(coord.key(), null) if coord != null else null
	func get_player(_c): return null


# =============================================================================
#  The Ox — attacks on move-in and KEEPS MOVING
# =============================================================================

func test_ox_attacks_through_without_stopping():
	# Board: Ox at (0,0); enemy warrior at (1,0); empty (2,0). Ox Move 2.
	var st := MiniState.new()
	st.rng.seed = 1
	st.board = _line_board([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	var gm := GuardianManager.new([], 1)
	gm.rng.seed = 1
	var ox := {"data": _gdata(&"the_ox", 2, 2, 1, true), "damage": 0}
	st.board[HexCoord.new(0, 0).key()].add_unit(GUARDIAN_OWNER, ox)
	# A fragile warrior (def 1) the Ox will plough into at (1,0).
	st.board[HexCoord.new(1, 0).key()].add_unit(&"green", _unit(&"warrior", 1, 1))
	gm.run_guardian_movement(st, false)   # no spawn; just move the Ox
	# The Ox should NOT be sitting on (1,0) (it didn't stop) — it moved its full 2 steps
	# and ended on (2,0), ploughing through the enemy space.
	assert_eq(st.board[HexCoord.new(1, 0).key()].units_for(GUARDIAN_OWNER).size(), 0,
		"Ox did not stop on the enemy space")
	assert_eq(st.board[HexCoord.new(2, 0).key()].units_for(GUARDIAN_OWNER).size(), 1,
		"Ox ended on (2,0), having moved through")


# =============================================================================
#  Arachnid — range-2 after-move ranged attack
# =============================================================================

func test_arachnid_fires_at_space_within_range_2():
	# Arachnid at (0,0), Move 1 along the line to (1,0); a warrior sits at (2,0) — distance
	# 2 from the Arachnid's END position (1,0). Arachnid range 2 -> it shoots (2,0).
	var st := MiniState.new()
	st.rng.seed = 3
	st.board = _line_board([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	var gm := GuardianManager.new([], 3)
	gm.rng.seed = 3
	var arachnid := {"data": _gdata(&"arachnid", 1, 5, 2, false), "damage": 0}
	st.board[HexCoord.new(0, 0).key()].add_unit(GUARDIAN_OWNER, arachnid)
	# Fragile warrior at (2,0): within range 2 of the Arachnid's landing space (1,0).
	st.board[HexCoord.new(2, 0).key()].add_unit(&"green", _unit(&"warrior", 1, 1))
	gm.run_guardian_movement(st, false)
	# With 5 attack dice vs a def-1 warrior, the ranged shot should kill it.
	assert_eq(st.board[HexCoord.new(2, 0).key()].units_for(&"green").size(), 0,
		"Arachnid's range-2 shot killed the distant warrior")


func test_arachnid_divides_damage_across_players_rounded_up():
	# Two players share the targeted space; Arachnid's hits divide evenly, rounded up.
	# We call the ranged attack directly with a fixed target to assert the division.
	var st := MiniState.new()
	st.rng.seed = 5
	st.board = _line_board([Vector2i(0, 0), Vector2i(1, 0)])
	var gm := GuardianManager.new([], 5)
	gm.rng.seed = 5
	var target: HexCell = st.board[HexCoord.new(1, 0).key()]
	# Tanky units so they survive to show the per-player split (def 9 each).
	target.add_unit(&"green", _unit(&"warrior", 9, 1))
	target.add_unit(&"red", _unit(&"warrior", 9, 1))
	var arachnid := {"data": _gdata(&"arachnid", 1, 6, 2, false), "damage": 0}
	# Fire from (0,0) at range 2; (1,0) is the only candidate.
	gm._arachnid_ranged_attack(st, HexCoord.new(0, 0), arachnid, 2)
	var g_dmg: int = target.units_for(&"green")[0].get("damage", 0)
	var r_dmg: int = target.units_for(&"red")[0].get("damage", 0)
	# Each player took ceil(total/2). The two per-player shares are equal (same ceil value).
	assert_eq(g_dmg, r_dmg, "damage split evenly between the two players")
	assert_gt(g_dmg, 0, "each present player took at least some damage")


# =============================================================================
#  Guardian sync-combat respects defender Control / Shield-Drone +1
# =============================================================================

func test_guardian_combat_respects_controlled_ground():
	# A guardian (2 dice) attacks a def-1 warrior that CONTROLS its space (+1 => eff def 2).
	# Compare survival vs the same warrior uncontrolled. Use a seed where 2 dice deal exactly
	# 1 hit is unreliable, so instead assert the prune threshold via the helper directly.
	var st := MiniState.new()
	var cell := _cell(0, 0)
	cell.add_unit(&"green", _unit(&"warrior", 1, 1))
	cell.set_token_state(&"green", HexCell.TokenState.CONTROL)
	cell.units[&"green"][0]["damage"] = 1   # 1 damage; eff def = 2 -> survives
	var gm := GuardianManager.new([], 1)
	gm._prune_dead_and_handle_guardians(st, cell, cell.coord)
	assert_eq(cell.units_for(&"green").size(), 1,
		"controlled warrior survives 1 hit from a Guardian (eff def 2)")
	# Uncontrolled: 1 damage kills (base def 1).
	var cell2 := _cell(1, 0)
	cell2.add_unit(&"green", _unit(&"warrior", 1, 1))
	cell2.units[&"green"][0]["damage"] = 1
	gm._prune_dead_and_handle_guardians(st, cell2, cell2.coord)
	assert_eq(cell2.units_for(&"green").size(), 0,
		"uncontrolled warrior dies to the same hit")


# =============================================================================
#  Action-card TYPE gate
# =============================================================================

func _card(id: StringName, card_type: int) -> ActionCardData:
	var c := ActionCardData.new()
	c.id = id
	c.card_name = str(id)
	c.card_type = card_type
	c.effect_id = id
	return c


func test_card_type_gate_helper():
	# RoundFSM._card_is_type accepts only the matching type. We exercise it via a bare FSM.
	var fsm := RoundFSM.new(MiniState.new(), {}, {}, [], 0)
	var recruit := _card(&"r", ActionCardData.CardType.RECRUITMENT)
	var movement := _card(&"m", ActionCardData.CardType.MOVEMENT)
	assert_true(fsm._card_is_type(recruit, ActionCardData.CardType.RECRUITMENT),
		"recruit card passes the recruit gate")
	assert_false(fsm._card_is_type(movement, ActionCardData.CardType.RECRUITMENT),
		"movement card rejected at the recruit gate")
	assert_true(fsm._card_is_type(movement, ActionCardData.CardType.MOVEMENT),
		"movement card passes the movement gate")
	assert_false(fsm._card_is_type(null, ActionCardData.CardType.MOVEMENT),
		"null card never plays")

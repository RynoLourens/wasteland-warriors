extends RefCounted
class_name ArtefactEffects
## Artifact-card effect resolver (rulebook Ch.11 + Artifact Deck cards).
##
## Mirrors CardEffects: dispatch on a card's `effect_id`, never on display names. A
## player draws Artifacts face-down (Ancient Artifact env token / any Function flip) into
## `player.artefacts`; later they DISCARD one to trigger its effect. This module is the
## single place an Artifact's rules text becomes a mutation.
##
## Each Artifact names the PHASE it may be used in and what target it needs. `resolve`
## returns the same small contract as CardEffects:
##   {"ok": bool, "needs": "" | "<target-kind>", "reason": String, "summary": String}
## When "needs" is set the UI/agent collects the target, then calls `resolve_targeted`.
##
## Target kinds used here:
##   "own_space"       — a space containing one of your Units (Sunstone, Psychic source)
##   "psychic_steal"   — {source: HexCoord, enemy_unit: Dictionary, enemy_coord: HexCoord}
##   (Jam Gobbar / Snooperbot / Medical need no board target.)
##
## DEPENDENCIES (deps Dictionary, all optional so headless tests inject only what they
## assert on):  { "rng", "unit_db", "draw_action": Callable, "players": Array }
##
## The five designed Artifacts:
##   the_jam_gobbar       — Recruitment: remove up to 5 Cowards from your bag.
##   medical_machine      — passive: tag a just-killed Unit; redeploy it free next Recruit.
##   snooperbot_6000      — Recruitment: draw (#players) Action cards, give 1 to each player.
##   sunstone_fragments   — Action: a chosen friendly space — RANGED attackers (range>=1,
##                          incl. Guardians) hit it only on 6. Melee (Range 0) unaffected.
##   psychic_control_belt — Guardian: steal one adjacent enemy Unit into a friendly space.

const COWARD := &"coward"
const GUARDIAN_OWNER := &"guardian"


## Try to resolve discarding `card` (an ArtefactData) played by `color`. `phase` is the
## current GameState.Phase so we can reject out-of-phase use. Returns the contract above.
static func resolve(state, color: StringName, card, phase: int, deps: Dictionary = {}) -> Dictionary:
	if card == null:
		return _fail("no card")
	var p = state.get_player(color)
	if p == null:
		return _fail("no such player")
	if not _holds(p, card):
		return _fail("you don't hold that Artifact")
	var eid: StringName = card.effect_id

	match eid:
		&"the_jam_gobbar":
			if not _is_phase(state, phase, "RECRUITMENT"):
				return _fail("The Jam Gobbar is used during Recruitment.")
			var removed := _remove_cowards(p, 5)
			_discard(p, card)
			return _done("Removed %d Coward(s) from your bag." % removed)

		&"snooperbot_6000":
			if not _is_phase(state, phase, "RECRUITMENT"):
				return _fail("Snooperbot 6000 is used during Recruitment.")
			var dealt := _snooperbot_distribute(state, color, deps)
			_discard(p, card)
			return _done("Drew %d Action card(s) and dealt one to each player." % dealt)

		&"sunstone_fragments":
			if not _is_phase(state, phase, "ACTION"):
				return _fail("Sunstone Fragments is used during the Action phase.")
			return _need("own_space",
				"Pick a space with your Units — ranged attackers hit it only on a 6 this round.")

		&"psychic_control_belt":
			if not _is_phase(state, phase, "GUARDIAN"):
				return _fail("Psychic Control Belt is used during the Guardian phase.")
			return _need("psychic_steal",
				"Pick one of your Units, then an adjacent enemy Unit to take control of.")

		&"medical_machine":
			# Medical Machine is a PASSIVE tag, not an active discard: it's armed when a
			# Unit dies (see arm_medical_machine). Discarding it directly is a no-op here.
			return _fail("Medical Machine triggers automatically when a Unit is killed.")

		_:
			return _fail("unknown Artifact effect")


## Second step for Artifacts that needed a target. `params` carries the collected target
## per the "needs" kind documented above.
static func resolve_targeted(state, color: StringName, card, phase: int, params: Dictionary, deps: Dictionary = {}) -> Dictionary:
	var p = state.get_player(color)
	if p == null:
		return _fail("no such player")
	if not _holds(p, card):
		return _fail("you don't hold that Artifact")
	var eid: StringName = card.effect_id

	match eid:
		&"sunstone_fragments":
			var coord = params.get("space")
			if not (coord is HexCoord):
				return _fail("need a space")
			var cell = state.get_cell(coord)
			if cell == null or cell.units_for(color).is_empty():
				return _fail("that space has none of your Units")
			# Mark the space for this round: ranged attackers can only hit it on a 6.
			if state.has_method("add_sunstone_mark"):
				state.add_sunstone_mark(coord)
			_discard(p, card)
			return _done("Sunstone Fragments: that space can only be hit on a 6 this round.")

		&"psychic_control_belt":
			var src = params.get("source")
			var enemy_coord = params.get("enemy_coord")
			var enemy_unit = params.get("enemy_unit")
			if not (src is HexCoord) or not (enemy_coord is HexCoord) or enemy_unit == null:
				return _fail("need your Unit and an adjacent enemy Unit")
			if not _are_adjacent(src, enemy_coord):
				return _fail("the enemy Unit must be in an adjacent space")
			var src_cell = state.get_cell(src)
			var enemy_cell = state.get_cell(enemy_coord)
			if src_cell == null or enemy_cell == null:
				return _fail("space not on board")
			if src_cell.units_for(color).is_empty():
				return _fail("you have no Unit in the source space")
			var enemy_owner := _owner_of_unit(enemy_cell, enemy_unit)
			if enemy_owner == &"" or enemy_owner == color or enemy_owner == GUARDIAN_OWNER:
				return _fail("must target another player's Unit")
			# Transfer ownership: remove from the enemy, add under your color in the source.
			enemy_cell.remove_unit(enemy_owner, enemy_unit)
			src_cell.add_unit(color, enemy_unit)
			_discard(p, card)
			return _done("Psychic Control Belt: took control of an enemy Unit.")

		_:
			return _fail("that Artifact needs no target")


# ---------------------------------------------------------------------------
#  Medical Machine — passive arm + redeploy
# ---------------------------------------------------------------------------

## Called from combat clean-up (ActionResolver.finish_combat) when a Unit dies. If
## `color` holds a Medical Machine and hasn't already armed one, store the killed unit's
## id for a free redeploy next Recruitment, and discard the card. Returns true if armed.
static func arm_medical_machine(state, color: StringName, killed_unit) -> bool:
	var p = state.get_player(color)
	if p == null:
		return false
	var card = _find_artefact(p, &"medical_machine")
	if card == null:
		return false
	var unit_id := _unit_id_of(killed_unit)
	if unit_id == &"":
		return false
	# Stash the redeploy on the player; RoundFSM Recruitment honours it.
	if not ("pending_redeploys" in p):
		return false
	p.pending_redeploys.append(unit_id)
	_discard(p, card)
	return true


## Apply any pending Medical Machine redeploys at the start of `color`'s Recruitment:
## place each stashed unit in their Rally Zone for free. Returns the number placed.
static func apply_pending_redeploys(state, color: StringName, deps: Dictionary = {}) -> int:
	var p = state.get_player(color)
	if p == null or not ("pending_redeploys" in p) or p.pending_redeploys.is_empty():
		return 0
	var db: Dictionary = deps.get("unit_db", {})
	var rz = p.rally_zone
	var cell = state.get_cell(rz) if rz != null else null
	if cell == null:
		return 0
	var placed := 0
	for uid in p.pending_redeploys:
		var data = db.get(uid, null)
		if data != null:
			cell.add_unit(color, {"data": data, "damage": 0})
			placed += 1
	p.pending_redeploys.clear()
	return placed


# ---------------------------------------------------------------------------
#  Snooperbot — draw N and deal one to each player
# ---------------------------------------------------------------------------

static func _snooperbot_distribute(state, color: StringName, deps: Dictionary) -> int:
	var draw = deps.get("draw_action")
	if draw == null or not (draw is Callable) or not draw.is_valid():
		return 0
	var n: int = state.players.size()
	var drawn := []
	for _i in range(n):
		var c = draw.call()
		if c != null:
			drawn.append(c)
	# Deal one to each player in turn order; the acting player distributes (headless: in
	# order). Leftovers (if the deck ran dry) simply aren't dealt.
	var i := 0
	for pl in state.players:
		if i >= drawn.size():
			break
		pl.hand.append(drawn[i])
		i += 1
	return drawn.size()


# ---------------------------------------------------------------------------
#  Small helpers
# ---------------------------------------------------------------------------

static func _remove_cowards(p, max_n: int) -> int:
	var removed := 0
	while removed < max_n:
		var idx: int = p.bag.find(COWARD)
		if idx == -1:
			break
		p.bag.remove_at(idx)
		removed += 1
	return removed


static func _holds(p, card) -> bool:
	for a in p.artefacts:
		if is_same(a, card) or (a != null and card != null and a.effect_id == card.effect_id):
			return true
	return false


static func _find_artefact(p, effect_id: StringName):
	for a in p.artefacts:
		if a != null and a.effect_id == effect_id:
			return a
	return null


static func _discard(p, card) -> void:
	for i in range(p.artefacts.size()):
		if is_same(p.artefacts[i], card) or (p.artefacts[i] != null and card != null and p.artefacts[i].effect_id == card.effect_id):
			p.artefacts.remove_at(i)
			return


static func _is_phase(_state, phase: int, want: String) -> bool:
	# GameState.Phase is a global enum: RECRUITMENT=0, ACTION=1, GUARDIAN=2. A negative
	# `phase` (the default callers may pass headless) skips the gate so pure-logic tests
	# can resolve any Artifact without threading a phase in.
	if phase < 0:
		return true
	match want:
		"RECRUITMENT": return phase == GameState.Phase.RECRUITMENT
		"ACTION": return phase == GameState.Phase.ACTION
		"GUARDIAN": return phase == GameState.Phase.GUARDIAN
	return false


static func _are_adjacent(a: HexCoord, b: HexCoord) -> bool:
	return a.distance_to(b) == 1


static func _owner_of_unit(cell, unit) -> StringName:
	for owner in cell.units.keys():
		for u in cell.units[owner]:
			if is_same(u, unit):
				return owner
	return &""


static func _unit_id_of(unit) -> StringName:
	if unit is Dictionary:
		var d = unit.get("data")
		if d != null:
			return d.get("id")
	return &""


static func _done(summary: String) -> Dictionary:
	return {"ok": true, "needs": "", "reason": "", "summary": summary}


static func _need(kind: String, reason: String) -> Dictionary:
	return {"ok": true, "needs": kind, "reason": reason, "summary": ""}


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "needs": "", "reason": reason, "summary": ""}

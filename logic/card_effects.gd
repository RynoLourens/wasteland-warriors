extends RefCounted
class_name CardEffects
## Section F, Piece 5b — the Action-card effect resolver.
##
## Dispatches on a card's `effect_id` (flag/id-driven, NEVER hardcoded card names,
## per the project's no-`if name ==` rule). The UI/AI plays a card through the SAME
## intent path as everything else; this is the one place a card's rules text becomes
## a mutation. It owns the effect logic but defers all RNG/bag mechanics to Player and
## all board mutations to HexCell/GameState helpers.
##
## Two-step targeting: some cards need a target the player must pick (a space they
## control, or another player). `resolve()` returns a small Dictionary:
##   {"ok": bool, "needs": "" | "controlled_space" | "player", "reason": String}
## When "needs" is non-empty, the UI collects the target and calls `resolve_targeted()`.
##
## The 3 combat-interrupt cards (Re-roll / Cancel Attack / Extra Attack) are NOT here —
## they need mid-combat prompts and land in Piece 5c.

const COWARD := &"coward"

# Regular Units ("Units"): Warrior, Scout, Gunner, Heavy.
const REGULAR_UNIT_IDS := [&"warrior", &"scout", &"gunner", &"heavy"]
# Special Units: Berserker, Manstopper, Infiltrator, Sapperteur.
const SPECIAL_UNIT_IDS := [&"berserker", &"manstopper", &"infiltrator", &"sapperteur"]


## Try to resolve `card` played by `color`. `state` is GameState; `unit_db` maps unit
## id -> UnitData (for placing units). Returns the result Dictionary described above.
static func resolve(state, color: StringName, card, unit_db: Dictionary) -> Dictionary:
	if card == null:
		return _fail("no card")
	var eid: StringName = card.effect_id
	var p = state.get_player(color)
	if p == null:
		return _fail("no such player")

	match eid:
		# --- Immediate, no target ---
		&"action_07":   # Cull Cowards — take 3 Cowards out of your own bag
			var removed := _remove_cowards(p, 3)
			return _done("Removed %d Coward(s) from your bag." % removed)
		&"action_13":   # Defensive Stance — all your Units +1 Defense this round
			state.add_extra_defense(color, 1)
			return _done("Your Units have +1 Defense until end of round.")
		# --- Per-space movement buffs: pick the controlled space they apply to ---
		&"action_01":   # Move Through Enemies — Units in a controlled space, this round
			return _need("controlled_space", "Pick a space you control — its Units can move through enemies this round.")
		&"action_02":   # Extra Move — Units in a controlled space get +1 Move, this round
			return _need("controlled_space", "Pick a space you control — its Units get +1 Move this round.")
		&"action_09":   # Extra Recruitment — take another Recruitment action
			# Flagged for the round flow; the controller grants one more recruitment
			# decision to this player when set.
			if state.has_method("grant_extra_recruitment"):
				state.grant_extra_recruitment(color)
			return _done("You may take an extra Recruitment action.")

		# --- Need a target the UI must pick ---
		&"action_03":   # Deploy Unit — place 1 Unit from supply in a space you control
			return _need("controlled_space", "Pick a space you control to deploy a Unit.")
		&"action_05":   # Sticky Bomb — place a Sticky Bomb token in a space you control
			return _need("controlled_space", "Pick a space you control for the Sticky Bomb.")
		&"action_06":   # Sabotage Bag — put 3 Cowards into any player's bag
			return _need("player", "Pick a player to receive 3 Cowards.")
		&"action_11":   # Force Discard — any player discards 2 Action cards
			return _need("player", "Pick a player to discard 2 cards.")

		# --- Deploy Special Unit: pick WHICH special; it goes to your Rally Zone ---
		&"action_04":
			return _need("special_unit", "Pick a Special Unit to deploy to your Rally Zone.")

		&"action_10", &"action_14", &"action_15":
			# Combat cards are played in the pre-combat window when you move into a
			# fight — not from the hand on their own. Tell the player and don't consume.
			return _fail("Play this when you move into combat, not on its own.")
		_:
			return _fail("This card has no effect.")


## Apply a card that needed a target, now that the UI has one.
## `target` is a HexCoord (for "controlled_space") or a color StringName (for "player").
static func resolve_targeted(state, color: StringName, card, unit_db: Dictionary, target) -> Dictionary:
	if card == null:
		return _fail("no card")
	var eid: StringName = card.effect_id
	var p = state.get_player(color)
	if p == null:
		return _fail("no such player")

	match eid:
		&"action_03":   # Deploy 1 chosen Unit into a controlled space
			# target = { "space": HexCoord, "unit_id": StringName }
			if not (target is Dictionary):
				return _fail("need a space + unit")
			var space = target.get("space")
			var unit_id: StringName = target.get("unit_id", &"warrior")
			if not (space is HexCoord):
				return _fail("need a space")
			if not state.player_controls(color, space):
				return _fail("you don't control that space")
			var cell: HexCell = state.get_cell(space)
			if cell == null:
				return _fail("no such space")
			if not (unit_id in REGULAR_UNIT_IDS):
				return _fail("Deploy Unit takes a regular Unit, not a Special")
			var data = unit_db.get(unit_id, null)
			if data == null:
				return _fail("no such Unit in supply")
			cell.add_unit(color, {"data": data, "damage": 0})
			return _done("Deployed a %s." % str(unit_id).capitalize())
		&"action_04":   # Deploy a chosen Special Unit to your Rally Zone
			if not (target is StringName) and not (target is String):
				return _fail("need a Special Unit")
			var sid: StringName = StringName(str(target))
			if not (sid in SPECIAL_UNIT_IDS):
				return _fail("that is not a Special Unit")
			if p.rally_zone == null:
				return _fail("no rally zone")
			var rz_cell: HexCell = state.get_cell(p.rally_zone)
			if rz_cell == null:
				return _fail("rally zone not on board")
			var sdata = unit_db.get(sid, null)
			if sdata == null:
				return _fail("no such Special in supply")
			rz_cell.add_unit(color, {"data": sdata, "damage": 0})
			return _done("Deployed a %s to your Rally Zone." % str(sid).capitalize())
		&"action_01":   # Move Through Enemies for Units in a controlled space
			if not (target is HexCoord):
				return _fail("need a space")
			if not state.player_controls(color, target):
				return _fail("you don't control that space")
			state.grant_move_through_enemies_space(color, target)
			return _done("Units there can move through enemies this round.")
		&"action_02":   # +1 Move for Units in a controlled space
			if not (target is HexCoord):
				return _fail("need a space")
			if not state.player_controls(color, target):
				return _fail("you don't control that space")
			state.add_extra_move_space(color, target, 1)
			return _done("Units there have +1 Move this round.")
		&"action_05":   # Place a Sticky Bomb token in a controlled space
			if not (target is HexCoord):
				return _fail("need a space")
			if not state.player_controls(color, target):
				return _fail("you don't control that space")
			var cell2: HexCell = state.get_cell(target)
			if cell2 == null:
				return _fail("no such space")
			cell2.tokens.append({"data": null, "face_up": true, "kind": "sticky_bomb", "owner": color})
			return _done("Placed a Sticky Bomb.")
		&"action_06":   # Put 3 Cowards into target player's bag
			var tp = state.get_player(target)
			if tp == null:
				return _fail("no such player")
			for _i in range(3):
				tp.bag.append(COWARD)
			return _done("Put 3 Cowards into %s's bag." % str(target).to_upper())
		&"action_11":   # Target player discards 2 Action cards
			var tp2 = state.get_player(target)
			if tp2 == null:
				return _fail("no such player")
			var discarded := 0
			for _i in range(2):
				if tp2.hand.is_empty():
					break
				var c = tp2.hand.pop_back()
				if state.has_method("discard_action_card"):
					state.discard_action_card(c)
				discarded += 1
			return _done("%s discarded %d card(s)." % [str(target).to_upper(), discarded])
		_:
			return _fail("card needs no target")


# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------

static func _remove_cowards(p, n: int) -> int:
	var removed := 0
	for _i in range(n):
		var idx: int = p.bag.find(COWARD)
		if idx == -1:
			break
		p.bag.remove_at(idx)
		removed += 1
	return removed


static func _done(msg: String) -> Dictionary:
	return {"ok": true, "needs": "", "reason": msg}


static func _need(kind: String, msg: String) -> Dictionary:
	return {"ok": true, "needs": kind, "reason": msg}


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "needs": "", "reason": reason}

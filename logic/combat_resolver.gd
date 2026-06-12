extends RefCounted
class_name CombatResolver
## Section C — the Combat resolver.
##
## This is the hardest, highest-risk module in the game, so it is built as a
## STRICT PIPELINE, never an ad-hoc calculation:
##
##     declare -> roll -> assign -> apply -> check deaths
##
## Hard rules baked in (from the build plan, Section C):
##   1. SIMULTANEOUS combat. Compute ALL hits for ALL participants first, then
##      apply them. Units are NEVER removed mid-calculation: a dying unit still
##      deals its damage this round (both sides hit in the same round).
##   2. CASCADING CRITS are a `while` loop: each crit (a 6, or 5-6 for
##      Berserker/Cutter) grants one bonus die, which can crit again. Every die
##      roll is emitted as a DISCRETE EVENT so the UI (Section G) can replay the
##      chain rather than only seeing a final number.
##   3. DICE & HITS: a side rolls (sum of attack-dice across its units) dice.
##      4/5/6 = hit; the crit face = hit + one bonus die. hit_only_on overrides
##      the 4+ rule (Typhoon/Infiltrator only hit on a 6).
##   4. DEFENDER ASSIGNS hits to their own units. Excess hits on a killed unit
##      are LOST. Assignment is a pluggable policy; the default minimises losses.
##   5. ABILITY FLAGS drive every exception — we query the unit/guardian Resource
##      and NEVER hardcode unit names. crit_on, hit_only_on, applies_hits_first
##      (Razor), extra_attack_rounds (Scrape), attacks_on_move (The Ox),
##      reduces_attack (Blackout), sticky_bomb_dice (Sapperteur), range (ranged).
##   6. DAMAGE PERSISTS within a round: damage tokens stay on survivors across
##      combats; a unit dies when total damage >= its GREEN Defense. Healing
##      happens at end-of-round Cleanup (Section D), not here.
##   7. DEFENDER MITIGATION: +1 Defense for controlling the space; does NOT
##      stack with a Shield Drone (cap +1 from "controlled ground"). Other
##      buffs (Siyana etc.) still stack and arrive via `extra_defense`.
##   8. PRE-COMBAT sub-rounds: Sticky Bomb (Sapperteur) and Razor
##      (applies_hits_first) roll BEFORE the main simultaneous round; their
##      kills remove targets before those targets get to roll.
##
## The resolver is PURE: it takes an explicit context, mutates the units passed
## in (damage / death), and returns an event log. It does not touch GameState or
## EventBus directly — the caller emits `EventBus.combat_resolved(event_log)`.
## This keeps it trivially unit-testable and the event log trivially replayable.

const HIT_THRESHOLD := 4   ## default: 4, 5, 6 are hits (unless hit_only_on set)
const MAX_CASCADE := 100   ## safety cap so a pathological RNG can't infinite-loop

## All die faces come from _next_face(). In production that is the seeded rng.
## Tests may push a queue of forced faces (context["forced_faces"]) so a single
## die outcome is scriptable without un-seeding the rng. When the queue is
## exhausted we fall back to the rng, so partial scripting still works.
var _rng: RandomNumberGenerator = null
var _forced_faces: Array = []
## Section F Re-roll card (action_10): per-side budget of MISSED dice that get one
## re-roll. Populated from context["reroll_misses"] = { side -> count }.
var _reroll_budget: Dictionary = {}


## The ONE place a d6 is produced. Forced faces (tests) drain first, then rng.
func _next_face() -> int:
	if not _forced_faces.is_empty():
		return int(_forced_faces.pop_front())
	return _rng.randi_range(1, 6)


## A combatant is a thin wrapper around a unit dict {data, damage} plus its side.
## We keep `alive` separate so simultaneous combat can mark a unit dead in the
## check-deaths phase WITHOUT removing it before everyone has dealt damage.
class Combatant:
	var data                      # UnitData or GuardianData
	var side: StringName          # owner colour / faction this combatant fights for
	var unit_dict: Dictionary     # the live {data, damage} dict on the HexCell
	var alive: bool = true
	## Defense added by controlled ground / Shield Drone / stacking buffs, set
	## once per combat for this unit's side. CRITICAL: death is checked against
	## EFFECTIVE defense (base + this), so the +1 control bonus that lets a unit
	## survive a hit must also be honoured when deciding whether it died. Without
	## this, targeting and death disagree and controlled units die a hit early.
	var defense_bonus: int = 0

	func _init(_data, _side: StringName, _unit_dict: Dictionary) -> void:
		data = _data
		side = _side
		unit_dict = _unit_dict

	func base_defense() -> int:
		return int(data.get("defense"))

	## Effective Defense = printed GREEN Defense + any controlled-ground / buff
	## bonus active for this unit's side this combat.
	func defense() -> int:
		return base_defense() + defense_bonus

	func damage() -> int:
		return int(unit_dict.get("damage", 0))

	func add_damage(n: int) -> void:
		unit_dict["damage"] = damage() + n

	## A unit is dead once accumulated damage reaches its EFFECTIVE Defense.
	func is_dead() -> bool:
		return damage() >= defense()


# ---------------------------------------------------------------------------
#  Public entry point
# ---------------------------------------------------------------------------

## Resolve a combat in one space.
##
## `context` keys:
##   sides         : Array[StringName]            — the factions involved (>= 2)
##   combatants    : { side -> Array[Combatant] } — every unit fighting, by side
##   controller    : StringName or &""            — who Controls the space (+1 def)
##   extra_defense : { side -> int }              — stacking buffs (Siyana, etc.)
##   entering_side : StringName or &""            — side that moved IN (sticky-bomb target)
##   assign_policy : Callable or null             — defender hit-assignment policy
##   rng           : RandomNumberGenerator        — seeded; ALL randomness goes here
##
## Returns the event log (Array of small Dictionaries) describing every roll,
## hit, assignment, and death in order — replayable by the UI.
func resolve(context: Dictionary) -> Array:
	var rng: RandomNumberGenerator = context.get("rng")
	assert(rng != null, "CombatResolver.resolve requires a seeded rng")
	_rng = rng
	_forced_faces = (context.get("forced_faces", []) as Array).duplicate()
	_reroll_budget = (context.get("reroll_misses", {}) as Dictionary).duplicate()

	var sides: Array = context.get("sides", [])
	var combatants: Dictionary = context.get("combatants", {})
	var controller: StringName = context.get("controller", &"")
	var extra_defense: Dictionary = context.get("extra_defense", {})
	var entering_side: StringName = context.get("entering_side", &"")
	var assign_policy: Callable = context.get("assign_policy", Callable())

	var log: Array = []
	log.append({"event": "combat_start", "sides": sides.duplicate()})

	# --- PRE-COMBAT SUB-ROUNDS (kills here pre-empt the main round) ---
	# (a) Sticky Bombs trigger on the side that ENTERED the space.
	if entering_side != &"":
		_sticky_bomb_subround(sides, combatants, entering_side, controller,
			extra_defense, assign_policy, rng, log)

	# (b) Razor (applies_hits_first) resolves his attack before the main round.
	_hits_first_subround(sides, combatants, controller, extra_defense,
		assign_policy, rng, log)

	# --- MAIN SIMULTANEOUS ROUND(S) ---
	# Scrape's extra_attack_rounds makes the WHOLE combat run additional full
	# simultaneous rounds (1 base + max extra_attack_rounds among live units).
	# Section F card hooks (passed in via context, default 0 so headless tests are
	# unaffected): Extra Attack (action_15) adds rounds; Cancel Attack (action_14)
	# removes them (clamped at 0).
	var card_extra: int = int(context.get("extra_combat_rounds", 0))
	var card_cancel: int = int(context.get("cancelled_rounds", 0))
	var total_rounds: int = 1 + _max_extra_rounds(sides, combatants) + card_extra - card_cancel
	total_rounds = int(max(total_rounds, 0))
	for round_index in range(total_rounds):
		if _live_side_count(sides, combatants) < 2:
			break   # combat already decided; no one left to fight
		_simultaneous_round(round_index, sides, combatants, controller,
			extra_defense, assign_policy, rng, log)

	log.append({"event": "combat_end", "survivors": _survivor_summary(sides, combatants)})
	return log


## INTERACTIVE per-round variant (Fix H). Same combat, but BEFORE each main round it
## awaits `round_provider.call(round_index, sides_snapshot, combatants)` which returns
## that round's card modifiers:
##   { "extra_defense": {side->int},   # Defensive Stance this round (stacks)
##     "reroll_misses": {side->int},   # Re-roll budget added this round
##     "extra_rounds": int,            # Extra Attack adds rounds
##     "cancel_round": bool }          # Cancel Attack skips THIS round
## The headless resolve() is untouched, so all GUT tests keep passing; only the live
## game uses this coroutine.
func resolve_interactive(context: Dictionary, round_provider: Callable) -> Array:
	var rng: RandomNumberGenerator = context.get("rng")
	assert(rng != null, "resolve_interactive requires a seeded rng")
	_rng = rng
	_forced_faces = (context.get("forced_faces", []) as Array).duplicate()
	_reroll_budget = (context.get("reroll_misses", {}) as Dictionary).duplicate()

	var sides: Array = context.get("sides", [])
	var combatants: Dictionary = context.get("combatants", {})
	var controller: StringName = context.get("controller", &"")
	var extra_defense: Dictionary = (context.get("extra_defense", {}) as Dictionary).duplicate()
	var entering_side: StringName = context.get("entering_side", &"")
	var assign_policy: Callable = context.get("assign_policy", Callable())

	var log: Array = []
	log.append({"event": "combat_start", "sides": sides.duplicate()})

	if entering_side != &"":
		_sticky_bomb_subround(sides, combatants, entering_side, controller,
			extra_defense, assign_policy, rng, log)
	_hits_first_subround(sides, combatants, controller, extra_defense,
		assign_policy, rng, log)

	var total_rounds: int = 1 + _max_extra_rounds(sides, combatants)
	var round_index := 0
	while round_index < total_rounds:
		if _live_side_count(sides, combatants) < 2:
			break
		var mods = await round_provider.call(round_index, sides.duplicate(), combatants)
		if mods is Dictionary:
			for s in (mods.get("extra_defense", {}) as Dictionary).keys():
				extra_defense[s] = int(extra_defense.get(s, 0)) + int(mods["extra_defense"][s])
			for s in (mods.get("reroll_misses", {}) as Dictionary).keys():
				_reroll_budget[s] = int(_reroll_budget.get(s, 0)) + int(mods["reroll_misses"][s])
			total_rounds += int(mods.get("extra_rounds", 0))
			if mods.get("cancel_round", false):
				log.append({"event": "round_cancelled", "round": round_index})
				round_index += 1
				continue
		_simultaneous_round(round_index, sides, combatants, controller,
			extra_defense, assign_policy, rng, log)
		round_index += 1

	log.append({"event": "combat_end", "survivors": _survivor_summary(sides, combatants)})
	return log


# ---------------------------------------------------------------------------
#  Rounds
# ---------------------------------------------------------------------------

## One full simultaneous round: every side rolls, hits are pooled, THEN all hits
## are assigned and applied, THEN deaths are checked. Nothing is removed until
## every side has rolled — that is what "simultaneous" means here.
func _simultaneous_round(round_index: int, sides: Array, combatants: Dictionary,
		controller: StringName, extra_defense: Dictionary,
		assign_policy: Callable, rng: RandomNumberGenerator, log: Array) -> void:
	log.append({"event": "round_start", "round": round_index})

	# DECLARE + ROLL: each side rolls all its dice; collect hits per side.
	# Blackout (reduces_attack) on any side subtracts 1 die from EACH side in
	# the space (it dampens all attackers in the room).
	var global_die_penalty := _global_attack_penalty(sides, combatants)
	var hits_by_side: Dictionary = {}
	for side in sides:
		hits_by_side[side] = _roll_side(side, global_die_penalty,
			combatants.get(side, []), rng, log)

	# ASSIGN + APPLY: defender assigns the hits scored AGAINST them. We compute
	# all assignments first (against the pre-round live set), then apply.
	for attacker_side in sides:
		var hits: int = hits_by_side[attacker_side]
		if hits <= 0:
			continue
		for defender_side in sides:
			if defender_side == attacker_side:
				continue
			# In a 2-side fight this is the only opponent; in a brawl, the
			# attacker's hits are split — default: all land on the strongest
			# present enemy side (caller may override via assign_policy).
			var share := _hits_share(hits, sides, attacker_side, defender_side)
			if share <= 0:
				continue
			_assign_and_apply(defender_side, share, combatants.get(defender_side, []),
				controller, extra_defense, assign_policy, log)

	# CHECK DEATHS: now — and only now — mark dead units.
	_check_deaths(sides, combatants, log)
	log.append({"event": "round_end", "round": round_index})


## Sticky Bomb pre-combat: every unit ALREADY in the space that carries a sticky
## bomb rolls `sticky_bomb_dice` at the entering side, before the main round.
func _sticky_bomb_subround(sides: Array, combatants: Dictionary,
		entering_side: StringName, controller: StringName,
		extra_defense: Dictionary, assign_policy: Callable,
		rng: RandomNumberGenerator, log: Array) -> void:
	for side in sides:
		if side == entering_side:
			continue
		for c in combatants.get(side, []):
			if not c.alive:
				continue
			var bomb_dice: int = 0
			if _flag(c.data, "places_sticky_bomb"):
				bomb_dice = int(c.data.get("sticky_bomb_dice"))
			if bomb_dice <= 0:
				continue
			log.append({"event": "sticky_bomb", "side": side, "dice": bomb_dice})
			var hits := _roll_dice(bomb_dice, _crit_face(c.data), _hit_floor(c.data),
				rng, log, "sticky_bomb", side)
			if hits > 0:
				_assign_and_apply(entering_side, hits,
					combatants.get(entering_side, []), controller, extra_defense,
					assign_policy, log)
	_check_deaths(sides, combatants, log)


## Razor sub-round: units flagged applies_hits_first roll and apply BEFORE the
## main simultaneous round, so their kills remove targets pre-emptively.
func _hits_first_subround(sides: Array, combatants: Dictionary,
		controller: StringName, extra_defense: Dictionary,
		assign_policy: Callable, rng: RandomNumberGenerator, log: Array) -> void:
	var any := false
	for side in sides:
		for c in combatants.get(side, []):
			if not c.alive:
				continue
			if not _flag(c.data, "applies_hits_first"):
				continue
			any = true
			var dice := _unit_dice(c.data)
			log.append({"event": "hits_first", "side": side, "dice": dice})
			var hits := _roll_dice(dice, _crit_face(c.data), _hit_floor(c.data),
				rng, log, "hits_first", side)
			if hits > 0:
				# Razor's hits go to every opposing side (split by policy).
				for defender_side in sides:
					if defender_side == side:
						continue
					var share := _hits_share(hits, sides, side, defender_side)
					if share > 0:
						_assign_and_apply(defender_side, share,
							combatants.get(defender_side, []), controller,
							extra_defense, assign_policy, log)
	if any:
		_check_deaths(sides, combatants, log)


# ---------------------------------------------------------------------------
#  Rolling
# ---------------------------------------------------------------------------

## Roll all dice for one side and return total hits, emitting a discrete event
## per die (and per cascade die) so the UI can replay the chain.
##
## `die_penalty` is the global -1-per-Blackout reduction (rule: Blackout dampens
## EVERY side in the space). It trims dice from this side's pool BEFORE rolling —
## we drain it across this side's units so the penalty actually lands. (Earlier
## bug: the penalty was computed then discarded because each unit re-rolled its
## full dice; GUT caught the divergence from the Python verification model.)
func _roll_side(side: StringName, die_penalty: int, side_combatants: Array,
		rng: RandomNumberGenerator, log: Array) -> int:
	# A side can mix units with different crit faces (e.g. a Berserker among
	# Warriors). We roll each unit's contribution with that unit's own profile
	# so crit_on / hit_only_on are honoured per-unit, never globally.
	var total := 0
	var remaining_penalty: int = int(max(0, die_penalty))
	for c in side_combatants:
		if not c.alive:
			continue
		var n := _unit_dice(c.data)
		# Drain the global penalty across this side's dice pool.
		if remaining_penalty > 0:
			var drop: int = int(min(remaining_penalty, n))
			n -= drop
			remaining_penalty -= drop
		if n <= 0:
			continue
		total += _roll_dice(n, _crit_face(c.data), _hit_floor(c.data),
			rng, log, "attack", side)
	return total


## Roll `n` dice with cascading crits. `crit_face` is the lowest face that crits
## (6 normally, 5 for Berserker/Cutter). `hit_floor` is the lowest face that
## counts as a hit (4 normally; equals crit_face for hit_only_on units). Each
## die — base and cascade — is emitted as a discrete event.
## `rng` param retained for call-site symmetry but die faces now come from
## _next_face() (which uses _rng, or a test-forced queue). This is the single
## randomness seam for the whole resolver.
func _roll_dice(n: int, crit_face: int, hit_floor: int,
		rng: RandomNumberGenerator, log: Array, phase: String,
		side: StringName) -> int:
	var hits := 0
	var pending := n
	var cascade_guard := 0
	while pending > 0:
		pending -= 1
		cascade_guard += 1
		if cascade_guard > MAX_CASCADE:
			break
		var face := _next_face()
		var is_crit := face >= crit_face
		var is_hit := face >= hit_floor
		# Re-roll card (action_10): if this die MISSED and the side still has a
		# re-roll in its budget, re-roll it once (the new face stands).
		if not is_hit and int(_reroll_budget.get(side, 0)) > 0:
			_reroll_budget[side] = int(_reroll_budget[side]) - 1
			log.append({"event": "reroll", "side": side, "from": face})
			face = _next_face()
			is_crit = face >= crit_face
			is_hit = face >= hit_floor
		if is_hit:
			hits += 1
		if is_crit:
			pending += 1   # cascade: a crit grants one more die
		log.append({
			"event": "die", "phase": phase, "side": side,
			"face": face, "hit": is_hit, "crit": is_crit,
		})
	return hits


# ---------------------------------------------------------------------------
#  Assignment & application (defender chooses; default minimises losses)
# ---------------------------------------------------------------------------

## Apply `hits` to one defending side. The defender's policy picks which unit
## eats each hit; effective defense per unit accounts for the +1 controlled-
## ground cap and stacking buffs. Excess hits on a unit that dies are lost.
func _assign_and_apply(defender_side: StringName, hits: int, defenders: Array,
		controller: StringName, extra_defense: Dictionary,
		assign_policy: Callable, log: Array) -> void:
	var live: Array = []
	for c in defenders:
		if c.alive:
			live.append(c)
	if live.is_empty():
		return

	# Compute the side's effective-defense bonus ONCE and stamp it onto every
	# live defender, so death checks (is_dead) see the same effective Defense
	# that targeting does. Controlled-ground (+1, capped) does NOT stack with a
	# Shield Drone; stacking buffs (Siyana) add on top.
	var ground_bonus := _ground_defense_bonus(defender_side, controller, live)
	var stack_bonus := int(extra_defense.get(defender_side, 0))
	var total_bonus := ground_bonus + stack_bonus
	for c in live:
		c.defense_bonus = total_bonus

	for _h in range(hits):
		# Re-evaluate live targets each hit (a unit may have just died).
		var targets: Array = []
		for c in live:
			if c.alive and not c.is_dead():
				targets.append(c)
		if targets.is_empty():
			break   # everyone on this side is already dead; excess hits lost
		var target: Combatant = _choose_target(targets, defender_side, assign_policy)
		target.add_damage(1)
		log.append({
			"event": "hit_assigned", "side": defender_side,
			"unit": target.data.get("id"), "damage_total": target.damage(),
			"effective_defense": target.defense(),
		})


## Default hit-assignment policy: MINIMISE LOSSES. Stack hits onto whichever
## live unit is closest to dying (fewest remaining hits to kill) so the fewest
## units die. Each target's effective Defense already includes its defense_bonus.
## A custom policy may override this (it receives the live targets + side).
func _choose_target(targets: Array, defender_side: StringName,
		assign_policy: Callable) -> Combatant:
	if assign_policy.is_valid():
		var chosen = assign_policy.call(targets, defender_side)
		if chosen != null:
			return chosen
	var best: Combatant = targets[0]
	var best_remaining := _remaining_hp(best)
	for i in range(1, targets.size()):
		var c: Combatant = targets[i]
		var rem := _remaining_hp(c)
		if rem < best_remaining:
			best = c
			best_remaining = rem
	return best


func _remaining_hp(c: Combatant) -> int:
	return c.defense() - c.damage()


# ---------------------------------------------------------------------------
#  Deaths
# ---------------------------------------------------------------------------

func _check_deaths(sides: Array, combatants: Dictionary, log: Array) -> void:
	for side in sides:
		for c in combatants.get(side, []):
			if c.alive and c.is_dead():
				c.alive = false
				log.append({"event": "death", "side": side, "unit": c.data.get("id")})


# ---------------------------------------------------------------------------
#  Flag-driven helpers (NO hardcoded unit names anywhere below)
# ---------------------------------------------------------------------------

## Dice a single unit contributes: explicit attack_dice if set, else the printed
## Attack value (for regular units, Attack IS the dice count).
func _unit_dice(data) -> int:
	var ad := _num(data, "attack_dice", 0)
	if ad > 0:
		return ad
	return _num(data, "attack", 0)


## The lowest face that crits: crit_on (6, or 5 for Berserker/Cutter).
func _crit_face(data) -> int:
	var v := _num(data, "crit_on", 6)
	return v if v > 0 else 6


## The lowest face that counts as a hit. Normally 4; if hit_only_on is set
## (Typhoon/Infiltrator = 6) ONLY that face hits.
func _hit_floor(data) -> int:
	var v := _num(data, "hit_only_on", 0)
	return v if v > 0 else HIT_THRESHOLD


## Blackout (reduces_attack): -1 die to EVERY side in the space. We return the
## largest penalty present (multiple Blackouts don't stack beyond design, but we
## sum conservatively at 1 each — confirm in playtest; flag-driven either way).
func _global_attack_penalty(sides: Array, combatants: Dictionary) -> int:
	var penalty := 0
	for side in sides:
		for c in combatants.get(side, []):
			if c.alive and _flag(c.data, "reduces_attack"):
				penalty += 1
	return penalty


## Max extra full rounds requested by any live unit (Scrape = 1 -> 2 rounds).
func _max_extra_rounds(sides: Array, combatants: Dictionary) -> int:
	var m := 0
	for side in sides:
		for c in combatants.get(side, []):
			if c.alive:
				m = max(m, _num(c.data, "extra_attack_rounds", 0))
	return m


## Ground-defense bonus: +1 for controlling the space AND +1 per Shield Drone
## present — these DO stack. (A controlled space defended by a Shield Drone is
## +2.) Stacking buffs (Siyana) are applied separately via extra_defense.
func _ground_defense_bonus(defender_side: StringName, controller: StringName,
		live: Array) -> int:
	var bonus := 0
	if controller == defender_side and controller != &"":
		bonus += 1
	for c in live:
		if _flag(c.data, "grants_ground_defense"):
			bonus += 1
	return bonus


## How many of `attacker`'s hits land on `defender`. 2-side fight -> all of them.
## Multi-side brawl default: hits hit the single strongest other side (most live
## units); callers wanting a different split supply their own combatant sets.
func _hits_share(hits: int, sides: Array, attacker: StringName,
		defender: StringName) -> int:
	var opponents: Array = []
	for s in sides:
		if s != attacker:
			opponents.append(s)
	if opponents.size() == 1:
		return hits if opponents[0] == defender else 0
	# Multi-side: send all hits to the first opponent in turn order (deterministic);
	# richer targeting is a Section H/AI concern, kept simple + reproducible here.
	return hits if defender == opponents[0] else 0


func _live_side_count(sides: Array, combatants: Dictionary) -> int:
	var n := 0
	for side in sides:
		for c in combatants.get(side, []):
			if c.alive:
				n += 1
				break
	return n


func _survivor_summary(sides: Array, combatants: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for side in sides:
		var ids: Array = []
		for c in combatants.get(side, []):
			if c.alive:
				ids.append(c.data.get("id"))
		out[side] = ids
	return out


## Read a boolean flag off a Resource OR a plain dict; false if absent. This is
## the ONLY way combat queries unit/guardian abilities — no hardcoded names.
func _flag(data, prop: String) -> bool:
	if data is Dictionary:
		return bool(data.get(prop, false))
	var v = data.get(prop)   # Resource.get returns null for an absent property
	return v != null and bool(v)


## Read an int property off a Resource OR a plain dict; `default` if absent.
func _num(data, prop: String, default: int) -> int:
	if data is Dictionary:
		return int(data.get(prop, default))
	var v = data.get(prop)
	return int(v) if v != null else default


# ---------------------------------------------------------------------------
#  Convenience builder for callers / tests
# ---------------------------------------------------------------------------

## Build the `combatants` map from a HexCell-style units dictionary
## ({owner -> Array[{data,damage}]}). Each entry becomes a Combatant wrapping
## the SAME dict, so damage written here persists on the cell (rule 6).
static func combatants_from_units(units_by_owner: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for owner in units_by_owner.keys():
		var arr: Array = []
		for u in units_by_owner[owner]:
			arr.append(Combatant.new(u["data"], owner, u))
		out[owner] = arr
	return out

# Section F — Playthrough Punch-List

Section F's done-criteria is *"play an entire game through without any rules issues."*
This is the review + fix record for the gaps that blocked a clean playthrough, found by
tracing the live game path (`game_controller.gd → game_state.gd → action_resolver.gd →
map_generator.gd → hex_graph.gd`) against the revised rulebook (Setup Ch.4, Map Building
Ch.5, Other Rules Ch.11, Tokens Ch.13).

Status legend: ✅ fixed this pass · ⚠️ partial / documented limitation · ⬜ still open.

---

## Fixed this pass

### ✅ 1. Starting Warrior + Scout were never placed (Setup rule 7)
**Symptom:** Every player began with an empty board presence. The live setup
(`GameController.start_match → GameState.setup_match`) ran Setup steps 1–6 but never did
step 7 (*"Each player puts one Warrior and one Scout from the supply into their Rally
Zone"*). Only the Section-E greybox `_seed_demo_units()` ever placed starting units, and
that isn't on the real path.
**Fix:** `GameController._place_starting_units(seats)` — called right after
`setup_match` — drops one Warrior + one Scout (from `unit_db`, i.e. the supply, NOT the
bag) into each player's rally-zone cell.

### ✅ 2. Teleporter / Tough Terrain effect-IDs didn't match the tokens
**Symptom:** `hex_graph.gd` looked for `&"teleporter_node"` / `&"tough_terrain"`, but the
shipped `.tres` tokens carry the `env_` prefix (`&"env_teleporter_node"` /
`&"env_tough_terrain"`). The strings never matched, so **even the movement mechanics that
were coded never fired** with the real token set. No test caught it because no test used
the real IDs.
**Fix:** `HexGraph.TELEPORTER_EFFECT` / `TOUGH_TERRAIN_EFFECT` constants now carry the
`env_` prefix to match the tokens.

### ✅ 3. Environment tokens flipped but resolved NOTHING (Ch.11 + Ch.13)
**Symptom:** `ActionResolver._resolve_environment_on_arrival` set `face_up = true` and
emitted a signal — and did nothing else. None of the 14 environment effects happened, so
exploration had no risk and no reward.
**Fix:** New `logic/token_effects.gd` (`class_name TokenEffects`) — an `effect_id`
dispatcher mirroring `card_effects.gd`. `ActionResolver` now calls
`TokenEffects.resolve_cell(state, cell, color, deps)` on arrival and
`resolve_on_passthrough(...)` is available for through-movement. Implemented:

| Effect | Behaviour |
|---|---|
| `env_guardian` | Spawns a Guardian into the space; the normal combat check then fights it |
| `env_turrets` | Rolls 3 Attack dice at your Units (minimise-losses assignment, prune dead) |
| `env_falling_debris` | Rolls 1 die at **each** of your Units |
| `env_gang_press_survivors` | Adds 2 Warriors from supply under your control |
| `env_dehydration` | Flags your last Activation token to stay face-up at Cleanup (see ⬜) |
| `env_schematics` | Draw 3 Action cards, discard 1 |
| `env_troubling_tales` | +1 Coward to your bag |
| `env_supplies` | Draw 1 Action card |
| `env_local_fauna` | Rolls 1 die at your Units |
| `env_teleporter_node` / `env_darkness` / `env_tough_terrain` | Persist; read by movement/combat |
| `env_ancient_artifact` | Draws a Bauble/Artefact (no-op until the Bauble deck is wired — see ⬜) |
| `env_dead_silence` | Nothing |

Dice use the same 4/5/6-hit, 6-crit-chains rule as `CombatResolver`, with a bounded loop.

### ✅ 4. Function tokens (yellow) were never flipped or used (Ch.11 + Ch.13)
**Symptom:** The mandatory-flip rule (*"If you have a Unit in a space with a face-down
Function token and no Environment token there, you must flip it … you must Control the
space to use its Function. Whenever you flip a Function token, draw an Artefact card"*)
was unimplemented; none of the 4 Functions worked.
**Fix (in `TokenEffects.resolve_cell`):** A Function flips only when a Unit of the active
color is present and no unresolved Environment token blocks it; flipping always draws an
Artefact (via the injected `draw_artefact` dep). Function effects:

- **Shield Drones** — `+1 Defense` to the controller's Units. Wired through combat:
  `ActionResolver.build_combat_context` adds `+1` to the controller's `extra_defense` when
  a face-up `func_shield_drones` token is present, so it stacks correctly with
  controlled-ground / Siyana via the resolver's existing path.
- **Defensive Turrets** — `+1 Range-1 Attack die per Unit` for the controller. Threaded
  through combat via a new `extra_attack_dice` context field consumed in
  `CombatResolver._roll_side` (additive; combats without the token are byte-identical to
  before).
- **Guardian Control Room** / **Teleporter Hub** — flip + Artefact + availability
  recorded with a Control gate. Their *use* is a Recruitment-phase action (see ⬜ below).

---

## Partial / documented limitations

### ⚠️ Guardian Control Room & Teleporter Hub Recruitment actions
These two Functions are *used during Recruitment* as an alternative to the normal
recruitment choice. The flip, Artefact draw, and Control-gated availability are wired, but
the actual recruitment-menu options ("spawn a Guardian here" / "Deploy into the Hub") are
NOT yet offered by the Agent/recruitment UI. They need a new recruitment-choice branch in
the agent interface + recruitment panel. Tracked as ⬜ below.

### ⚠️ Environmental damage ignores the controlled-ground / drone +1
`TokenEffects` prunes units killed by room hazards against their **base** Defense (the room
hurts you regardless of footing). If you'd rather the controlled-ground / Shield-Drone +1
protect against environmental dice too, that's a one-line change in
`TokenEffects._prune_dead_for`. Flag a ruling.

### ⚠️ Starting bag composition (Setup rule 5)
The rulebook lists the starting bag as 6 Cowards + 6 Warriors + 4 Gunners + 4 Heavies +
2 Scouts, but `Player.load_starting_bag()` loads only 6 Cowards + 6 Warriors (the tested
"bag = 12" contract). Left as-is to avoid silently changing a tested value — **confirm the
intended starting bag** and I'll update it + the test together.

---

## Still open (not started this pass)

- ⬜ **Recruitment-phase Function use** — Guardian Control Room / Teleporter Hub menu
  options (see ⚠️ above).
- ⬜ **Bauble / Artefact deck** — `draw_artefact` is an injected hook that currently
  no-ops (Baubles are deferred per the v1 scope). Wire the deck to activate Ancient
  Artifact + the Artefact-on-Function-flip draw.
- ⬜ **`env_dehydration` Cleanup honour** — `TokenEffects` calls
  `state.set_dehydration(color)` if present; `GameState` / Cleanup must implement the flag
  so the last Activation token genuinely stays face-up.
- ⬜ **Sapperteur unit-triggered Sticky Bomb** — the card version works; the unit ability
  ("when it stops, you may place a Sticky Bomb") is a separate trigger not on the move path.
- ⬜ **2P / 4P layouts + FAQ** — the only intentionally-deferred v1 items per the build plan.

---

## Verification

GUT cannot run in the sandbox (no Godot binary; network blocks the mirrors). Run locally:

```
test.bat          # or: godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

New suite: `tests/test_token_effects.gd` (env deterministic effects, dice damage + prune,
env-Guardian spawn, Function flip-gate + Artefact draw, Control gate).

**Before running:** `godot --headless --editor --quit` once so the new `class_name
TokenEffects` registers, then run GUT. Expect the prior 78 + the new TokenEffects tests.

> NOTE: this pass also restored `logic/combat_resolver.gd`, which had been **truncated**
> on disk (571 lines, missing `_ground_defense_bonus` / `_choose_target` / the
> minimise-losses policy / `combatants_from_units`) — the recurring Edit-tool truncation
> bug. Restored from the last good commit (737 lines) and re-applied the new
> `extra_attack_dice` hook on top. **Re-run GUT to confirm the restore is clean before
> committing.**

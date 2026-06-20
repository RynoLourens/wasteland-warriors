# Section G — Rules Audit & Remediation Plan

A meticulous trace of both rulebooks (original `.docx` + `Wasteland Warriors Rulebook
(Revised).md`) and every card/token's art text against the live game code
(`game_controller → round_fsm → action_resolver → token_effects / combat_resolver`).
Focus areas: **Function tokens, Environment tokens, and Artefact cards** — exactly where
the gaps clustered.

Status legend: 🔴 broken (rule silently does nothing) · 🟡 stubbed/partial · ⚪ ruling/cleanup.

Corin's rulings (2026-06-18):
- **Artefacts:** implement **all 5, fully**, including the Recruitment "discard a face-down
  Artifact to place a Special Unit you Control" path.
- **Environmental damage:** the Control / Shield-Drone **+1 Defense DOES apply** vs room
  hazard dice (Turrets, Falling Debris, Local Fauna).
- **Starting bag:** keep the current **6 Coward + 6 Warrior** ("bag = 12") — update the
  *rulebook* to match, not the code.

---

## Findings summary

| # | Sev | Area | Issue |
|---|-----|------|-------|
| 1 | 🔴 | Artefacts | All 5 artefact cards draw but **never resolve** — `player.artefacts` is never read; no effect dispatcher exists. |
| 2 | 🔴 | Environment | **Darkness (−1 Attack) is never applied** in combat — code only reads `reduces_attack` (Blackout's unit flag), not the Darkness env token. |
| 3 | 🔴 | Special Units | **Manstopper's setup cost is unimplemented** — `extra_setup_move=true` is never consumed; it attacks for free. |
| 4 | 🟡 | Artefacts/Env | "Discard face-down Artifact during Recruitment → place a Special Unit you Control" path is dead (blocked by #1). |
| 5 | 🟡 | Function | Guardian Control Room & Teleporter Hub **Recruitment use** still stubbed (flip+draw+gate wired; menu option missing). |
| 6 | 🟡 | Environment | **Dehydration Cleanup flag is dead** — `set_dehydration()` called behind `has_method` guard; never implemented in GameState/RoundFSM. |
| 7 | ⚪ | Environment | Env damage prunes vs **base** Defense — ruling: **apply the +1** (change `_prune_dead_for`). |
| 8 | ⚪ | Special Units | Sapperteur **unit-triggered** Sticky Bomb (on stop) missing — only the Action-card version works. |
| 9 | ⚪ | Docs | Rulebook starting bag (6/6/4/4/2) ≠ code (6/6). Ruling: **fix the rulebook** to 6 Coward + 6 Warrior. |
| 10 | ⚪ | Docs | Revised rulebook prose still lists **4 Leaders** & "7 Leader Cards"; game has **5** (Lil' Minerva shipped). Update Ch.1/Ch.2/Ch.17. |

---

## The plan (ordered: highest-impact and lowest-risk first)

### Step 1 — 🔴 Darkness −1 Attack (quick, high value)
**Where:** `combat_resolver.gd` (`_roll_side` / attack-dice assembly) + `action_resolver.gd`
`build_combat_context`.
1. In `build_combat_context`, detect a face-up `env_darkness` token on the cell
   (`cell.has_token_effect(&"env_darkness", true)`) and pass a new context flag
   `space_attack_penalty: 1`.
2. In `combat_resolver._roll_side`, subtract `space_attack_penalty` from **every side's**
   die count in that space (floor at 0), mirroring how Blackout's `reduces_attack` already
   works (`combat_resolver.gd:643`). Rulebook: "All Units get −1 Attack in this space."
3. Add a `test_combat_resolver` case: same combat with/without Darkness rolls one fewer die.
**Risk:** low — additive flag; combats without Darkness are byte-identical.

### Step 2 — 🔴 / ⚪ Environmental damage respects the +1 (ruling #7)
**Where:** `token_effects.gd` `_prune_dead_for` (+ `_apply_hits_minimise`).
1. Thread the controller's effective defense bonus (controlled-ground +1 and/or
   `func_shield_drones`) into pruning so a Unit dies at `base + bonus`, not `base`.
   Reuse the same lookup `action_resolver` uses for combat (`state.player_controls` /
   `cell.has_token_effect(&"func_shield_drones", true)`) so the two paths agree.
2. Update the minimise-losses "remaining HP" math to use `def + bonus`.
3. Update `tests/test_token_effects.gd` expectations (a Unit on controlled ground now
   survives one extra hit from Turrets/Debris/Fauna).
**Risk:** low-med — changes one death threshold; covered by the existing token-effects suite.

### Step 3 — 🔴 Manstopper setup cost
**Where:** `action_resolver.gd` move/attack assembly + `hex_graph.gd` reachability.
1. When a Manstopper (`extra_setup_move=true`) is moved into a space and **then attacks**,
   require it to have spent 1 of its 2 Move on setup — i.e. its **effective move range for an
   attacking move is 1**, not 2. Cleanest implementation: in the path/range calc, if the unit
   `extra_setup_move` AND the activated space contains enemies (an attack), cap its usable
   move at `move − 1`.
2. A Manstopper moving into an **empty** space (no attack) keeps full Move 2.
3. Test: Manstopper 2 spaces from an enemy cannot reach-and-attack in one action; 1 space
   away can.
**Risk:** med — touches movement reachability; needs a focused test so it doesn't regress
normal units.

### Step 4 — 🔴 Artefact effect framework + all 5 effects (ruling: all 5, fully)
The largest piece. Split into 4a (framework) → 4b (simple 3) → 4c (complex 2) → 4d (UI).

**4a. Dispatcher + storage.** New `logic/artefact_effects.gd` (`class_name ArtefactEffects`),
mirroring `card_effects.gd`: `static func resolve(effect_id, state, color, deps, params)`.
`player.artefacts` already holds drawn cards; add a "face-down in front of you" status so they
can be held and later discarded.

**4b. Self-contained effects (no new phase hooks):**
- **The Jam Gobbar** — remove up to 5 Cowards from the player's bag. (Trivial; reuse Punish
  Cowards bag logic.)
- **Medical Machine** — tag a just-killed Unit/Special (yours or enemy's) to the card; allow
  free placement in your Rally Zone next Recruitment. Needs a "killed this combat" hook in
  `action_resolver.finish_combat` to offer the choice.
- **Snooperbot 6000** — during Recruitment, draw `N=players` Action cards, distribute one to
  each player instead of the normal draw. Hook into `round_fsm.run_recruitment_phase` draw step.

**4c. Effects needing combat / Guardian-phase hooks:**
- **Sunstone Fragments** — during Action phase, mark a chosen friendly space so any **ranged**
  attacker (incl. Guardians) hits it only on a 6 this round. Add a per-space `hit_only_on=6`
  override read in `combat_resolver` (it already supports `hit_only_on` per unit — extend to a
  space/target modifier).
- **Psychic Control Belt** — during Guardian phase, steal one adjacent enemy Unit/Special into
  a chosen friendly space. Add a Guardian-phase pre-step in `round_fsm`/`guardian_manager` that
  offers the swap and reassigns the unit's owner on the board.

**4d. Recruitment "discard Artifact → place Special Unit you Control"** (finding #4): add the
recruitment-menu branch (see Step 5 — same menu surface) that consumes a face-down artefact and
drops one supply Special into a Controlled space.

**Tests:** `tests/test_artefact_effects.gd` — one case per effect with injected deps + FakeState.
**Risk:** med-high (4c/4d touch combat + recruitment + Guardian phase). Land 4a/4b first, verify
green, then 4c/4d.

### Step 5 — 🟡 Function Recruitment actions + Artifact discard menu
**Where:** `agent.gd` recruitment intent schema, `round_fsm._apply_recruitment_choice`,
recruitment panel UI.
1. Extend the recruitment intent with new choices: `"control_room_spawn"` (Guardian Control
   Room), `"hub_deploy"` (Teleporter Hub), `"artefact_place_special"` (Step 4d). All gated on
   Control of the relevant face-up Function/space.
2. Implement each branch in `_apply_recruitment_choice`; surface them in the recruitment panel
   only when legally available (player Controls a flipped Control Room / Hub / holds an artefact).
**Risk:** med — new UI + intent plumbing; no combat changes.

### Step 6 — 🟡 Dehydration Cleanup flag
**Where:** `autoload/game_state.gd` (add `set_dehydration`/`dehydrated_colors` state),
`round_fsm` Cleanup.
1. Implement `GameState.set_dehydration(color)` (records the player + their last-placed
   Activation token's coord).
2. In Cleanup, when removing face-up Activation tokens, **skip** the recorded one for a
   dehydrated player so it stays face-up one extra round; clear the flag after.
3. Test in `test_round_fsm`: a dehydrated player keeps their last Activation token at Cleanup.
**Risk:** low — isolated Cleanup branch; `token_effects` already calls the setter.

### Step 7 — ⚪ Sapperteur unit-triggered Sticky Bomb
**Where:** `action_resolver.gd` post-move ("when it stops" hook).
1. After a move resolves, for each Sapperteur (`places_sticky_bomb=true`) that **stopped** in a
   space, offer/auto-place a Sticky Bomb token there (same token shape `card_effects.gd:148`
   already creates).
**Risk:** low — reuses the existing sticky-bomb token + combat sub-round.

### Step 8 — ⚪ Documentation sync (no code)
1. **Starting bag (finding #9):** edit revised rulebook Setup rule 5 → **6 Cowards + 6 Warriors**
   (matches code, per ruling). Add a `[CHANGE]` note.
2. **Leaders (finding #10):** update Ch.1, Ch.2 ("7x Leader Cards"), and Ch.17 to reflect **5
   designed Leaders** incl. Lil' Minerva; drop the "only 4 designed" / "7 total" language.
3. Refresh `SECTION-F-punch-list.md` ⬜ items that this section closes.

---

## Verification (every step)
- GUT can't run in the sandbox (no Godot binary). Corin runs `test.bat` locally after each step
  group: expect the prior **88** green + new `test_artefact_effects.gd`, Darkness, env-+1,
  Manstopper, dehydration cases.
- **File-integrity discipline (recurring gotcha):** these `.gd` edits must be done via `git show
  HEAD:<f>` restores + python `open().write()` re-application — **not** the Edit tool, which has
  repeatedly truncated/NUL-corrupted this project's files. Re-check `NUL=0` and clean EOF
  (`tail -1`) on every touched `.gd` before declaring done.
- Suggested commit grouping: (S1+S2) combat dice fixes · (S3) Manstopper · (S4a-b) artefact core
  · (S4c-d+S5) artefact/function recruitment · (S6) dehydration · (S7) Sapperteur · (S8) docs.

---

## Suggested order of execution
1, 2, 3 (quick combat/movement correctness) → 6 (dehydration, isolated) → 7 (Sapperteur) →
4a/4b (artefact core + simple 3) → 4c/4d + 5 (complex artefacts + recruitment menu) → 8 (docs).
Land and GUT-verify each group before the next.

---

# IMPLEMENTATION RECORD — all steps shipped (2026-06-18)

Every step above is implemented in the working tree. All `.gd` edits were applied via bash
(python `open().write()` / line-index inserts), **not** the Edit tool, per the recurring
truncation/NUL gotcha. Every touched file re-checked: **NUL = 0, clean EOF, brackets
balanced, no space-indentation**.

**Files changed**
- `logic/combat_resolver.gd` — Darkness `_space_attack_penalty` folded into both
  simultaneous rounds; placed-Sticky-Bomb sub-round rolls (`PLACED_BOMB_DICE = 2`) in sync
  + async; Sunstone `_sunstone_active` raises the hit floor to 6 for all attack dice.
- `logic/action_resolver.gd` — context now carries `space_attack_penalty`, `sticky_bomb_count`,
  `sunstone_active`; Manstopper setup cost (`_reachable_via_state` reduced-move branch);
  Sapperteur drops a bomb when it stops; `_prune_dead` returns dead units → arms Medical
  Machine; `note_activation` recorded on every activation.
- `logic/token_effects.gd` — env damage now respects the controlled-ground / Shield-Drone
  +1 (`_ground_defense_bonus` used in minimise-assign + prune).
- `logic/artefact_effects.gd` — **NEW**: dispatcher + all 5 Artifacts + Medical Machine
  arm/redeploy + Snooperbot distribute.
- `logic/round_fsm.gd` — applies pending Medical redeploys at Recruitment; three new
  recruitment choices (`control_room_spawn` / `hub_deploy` / `artefact_place_special`);
  Cleanup honours Dehydration keep-coord + clears sunstone marks.
- `logic/guardian_manager.gd` — `spawn_into_cell` (Control Room).
- `logic/player.gd` — `pending_redeploys` field.
- `logic/agent.gd` — recruitment-intent docstring extended for the new choices.
- `autoload/game_state.gd` — Dehydration (`note_activation` / `set_dehydration` /
  `dehydration_keep_coord` / `clear_dehydration`), Sunstone marks, `extra_move_for`.
- `tests/test_section_g_fixes.gd` — **NEW** suite (Darkness, env +1, placed bomb, Jam
  Gobbar, Sunstone, Psychic Control Belt, Medical Machine).
- Rulebook (Revised) — starting bag 6/6, 5 Leaders, Bauble→Artifact terminology.

**Latent bug found & fixed (bonus):** placed Sticky Bomb tokens (from the Action card AND
the new Sapperteur drop) were **purely cosmetic** — the combat sub-round only rolled bombs
off a Sapperteur still standing in the space, never off a placed token. Placed bombs now
roll 2 dice at whoever enters, so they persist after the Sapperteur moves on (rulebook Ch.11).

## ✅ Sunstone Fragments scope — RESOLVED (Corin, 2026-06-20)
Ruling: **only Ranged Units have a Range** (the superscript above the red Attack star).
Warriors are **Range 0**. So "Units with Range" = `range >= 1`.

**Data bug this exposed & fixed:** every unit `.tres` had `range = 1` (the schema default),
including melee. Corrected from the tokens:
- **Range 1:** Gunner, Manstopper. **Range 0:** Warrior, Heavy, Scout, Berserker,
  Infiltrator, Sapperteur. (Guardians unchanged: Arachnid 2, rest 1.)
- `unit_data.gd` default `range` flipped `1 → 0`.

**Sunstone now gates on `range >= 1`:** in `_roll_side`, the hit floor is raised to 6 only
for attacking units with Range (and the Defensive-Turrets Range-1 bonus dice); melee dice
are unaffected. No live code read `range` before this, so nothing else regressed. New test
`test_sunstone_limits_ranged_not_melee` asserts melee out-hits ranged under Sunstone.

---

# RANGED ATTACK action implemented (2026-06-20)

The Ch.11 rule *"When you Activate a space containing Ranged Units that haven't moved, those
Units may Attack any Units within Range without moving into that space"* is now a real action
(it had no implementation — `range` had no readers before the data fix above).

**It is ONE-SIDED:** the firing player's ranged Units roll; the target does NOT retaliate
(distinct from shared-space melee). Ignores line of sight.

- `CombatResolver.resolve_ranged_attack(context)` — NEW public method: rolls the attacker
  Combatants via `_roll_side` (so crit/hit profiles, Darkness on the target, and Sunstone all
  apply), assigns hits to the target defenders via `_assign_and_apply` (honours the target's
  control/Shield-Drone/stacking defense), checks deaths. Reuses all the tested building blocks.
- `ActionResolver.resolve_ranged_attack(state, color, intent)` — validates: ranged Units
  (`range >= 1`) present in the activated space; target within max Range (hex distance, no
  LoS); target holds enemy forces. Activates the firing space, fires, prunes via
  `finish_combat` (Old Tech still drops for Guardians killed at range).
- `ActionResolver.ranged_targets_for(state, color, activate)` — UI/AI helper listing legal
  target coords (enemy spaces within range).
- Wired into the action loop in **both** `round_fsm.gd` (headless) and `game_controller.gd`
  (live, immediate — no deferred-combat window). Agent intent: `{"type": "ranged_attack",
  "activate": HexCoord, "target": HexCoord}`.
- Tests: fires-without-moving (shooter stays + untouched, target dies), out-of-range rejected
  (no activation), melee can't, targeting helper.

**UI follow-up (⬜):** the board UI needs a "ranged fire" affordance (highlight a space with
your ranged Units → highlight in-range enemy spaces via `ranged_targets_for` → emit the
intent). Engine + AI path are complete.

## Verification — Corin runs locally (GUT can't run in the sandbox)
```
godot --headless --editor --quit    # once, so new class_names (ArtefactEffects) register
test.bat                            # expect prior 88 green + test_section_g_fixes.gd
```
If anything fails to compile, it'll be a `class_name` registration order issue — run the
editor-quit line first. All static checks (NUL, EOF, brackets, indentation) pass here.

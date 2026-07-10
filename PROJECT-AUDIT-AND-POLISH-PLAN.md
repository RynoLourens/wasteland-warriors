# Wasteland Warriors — Project Audit & Polish Plan
*Audited 2026-07-01 against the working tree, git history, rulebook (Revised), and the build plan.*

---

# PART 1 — WHERE THE BUILD STANDS

## Section scoreboard (build plan A–J)

| Section | Status | Notes |
|---|---|---|
| A. Scaffold + data layer | ✅ Shipped | 56 `.tres`, schemas, autoloads |
| B. Hex engine + map generator | ✅ Shipped | Spanning-tree generator, 22-cell 3P board, rally fixtures |
| C. Combat resolver | ✅ Shipped | Flag-driven, replayable event log, interactive + sync paths |
| D. Round FSM / full headless game | ✅ Shipped | M4 reached; plays to victory headless |
| E. Greybox board + interaction | ✅ Shipped | Click Move-and-Attack, ring reveal |
| F. Full mobile UI | ✅ Shipped + 3 fix passes | Setup, hotseat hand-off, recruitment, cards, combat readout, win screen |
| F+. Rules audits | ✅ Shipped | Env/func tokens, artifacts engine, support fire, Arachnid, Ox, card-type gate |
| G. Art / animation / juice | ⚠️ **Done but didn't land** — see Part 2 | **ENTIRELY UNCOMMITTED** |
| H. AI (medium heuristic) | 🔴 **Not started** | AI seats are `PassAgent` — they instantly pass every turn |
| I. Balance sims | 🔴 Not started | Blocked on H |
| J. Ship (export, 2P/4P, FAQ) | 🔴 Not started | No `export_presets.cfg`; 2P/4P stubbed; no FAQ/tutorial |

## Health check

- **Code integrity: clean.** All 47 project `.gd` files: zero NULs, balanced brackets, intact tails (the recurring Edit-tool truncation did NOT strike this time; `map_generator.gd` merely lacks a trailing newline, same as HEAD).
- **Tests: 118 test functions across 11 GUT files.** The `.import` saga is resolved — all 82 PNGs have real Godot-generated `.import` files and 98 `.ctex` caches exist, so `test_art_registry` should now pass. **Action: run `test.bat` locally and confirm 118/118.**
- **Git: ⚠️ the whole graphics pass is uncommitted.** HEAD is `38fae85` (rulebook-coverage fixes). On disk but not committed: modified `board_view/card_ui/combat_readout/hand_panel/project.godot`, plus untracked `art/` (82 PNGs), `art_registry.gd`, `audio_manager.gd`, `info_panel.gd`, `game_theme.tres`, 2 test files. **One bad disk day loses Section G. Commit and push first, before any polish work.**
- No stale `.git/index.lock`. No file has been modified since 2026-06-20 — the "Opus visuals" pass is that Section G work.

## New assets since the graphics pass (unwired)

In the `Wasteland Warriors` source folder, added 2026-06-20:
- **`Razor Art.png`** (696×696) — the missing Guardian. Raw art, not token-framed (no stat icons like the other 450×450 guardian tokens).
- **`Lil Minerva.png`** (1833×1827) — the missing 5th Leader card.

Still missing (chip-fallback in game): env tokens **Ancient Artifact** and **Falling Debris**.

---

# PART 2 — WHY THE GRAPHICS PASS DIDN'T LAND

The G pass imported all the art and wired it *into the existing greybox layout* — it decorated the greybox instead of replacing it. Specifics, worst first:

## 2.1 Tile art contradicts the board (the big one)
Every tile PNG has **doorways painted onto specific edges** (metal doorframes vs. solid rock). But `ArtRegistry.tile()` picks a face by hashing the coordinate (`abs(q*7+r*13) % faces`) — the painted doorways have **no relationship to the cell's actual open exits**, and the art is never rotated. The result: the board *looks* wrong everywhere — doors into walls, walls where you can walk. That's why the yellow greybox exit bars are still drawn on top: they remain the only truthful connectivity signal, and they scream "debug build."

Also stacking up: the greybox `Polygon2D` + white outline still render under/around the art, and the coord label logic remains.

## 2.2 Token art at postage-stamp size
Unit/guardian tokens are gorgeous 450×450 pieces with the stat layout baked in (boot=Move, star=Attack, vest=Defense). They render inside **26×18 px** plates — with aspect-keep that's an **18×18** image. The entire token design is illegible; stats are only reachable via hover tooltip, and **the target platform is touch — there is no hover on a phone.** The per-cell 3-across grid layout is unchanged from greybox.

## 2.3 Greybox survivors with art available
- Activation/Control markers are still hand-drawn triangles/diamonds, though `activation_front.png`/`activation_back.png` are imported and registered.
- Old Tech renders at 20 px; env/func tokens at 22 px chips with 11 px text labels.
- Leader art (4 cards imported) is used **nowhere** — no leader select, no leader display in HUD/info panel.
- Artifact card art (5 + back) is used **nowhere** — the info panel shows only a count.

## 2.4 No atmosphere
Default engine-grey void behind the board, minimal theme (buttons+fonts only), no background texture, no vignette, no title treatment on the setup screen. Combat resolves in a **text modal** — nothing happens on the board itself; no dice, no hit flashes, no death animation at the hexes where the fight is.

## 2.5 What DID land (keep it)
Move tweens + ghost tokens, guardian step-by-step playback, card deal-in stagger, combat readout timed reveal with 1x/2x/4x/SKIP/REPLAY, token flip "pop," info panel with coward odds, owner-initial accessibility floor, AudioManager scaffold + haptics. The architecture (ArtRegistry id→texture with greybox fallback) is right — the *presentation layer sitting on it* is what needs the rework.

---

# PART 3 — FUNCTIONAL GAPS (beyond graphics)

## 3.1 🔴 Leaders are a dead subsystem (new finding — coverage-matrix false positive)
The matrix marks "Choose Leader ✅ (setup / leader_data)" but **no live code path assigns a leader**: `player.leader` is never set anywhere, the setup screen has no leader pick, and:

- **Seraph ID mismatch:** `round_fsm.gd:212` checks `&"seraph_recruit_bonus"`, but the `.tres` carries `&"seraph_recruit"` (the recruitment panel checks the correct one). Engine-side bonus can never fire.
- **Stormfoot (+1 Move), Rat's Eye (+1 Range), Siyana (+1 Def), Minerva (draw-2-keep-1): zero implementation.** The hooks exist (`extra_move_for`, `extra_defense` in combat context, the draw-card path) but nothing feeds leader passives into them.

Rulebook Ch.4 step 1 is "Each player chooses a Leader." Right now the game skips it entirely.

## 3.2 🟡 Artifacts: drawable but unusable
`ArtefactEffects.resolve/resolve_targeted` implements all 5 artifacts with a CardEffects-style contract — but the **only live call sites are Medical Machine's passive** (arm-on-death + redeploy). No UI (and no engine caller) lets a player *use* Jam Gobbar, Snooperbot, Sunstone, or Psychic Control Belt. Info panel shows a count, not which artifacts you hold.

## 3.3 🟡 Function-token recruitment actions: engine-only
`control_room_spawn`, `hub_deploy`, `artefact_place_special` exist in RoundFSM but the recruitment panel never offers them. (Known gap, documented in the matrix.)

## 3.4 🟡 Headless card-effect application
Matrix follow-up note, still open: in headless play a Movement/Recruitment card is removed from hand but its effect isn't applied. Matters for Section H (AI plays cards through the same path).

## 3.5 🔴 AI (Section H) — required by locked v1 scope
"Hotseat + rules-based AI at MEDIUM, empty seats AI-filled" — currently AI seats pass instantly, so solo play is playing against furniture. This is the largest remaining chunk of real work.

## 3.6 Ship-blockers (Section J)
No export presets (Android is a v1 target), no on-device test, no app icon beyond the default `icon.svg`, silent audio (CUES empty — allowed for v1, sourcing plan in Appendix A), 2P/4P layouts stubbed (still awaiting Corin's layout screenshots), no FAQ/help.

---

# PART 4 — STEP-BY-STEP POLISH PLAN

> **Implementation detail lives in `OPUS-BUILD-GUIDE.md`** — exact files, functions, algorithms, tests, and ground rules for each work package (WP0–WP10). This part stays the high-level map.

Ordered so each phase is independently shippable, engine-safe things go through GUT, and the highest-visibility fix (the board) comes first. Sandbox constraints throughout: **Corin runs `test.bat` + git commit/push locally; all `.gd` edits by Claude via bash/python (never the Edit tool).**

## P0 — Safeguard (do immediately, ~10 min, Corin)
1. `git add -A && git commit -m "Section G: art import + animation/juice pass" && git push`.
2. Run `test.bat` → expect **118/118** (confirms the regenerated imports fixed `test_art_registry`).
3. If any fail, report back before anything else.

## P1 — Make the board land (the "it didn't land" fix)
The goal: someone screenshots the board and it looks like the physical game, not a debugger.

1. **Exit-true tiles (the decision — see Part 5).** Build a per-face exit table (which of the 6 edges each room/corridor PNG has a doorway on), then at render time pick the face + rotation that best matches the cell's real exits, rotating the Sprite2D in 60° steps. Patch residual mismatches with small door/wall overlay sprites cropped from the tile art. Cache choice per cell.
2. **Retire the greybox layer where art exists:** drop the yellow exit bars (keep behind a debug toggle), drop the white hex outline and the poly tint under art (keep rally-zone tint as a soft ring/glow instead), keep poly-only rendering as the no-art fallback.
3. **Unit tokens at readable size:** rework the per-cell layout — tokens ~44–48 px (1–3 units), scale down gracefully to ~32 px (4–6), stack badge "×N" beyond that. Owner ring + initial kept. Damage pips on the token. Staged-to-move = lift + glow instead of a rectangle outline.
4. **Tap-to-inspect (touch-first):** tap-hold or a second tap on a unit/token opens a bottom-sheet card: full-size token art, stats, effective Defense, damage — replaces hover-only tooltips (keep hover for PC).
5. **Real activation/control markers:** use `activation_front/back.png` tinted per player at ~24 px, replacing triangles/diamonds (keep the shape as a colour-blind secondary cue, e.g. shaped border).
6. **Old Tech + env/func tokens:** art chips at ~28–32 px; face-down backs already exist (`_room_back`/`_corridor_back`/func `_back`).
7. **Atmosphere:** wasteland background texture (or radial gradient + grain) behind the board, subtle drop shadow under tiles, setup screen title treatment using leader art, richer `game_theme.tres` (panel styles, consistent font).
8. **Verify:** UI-TEST-CHECKLIST Section H (H1–H10) re-run + new checklist items for exit-true tiles ("every painted doorway leads somewhere; every walkable edge has a door").

## P2 — Wire the new art (small, do with P1)
1. `Razor Art.png` → frame into the 450×450 guardian-token template (rounded square, stat icons M2/A2/D2 R1) so it matches its siblings; add to `GUARDIAN_PATHS`. (Claude can composite it with PIL to match the template style; Corin approves the result.)
2. `Lil Minerva.png` → crop/scale to the 1575×1575 leader format; add to `LEADER_PATHS`.
3. Ancient Artifact + Falling Debris: Corin exports the two env-token PNGs if they exist in the design files; otherwise keep chip fallback (it's graceful).
4. Update `test_art_registry.gd` known-missing expectations.

## P3 — Leader subsystem (engine + UI, GUT-tested)
1. **Fix the Seraph ID** (`seraph_recruit_bonus` → `seraph_recruit`) — one line.
2. **Leader select at setup:** per-seat leader picker (portrait cards, no duplicates; AI seats auto-pick random); pass through `player_specs` → `Player.leader`.
3. **Implement the four missing passives, all flag-driven:**
   - `stormfoot_move`: +1 Move for Warriors & Scouts → fold into the abilities dict in `_reachable_via_state`.
   - `ratseye_range`: +1 Range for Warriors & Gunners → fold into `eligible_ranged_shooters` (and Sunstone's `range>=1` gate — a Stormfoot Warrior stays melee, a Rat's Eye Warrior becomes ranged; confirm intent).
   - `siyana_defense`: +1 Defense for Warriors & Heavies → feed via the existing `extra_defense` context (stacks per the control+drone precedent).
   - `minerva_card_advantage`: start +1 card; every draw = draw 2 discard 1 (worse card discarded automatically for AI; human picks) → wrap `_draw_action_card`.
4. **Show the leader:** portrait chip in HUD/info panel per player.
5. **Tests:** one GUT test per passive + leader-assignment test (~6 tests).

## P4 — Complete the play surface
1. **Artifact hand UI:** an "Artifacts" tray (like the card hand, uses the 450×600 card art); play → `ArtefactEffects.resolve` → target flow via the existing `needs`/`resolve_targeted` contract (mirrors action-card targeting).
2. **Function-token recruitment offers:** recruitment panel gains context buttons when the player Controls the relevant room — "Spawn Guardian (Control Room)," "Deploy via Hub," "Discard Artifact → place Special."
3. **Headless card-effect application** (matrix follow-up): route the headless Movement/Recruitment card windows through CardEffects so engine and UI paths agree — prerequisite for AI card play.
4. Tests for 1–3.

## P5 — Combat on the board (feel)
Keep the readout, but make the board tell the story in sync with it: dice burst / hit flash on the combat hex per `die_*` event, damage pips ticking up, death = token fade+fall, crit = brief freeze + shake (small), Arachnid ranged attack = projectile line (signal `guardian_ranged_attack` already exists), Old Tech drop = gold arc. All driven off the same event queue the readout already steps through — no new rules code.

## P6 — Section H: the medium AI (biggest remaining chunk)
`HeuristicAgent` implementing the existing `Agent` interface (the seam was built for this):
1. Recruitment heuristic: deploy vs recruit vs punish by bag composition + board position; leader-aware.
2. Action heuristic: score candidate activations (reachable Old Tech > kill odds vs Guardian > contest control > explore), using `HexGraph` + a cheap combat-odds estimate from CombatResolver stats.
3. Combat decisions: hit-assignment (minimise-losses default already exists), support-fire opt-in, attack-card play.
4. Card + artifact play via the P4 paths.
5. Wire into `game_controller` seat setup (replaces `PassAgent`); AI-turn pacing (~0.5 s beats) so hotseat players can follow.
6. GUT: AI-vs-AI seeded full games terminate, never crash, AI wins vs PassAgent nearly always.

## P7 — Section I: balance
Seeded AI-vs-AI batches (hundreds of games headless): win-rate by seat order, leader win-rates, game length distribution, Guardian lethality. Tune, re-run, document in the rulebook FAQ.

## P8 — Ship it (Section J)
1. Audio pass (optional for v1 but cheap now): CC0 set per Appendix A, fill `CUES` — it's drop-in by design.
2. App icon + splash from key art; title screen polish.
3. `export_presets.cfg`: Android (landscape, keystore) + Windows; on-device playtest on Corin's phone — touch targets, performance, safe areas.
4. 2P/4P layouts **if** Corin supplies ring/rally screenshots (data-driven slots ready); otherwise ship 3P-only.
5. Help/FAQ screen (rulebook Ch. summaries) + first-game hint toasts.
6. Final sweep: full UI-TEST-CHECKLIST, GUT suite, version tag `v1.0`.

---

# PART 5 — DECISIONS NEEDED FROM CORIN

1. **Tile rendering approach (P1.1)** — ✅ DECIDED 2026-07-01: **match-then-patch**. Was recommended: *match-then-patch* (face+rotation best-fit against real exits, patch odd edges with door/wall overlays). Alternative A: strict — make the map generator draw from the real physical tile deck (face + orientation) so art always matches exactly; truest to the board game but a generator refactor with new failure modes. Alternative B: fully procedural doorway compositing on a doorless base; always correct, least faithful to the painted tiles.
2. **Rat's Eye + Sunstone interaction (P3.3):** does a +1-Range Warrior count as a "Ranged Unit" for Sunstone/turret purposes? (Proposed: yes — range≥1 at resolution time.)
3. **Ancient Artifact / Falling Debris art (P2.3):** export them, or keep chip fallback?
4. **2P/4P (P8.4):** in or out for v1? If in, the layout screenshots are the blocker.
5. **Audio in v1 (P8.1):** yes/no.

---

# APPENDIX — Session-sized work packages

| # | Package | Phase | Size |
|---|---|---|---|
| 1 | P0 commit/push + GUT confirm | P0 | 10 min (Corin) |
| 2 | Tile-exit table + match-then-patch renderer | P1.1–1.2 | 1 session |
| 3 | Token size/layout rework + tap-to-inspect | P1.3–1.4 | 1 session |
| 4 | Markers, chips, atmosphere, theme | P1.5–1.7 | 1 session |
| 5 | Razor/Minerva wiring + framing | P2 | ½ session |
| 6 | Leader select UI + 5 passives + tests | P3 | 1–2 sessions |
| 7 | Artifact UI + function-token offers + headless cards | P4 | 1–2 sessions |
| 8 | Combat-on-board juice | P5 | 1 session |
| 9 | HeuristicAgent + tests | P6 | 2–3 sessions |
| 10 | Balance sims + tuning | P7 | 1 session |
| 11 | Audio, exports, device QA, FAQ | P8 | 2 sessions |

Realistic path to `v1.0`: **11–14 working sessions**, with the game looking dramatically better after the first three.

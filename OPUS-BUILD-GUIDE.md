# Wasteland Warriors — Opus Build Guide
*Implementation-level instructions for finishing the build. Companion to `PROJECT-AUDIT-AND-POLISH-PLAN.md` (read Part 2–3 of that first for the WHY; this file is the HOW). Written 2026-07-01.*

Work through the packages **in order** (WP1 → WP11). Each has: files touched, exact approach, tests, a Definition of Done, and a suggested commit message. Stop points marked **⛔ CORIN** need a human (local GUT run, editor import, git push, or a decision).

---

# SECTION 0 — GROUND RULES (read before touching anything)

These are hard-won lessons from this specific project. Violating them has corrupted the working tree before.

1. **NEVER use the Edit tool on `.gd` files.** It has repeatedly silently truncated file tails and injected trailing NUL bytes (bit us in Sections C, D, F, G). Do ALL `.gd` edits via bash + python: `open(f).read()` → `str.replace(old, new)` with `assert s.count(old)==1` → `open(f,'w').write(s)`.
2. **After EVERY write to a `.gd` file, verify:** NUL count = 0 (`open(f,'rb').read().count(0)`), file ends with `\n`, bracket/paren balance unchanged, line count sane vs expectation, tail intact (`tail -5`). If a file is ever corrupted: restore via `git show HEAD:<file> > <file>` (bash redirect — `git checkout -- <file>` FAILS on this Windows mount with "unable to unlink"), then re-apply edits with python.
3. **No git writes from the sandbox.** `git add`/`commit` half-fail on the mount and leave a stale `.git/index.lock` that breaks Corin's local git. Read-only git (`status`, `log`, `diff`, `show`) is fine. All commits/pushes are Corin's, in PowerShell from the project dir (note the leading space in the ` App` folder name).
4. **Godot cannot run in the sandbox.** Verify logic with Python ports/mirrors, but a section is NOT done until Corin runs `test.bat` locally (Godot 4.6.3) and it's green. The Python port validates logic only — it cannot catch Godot-runtime semantics (Nil access, `Object == StringName` throws, class_name registration). When port and GDScript disagree, the GDScript is what ships.
5. **GDScript traps (warnings are treated as ERRORS here — one bad line un-registers the file's `class_name` and cascades into "Nonexistent function 'new'" everywhere):**
   - Never `var x := min(...)/max(...)/dict.get(...)/arr.pop_front()/... ` — these infer Variant. Wrap: `var x: int = int(min(a, b))`.
   - `var n := obj.method_returning_own_class()` fails inference — annotate the type explicitly.
   - `==` between a Resource and a StringName THROWS in Godot 4 — distinguish by type (`x is Resource`), never by equality across kinds.
   - Godot's stringify virtual is `_to_string()`, not `to_string()`.
   - Remove unused locals (warning-as-error).
6. **New `class_name` scripts don't register until the editor runs.** After adding any, tell Corin: `godot --headless --editor --quit` once (or open the editor) before GUT.
7. **New PNGs need editor import.** NEVER hand-write `.png.import` files. Drop the PNG in `art/`, then **⛔ CORIN** opens the editor once (generates real `.import` + `.ctex`). `ArtRegistry._tex()` already degrades to null (greybox) for unimported files.
8. **Rules questions:** the authoritative rulebook is `..\..\..\Wasteland Warriors\Wasteland Warriors Rulebook (Revised).md`. Known trap: controlled-ground +1 Defense and Shield Drone +1 **DO stack** (+2). When auditing coverage, go rulebook-first (enumerate rules, grep for readers) — a data flag with no readers is an unimplemented mechanic, not a convenience.
9. **Architecture invariants:** data (`.tres`) / logic (headless, GUT-tested) / visuals (scenes) stay separated. All unit/guardian/leader exceptions are **flags on Resources**, never `if name == "the_ox"`. AI and UI both speak the same `Agent` intent interface — no back doors into GameState. Every board mutation flows input → intent → resolver → EventBus signal → redraw.
10. **Don't break the 118.** Run the full GUT suite (via Corin) after every engine-touching WP. UI-only WPs still need a smoke playtest (`run.bat`).

---

# SECTION 1 — SESSION MAP

| WP | What | Plan phase | Engine risk | Needs Corin for |
|---|---|---|---|---|
| 0 | Commit Section G + confirm 118/118 | P0 | — | everything |
| 1 | Exit-true tiles (match-then-patch) | P1.1–1.2 | none (render only) | editor import of patch PNGs, playtest |
| 2 | Token size/layout + tap-to-inspect | P1.3–1.4 | none | playtest |
| 3 | Markers, chips, atmosphere, theme | P1.5–1.7 | none | playtest |
| 4 | Razor + Minerva wiring | P2 | none | art approval, editor import |
| 5 | Leader subsystem | P3 | medium | GUT run |
| 6 | Artifact UI + function-token offers + headless cards | P4 | medium | GUT run, playtest |
| 7 | Combat-on-board juice | P5 | none | playtest |
| 8 | HeuristicAgent (Section H) | P6 | high | GUT run |
| 9 | Balance sims (Section I) | P7 | none | run time, rulings |
| 10 | Ship: audio/exports/help (Section J) | P8 | low | device QA, keystore, decisions |

---

# SECTION 2 — WORK PACKAGES

## WP0 — ⛔ CORIN ONLY (do nothing until this is done)
```powershell
cd "~/Documents/Claude/Projects/Wasteland Warriors Video Game/ App"
git add -A
git commit -m "Section G: art import + animation/juice pass"
git push
./test.bat   # expect 118/118
```
If tests fail, bring the output back before any new work.

---

## WP1 — Exit-true tiles (match-then-patch)  ← the fix that makes the board land

**Problem recap:** tile PNGs have doorways painted on specific edges; `ArtRegistry.tile()` hash-picks a face with no rotation, so painted doors contradict real exits. Decision (Corin, Jul 1): **match-then-patch**.

**Files:** new `ui/tile_art_matcher.gd` (pure logic, `class_name TileArtMatcher`, all static — testable headless), edits to `autoload/art_registry.gd`, `ui/board_view.gd`; new test `tests/test_tile_art_matcher.gd`; possibly 2 new PNGs `art/tiles/patch_door.png`, `art/tiles/patch_wall.png`.

### Step 1 — Derive the per-face exit table (one-time, in the sandbox)
For each of the 17 face PNGs (8 `room_*`, 9 `corridor_*`; `center.png` is handled separately), determine which of its 6 edges has a painted doorway:
- Programmatic first pass (PIL): sample a small patch at each edge midpoint, ~88% of the way from centre to edge. Doorway pixels are grey/desaturated (walkway/doorframe); rock is orange/brown (hue ~20–35°, high saturation). Classify by mean saturation + hue.
- **Then verify EVERY face visually** (Read each PNG and look). The table is hardcoded forever; get it right once.
- Record edges as **pixel angles**, not direction indices (see Step 2 for why). Edge midpoint angles for a flat-top hex in y-down pixel space: `30°, 90°, 150°, 210°, 270°, 330°`.

Encode in `tile_art_matcher.gd`:
```gdscript
# Which edge-midpoint angles (deg, y-down pixel space) have a painted doorway.
# Derived by pixel-sampling + visual verification 2026-07; see OPUS-BUILD-GUIDE WP1.
const FACE_DOORS := {
    "room_01": [90.0, 210.0, 330.0],   # example — fill from derivation
    ...
}
```

### Step 2 — Matching in pixel-angle space (avoids the dir-index trap)
`HexCoord.DIRECTIONS` indices (0=E…5=SE) do **not** map cleanly onto pixel edges — `board_view._draw_cell_edges` already resolves logical dir → pixel edge by best-dot matching. Do the same here and never touch dir indices:
- Cell's real exits → set of pixel angles: for each open dir, `angle = rad_to_deg(_hex_to_pixel(DIRECTIONS[dir].x, DIRECTIONS[dir].y).angle())`, normalised to [0,360).
- A face rotated by `k*60°` (Godot rotation is clockwise-positive in y-down) maps a painted door at angle `a` to `fposmod(a + k*60.0, 360.0)`.
- Score every (face, k) pair for the cell's tile_type: `score = 6 − (doors_after_rotation XOR cell_exit_angles).size()` (compare as sets with a ±5° snap). Prefer exact matches; tie-break deterministically with `abs(q*7 + r*13 + k)` so a given board renders identically across redraws.
- Public API: `static func pick(tile_type: String, exit_angles: Array, q: int, r: int) -> Dictionary` returning `{face: String, rotation_deg: float, missing_doors: Array, extra_doors: Array}` (angles the art lacks / has spuriously).

### Step 3 — Patch sprites
- Crop a clean doorway strip and a clean rock strip from existing tile art with PIL → `art/tiles/patch_door.png` / `patch_wall.png` (roughly 380×140 at source scale, transparent background, drawn to sit on the hex edge). **⛔ CORIN: open the editor once to import; eyeball the two patches.**
- At render time: for each `missing_doors` angle, place a `patch_door` Sprite2D at the edge midpoint (`position = Vector2.from_angle(deg_to_rad(a)) * HEX_H * 0.5`... use the actual edge-midpoint offset, `rotation = deg_to_rad(a + 90)`); for each `extra_doors`, same with `patch_wall`. Scale to match the tile sprite's scale factor.

### Step 4 — board_view changes (render path only, no engine files)
In `_build_board_nodes` / `_tile_art`:
- Replace the `ArtRegistry.tile(tt,q,r)` call: compute the cell's exit angles, call `TileArtMatcher.pick(...)`, load the face via a new `ArtRegistry.tile_face(face_name)` (keep the old `tile()` for the fallback path), set `spr.rotation = deg_to_rad(rotation_deg)`, add patches.
- `center.png`: no matching — the Central Chamber is unique; render unrotated, patch nothing (verify its painted exits vs generated centre exits; patch if needed like any face).
- **When art is present:** stop drawing the yellow exit bars and the white `Line2D` outline; drop the poly `darkened` tint trick — set `poly.color = Color(0,0,0,0)` under art (poly stays for click-geometry + fallback). Add `const DEBUG_EXIT_BARS := false` to re-enable bars for debugging.
- Rally-zone tint: replace the whole-poly tint with a soft player-agnostic glow ring (a `Polygon2D` ring or large radial `Sprite2D` modulated gold) so rally art still reads.
- Keep the full greybox path intact when `ArtRegistry.any_art_present()` is false — the fallback contract is load-bearing (tests + missing-art degradation).

### Step 5 — Tests (`tests/test_tile_art_matcher.gd`)
Pure-logic, no scenes: (a) a face with doors {90,210,330} matched against exits {150,270,30} returns rotation 60 or 240 with zero diffs; (b) every entry in FACE_DOORS has 1–6 angles, all on the 6 valid midpoints; (c) pick() is deterministic for fixed inputs; (d) over every cell of `generate_map(3, seed)` for 50 seeds, `missing_doors.size() + extra_doors.size() <= 2` (sanity: the face pool covers real boards reasonably) — tune the bound to reality once the table exists.

**DoD:** on a fresh match, every painted doorway on screen leads to a walkable edge and vice versa (patches invisible at arm's length); no yellow bars; greybox fallback still works with art renamed away; GUT green.
**⛔ CORIN:** editor import (patches), `test.bat`, playtest screenshot check, commit `"WP1: exit-true tile rendering (match-then-patch)"`.

---

## WP2 — Token size & tap-to-inspect

**Files:** `ui/board_view.gd` (`_add_unit_rect`, `_redraw_cell_overlay`, input handlers), new `ui/inspect_sheet.gd`.

1. **Rework `_add_unit_rect` sizing.** Tokens are square (450×450 source). Target on-board sizes: 1 unit → 48 px; 2–3 → 40 px; 4–6 → 30 px in a 3-wide grid; 7+ → render first 5 + a "+N" badge token. Replace the `w×h = 26×18` constants with a size chosen from `total`; keep returning `Rect2` for hit-testing (all existing click/stage code keys off those rects — preserve the contract).
2. **Ownership**: replace the backing plate with a 2–3 px owner-colour border (a `ColorRect` slightly larger than the art, or 4 thin rects) + keep the owner-initial outline label. Keep colour-never-the-only-cue.
3. **Damage pips**: `unit["damage"]` (cell unit dicts carry it) → red dots (4 px) along the token's bottom edge. Guardians included.
4. **Staged state**: replace the rectangle outline with scale 1.12 + a glow (`modulate` pulse via tween, or a soft `Sprite2D` halo). Keep the `COL_STAGED` count badge.
5. **Tap-to-inspect** (`ui/inspect_sheet.gd`, `CanvasLayer` layer 25): long-press (≥0.45 s, and touch only — desktop keeps hover tooltips) on a unit/token/tile opens a bottom sheet: full-size art (token 200 px), name, M/A/D + range, effective Defense breakdown (reuse `_effective_defense_for`), damage, ability text (`passive_text`/rules text). One sheet instance, repopulated. Swipe-down/tap-outside closes. Wire from `_input` where hover currently resolves via `_unit_at_point`/`_token_at_point` — same hit paths, new gesture.
6. Old Tech art at 30 px + count.

**DoD:** on a phone-sized window every token is identifiable at a glance; any unit's stats reachable in one long-press; hotseat playtest of a full game without hovering once. UI-TEST-CHECKLIST: add items under a new "I" section.
**⛔ CORIN:** playtest + commit `"WP2: readable tokens + tap-to-inspect"`.

---

## WP3 — Markers, chips, atmosphere

**Files:** `ui/board_view.gd`, `ui/game_theme.tres`, `ui/setup_screen.gd`, `scenes/*.tscn` backgrounds.

1. `_draw_token_markers`: use `ArtRegistry.misc(&"activation_front")` (ACTIVE) / `&"activation_back"` (CONTROL) at ~26 px, `self_modulate` = player colour; keep a shaped border (triangle vs diamond outline) as the colour-blind cue.
2. Env/func chips: art at 30 px; face-down uses the `_back` art already registered; face-up keeps the short-name label under the art (11 px, outlined).
3. Background: full-screen `TextureRect`/gradient (dark wasteland brown-black radial) behind `_hex_root` in BoardView + SetupScreen; subtle shadow under each tile (a dark hex poly offset (3,4) at alpha 0.35, drawn before art).
4. `game_theme.tres`: panel StyleBoxFlats (dark steel + rust accent), consistent corner radii, font sizes for the existing Labels/Buttons. Small, targeted — don't restyle every control by hand; let the theme cascade.
5. Setup screen: title + the four leader cards as a banner strip (pre-leader-select; WP5 makes them functional).

**DoD:** a screenshot reads as "a game," not a tool. Commit `"WP3: markers, chips, board atmosphere, theme"`.

---

## WP4 — Wire Razor + Lil' Minerva

**Source files** (in `..\..\..\Wasteland Warriors\`): `Razor Art.png` (696×696, raw art — NOT token-framed), `Lil Minerva.png` (1833×1827).

1. **Razor token composite (PIL in sandbox):** build a 450×450 token matching siblings: sample an existing guardian token for the rounded-square frame/background; centre-paste Razor art scaled to fit; add stat icons by **cropping the boot/star/vest icon clusters from an existing guardian token** and compositing digits — Razor is **M2 / A2 / D2 / R1** (stats confirmed by Corin 2026-06-09). Save → `art/tokens/guardians/razor.png`. **⛔ CORIN approves the composite** (or supplies a hand-made token — offer both).
2. **Minerva:** centre-crop/scale to 1575×1575 → `art/leaders/lil_minerva.png`.
3. `art_registry.gd`: add `&"razor"` and `&"lil_minerva"` entries; update the comments listing missing art.
4. `tests/test_art_registry.gd`: razor/minerva move from the known-missing assertions to the resolve-hit assertions. Ancient Artifact + Falling Debris remain known-missing (chip fallback) unless Corin exports them.
5. **⛔ CORIN:** editor import, `test.bat`, commit `"WP4: Razor + Lil' Minerva art wired"`.

---

## WP5 — Leader subsystem (engine + UI)

**The one-liner first:** in `logic/round_fsm.gd` (~line 212) replace `&"seraph_recruit_bonus"` with `&"seraph_recruit"` (the `.tres` value; `ui/recruitment_panel.gd:200` already checks the correct ID).

**Schema (data-driven passives — matches the flags-on-Resources architecture).** Extend `data/leader_data.gd`:
```gdscript
@export var affected_unit_ids: Array[StringName] = []  # units the stat bonus applies to
@export var bonus_move: int = 0
@export var bonus_range: int = 0
@export var bonus_defense: int = 0
```
Fill the `.tres`: stormfoot `[warrior, scout] move+1`; ratseye `[warrior, gunner] range+1`; siyana `[warrior, heavy] defense+1`; seraph/minerva keep bonuses 0 (their passives are behavioural, dispatched on `passive_effect_id`).

**Assignment path:**
1. `ui/setup_screen.gd`: per-seat leader picker — 5 leader-card buttons (`ArtRegistry.leader(id)`, greybox name-button fallback), no duplicates across seats, AI seats auto-assign randomly from the remainder on start. Add `"leader": StringName` to each seat spec.
2. `autoload/game_state.gd` `setup_match`: load `data/leaders/*.tres` into a `leader_db`, set `p.leader` from the spec (default: random unique — headless tests keep working with no spec change).
3. HUD/info panel: leader name + portrait chip per player (info_panel already lists per-player blocks).

**Passive wiring (each is a small, central hook — no per-leader branches at call sites):**
1. New helper in `game_state.gd`:
```gdscript
func leader_bonus_for(color: StringName, unit_data, stat: String) -> int:
    var p = get_player(color)
    if p == null or p.leader == null or unit_data == null: return 0
    if not ("id" in unit_data) or not (unit_data.id in p.leader.affected_unit_ids): return 0
    match stat:
        "move": return p.leader.bonus_move
        "range": return p.leader.bonus_range
        "defense": return p.leader.bonus_defense
    return 0
```
2. **Move (Stormfoot):** in `action_resolver.gd` where the abilities dict is built for reachability (`_reachable_via_state` / the `abilities["move"] += extra_move_for(...)` site at ~line 363): also `+= state.leader_bonus_for(owner, unit_data, "move")`. Mirror in the Manstopper reduced-move branch.
3. **Range (Rat's Eye):** in `ActionResolver.eligible_ranged_shooters`: effective range = `data.range + leader_bonus_for(color, data, "range")`. **Ruling needed ⛔ CORIN (plan Part 5 Q2):** does a +1-range Warrior count as "ranged" for Sunstone/turrets? Proposed YES (evaluate `range >= 1` on the *effective* value); implement per ruling and note it in the rulebook FAQ.
4. **Defense (Siyana):** in `ActionResolver.build_combat_context` where `extra_defense` per side is assembled (~line 196): per-unit bonus, not per-side — the cleanest seam is `CombatResolver`'s `Combatant.defense_bonus` stamp: add the leader bonus where combatants are built (both `combatants_from_units` call sites get the owning color; pass a `leader_lookup` callable through the context like `forced_faces` does). Also fold into `token_effects`' prune-vs-effective-defense and `_effective_defense_for` in board_view (display). Stacks with control/drone per the stacking rule.
5. **Minerva:** in **both** draw paths (`round_fsm.gd:467` and `game_controller.gd:480` `_draw_action_card`): if leader passive is `&"minerva_card_advantage"`, draw 2; keep-policy: headless/AI keeps the first Recruitment-type card else the first; human path → tiny two-card picker modal (reuse the unit-picker overlay pattern in board_view). Plus one extra card at match start (`setup_match` or first deal).
6. **Seraph:** after the ID fix, verify counts 5 units / 3 special flow through BOTH the FSM path (`_apply_leader_recruit_passive`) and the live path — the recruitment panel gates counts client-side, but `GameController._apply_recruitment_choice` must also enforce the cap server-side (add the check; AI path relies on it).

**Tests — new `tests/test_leaders.gd` (~8):** assignment via spec + random-unique default; stormfoot scout reaches distance 3; ratseye warrior appears in eligible shooters (+ sunstone interaction per ruling); siyana warrior survives a hit that kills a control-less baseline; minerva draws 2 keeps 1 (forced deck); seraph recruit 5; seraph cap enforced in controller; no-leader = all bonuses 0.

**⛔ CORIN:** `godot --headless --editor --quit` (new test file + schema fields), `test.bat`, playtest leader select, commit `"WP5: leader select + all 5 passives (fix Seraph ID)"`.

---

## WP6 — Artifact UI, function-token offers, headless cards

### 6a. Artifact tray (play surface for `ArtefactEffects`)
**Files:** new `ui/artifact_tray.gd`, edits to `ui/game_hud.gd`, `logic/game_controller.gd`, `ui/board_view.gd`.
1. HUD button `"🏺 ×N"` (current player's `p.artefacts.size()`) → tray panel: artifact cards (450×600 art via `ArtRegistry.artefact(id)`), each with a PLAY button enabled only in the artifact's legal phase (the effect returns `_is_phase` failures — but grey the button proactively: jam_gobbar/snooperbot=Recruitment, sunstone=Action, psychic_belt=Guardian, medical_machine=passive/never playable).
2. `GameController.play_artifact(color, effect_id)` → `ArtefactEffects.resolve(state, color, card, phase, deps)`; on `{"needs": kind}` → hand off to board_view target mode. Reuse the card-targeting infrastructure (`_enter_card_target_mode`) — add the two target kinds: `"own_space"` (tap a space with your units) and `"psychic_steal"` (tap adjacent enemy unit; two-step: source space then unit, reuse `_show_unit_picker_overlay`), then `ArtefactEffects.resolve_targeted`.
3. Emit a summary through the existing action-hint pill; redraw via EventBus.

### 6b. Function-token recruitment offers
**Files:** `ui/recruitment_panel.gd`, `logic/game_controller.gd`.
1. New `game_state.gd` helper: `controlled_function_rooms(color) -> Array[{coord, effect_id}]` (face-up func token + `TokenState.CONTROL` for color).
2. Recruitment panel: context buttons when available — "Spawn Guardian — Control Room", "Deploy via Teleporter Hub", "Discard Artifact → place Special". Each builds the intent the FSM already documents (`control_room_spawn` / `hub_deploy` / `artefact_place_special` with `room`/`special_id`/`space`).
3. **`GameController._apply_recruitment_choice` currently only handles deploy/recruit/punish** — add the three branches, delegating to the same RoundFSM logic (extract shared statics if needed rather than duplicating; FSM branches live at `round_fsm.gd:101–112`). Board-target sub-picks (which room, which space) reuse the pending-card board-click flow in board_view.

### 6c. Headless card-effect application (matrix follow-up)
In RoundFSM's recruitment + action card windows: after the type-gate passes, actually call `CardEffects.resolve(...)`; cards whose resolve returns `needs` are only playable headless if the agent intent carries `"card_params"` — otherwise reject the intent (agent keeps the card). Document in `agent.gd`'s intent docstring. This is what lets WP8's AI play cards through the same path as humans.

**Tests:** extend `test_section_g_fixes.gd` or new `test_artifacts_live.gd`: play each artifact through `GameController.play_artifact` on a scripted board (jam gobbar removes ≤5 cowards; snooperbot deals 1 card each; sunstone raises ranged floor to 6; psychic belt steals an adjacent unit); controller handles `control_room_spawn`/`hub_deploy`/`artefact_place_special`; headless movement card actually applies its effect.
**⛔ CORIN:** `test.bat`, playtest all five artifacts + all three function actions, commit `"WP6: artifact tray, function-token actions, headless card effects"`.

---

## WP7 — Combat on the board

**Files:** `ui/combat_readout.gd` (emit), `ui/board_view.gd` (react). No rules code.

1. `combat_readout.gd`: as the playback queue reveals each event, emit `signal event_shown(evt: Dictionary)` (the raw log dict — it already carries type/side/face/coord data). SKIP emits nothing further; REPLAY re-emits.
2. `board_view.gd`: new `_fx_root: Node2D` above overlays; connect `event_shown`:
   - `die_hit`/`die_crit`/`die_miss`: small rising-fading label at the combat hex ("4", crit gold + 1.4× pop, miss grey), jittered ±12 px so casts don't stack.
   - `hit_assigned`: flash the target unit's token red (modulate tween 0.15 s), tick a damage pip.
   - `death`: token fades + drops 8 px; redraw after.
   - `combat_start`: brief 1.08× pulse of the hex; `combat_end`: nothing (readout already summarises).
   - crit: camera micro-shake — `_cam.offset` noise for 0.12 s, amplitude 3 px, **once per crit chain**, not per die.
   - `guardian_ranged_attack` (EventBus signal, exists since the Arachnid fix): tween a 2-point `Line2D` bolt from guardian hex to target hex.
3. Effects must be fire-and-forget (tweens with `queue_free` on finish); never block the queue; cap simultaneous fx nodes (~40) and drop excess (SKIP-heavy replays).
4. `AudioManager.cue()` calls piggyback the same handler (`"die_crit"`, `"death"` cues) — still silent until WP10 fills CUES.

**DoD:** watching a 3-way fight at 1x, you can follow it on the BOARD with the readout as subtitles. Commit `"WP7: on-board combat playback fx"`.

---

## WP8 — Section H: the HeuristicAgent (medium AI)

**Files:** new `logic/heuristic_agent.gd` (`class_name HeuristicAgent extends Agent`), edits to `logic/game_controller.gd` (seat setup + pacing), new `tests/test_heuristic_agent.gd`. The `Agent` seam was built for exactly this — implement `decide_recruitment(state, color)` and `decide_action(state, color)` returning the documented intent dicts. **No GameState mutation from the agent, ever** — intents only. Seed all randomness from a `RandomNumberGenerator` handed in at construction (AI-vs-AI reproducibility).

### Recruitment policy (in priority order, first match wins)
1. If `controlled_function_rooms` offers Control Room and a Guardian near an enemy would hurt them more than us → `control_room_spawn` (cheap check: nearest enemy unit distance < nearest own distance).
2. If bag coward-fraction ≥ 0.45 → `punish` (draw 5).
3. If units-on-board < 3 or rally zone empty → `deploy`.
4. If supply has Specials and old-tech race is close → `recruit` Specials (respect 3/2 caps, 5/3 under Seraph — engine enforces after WP5).
5. Else `deploy`.
Play a held Recruitment-type card first when its effect is a no-brainer (Deploy Unit with a controlled space available); use `card_params` only for cards with trivial targeting, else hold.

### Action policy — score candidate activations
Enumerate: for each own-occupied space, `HexGraph.reachable` per unit (the engine's own reachability — never reimplement); candidate destinations = union. For each candidate `(dest, movable_units)` compute:
```
+1000 deliver Old Tech to own rally (win-progress; carriers need Control — check)
 +400 pick up / step onto unclaimed Old Tech with enough force to hold
 +250 attack a Guardian we beat in expectation
 +120 attack enemy units we beat in expectation
  +80 take Control of a contested/valuable room (func tokens, centre ring)
  +40 flip unexplored tokens (exploration)
  −300 expected own losses exceed gains (suicide guard)
```
Expected-combat estimate: `expected_hits = attack_dice_sum * 0.5` vs effective defense (base + control/drone/leader) both ways — crude is fine, it's MEDIUM. Support fire: accept all eligible shooters when the shot side is ours (`auto_support_fire` already does this headless — verify the live path asks the provider; return "all" for AI). Hit assignment: leave engine default (minimise-losses). Attack cards: play a reroll card when round-1 misses ≥ 2; else hold. Artifacts: use jam_gobbar when cowards ≥ 4; sunstone when defending a rally with OT; others hold (document as v1.1 upside).
Pass when best score < 30 (tune in WP9).

### Wiring & pacing
`game_controller.gd` seat setup (~line 97): `agents[color] = HeuristicAgent.new(rng)` instead of `PassAgent.new()`. Add a 0.4–0.7 s delay before each AI intent lands (timer in the controller's serve loop, skippable by tap) + "P2 is thinking…" via the existing action-hint pill. Keep `PassAgent` class for tests.

### Tests (`tests/test_heuristic_agent.gd`)
(a) 50 seeded AI-vs-AI-vs-AI headless games: all terminate < 60 rounds, zero crashes; (b) determinism: same seed → same winner & round count; (c) unit-level: given a hand-built board with adjacent unclaimed OT, agent's intent moves onto it; given only a suicide attack, agent passes; (d) HeuristicAgent beats 2 PassAgents ≥ 45/50 games; (e) full suite still green.
Mirror (a)–(b) in a Python port sim first (the usual pattern), but GUT-on-real-Godot decides.

**⛔ CORIN:** editor once (new class_names), `test.bat`, a human-vs-2-AI playtest, commit `"Section H: HeuristicAgent medium AI + pacing"`.

---

## WP9 — Section I: balance

1. New `tests/sim_balance.gd` OR a `--headless` entry script `tools/run_balance.gd` (keep it OUT of the default GUT dir so `test.bat` stays fast; Corin runs it explicitly): 300 seeded 3-AI games → per-seat win rate, per-leader win rate (random leaders), avg rounds, guardian kill counts, OT deliveries. Write `BALANCE-REPORT.md`.
2. Red flags: seat-1 win rate > 40% (first-mover), any leader > 26% or < 13% (5 leaders ⇒ fair = 20%), median game > 25 rounds (slog) or < 8 (rush), guardians killing < 5% of units (toothless).
3. Tune ONLY data/AI constants (leader bonuses, AI weights, guardian counts) — rules changes are **⛔ CORIN rulings**, recorded in the rulebook with [CHANGE] notes.
4. Re-run after every tweak; keep the report's history table.

**⛔ CORIN:** run time (~minutes locally), rulings, commit `"Section I: balance sims + tuning"`.

---

## WP10 — Section J: ship it

1. **Audio (if Corin says yes — plan Part 5 Q5):** CC0 set per build-plan Appendix A (Kenney UI/impact packs first); ~10 files into `audio/`; fill `AudioManager.CUES` (it's drop-in by design); `LICENSES-AUDIO.md` with per-file source+license. **⛔ CORIN:** editor import.
2. **Icon/splash:** 512×512 icon from key art (PIL composite), `boot_splash` in project.godot, title screen art.
3. **Export presets:** write `export_presets.cfg` — Android (package `com.rynolourens.wastelandwarriors`, landscape, min SDK per Godot 4.6 defaults, keystore paths left as placeholders — **never** commit a keystore; `.gitignore` already guards) + Windows Desktop. **⛔ CORIN:** install Android build template, create debug keystore, export, install on phone.
4. **Device QA checklist** (append to UI-TEST-CHECKLIST): touch targets ≥ 44 px at real DPI, long-press inspect vs scroll conflict, safe-area/notch, performance during combat fx + 60-token boards, battery/thermals in a 20-min session, back-button behaviour.
5. **2P/4P (plan Part 5 Q4):** if Corin supplies ring/rally screenshots → encode in `map_generator.gd` `rally_zones()` + `_build_deal()` (the slots are data-driven; mirror the 3P derivation: mandatory positions, deal budget, fixture coords) + GUT seeds test. Otherwise: hide the 2P/4P options in setup for v1 (don't ship a warning-stub).
6. **Help/FAQ screen:** `ui/help_screen.gd` — rulebook chapter summaries (Ch.7–11 condensed), leader/guardian/token galleries using the art registry, and the FAQ rulings accumulated in WP5/WP9. First-game hint toasts (3–4, one per phase, dismiss-forever flag in `user://settings.cfg` — NOT localStorage-style web storage; this is Godot, use ConfigFile).
7. Final sweep: full GUT, full UI-TEST-CHECKLIST, tag `v1.0`.

---

# SECTION 3 — STANDING VERIFICATION PROTOCOL (every WP)

1. Python-verify any engine logic before writing GDScript (port or targeted mirror).
2. After every `.gd` write: NUL=0, trailing newline, bracket balance, tail intact, `git diff --stat` sanity (no unexplained −hundreds).
3. Grep new code for the inference traps: `var \w+ := (min|max|.*\.(get|pop_front)\(|.*\[)` and unused locals.
4. New class_name / new PNG / new test file ⇒ tell Corin the editor must open once before GUT.
5. Corin runs `test.bat`; a WP is DONE only when GUT is green locally AND the WP's playtest passes.
6. Corin commits + pushes with the suggested message; verify `git log` shows it before starting the next WP.
7. Update the memory + `PROJECT-AUDIT-AND-POLISH-PLAN.md` scoreboard as sections complete.

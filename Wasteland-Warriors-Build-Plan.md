# Wasteland Warriors — Video Game Build Plan

*A start-to-finish plan for building the Wasteland Warriors digital game in Godot 4.*

**Scope decisions baked into this plan (from review):**

- **v1 target:** Hotseat (local pass-and-play) **plus a rules-based AI opponent** at a single **medium** difficulty. Empty seats are **filled by AI by default**. No online multiplayer in v1.
- **Content target:** Full **3-player** game with **all 5 Leaders** (the game has 5 total — Stormfoot, The Rat's Eye, Lady Seraph, Siyana, Lil' Minerva — all now authored as `.tres`). The Action-card deck (13 cards) and tile set are **complete** — the gaps in card numbering (08/12) and tile-draft numbers are just non-contiguous numbering, NOT missing content. The only genuinely deferred content is **2P/4P layouts and the FAQ** — data-driven slots to fill later, not part of v1 work.
- **Platform target:** **Mobile-first — a phone app held sideways (landscape) is the ideal platform**, with PC as a co-supported target. Godot exports to both from one project. This drives UI density, touch-target sizing, and layout throughout (see Section F/G).
- **Engine:** Godot 4, GDScript. Already installed.
- **Resourcing:** Solo, part-time. Milestones are sized as self-contained chunks you can finish in a sitting or two, so progress survives gaps between sessions.
- **Audio:** Optional for v1. A lightweight sourcing plan is included (Section G + Appendix) but audio never blocks a milestone.
- **Map building:** **Automated and randomized each match.** Players no longer take turns placing tiles — the game instantly generates a random, legal board (still obeying the three core rules and ring structure) so matches start faster. The pre-game placement mini-game is removed.
- **Source of truth:** `Wasteland Warriors Rulebook (Revised).md` (rules) and `Game-Design-Best-Practices-Guide.md` (architecture/UI). This plan operationalizes both.

The guiding principle from your best-practices guide runs through everything below: **separate data, logic, and visuals.** The game is a deterministic rules engine wearing art. Build the engine first, prove it with tests, then dress it.

---

## Part 1 — High-Level Build Overview

The build breaks into **ten sections (A–J)**. They are ordered so each one rests on the one before it. The first four (A–D) are the "rules engine" — no art, fully testable. The middle three (E–G) make it a playable, good-looking game. The last three (H–J) add the opponent, balance, and ship.

| # | Section | What it delivers | Depends on |
|---|---------|------------------|------------|
| **A** | **Project skeleton & data layer** | Godot project, folder structure, autoloads, `.tres` resource schemas for every unit/guardian/card/token | — |
| **B** | **Core logic: GameState & board model** | Hex-coordinate board, bags, Rally Zones, token/control state, phase machine — pure GDScript, no scenes | A |
| **C** | **Combat resolver** | Simultaneous combat, cascading crits, defender-assigns-hits, damage persistence, special-unit ability flags | B |
| **D** | **Rules engine: phases & actions** | Recruitment / Action / Guardian phases, Move-and-Attack, Guardian AI movement, victory check — all under GUT tests | B, C |
| **E** | **Greybox board & interaction** | Visible hex board, map-building placement rules, click→intent→logic→signal→visual loop, legal-move highlighting | B, D |
| **F** | **Round flow & hotseat UI** | Full round playable hotseat with plain UI: phase banners, turn passing, card hands, HUD | D, E |
| **G** | **Art, animation & juice** | Real card/token/tile art, tweens, combat playback queue, theme, tooltips, hidden-info surfacing | F |
| **H** | **AI opponent** | Rules-based heuristic AI with difficulty tiers, plugged into the same intent API as humans | D (then F) |
| **I** | **Balance, save/load & polish** | Seeded RNG, save/load, simulated-combat balancing, settings, accessibility | G, H |
| **J** | **Content completion & release prep** | Fill stubbed content (Leaders, 2P/4P layouts, FAQ/tutorial), package & export PC build | I |

**The critical sequencing rule:** Do **not** start Section E (anything visual) until Sections A–D pass their unit tests. Every hour spent on UI before the rules are proven is an hour you may rip out. Your guide is emphatic on this, and Wasteland Warriors' combat (cascading crits, special-unit exceptions, damage-after-death) is exactly the kind of thing that looks fine in the UI and is silently wrong underneath.

---

## Part 2 — Step-by-Step Per Section

Each section lists concrete steps. Code-level detail (node structures, resource fields, test targets) is included alongside the higher-level "what and why," per the request for both.

### Section A — Project skeleton & data layer ✅ COMPLETE (2026-06-09)

**Goal:** A clean Godot project where all game content lives in data files, not code.

> **Status — DONE.** Godot 4.6 project scaffolded and pushed to GitHub
> (https://github.com/RynoLourens/wasteland-warriors). Folder layout, `EventBus` +
> `GameState` autoloads, all 7 `Resource` schema scripts, GUT installed/enabled, and
> **56 `.tres` instances** authored (8 units, 8 guardians, 4 leaders, 5 artefacts,
> 18 env/function tokens, **13 action cards = the COMPLETE deck** — the 08/12 gaps are
> just non-contiguous numbering, not missing cards). Combat numbers now all read from
> token art (tracked in `SECTION-A-tres-checklist.md`).

**Steps:**

1. **Create the Godot 4 project** and commit it to git immediately. Add a `.gitignore` for Godot (`.godot/`, `*.import` caches). Version control is non-negotiable for a part-time project — it's your undo across sessions.
2. **Create the folder layout** from your guide:
   ```
   /data        (.tres resources: units, guardians, cards, tokens)
   /logic       (pure GDScript: GameState, CombatResolver, Rules, AI)
   /scenes      (Board, HexTile, UnitToken, CardUI, HUD, menus)
   /ui          (themes, fonts, reusable Control scenes)
   /tests       (GUT unit tests for the logic layer)
   /autoload    (GameState, EventBus, managers)
   /art         (imported PNGs from the Wasteland Warriors folder)
   ```
3. **Install GUT** (Godot Unit Test) from the Asset Library now, before writing logic — you'll write tests as you go, not after.
4. **Define resource scripts (`Resource` subclasses)** — these are schemas; instances become `.tres` files:
   - `UnitData` — fields: `id`, `display_name`, `move:int`, `attack:int`, `defense:int`, `range:int`, and **ability flags** as a dictionary or typed fields: `crit_on:int` (default 6), `hit_only_on:int` (0=normal), `moves_through_enemies:bool`, `extra_setup_move:bool`, `places_sticky_bomb:bool`. This flag approach is what keeps special units (Infiltrator, Berserker, Manstopper, Sapperteur) out of hardcoded `if` tangles.
   - `GuardianData` — same shape plus guardian-specific flags: `crit_on`, `hit_only_on`, `attack_dice`, `attacks_on_move:bool` (The Ox), `applies_hits_first:bool` (Razor), `extra_attack_rounds:int` (Scrape), `moves_through_walls:bool` (Blink), `reduces_attack:bool` (Blackout), plus `range` (Arachnid=2).
   - `ActionCardData` — `id`, `name`, `text`, `card_type:enum{RECRUITMENT, MOVEMENT, ATTACK}`, and an `effect_id` the rules engine dispatches on.
   - `ArtefactData`, `EnvironmentTokenData`, `FunctionTokenData` — `id`, `name`, `effect_id`, `color/category`, `persists_in_room:bool` (Teleporter Node, Darkness, Tough Terrain stay).
   - `LeaderData` — `id`, `name`, `passive_effect_id`. All **5** Leaders authored (the game has 5 total).
5. **Author the `.tres` instances** straight from the rulebook:
   - Units: Warrior M1/A2/D1, Heavy M1/A1/D2, Gunner M1/A1-R1/D1, Scout M2/A1/D1, plus the 4 Special Units with their flags.
   - 8 Guardians (Blackout, The Ox, Blink, Cutter, Typhoon, Razor, Arachnid, Scrape) with flags. Note: the rulebook's Guardian *list* in Ch.12 names these — confirm the bag is 8 Guardians + 4 Scrap.
   - Action cards: **all 13 authored = the complete deck.** The 08/12 numbering gaps are not missing cards, just non-contiguous export numbers.
   - Artefacts: **the Artefact deck and the "Bauble" deck are one and the same** — model a single deck. The 5 designed Artefacts (Medical Machine, Psychic Control Belt, Snooperbot 6000, Sunstone Fragments, The Jam Gobbar) populate it; the Ancient Artifact environment draws from this same deck.
   - Environment tokens (6 room + 8 corridor), Function tokens (4), Leaders (**all 5** — Stormfoot, The Rat's Eye, Lady Seraph, Siyana, Lil' Minerva).
6. **Define the EventBus autoload** as a stateless signal hub: `unit_moved`, `combat_resolved`, `phase_changed`, `guardian_spawned`, `old_tech_captured`, `token_flipped`, `control_changed`, `turn_passed`. Nothing in it but signal declarations.

**Section A is done when:** every game noun exists as a `.tres` you can inspect, and the project opens clean with autoloads registered. ✅ Met.

### Section B — Core logic: GameState & board model ✅ COMPLETE (2026-06-09)

> **DONE.** Built `logic/hex_coord.gd` (cube/axial: neighbours, distance, ring,
> spiral), `logic/hex_cell.gd` (per-tile state: edges, units-by-owner, explicit
> TokenState, env/func tokens, Old Tech), `logic/player.gd` (seeded
> sample-without-replacement bag + Deploy/Recruit/Punish), `logic/hex_graph.gd`
> (dynamic-edge reachability: doorways, enemy-block pass-through, Infiltrator,
> Blink, Teleporter network, Tough Terrain stop), and `logic/map_generator.gd`
> (`generate_map` + `is_legal_placement` + `seed_tokens` + 3P rally zones).
> `autoload/game_state.gd` now composes them via `setup_match()`.
>
> **3P map design locked from Corin's layout screenshot:** the mandatory tile
> positions ("green dots") snap exactly to **ring 1 (6) + ring 2 (12) = 18
> positions**, matching the **18-tile budget** (3 players × [2 Rooms + 4
> Corridors] = 6 Rooms + 12 Corridors). Inner ring completes before the next.
> Rally zones on ring 3 (~120° apart): green (-3,0) TL, blue (3,-3) TR, red (0,3)
> bottom. 2P/4P are documented stubs (`rally_zones()` returns empty + warns).
>
> **Generator approach (revised from the plan's "orient-and-hope + backtracking"):**
> a naive orient-each-tile generator leaves islands ~56% of the time (verified).
> Instead we model each shared boundary as ONE truth value (open for both tiles
> at once), so rule 2 ("no Closing") is impossible to violate by construction,
> then build a spanning tree outward from center (guaranteed connectivity) plus
> random extra edges (loops) and dangling mouths (the open arms into the desert).
>
> **Verification:** the core algorithm was ported to Python and run over **20,000
> seeds — every board is exactly 19 cells, fully connected, zero rule-2
> violations, deterministic per seed.** GUT suite mirrors this: `tests/`
> test_hex_coord, test_player_bag, test_map_generator (1,000-seed sweep +
> determinism + token-seeding + legality), test_hex_graph (movement). All test
> assertions were cross-checked against Python ports of the algorithms.
>
> **Milestone M2 reached.** Next = Section C (Combat resolver). Corin to run GUT
> locally (`godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`)
> and `git add -A && git commit && git push`.

**Goal:** An authoritative, headless model of a game in progress. No scenes loaded.

**Steps:**

1. **Model hex coordinates with cube/axial coordinates from day one** (Red Blob Games is your reference, linked in the guide). Build a `HexCoord` helper with neighbor, distance, and direction math. Retrofitting this later is painful — the "every other row is offset" trap bites everyone who starts in pixels.
2. **Build `GameState`** (autoload) holding: a `Dictionary` of `HexCoord → HexCell`, each `HexCell` storing occupants (units by owner), tokens present (Environment/Function face-up/down state), Old Tech tokens, and an **explicit token-state enum per player per hex**: `enum {NONE, ACTIVE, CONTROL}`. Encode this explicitly — never infer face-up vs face-down from other state. The rulebook's "(face-down tokens don't count)" caveats are precisely where bugs hide.
3. **Model each player:** `bag` (a list sampled without replacement via **seeded RNG** — not a reshuffle-each-draw model), `rally_zone:HexCoord`, `leader`, `hand` (Action cards), `old_tech_count`, `control_set`.
4. **Model the board as a graph** for movement. Plan now to use `AStarGrid2D` or a custom hex A* where **edges are dynamically enabled/disabled** per unit ability and board state (enemy-occupied spaces block pass-through; Tough Terrain stops movement; Teleporter Nodes are adjacent to all other teleporters; Blink crosses walls). "Distance" math will not survive these rules.
5. **Implement automated map generation (Ch.5)** as a pure, seeded function `generate_map(player_count, seed) -> board`. **[DESIGN CHANGE]** The map is now **built automatically and randomized each match**, not placed by players turn-by-turn — this cuts the pre-game friction and gets players into the actual game faster (per the guide: automate upkeep, preserve decisions; tile placement is a procedure, not a strategic choice). The generator must still obey the **same three core rules and ring structure** as the old manual process:
   - Keep `is_legal_placement(tile, coord)` as a pure predicate enforcing **Connected + exactly one Open Space + one Potential Space**, the **no-Closing** rule, and the **"ignore Rule 1/2 if impossible"** fallback. This is the validity oracle the generator calls.
   - The generator fills **concentric rings outward from the Central Chamber, completing each ring before the next.** Within a ring, at each step it: computes the set of legal (Potential Space, tile-orientation) placements via the predicate, draws the next tile from the appropriate shuffled deck (Room/Corridor, seeded), picks a legal placement at random, and places it. Respect the deck composition (the finalized tile set; Components lists "30x Tiles") and the Room/Corridor mix the rings require.
   - **Determinism:** drive every shuffle and random choice from the match `seed` so a given seed always reproduces the same board — needed for reproducible bug reports and "same board" rematches.
   - **Guarantee a valid, fully-connected board:** because some random draw orders can dead-end (a ring slot with no legal placement for the drawn tile), build in **backtracking or constrained re-draw** so generation always terminates with a legal board. Cap attempts and, on the rare failure, re-roll from a derived seed. Add a GUT test that generates thousands of boards across seeds and asserts every one is legal, fully connected, and ring-complete.
   - Then seed tokens (step 6) and place Rally Zones (step 7) on the finished board exactly as before.
6. **Implement token seeding** after map build: blue Environment in each Corridor, orange Environment + yellow Function in each Room, none in Central Chamber.
7. **Write the 3-player Rally Zone placement** (~120° apart; green top-left, blue top-right, red bottom-center). Leave 2P/4P as stub functions returning "not yet defined."

**Section B is done when:** GUT tests prove a board can be built, tokens seeded, bags drawn deterministically from a seed, and legal placements/movements computed — all with no scene loaded.

### Section C — Combat resolver

> ## ✅ SECTION C COMPLETE (2026-06-09) — Milestone M3 reached
>
> **`logic/combat_resolver.gd`** implements the full pipeline:
> declare → roll → assign → apply → check-deaths, **simultaneous** (all hits
> computed before any unit is removed), with **cascading crits as a bounded
> `while` loop** that emits one discrete `die` event per roll so the UI
> (Section G) can replay the chain. The resolver is **pure** (no GameState /
> EventBus coupling) and returns a replayable event log; the caller emits
> `EventBus.combat_resolved(event_log)`.
>
> **All exceptions are flag-driven** via `_flag()` / `_num()` querying the
> unit/guardian Resource — zero hardcoded unit names: Berserker/Cutter
> `crit_on=5`, Typhoon/Infiltrator `hit_only_on=6`, Razor `applies_hits_first`
> (resolved in a **pre-combat sub-round** so his kills pre-empt the main round),
> Scrape `extra_attack_rounds` (the **whole combat runs 2 full simultaneous
> rounds**), The Ox `attack_dice=2`, Blackout `reduces_attack` (−1 die to **each**
> side), Sapperteur Sticky Bomb (**pre-combat** sub-round vs the entering side).
>
> **Decisions locked this session (Corin):** Razor = pre-combat sub-round;
> default hit-assignment policy = **minimise losses** (stack onto the unit
> closest to dying); Scrape = **entire combat runs 2 rounds**.
>
> **Damage persistence + defense:** damage tokens live on the unit dict and
> persist across combats (heal at Cleanup, Section D). Death is checked against
> **effective Defense** = base + controlled-ground/buff bonus, stamped onto
> defenders so targeting and death agree (this was a real bug, caught and fixed
> in verification: without it a controlled unit died one hit early). The +1 for
> controlling a space **DOES stack with a Shield Drone** (+1 each → +2 on a
> controlled space defended by a drone); stacking buffs (Siyana) add on top via
> `extra_defense`.
>
> **Schema additions:** `data/unit_data.gd` gained `attack_dice` (0 = use printed
> Attack), `sticky_bomb_dice`, `grants_ground_defense` (Shield Drone). Guardian
> schema already carried its flags.
>
> **Verification:** core math ported to Python and run over a **10,000-combat
> seeded sim — zero crashes, bounded cascades, sane hit rate (~0.47; below 0.5
> because hit-on-6 units pull the mean down).** **16 edge-case checks** + **17
> forced-die-sequence checks** all green, each mirroring a GUT assertion exactly.
> GUT suite: **`tests/test_combat_resolver.gd`** (per-special-unit + per-Guardian
> isolation tests via a scriptable `forced_faces` die seam, defensive-interaction
> tests, bounded-cascade test, 10k-combat sim). Godot is NOT runnable in the
> sandbox — Corin runs GUT locally
> (`& "<exe>" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`,
> running `godot --headless --editor --quit` once first to register the new
> `class_name CombatResolver`), then `git add -A && git commit && git push`.
>
> **Next = Section D (Rules engine: phases & actions).**

**Goal:** A combat function that takes board state + participants and returns a result, correct for every special-unit and Guardian exception.

This is the hardest, highest-risk module. Build it as a strict pipeline, not an ad-hoc calculation.

**Steps:**

1. **Pipeline: declare → roll → assign → apply → check deaths.** Compute *all* hits for *all* participants first, then apply them. Never remove units mid-calculation — your rules say hits apply even if the unit dealing them is killed, and both sides deal damage in the same round. Order-dependent removal is a classic source of silent bugs here.
2. **Cascading crits as a `while` loop:** each 6 (or 5–6 for Berserker/Cutter) grants another die, which can crit again. The code is easy; the hard part lives in the UI (Section G) — so **emit each die roll as a discrete event** into a result log the UI can replay, rather than returning only a final number.
3. **Dice & hits:** sum RED Attack across a player's units in the space = dice rolled; 4/5/6 = hit; 6 = crit + bonus die. All players roll **simultaneously**.
4. **Defender assigns hits to their own units** (changed from original). Excess hits on a killed unit are lost. Model "assign" as a function the defender (human or AI) supplies; in tests, supply a deterministic policy.
5. **Ability flags drive exceptions** — query the unit/guardian Resource, never hardcode: `crit_on` (Berserker/Cutter 5), `hit_only_on` (Typhoon/Infiltrator 6), `applies_hits_first` (Razor — resolve his sub-roll before others), `extra_attack_rounds` (Scrape = 2 rounds), `attacks_on_move` (The Ox — 2 dice, doesn't stop), `reduces_attack` (Blackout — −1 die to all in space).
6. **Damage persists within a round:** Damage tokens stay on survivors across combats; death when total Damage ≥ GREEN Defense. All units heal fully at end-of-round Cleanup (handled in Section D).
7. **Defender mitigation:** +1 Defense for controlling the space; does **not** stack with Shield Drones (cap +1 from "controlled ground"). Other buffs (Siyana) still stack.
8. **Sticky Bombs & ranged pre-combat:** Sticky Bomb rolls 2 Attack dice on enemies entering, *before* regular attack. Ranged units (Range from the number beside Attack) attack within range without moving; **no line of sight required**.

**Section C is done when:** GUT tests cover each special unit and Guardian in isolation, plus a simulated 10,000-combat run that never crashes and produces sane hit distributions.

### Section D — Rules engine: phases & actions

**Goal:** A full round playable in code, driven by a finite state machine.

**Steps:**

1. **Round FSM:** node-based or class-based state machine, states `Recruitment → Action → Guardian → (repeat)`. Each phase is its own script that decides when it's done and transitions. This beats one giant `match` statement.
2. **Recruitment phase:** draw an Action card each; optional Recruitment card; each player picks one of Deploy (draw 3, place Units, return Cowards to bag) / Recruit (3 Units or 2 Special into bag) / Punish Cowards (draw 5, remove Cowards, return Units). Apply Leader passives here where relevant (e.g. Lady Seraph alters Recruit counts).
3. **Action phase as a nested sub-loop:** one action per player in turn order until all Pass. Actions: Move-and-Attack, play a Movement card, Pass. Drive turn order through `GameState.turn_order`, never through UI button state — that's how hotseat (and later AI/online) desync.
4. **Move-and-Attack resolution:** Activate a space (place face-up Activation token; never two of same color in one space; face-down Control tokens don't count); move units in range from **multiple source spaces** into it (respecting can't-move-through-enemies, can't-leave-your-own-activated-space, Environment-on-the-way resolution); if entering enemies, call the Combat resolver.
5. **Guardian phase:** victory check (3 Old Tech in Rally Zone; tie-break fewest Cowards, then Facility wins) → spawn 1 Guardian if anyone reached Central Chamber + move each Guardian (roll per green Move, one die at a time, attack-and-stop on contact, automated targeting) → Cleanup (remove Activation tokens, **remove all Damage tokens / heal all**, place face-down Control tokens where your units are the only force, pass First Player token).
6. **Central Chamber spawn:** stopping there with no Guardians present spawns **2** Guardians. Guardian-bag rule: draw from 8 Guardians + 4 Scrap; Scrap returns to bag; **if no Guardians left, skip spawn draws until one is killed** (killed Guardian returns to bag, drops Old Tech where it died).
7. **Old Tech movement:** only with Control of the space; each unit carries one when leaving.

**Section D is done when:** a scripted test plays several full rounds headlessly, reaches a victory condition, and all win/tie-break/Cleanup edge cases pass GUT tests. **This is the milestone that means "the game works" — everything after is making it playable and pretty.**

### Section E — Greybox board & interaction

> ✅ **COMPLETE (2026-06-10).** `scenes/BoardView.tscn` + `ui/board_view.gd` (set as main scene). Board auto-generates and animates in ring-by-ring (skippable); full click-driven Move-and-Attack works end to end on real Godot — activate a space, legal-move highlighting, pull units in, combat resolves correctly (verified live: warrior-vs-warrior single round). Logic stays authoritative throughout (input→ActionResolver→EventBus→redraw). One real engine bug surfaced and fixed: `HexGraph.reachable` now allows an enemy cell as a valid move ENDPOINT (attack into it) while still blocking pass-through, per the locked rule "move into an enemy space only as your final destination." GUT green. Test scaffolding (combat seed, debug prints) stripped. **Deferred to Section F: sidebar unit-selection UI (list across multiple source spaces, hover-to-highlight, ×N stacking for dense cells); ranged-unit attacks; larger touch targets.**

**Goal:** See and click the board, with grey shapes, wired correctly to the proven logic.

**Steps:**

1. **Greybox the board** with a `TileMapLayer` set to hexagonal, or instanced `Polygon2D` hexes. Use `local_to_map()` / `map_to_local()` for pixel↔hex — never track positions in raw pixels.
2. **Map-generation reveal (not a placement UI):** since the board is now auto-generated (Section B), there's no player placement screen. Instead, call `generate_map(player_count, seed)` and **animate the finished board appearing** — either instant, or a quick ring-by-ring "tiles snap into place from the center outward" flourish that turns the old chore into a few seconds of spectacle. Keep it skippable. This still visually exercises the Section B generator and ring logic, just without player input.
3. **Wire input → intent → logic → signal → visual, one direction always.** A hex click asks logic "is this legal?"; logic mutates `GameState` and emits an EventBus signal; the visual layer hears it and updates. The visual layer never contains rules.
4. **Legal-move highlighting:** on Activate, run the movement/range query and tint reachable hexes; block illegal ones. This is your single biggest advantage over the tabletop — lean on it.
5. **Greybox tokens & Old Tech** as labeled rectangles so you can watch a real game unfold before any art.

**Section E is done when:** the board auto-generates and displays, and you can perform a Move-and-Attack entirely by clicking, with grey shapes, and the logic stays authoritative.

### Section F — Round flow & UI (mobile-first, landscape)

**Goal:** A complete game, plain but fully playable end to end, **designed for a phone held sideways** first and PC second.

**Mobile-first ground rules — set these before laying out a single screen:**

- **Design for landscape phone as the primary canvas.** Target a ~16:9 / 19.5:9 landscape viewport; treat PC as the same layout with more breathing room, not a different design. Set Godot's project to a landscape base resolution with the `canvas_items` stretch mode and `expand` aspect so one layout scales across phones and desktop.
- **Touch targets ≥ ~44–48px** (≈9mm) with generous spacing. Anything tappable must comfortably fit a thumb; this is the biggest practical constraint on density.
- **Input abstraction from day one:** route taps and clicks through the same input→intent path so touch and mouse are interchangeable. Add hover-only affordances (tooltips, zoom-on-hover) as *enhancements* for PC, never as the only way to reach information — on phone there is no hover.
- **Reachability:** put primary actions within thumb arcs (lower corners in landscape), keep the board centered, and avoid tiny top-edge controls.

**Steps:**

1. **Phase/turn UI:** clear "it's [color]'s turn," current phase banner, and a **hand-off screen for hotseat** so a passed phone doesn't reveal the next human's hidden info (bag odds, hand). With AI filling seats by default, this only appears between human seats.
2. **Recruitment UI:** present the three choices as large tap targets; show bag composition and draw results.
3. **Action UI:** Activate/Move/Attack/Pass as big buttons gated by *logic-reported* legality, not hardcoded enabling.
4. **Card hand UI:** a reusable `CardUI.tscn` that takes an `ActionCardData` and renders itself; unlimited hand size; unplayed cards persist between rounds. On a small screen, use a fanned/scrollable hand with **tap-to-zoom** (not hover) for card detail.
5. **Combat UI (plain):** show the resolver's event log as text/number readouts first — animation comes in G.
6. **Win screen + new game + setup screen** (seat count, per-seat human/AI toggle defaulting to AI).

**Section F is done when:** a full 3-player-rules game (you + AI seats by default, or a second human via the toggle) plays start to finish **on a phone in landscape** and on PC, with no rules gaps and no illegal moves possible.

### Section G — Art, animation & juice ✅ COMPLETE (2026-06-20)

> Built: 82 real-art PNGs imported + wired via the new **ArtRegistry** autoload (greybox
> fallback for the 4 missing assets — Razor, Lil' Minerva, ancient_artifact, falling_debris);
> tweens on moves/flips/control/card-deals; **combat playback queue** (one event at a time,
> crit/death pops, SPEED/SKIP/REPLAY) + **Guardian step-movement playback**; a project-wide
> **Theme** (ui/game_theme.tres); an **InfoPanel** surfacing bag odds / deck / Old Tech;
> an **AudioManager** autoload (audio-ready, no-op until files added) + handheld haptics; and
> the accessibility floor (owner initials, shape-coded tokens — color is never the only cue).
> Record: SECTION-G-graphics-record.md. UI test steps: Section H of UI-TEST-CHECKLIST.md.
> Tests added: test_art_registry.gd, test_combat_playback.gd. Awaiting Corin's local GUT run.

**Goal:** Make it feel like a game, not a spreadsheet — against a layout that already works.

**Steps:**

1. **Import the existing art.** You already have card fronts/backs, unit/guardian/special tokens, hex tiles (Room/Corridor drafts + backs), Center Hex, environment/function tokens, Leader cards (all 5). Wire each `.tres` to its texture. The numbered ROOM/CORRIDOR HEX DRAFT files are the distinct tile faces of the deck (numbering is non-contiguous but nothing is missing), not duplicates to cull — the tile art set is complete.
2. **Tweens early and everywhere:** token moves, card draws, dice. Even 0.2s tweens with `TRANS_CUBIC`/`EASE_OUT` are the difference between "spreadsheet" and "game."
3. **Combat playback queue:** push the resolver's event log into a queue and play one tween at a time so cascading-crit chains are legible (this is *why* C emits discrete events). Offer a speed/skip toggle.
   - **Guardian step-movement playback (DEFERRED from Section F UI pass, 2026-06-12):** animate Guardians moving **one space at a time, one Guardian at a time** during the Guardian phase, with a brief pause between steps, to build tension before they attack. The engine already moves Guardians a die's-worth of spaces per turn (RoundFSM); this is purely the *visual* reveal of that movement (tween each hop, sequence the Guardians) — not a rules change. Wire it off the existing movement events so it slots into the same playback queue as combat.
4. **Theme once, reuse everywhere:** a Godot `Theme` resource for fonts, colors, button styles; build with `Container` nodes (`PanelContainer`, `HBox/VBox`, `MarginContainer`), not manual positioning.
5. **Surface hidden info:** bag odds, remaining deck, Old Tech per player, hover tooltips explaining each Environment/Function token. A reusable `Tooltip.tscn`.
6. **Feedback within ~100ms** on every input; "every action gets a reaction" (visual + audio cue). Add a basic `AudioManager`. On phone, add subtle **haptic feedback** on key actions (Godot supports device vibration) — cheap and makes touch feel responsive. **Audio is optional in v1** — wire the `AudioManager` and event hooks so adding sounds later is drop-in, but the game must be fully enjoyable muted.
7. **Readability/accessibility floor:** WCAG 2.1 AA contrast; never rely on color alone for ownership/status — pair with shape/icon/text (also covers colorblind players, important since players are color-coded). **On a phone screen this is stricter** — assume small physical size and verify numbers/icons read at arm's length on an actual handset, not just in the editor.

**Section G is done when:** a stranger watching over your shoulder can follow what's happening in a combat without you narrating.

### Section H — AI opponent

**Goal:** A rules-based AI that plays a competent game through the same intent API humans use.

**Steps:**

1. **AI consumes the same intent API** as the UI — it proposes the same legal actions the logic layer validates. No special AI back door into `GameState`; this keeps it honest and prevents desync.
2. **Heuristic decision layers** (rules-based is enough and far cheaper than anything fancy): score candidate actions by simple weights — advance toward Old Tech, contest/defend Old Tech in Rally Zone, fight Guardians when favorable, avoid bad combats, thin Cowards when bag is clogged, recruit when thin.
3. **Per-phase policies:** a Recruitment policy (Deploy/Recruit/Punish based on bag state), an Action policy (pick best Move-and-Attack or Pass), a defender-hit-assignment policy (protect high-value/Old-Tech-carrying units).
4. **Single "medium" difficulty for v1.** Build one well-tuned weight set rather than easy/medium/hard tiers — but keep the weights in a Resource so adding tiers later is just new weight sets, no code change.
5. **AI fills empty seats by default.** Any seat not taken by a human is an AI player using these policies; the game always runs a full table (e.g. you + 2 AI in a 3-player game). A per-seat human/AI toggle on the setup screen lets a second human take a seat for hotseat.
6. **Leverage determinism:** because the engine is seeded and the AI uses the public API, you can simulate thousands of AI-vs-AI games for both balance (Section I) and AI tuning.

**Section H is done when:** the AI completes full games without illegal moves, beats a passive/random baseline reliably, fills empty seats automatically, and gives a casual human a real game at the medium setting.

### Section I — Balance, save/load & polish

**Goal:** A robust, reproducible, tunable game.

**Steps:**

1. **Seeded RNG end to end** (already designed in B/C) — expose it for reproducible bug reports and "same deal" rematches.
2. **Save/load:** board games have clean discrete state — serialize `GameState` to JSON. Decide save points (end of phase is safest).
3. **Balance via data:** run simulated combats and AI-vs-AI games; log who won, turn counts, action frequencies; hunt dominant strategies and dead Action cards. Rebalance by editing `.tres` numbers — no recompiles, which is the entire payoff of the data-driven design.
4. **Rule unit tests as the safety net:** keep GUT green while you rebalance; every win-condition and scoring edge case stays locked.
5. **Settings & accessibility:** animation speed/skip, scalable UI text, remappable controls, contrast — cheaper now than retrofitting.
6. **Real playtests:** watch silently; where a player hesitates is a UI/onboarding bug, not a player error.

**Section I is done when:** you can save/resume any game, reproduce any bug from a seed, and the balance logs show no single dominant strategy or dead card.

### Section J — Content completion & release prep

**Goal:** Fill the stubbed design content and ship a PC build.

**Steps:**

1. **Leaders — DONE.** All 5 Leaders are authored as `LeaderData` `.tres` (the game has 5 total, not 7). Section J just needs each `passive_effect_id` wired into the engine: stormfoot_move, ratseye_range, seraph_recruit, siyana_defense, minerva_card_advantage.
2. **Document & implement 2P and 4P** ring sizes and Rally Zone positions (you flagged these need layout screenshots). Until then, ship 3P and gate 2P/4P behind "coming soon."
3. **Write FAQ / in-game tutorial / onboarding** — the guide stresses a "foolproof guidance system." A short interactive tutorial doubles as onboarding.
4. **Confirm component counts** (e.g. Damage tokens) from playtest data — in digital they're unbounded, but the UI should still read clearly at high counts.
5. **Export mobile + PC builds.** Phone is the priority platform:
   - **Android:** Godot's Android export is straightforward — install the Android SDK/build template, set a keystore, export an APK/AAB. Test on a real device early and often (the editor lies about touch feel and text size). This is your fastest path to "a phone app held sideways."
   - **iOS:** requires a Mac with Xcode and an Apple Developer account to build/sign; plan for this only if you want App Store distribution. Android-first is the pragmatic order.
   - **PC:** Godot's desktop export is first-class and nearly free given the shared landscape layout — ship it alongside.
   - **Lock orientation to landscape** in export settings, and test on at least one short/wide phone and one tall phone for safe-area/notch handling.
   - Console export needs a third-party porting house later — out of v1 scope.

**Section J is done when:** an Android build (and a PC build) runs a complete 3-player game (with AI) **in landscape on a real phone**, includes a tutorial, and the content backlog is cleanly gated.

---

## Part 3 — Milestones

These are the "you can stop and feel good" checkpoints. Sized for solo part-time work, each is independently demonstrable.

1. **M1 — Data spine.** All units/guardians/cards/tokens/Leaders exist as `.tres`; project opens clean; GUT installed. *(End of A.)*
2. **M2 — Headless board.** A game can be set up, map built, bags drawn from a seed, legal moves computed — all in tests, no scenes. *(End of B.)*
3. **M3 — Combat is correct.** Every special unit and Guardian passes isolated tests; 10k-combat sim runs clean. *(End of C.)*
4. **M4 — The game works (headless).** Full rounds play to a win in code, all phases and Cleanup correct. **The pivotal milestone.** *(End of D.)*
5. **M5 — Clickable greybox.** Build a map and do a Move-and-Attack by clicking grey shapes. *(End of E.)*
6. **M6 — Playable hotseat.** A complete plain-UI game start to finish on one PC. *(End of F.)*
7. **M7 — It looks like a game.** Real art, tweens, legible combat playback, themed UI. *(End of G.)*
8. **M8 — You have an opponent.** AI plays full legal games and is fun on medium. *(End of H.)*
9. **M9 — Robust & balanced.** Save/load, seeded replays, balance logs clean, accessibility in. *(End of I.)*
10. **M10 — Shippable.** Packaged PC build with tutorial; stubbed content filled or gated. *(End of J.)*

**A note on pacing for part-time work:** M1–M4 (the engine) is where to spend your best, most-focused sessions — it's the part that's hard to fix later and easy to test in small bites between sessions. M5 onward is more forgiving of interruptions because you can *see* progress and the tests guard the rules behind you.

---

## Part 4 — Pitfalls to Watch For

Drawn from your guide's Wasteland-Warriors-specific warnings plus general adaptation traps:

**Architecture & process**

- **Building UI before the rules are proven.** The single most expensive mistake. Keep A–D scene-free and tested; resist the urge to "just see it on screen" early.
- **Autoload over-use / circular dependencies.** Keep to ~5–10 autoloads. If autoload A needs B and B needs A, Godot hangs on the splash screen. Don't stash transient match/UI state in autoloads — it leaks across scene changes.
- **Hardcoding rules into buttons.** Turn order, legality, and phase flow must live in the logic layer + FSM, driven by `GameState.turn_order` — never in UI button enable/disable. That's how hotseat and later AI desync.

**Wasteland Warriors mechanics specifically**

- **Cascading crits in the UI.** The math is a trivial `while` loop; the trap is animating an unbounded chain so a player understands why someone took 11 damage. Build combat as a replayable event list from the start (Section C emits it, Section G plays it).
- **Simultaneous combat & damage-after-death.** Compute all hits, *then* apply. Removing units mid-calculation gives order-dependent bugs.
- **Special-unit / Guardian exceptions.** Infiltrator (move-through, hit-only-on-6), Berserker/Cutter (crit 5–6), Typhoon (hit-only-on-6), Razor (hits first), Arachnid (range 2, splits damage), Scrape (2 rounds), Blink (through walls), The Ox (attack-on-move). Hardcode these and combat becomes an `if`-tangle. Use ability flags on Resources that the systems query.
- **Map generator dead-ends.** Random tile draws can paint a ring slot into a corner where no legal placement exists for the drawn tile. Without backtracking/re-draw and an attempt cap, generation can loop forever or emit an illegal/disconnected board. Test with thousands of seeds and assert every board is legal, ring-complete, and fully connected. (This replaced the manual placement mini-game; the *rules* are unchanged, only who applies them.)
- **Movement is a graph problem, not distance.** Can't-move-through-enemies, can't-leave-your-activated-space, Tough Terrain, Teleporter adjacency, Blink-through-walls all break simple range math. Use dynamic-edge hex A* and recompute legal moves each activation.
- **Activation vs Control token state.** Face-up (Activation) and face-down (Control) tokens behave differently; face-down ones don't block movement or count for the two-token rule. Encode an explicit enum per player per hex — the "(face-down don't count)" caveats are bug nests.
- **Bag-building randomness.** Sampling without replacement, seeded — not reshuffle-per-draw. Get this wrong and your odds (and reproducibility) are off.
- **Old Tech coupling to Control.** Tokens move only with Control, one per unit. Handle in move resolution, not as a UI afterthought.
- **First-player rotation & "until all pass."** Drive through the FSM and turn order; a subtle place for off-by-one and stuck-phase bugs.

**Mobile-first**

- **Hover-dependent UI.** Phones have no hover. Any info reachable only by hovering (tooltips, card zoom) is invisible on the primary platform. Make tap the first-class path; hover is a PC bonus.
- **Tiny touch targets / dense layouts.** A layout that's fine with a mouse is unusable with a thumb. Hold the ≥44–48px target floor and test on a real handset, not the editor viewport.
- **Designing PC-first then "porting" to phone.** That's a known trap your guide flags ("decide this up front, not as a port later"). Build landscape-phone-first; PC inherits it.
- **Text legibility at physical phone size.** Numbers that read fine on a 27" monitor can be illegible at arm's length on a 6" screen. Verify on hardware.

**Scope**

- **Online multiplayer creep.** Explicitly out of v1. Your deterministic, command-based engine makes it *addable later* (sync inputs, not state) — but only once the engine is rock-solid. Don't start it now.
- **Chasing missing content before the engine exists.** 2P/4P layouts are data slots. Don't let "finish the design" block "build the engine." (Leaders are all 5 done.)
- **Polishing un-fun loops.** If the greybox turn isn't satisfying, art won't save it. Prove fun at M5–M6 before the art pass.

---

## Rule Changes & Clarifications — Section F build

These are the gameplay-rule decisions, corrections, and clarifications that surfaced while building and playtesting Section F. They are the authoritative statement of each rule for the digital game; where the original rulebook differed or was ambiguous, the version below wins. (Pure UI/layout fixes are not listed here.)

1. **Central Chamber / Guardian spawning (clarified to three parts).** Every Guardian phase spawns **1** Guardian in the Central Chamber (bag draw, may fizzle to Scrap), starting from round 1. The moment a player moves a unit into the Central Chamber, spawn **1** Guardian there immediately and resolve combat. Once *any* player has ever reached the Central Chamber (the "breach"), from then on **2** Guardians spawn in the centre each Guardian phase. *(This replaced an older, contradictory "stopping in the centre with no Guardians present wakes 2" rule, which has been removed from the code.)*

2. **Controlled-ground and Shield Drone defense bonuses DO stack (+2).** Defending on a space your side controls grants +1 Defense, and a Shield Drone present grants +1 Defense — **these stack**, so a unit on its controlled space with a drone has +2 effective Defense. Multiple drones each add +1. Other stacking buffs (e.g. Siyana) add on top. This must be applied identically in combat and in end-of-round cleanup.

3. **Defender assigns hits.** When a side takes hits in combat, that side's controller chooses which of their own units absorbs each hit (excess hits on a unit that dies are lost). In the digital game a human defender is prompted to choose, but only when there is a genuine choice (two or more of their units could legally take the hit); otherwise it is assigned automatically.

4. **Guardians stay and fight.** A Guardian that moves into a space containing units attacks them and **stops** there for the rest of that movement, rather than continuing on.

5. **Card play is governed by card type, and on-board targets are chosen at play time.** Recruitment-type cards are playable in the Recruitment phase, Movement cards in the Action phase, and Attack cards only inside combat windows. When a card needs an on-board target (e.g. Deploy Unit, Sticky Bomb), the target space is chosen the moment the card is played, in the phase it is legally played in — not deferred to a later phase.

6. **One card per Recruitment turn.** A player may play at most **one** card during their Recruitment turn. (This is separate from the Extra Recruitment card/effect, which grants an additional recruitment *action*, not an additional card play.)

7. **Guardian bag handling.** The Guardian bag is 8 Guardians + 4 Scrap. A spawn draws one token: a Guardian is placed; Scrap returns to the bag (the spawn "fizzles"). A Guardian that dies returns to the bag and drops an Old Tech token where it died. If the bag has **no Guardians left to draw**, spawn draws are **skipped** until a Guardian is killed (which returns one to the bag).

8. **Move-into-enemy is destination-only.** A unit may move into an enemy-occupied space only as the **final destination** of its move (to attack it); it may not pass *through* an enemy-occupied space.

9. **Starting bag composition.** Each player begins with **6 Cowards + 6 Warriors** (the reviewed standard bag).

---

## Part 5 — Resolved Decisions

These were the open questions; all are now settled and folded into the plan above.

1. **Missing Action cards** — **Deferred.** Author only finalized cards; leave `effect_id` slots for the rest.
2. **Missing tiles** — **Deferred.** Build with the finalized tile set; the data-driven design absorbs additions later.
3. **Leaders** — **All 5 done** (the game has 5 total, not 7). No longer a gap.
4. **AI difficulty** — **One medium tier** for v1, weights in a Resource so more tiers are a future no-code addition.
5. **Empty seats** — **AI-filled by default**, with a per-seat human/AI toggle on the setup screen for hotseat.
6. **Artefacts vs Baubles** — **Same deck.** Modeled as one; the Ancient Artifact environment draws from it.
7. **Audio** — **Optional for v1.** Lightweight sourcing plan below (Appendix A); never blocks a milestone.
8. **Platform** — **Mobile-first, phone in landscape, ideal target**, with PC co-supported from the same Godot project. UI guidance throughout (Sections F/G) and export plan (Section J) reflect this.

---

## Appendix A — Optional Audio Sourcing Plan

Audio is optional for v1, but here's a low-cost, low-effort path so it's a drop-in later rather than a redesign. The architecture is already audio-ready: the EventBus emits domain signals (`combat_resolved`, `unit_moved`, `old_tech_captured`, etc.), so an `AudioManager` just subscribes and plays clips — no gameplay code changes needed when sound arrives.

**What the game actually needs (small list):**

- **UI SFX:** tap/confirm, invalid-action buzz, card draw, card play, phase-change sting, turn hand-off.
- **Gameplay SFX:** die roll, hit, critical hit (distinct from a normal hit so cascading crits *sound* like they're escalating), unit death, Guardian spawn/stomp, Old Tech pickup, victory fanfare.
- **Ambience/music (lowest priority):** one looping wasteland/facility ambient bed; optionally a menu track and a tension track for combat.

**Where to source it cheaply:**

- **Free, commercial-friendly libraries:** Kenney.nl (game SFX packs, CC0 — ideal starting point), Freesound.org (check each clip's license, mostly CC0/CC-BY), OpenGameArt, Sonniss GDC archives (huge free pro libraries released yearly).
- **Affordable music:** Incompetech (Kevin MacLeod, CC-BY with attribution), or a one-off royalty-free pack from itch.io / Humble.
- **AI-generated audio** (e.g. Suno/Udio for music, ElevenLabs SFX) for placeholder beds — **verify the tool's commercial-use terms before shipping.**
- **Custom later:** if the game gains traction, commission a small SFX/music pass on Fiverr or from an indie composer; the EventBus hooks mean swapping placeholders for finals is trivial.

**Process:** drop CC0 placeholders in during the Section G juice pass so you can feel the timing, keep a `CREDITS`/licenses file from day one (attribution is far easier to track as you go), and treat a polished final pass as a post-M7 nicety.

**Pitfall:** licensing. Every clip and track needs a license that permits commercial use and (for some) attribution. Track this per-asset from the first file you add, not at the end.

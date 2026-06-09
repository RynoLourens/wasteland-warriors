# Video Game Design Best Practices Guide
### For adapting a board game into a 2D digital game

This guide is tailored to your situation: a **2D adaptation of a board game**, built by someone **comfortable writing some code**. It covers engine choice, the design and testing process, and how to build a UI that feels cool and seamless.

---

## 1. Core Best Practices (the mindset)

A board-game-to-video-game adaptation succeeds or fails on a few principles. Keep these on the wall:

- **The board game is your design doc, not your constraint.** The rules already work — they've been tested across many plays. Your job is to translate them, then *remove friction* the physical version had (shuffling, counting, upkeep, rules lookups). Automate the boring parts; preserve the decisions.
- **Decisions over animations.** Players came for the strategy. Polish serves the decision-making; it never gets in its way.
- **Make the legal moves obvious, the illegal moves impossible.** A great digital adaptation never lets a player make an invalid move, and constantly shows what they *can* do. This is the single biggest advantage over the tabletop.
- **Build the smallest thing that proves the fun, then iterate.** Prototype → playtest → iterate is the loop that separates finished games from abandoned ones.
- **Scope ruthlessly.** Cut features, not quality. A small game that's complete and polished beats a big game that's 60% done.
- **Data-drive everything.** Cards, units, costs, and rules should live in data files (JSON/CSV/scriptable objects), not hardcoded. You'll re-balance constantly, and you want to do it without recompiling.

---

## 2. Choosing an Engine

For a 2D, turn-based / board-style game made by someone who'll write some code, three engines are worth considering. All three can ship a commercial 2D game.

### Godot — recommended starting point
- **Free forever**, open source, **no royalties or subscription**.
- **GDScript** is Python-like and very beginner-friendly; you can also use C#.
- Purpose-built 2D renderer (true 2D, not faked 3D), lightweight, fast iteration.
- Great fit for turn-based logic, tile/grid boards, and UI-heavy screens (its `Control` node system is excellent for menus and HUDs).
- **Trade-off:** weaker out-of-the-box console export (Switch/PlayStation/Xbox usually need a third-party porting house). Fine if you're targeting PC/web/mobile first.

### GameMaker — most accessible for 2D
- Built specifically for 2D; the room editor and sprite tools feel intuitive.
- **GML** is simple but capable — *Undertale, Hotline Miami, Katana Zero* shipped on it.
- **Legitimate console export support** (Switch, PlayStation, Xbox), unlike Godot.
- Indie tier is ~$10/month.
- **Trade-off:** less flexible than Godot for complex, deeply nested UI and data structures.

### Unity — most powerful, biggest ecosystem
- Huge asset store, tutorials, and hiring pool; strongest tooling overall.
- C# is a great, transferable language.
- **Trade-off:** 2D is secondary — it treats 2D as modified 3D, so there's more overhead. Heavier to learn, and licensing terms have shifted in recent years, so read the current pricing before committing.

### Quick recommendation for you
**Start with Godot.** It's free, the language is friendly, its 2D and UI systems are first-class, and turn-based board logic maps cleanly to it. If console release is a top priority from day one, lean **GameMaker** instead. Choose **Unity** only if you specifically want its ecosystem or already know C#.

> No-code note: if at any point you decide you don't want to write code at all, **GDevelop** and **Construct 3** are the leading visual/no-code 2D engines.

---

## 3. The Design Process & Key Decisions

Think of development in phases. At each phase you make specific decisions — here's what to decide and when.

### Phase 0 — Translation design (before you open the engine)
Decide on paper:
- **What stays, what's automated, what's cut.** List every physical action (deal, shuffle, count score, resolve combat). Mark each: keep as a decision, auto-resolve, or remove.
- **Scope of v1.** Single-player vs. multiplayer, AI opponent vs. hotseat vs. online. *Strong advice: ship single-player / hotseat first.* Online multiplayer multiplies complexity.
- **Platform priority.** PC first is almost always the right call for a board-game adaptation — it informs your input model and UI density.
- **Core loop.** Write the one-sentence loop: e.g. "Draw resources → plan your turn → take actions → resolve → opponent responds."

### Phase 1 — Prototype (prove the fun)
A prototype has **one specific question to answer** (e.g. "Is the core turn satisfying without animations?"). It's ugly on purpose. Use placeholder rectangles and text. Don't polish. If the core loop isn't fun with grey boxes, art won't save it.

### Phase 2 — First playable / MVP
The **MVP** is the simplest *complete* version: a full turn cycle, win/lose conditions, basic AI or hotseat, and a real (if plain) UI. Built to final-product quality but minimal in scope. This is what you put in front of testers.

### Phase 3 — Vertical slice
One slice of the game polished to *shipping* quality — final art, sound, UI, and feel — so you know what "done" looks like and can estimate the rest.

### Phase 4 — Production & content
Now build out the remaining content (cards, levels, factions, AI difficulty) against your data-driven systems. Re-balance continuously.

### Key recurring decisions
- **AI design:** rules-based heuristics are usually enough and far cheaper than anything fancy. Give the AI difficulty tiers.
- **Save/load & game state:** decide early how a full game state serializes. Board games have clean, discrete state — lean into that.
- **Randomness & seeds:** use a seeded RNG so you can reproduce bugs and offer "same deal" rematches.
- **Animation budget:** decide a per-action time budget so the game stays snappy (see UI section).

### Testing & playtesting
- **Loop: prototype → playtest → iterate.** Test small slices, watch real players, adjust *before* committing to full production.
- **Watch, don't explain.** Sit on your hands. Where players hesitate or do the wrong thing is a UI/onboarding bug, not a player error.
- **Test during live play, not just in review.** A screen can look perfect in a static mockup and fail under real pressure, movement, and interruptions.
- **Automated tests for rules.** Because board-game rules are deterministic, write unit tests for win conditions, scoring, and edge cases. This is your safety net while re-balancing.
- **Balance with data.** Log outcomes (who won, turn counts, action frequencies) and look for dominant strategies or dead cards.

---

## 4. Designing a Cool, Seamless UI

For a board-game adaptation, the UI *is* the game — there's no fast action to hide behind. These principles make it feel effortless.

### Readability first
- **High contrast and legible iconography.** Meet **WCAG 2.1 AA** contrast as a floor. Use clear icons with deliberate negative space so primary info reads instantly and secondary info stays out of the way.
- **Never rely on color alone** to signal status, urgency, or ownership — pair it with shape, icon, or text (also covers colorblind players).
- **Readable at small sizes.** Assume someone is watching at low resolution or on a laptop. If your numbers aren't legible there, they're too small.

### Feedback that feels instant
- **Respond within ~100ms** to any input. Even a tiny highlight, sound, or scale-bump on click makes the UI feel alive and responsive.
- **Let information linger appropriately.** Toasts, pickups, and notifications should stay on screen ~2–5 seconds depending on how much there is to read.
- **Every action gets a reaction.** Playing a card, gaining a resource, taking damage — each needs a clear visual + audio cue so players always know *what just happened and why*.

### Seamlessness for turn-based games
- **Guide the turn without removing control.** Highlight legal moves, gently indicate "it's your turn / their turn," and show the active phase. The best adaptations have a "foolproof guidance system" — the player always knows what they can do and what's expected next.
- **Show, don't make them remember.** Surface hidden info the tabletop forced players to track: remaining deck size, available actions, current score, what an icon means on hover.
- **Animate to inform, not to impress.** Keep a tight time budget per action so the game never feels slow. Offer a speed/skip setting for animations — power players will thank you.
- **Confirm only destructive or irreversible actions.** Everything else should be one click. Friction kills flow.

### Structure & consistency
- **One visual language.** Consistent button styles, spacing, type scale, and iconography across every screen. Inconsistency reads as "unfinished."
- **Layered information.** Show essentials always; reveal detail on hover/tap (tooltips, card zoom). Don't dump everything at once.
- **Design for your platform.** PC: denser layouts, hover states, keyboard shortcuts. Mobile: large touch targets and generous spacing. Decide this up front, not as a port later.
- **Accessibility is core, not a bolt-on.** Scalable UI text, remappable controls, and clear contrast from the start. It's far cheaper than retrofitting.

### A simple UI build order
1. Greybox every screen with placeholder boxes and real (if ugly) data.
2. Get the *flow* right — can a new player complete a full turn without help?
3. Add feedback (clicks, highlights, sounds).
4. Layer in final art and animation last, against a layout that already works.

---

## 5. Suggested Roadmap for Your Project

1. **Translation design on paper** — decide what to keep/automate/cut; write the core loop; scope v1 to single-player or hotseat, PC-first.
2. **Greybox prototype in Godot** — prove the turn is fun with rectangles and text.
3. **Data-drive your content** — move cards/units/costs into JSON or resource files.
4. **Build the MVP** — full turn cycle, win/lose, basic AI, plain but functional UI.
5. **Playtest with real people** — watch silently, log outcomes, fix the friction.
6. **Polish a vertical slice** — one screen/flow to shipping quality to define "done."
7. **Write rule unit tests** — lock down scoring and win conditions before heavy balancing.
8. **Produce remaining content and re-balance** using your logs.

---

## 6. Godot Deep Dive — Best Practices, Advanced Tips & Wasteland Warriors Pitfalls

This section is the practical playbook for building Wasteland Warriors in Godot 4. It assumes you'll write GDScript and goes from architecture down to the specific traps your game's mechanics will surface.

### 6.1 The single most important idea: separate *data*, *logic*, and *visuals*

Wasteland Warriors is a rules engine wearing a coat of art. Build it that way. Three layers, kept apart:

- **Data layer (Resources):** every Unit, Guardian, Action Card, Artefact, Environment/Function token is a `Resource` (`.tres` file) holding only numbers and text — Move, Attack, Defense, Range, special-ability flags. Resources are lightweight; you can define hundreds with zero performance worry.
- **Logic layer (plain GDScript, no nodes):** the game state and rules — whose turn it is, what's on each hex, combat resolution, win check. This layer should be runnable *with no scene loaded at all*, which is exactly what makes it unit-testable.
- **Visual layer (Scenes/nodes):** `UnitToken.tscn`, `HexTile.tscn`, `CardUI.tscn` — these *read* from data and *send player intent* to the logic layer. They never contain rules.

Why this matters for you specifically: you will re-balance dice, Defense values, and card effects constantly. If those live in `.tres` files and a rules script, you change a number and re-test — no hunting through UI code, no recompiling behavior into buttons.

### 6.2 Recommended project architecture

**Autoloads (singletons) — keep to a handful.** Use them only for things that are truly global and live the whole game:

- `GameState` — the authoritative board model (hex contents, each player's bag, Rally Zones, Old Tech locations, current phase, turn order).
- `EventBus` — a *stateless* signal hub. Define domain signals like `unit_moved`, `combat_resolved`, `phase_changed`, `guardian_spawned`, `old_tech_captured`. UI listens; logic emits. This decouples everything — new UI plugs in without touching rules.
- `AudioManager`, `SaveManager` — utility globals.

**Autoload anti-patterns to avoid (these will bite you):**

- Don't create circular dependencies between autoloads (A needs B, B needs A) — Godot hangs on the splash screen.
- Don't stuff scene-specific/temporary state into autoloads — it persists across scene changes and leaks. Keep "this match's transient UI state" in the scene.
- Don't turn everything into an autoload. Aim for ~5–10 max; over-use creates "God objects" and tight coupling.

**Use a finite state machine for the round structure.** Your game has a strict phase order: Recruitment → Action → Guardian → (repeat). Model it as a node-based state machine where each phase is its own node/script and each state decides when it's done and transitions to the next. This keeps the messy phase-specific rules isolated instead of one giant `match` statement. The Action phase itself is a sub-loop (player takes one action, pass to next, until all pass) — model that as a nested state or its own small machine.

**Folder layout that scales:**
```
/data        (.tres resources: units, guardians, cards, tokens)
/logic       (pure GDScript: GameState, CombatResolver, Rules, AI)
/scenes      (Board, HexTile, UnitToken, CardUI, HUD, menus)
/ui          (themes, fonts, reusable Control scenes)
/tests       (GUT unit tests for the logic layer)
/autoload    (GameState, EventBus, managers)
```

### 6.3 Step-by-step: building a *seamless* experience in Godot

1. **Greybox the board first.** Use a `TileMapLayer` set to hexagonal, or instance simple hex `Polygon2D` scenes. Get tiles placing and connecting with grey shapes before any art. Use `local_to_map()` / `map_to_local()` to convert between pixels and hex coordinates — never track positions in raw pixels.
2. **Model hex coordinates properly from day one.** Hex grids have 6 neighbors and the "every other row is offset" problem trips everyone up. Use cube/axial coordinates (per Red Blob Games' hex guide) for adjacency, range, and line-of-sight math; convert to screen position only for drawing. Retrofitting this later is painful.
3. **Wire input → intent → logic → signal → visual.** A click on a hex shouldn't move a unit directly. It should ask the logic layer "is this a legal Move?"; logic updates `GameState` and emits `unit_moved`; the visual layer hears the signal and animates. One direction of flow, always.
4. **Make legal moves visible.** When a player activates a space, immediately highlight reachable hexes (run your movement/range query and tint those tiles). Grey out or block illegal actions. This is your biggest advantage over the tabletop — lean on it.
5. **Add tweens early — they are the difference between "spreadsheet" and "game."** Even 0.2s tweens on token movement, card draws, and dice make it feel alive. Tween `position`, `rotation`, and `scale`. Use transition + ease types (e.g. `TRANS_CUBIC`, `EASE_OUT`) for natural motion. Cards and tokens without tweens feel terrible.
6. **Queue and sequence animations.** Combat with cascading 6s (see pitfalls) produces *chains* of events. Don't fire them all at once. Push gameplay events into a queue and play them one tween at a time so the player can follow what happened. Offer a speed/skip toggle for repeat players.
7. **Build UI with Control nodes + Containers, not manual positioning.** Use `PanelContainer`, `HBoxContainer`/`VBoxContainer`, `MarginContainer`, `Label`, `TextureRect`. They give you layout, theming, and input handling for free and adapt to window size. Only drop to custom `_draw()` if a Control truly can't achieve the look — you'd lose layout/input/accessibility otherwise.
8. **Theme once, reuse everywhere.** Create a Godot `Theme` resource for fonts, colors, button styles. Consistency across screens is what reads as "polished." Build a reusable `CardUI.tscn` that takes a card Resource and renders itself, and a `Tooltip` scene for hover details.
9. **Surface hidden tabletop info.** Show bag composition odds, remaining deck, what an Environment/Function token does on hover, current Old Tech count per player. The physical game forced players to remember these; the digital version shouldn't.
10. **Test the rules headless.** Use GUT (Godot Unit Test) to test `CombatResolver`, win conditions, and movement legality with no scene. Because your logic layer is pure, you can simulate thousands of combats to find balance problems.

### 6.4 Pitfalls Wasteland Warriors specifically will surface

Your rulebook has several mechanics that are deceptively hard to implement cleanly. Plan for these now:

- **Cascading critical hits (infinite-ish recursion).** Every 6 grants another die, which can roll another 6, and so on. In code this is a `while` loop, not a fixed roll — easy. The *real* trap is the **UI**: you must animate an unbounded chain of bonus dice. Build combat as a list of timed events you replay, not a single instant calculation, or players won't understand why someone took 11 damage.
- **Simultaneous combat & damage-after-death.** Your rules say hits still apply even if a unit is killed, and both sides deal damage in a round. Resolve combat by first *computing* all hits for all participants, then *applying* them — don't remove units mid-calculation or you'll get order-dependent bugs. Keep a clear "declare → roll → assign → apply → check deaths" pipeline.
- **Special-unit and Guardian exceptions break naive code.** Infiltrator moves through enemies and is only hit on a 6; Berserker crits on 5–6; Typhoon only hit on 6; Razor applies hits first; Arachnid shoots around corners and splits damage. If you hardcode combat, each of these becomes a tangle of `if`. Instead, give units/guardians **ability flags or small behavior Resources** that the combat and movement systems query (e.g. `crit_on: 5`, `hit_only_on: 6`, `moves_through_enemies: true`). This is the data-driven payoff.
- **Movement constraints are graph problems, not "distance."** "Can't move through enemy-occupied spaces," "can't leave a space you've activated," Tough Terrain stopping movement, Teleporter Nodes being adjacent to all other teleporters, Blink moving through walls — these break simple range math. Model the board as a graph and use `AStar2D`/`AStarGrid2D` (or a custom hex A*) where edges are dynamically enabled/disabled per unit's abilities and current board state. Recompute legal moves each activation.
- **Control & Activation token state is subtle.** Face-up vs face-down activation tokens behave differently (face-down "Control" tokens don't block movement or count for the two-token rule). Encode token state explicitly (`enum {NONE, ACTIVE, CONTROL}` per player per hex) rather than inferring it — the rulebook's "(face-down tokens don't count)" caveats are exactly where bugs hide.
- **Bag-building / randomness.** Drawing tokens from a bag is sampling-without-replacement; use a seeded RNG so bugs are reproducible and you can offer deterministic replays. Don't model the bag as reshuffling each draw.
- **Multiplayer turn order + first-player rotation.** The Action phase is "one action each, in order, until all pass," and the first-player token rotates each round. Drive this through your state machine and `GameState.turn_order`, never through UI button enabling/disabling alone, or hotseat and (later) online will desync.
- **Old Tech movement is conditional on Control.** Tokens only move with units when you Control the space, and each unit can carry one. This couples movement to control state — handle it in the logic layer's move resolution, not as a UI afterthought.
- **Online multiplayer is a different game.** Your rules are clean and deterministic, which is great, but networking still multiplies complexity (state sync, validation, disconnects). Ship **hotseat / single-player vs. AI first**; add online only once the rules engine is rock-solid. Because your logic layer is authoritative and deterministic, you can later sync *inputs/commands* rather than full state.

### 6.5 A pragmatic build order for Wasteland Warriors in Godot

1. Pure-logic `GameState` + `CombatResolver` with GUT tests — no visuals. Prove dice, deaths, and win check work.
2. Greybox hex board with placement rules and the connect/ring constraints.
3. Movement & activation on the board (graph + A*), with legal-move highlighting.
4. Full round state machine: Recruitment → Action → Guardian, hotseat.
5. Data-drive every unit/guardian/card/token as Resources with ability flags.
6. Animation pass: tweens, event queue, combat playback, juice.
7. UI/theme pass: HUD, card hands, tooltips, hidden-info surfacing.
8. AI opponent (rules-based heuristics, difficulty tiers).
9. Balance via simulated combats + real playtests.
10. Only then: consider online multiplayer.

---

## Sources

**Engines**
- [The Best Game Engine for Beginners in 2026 — Summer Engine](https://www.summerengine.com/blog/best-game-engine-for-beginners)
- [The Best Free 2D Game Engines in 2026 — Summer Engine](https://www.summerengine.com/blog/best-free-2d-game-engines)
- [6 Best 2D Game Engines To Use in 2026 — RocketBrush](https://rocketbrush.com/blog/best-2d-game-engines)
- [Unity vs Godot vs GameMaker 2026 — EarnifyHub](https://earnifyhub.com/gaming/unity-vs-godot-vs-gamemaker-indie-income-2026)
- [Best Game Engines for Beginner Game Developers in 2026 — GameDesignSkills](https://gamedesignskills.com/game-development/video-game-engines/)
- [7 Best Board Games On Steam In 2026 — TheGamer](https://www.thegamer.com/best-board-games-on-steam-2026-digital-editions/)

**Design & testing process**
- [Game Dev Glossary: Prototype, Vertical Slice, MVP — askagamedev](https://www.tumblr.com/askagamedev/746300998961741824/game-dev-glossary-prototype-vertical-slice)
- [Prototyping, Playtesting, Iteration & Fun — Medium](https://medium.com/understanding-games/prototyping-playtesting-iteration-fun-18d002c500b2)
- [The Ultimate Guide to Game Prototype Testing — Indie Dev Games](https://indiedevgames.com/the-ultimate-guide-to-game-prototype-testing-tools-software-and-best-practices/)

**UI / UX**
- [Game UI/UX Design Principles: HUD, Menus, and Feedback — StraySpark](https://www.strayspark.studio/blog/game-ui-ux-design-principles)
- [5 Best Practices for Game UI Design — Procreator](https://procreator.design/blog/best-practices-for-game-ui-design/)
- [Game UX Design: A Complete Guide (2026) — UXPin](https://www.uxpin.com/studio/blog/game-ux/)
- [Game UI and UX Guide: Menus, HUDs, and Feedback — Outlook Respawn](https://respawn.outlookindia.com/gaming/gaming-guides/ui-and-ux-in-games-building-menus-huds-and-feedback-systems)

**Godot 4**
- [Singletons (Autoload) — Godot Engine documentation](https://docs.godotengine.org/en/4.4/tutorials/scripting/singletons_autoload.html)
- [Autoload architecture & anti-patterns — gd-agentic-skills](https://github.com/thedivergentai/gd-agentic-skills/blob/main/skills/godot-master/references/autoload-architecture.md)
- [Make a Finite State Machine in Godot 4 — GDQuest](https://www.gdquest.com/tutorial/godot/design-patterns/finite-state-machine/)
- [Node-Based State Machine in Godot 4 — Godot Foundry](https://godotfoundry.com/blog/godot-4-state-machine-tutorial)
- [How to Build a Card Game in Godot 4: Deckbuilder Systems — SlashSkill](https://www.slashskill.com/how-to-build-a-card-game-in-godot-4-deckbuilder-systems-from-scratch/)
- [Tweens in Godot 4 — GoTut](https://www.gotut.net/tweens-in-godot-4/)
- [Overview of Godot UI containers — GDQuest](https://school.gdquest.com/courses/learn_2d_gamedev_godot_4/start_a_dialogue/all_the_containers)
- [Hex Strategy Map toolkit (cube coords, A*, fog) — Godot Asset Store](https://store.godotengine.org/asset/javier-islas/hex-strategy-map/)
- [godot-gdhexgrid (hex grid + A*) — GitHub](https://github.com/romlok/godot-gdhexgrid)
- [Hexagonal Grids — Red Blob Games (Amit Patel)](https://www.redblobgames.com/grids/hexagons/)
- [Programming a tactical strategy game in Godot 4 — The Shaggy Dev](https://shaggydev.com/2024/09/04/unto-deepest-depths-devlog/)

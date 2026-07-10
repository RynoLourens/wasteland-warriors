# Section G — Art, Animation & Juice — Completion Record

**This is the build plan's real Section G (graphics/feel).** Not to be confused with
`SECTION-G-rules-audit-plan.md`, which reused the "Section G" label for a rules pass.

Date: 2026-06-20. All `.gd` edits made via scripted `str.replace` (the Edit tool truncated
file tails twice this session — see note at the bottom). Every touched file verified:
NUL=0, EOF clean, brackets balanced, no mixed indentation. **Not yet GUT-run — the sandbox
has no Godot; run `test.bat` locally.**

## What shipped (maps to the build plan's 7 Section-G steps)

### Step 1 — Import the existing art ✅
- Source art lived in the **`Wasteland Warriors` folder** (not the repo). Copied **82 PNGs** into
  an organized `art/` tree: `cards/`, `tokens/{units,special,guardians,env,func,misc}/`, `tiles/`,
  `leaders/`, `artefacts/`. Generated 82 matching `.png.import` files (Godot regenerates the
  `.ctex` cache on open).
- New autoload **`autoload/art_registry.gd` (ArtRegistry)** — one id→`Texture2D` lookup, lazy
  `load()` + cache, **returns null on miss so the board falls back to greybox** (no crashes).
- Wired sprites into `ui/board_view.gd` (tiles, unit/guardian tokens, env/func tokens, Old Tech)
  and `ui/card_ui.gd` (full-bleed card fronts). Greybox kept as fallback everywhere.
- **Known missing art (intentional greybox):** Razor guardian, Lil' Minerva leader, env tokens
  `ancient_artifact` + `falling_debris`. (`SOLDIER` token art is wired to the `warrior` id.)

### Step 2 — Tweens early and everywhere ✅
- Token moves slide (`TRANS_CUBIC`/`EASE_OUT`, ~0.3s) via a movement queue.
- Token flips & control changes get a scale "pop".
- Cards deal in (rise + fade, staggered) in `hand_panel.gd`.

### Step 3 — Combat playback queue (the marquee item) ✅
- `ui/combat_readout.gd` rewritten from "dump all lines" to a **timed reveal queue**: one event
  at a time, per-event delays (crits/deaths linger, misses are quick), crit/death lines **pop**.
- **SPEED** (1x/2x/4x), **SKIP** (reveal all), **REPLAY** (when finished).
- **Guardian step-movement playback** (deferred from Section F): the move queue plays Guardian
  hops **one space / one Guardian at a time** with a pause between hops.

### Step 4 — Theme once, reuse everywhere ✅
- `ui/game_theme.tres` (button styles incl. hover/pressed, default font sizes, label colors),
  applied project-wide via `gui/theme/custom` in `project.godot`.

### Step 5 — Surface hidden info ✅
- New `ui/info_panel.gd` (**ℹ INFO** toggle, top-right): per-player Old Tech, hand size, bag size +
  Coward count, **next-draw Coward odds %**, artifacts, and bag unit composition.
- Per-unit and per-token hover tooltips already existed (Section F) and remain.

### Step 6 — Feedback within ~100ms / audio-ready / haptics ✅
- New autoload **`autoload/audio_manager.gd` (AudioManager)** — listens to every EventBus signal
  and fires a named cue; **audio is no-op until files are dropped into `CUES`** (game fully
  enjoyable muted). Each cue also fires a short **`Input.vibrate_handheld()`** on phones.

### Step 7 — Readability / accessibility floor ✅
- Owner **initial letter** (G/B/R) on each unit token; Activation = triangle, Control = diamond
  (shape, not just color); info panel uses a ◆ swatch + color name. **Color is never the only cue.**

## Files
- New: `autoload/art_registry.gd`, `autoload/audio_manager.gd`, `ui/info_panel.gd`,
  `ui/game_theme.tres`, `tests/test_art_registry.gd`, `tests/test_combat_playback.gd`, `art/**`.
- Edited: `ui/board_view.gd`, `ui/card_ui.gd`, `ui/combat_readout.gd`, `ui/hand_panel.gd`,
  `project.godot` (3 autoloads + theme).

## To verify locally
1. Open in Godot (it imports the 82 PNGs).
2. `test.bat` — expect prior suite + `test_art_registry.gd` + `test_combat_playback.gd` green.
3. Walk **Section H** of `UI-TEST-CHECKLIST.md` (H1–H10).

## ⚠️ Tooling note
The **Edit tool silently truncated file tails** twice (`card_ui.gd`, `board_view.gd`) and a
pre-existing truncation was found in `tests/test_guardian_abilities.gd` (restored from HEAD).
For `.gd` files use scripted edits + verify (line count vs HEAD, tail intact, bracket balance).

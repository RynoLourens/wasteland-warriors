# Wasteland Warriors

A digital adaptation of the **Wasteland Warriors** board game, built in **Godot 4** (GDScript).

## Scope (v1)

- **Opponents:** Hotseat + rules-based AI at a single MEDIUM difficulty. Empty seats are AI-filled by default, with a per-seat human/AI toggle. No online multiplayer in v1.
- **Platform:** Mobile-first — phone held sideways (landscape) is the ideal target; PC co-supported from the same project. Android-first for mobile export.
- **Content:** Full **3-player** game with the **4 designed Leaders**. Remaining content (3 more Leaders, 2P/4P layouts, unfinished Action cards, missing tiles, FAQ) is deferred and handled via data-driven slots.
- **Map building:** Automated and randomized each match — the game generates a legal, fully-connected board instantly from a seed.

## Architecture

Strict separation of **data / logic / visuals**:

- `data/` — `.tres` Resource schemas (units, guardians, cards, tokens, leaders). Special abilities are **flags on Resources**, not hardcoded `if`s.
- `logic/` — pure GDScript: `GameState`, `CombatResolver`, rules, AI. Runnable headless (no scene) so it's unit-testable.
- `scenes/` — Board, HexTile, UnitToken, CardUI, HUD, menus.
- `ui/` — themes, fonts, reusable Control scenes.
- `tests/` — GUT unit tests for the logic layer.
- `autoload/` — `GameState`, `EventBus`, managers.
- `art/` — imported PNGs.

Hex board uses cube/axial coordinates + dynamic-edge A*. Combat is a declare → roll → assign → apply → check-deaths pipeline emitting a replayable event log. Seeded RNG throughout for reproducibility and AI-vs-AI balance sims.

## Status

Section A — project skeleton & data layer (in progress).

## Build

Requires [Godot 4](https://godotengine.org/) (4.4+). Open the folder as a project in the Godot editor. Tests run via [GUT](https://github.com/bitwes/Gut).

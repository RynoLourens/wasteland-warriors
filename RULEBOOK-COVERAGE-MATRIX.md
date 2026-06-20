# Wasteland Warriors — Rulebook Coverage Matrix

A **rulebook-first** audit: every rule, action, ability, token, and card enumerated from the
rulebook, then checked for a real code path. This is the sweep that should have caught the
missing ranged-attack mechanic the first time. Each row is marked:

- ✅ **Implemented** — a real code path exists and is wired into the live + headless flow.
- 🟡 **Partial** — implemented but with a known gap, or only on one path (e.g. live but not headless).
- 🔴 **ABSENT** — the rule has no implementation at all (the ranged-attack failure mode).
- ⚪ **Deferred** — intentionally out of v1 scope (per build plan).

Method: each row lists the implementing symbol I grepped for. "ABSENT" means the grep found
the rule only in data/comments, never in a behavioral code path.

---

## Ch.4 Setup
| Rule | Status | Where |
|---|---|---|
| Choose Leader | ✅ | setup / leader_data |
| First Player by die roll | 🟡 | `first_player_index` exists, but the **initial** holder is just index 0 — no opening die-roll (cosmetic; rotation works) |
| Deal Action card each | ✅ | `_draw_action_card` |
| Deal Room/Corridor tiles | ✅ | map_generator |
| Load starting bag (6C+6W) | ✅ | `Player.load_starting_bag` |
| Build map (auto) | ✅ | map_generator |
| Place 1 Warrior + 1 Scout per Rally Zone | ✅ | `_place_starting_units` |

## Ch.7 Recruitment
| Rule | Status | Where |
|---|---|---|
| Draw an Action card | ✅ | `_draw_action_card` |
| Play a Recruitment card | 🟡 | card removed from hand; effect applied via CardEffects, but the **"is this card a Recruitment-type?" gate isn't enforced** — any card index is accepted |
| Deploy / Recruit / Punish | ✅ | `_apply_recruitment_choice` |
| Guardian Control Room / Teleporter Hub use | 🟡 | engine branches exist (`control_room_spawn`/`hub_deploy`); **no UI to offer them** |
| Artifact discard → place Special | 🟡 | engine branch exists; **no UI** |

## Ch.8 Action Phase
| Rule | Status | Where |
|---|---|---|
| Move and Attack | ✅ | `resolve_move_attack` |
| Multi-source pull into activated space | ✅ | plan loop |
| Can't move through enemy spaces | ✅ | hex_graph |
| Can't move out of your activated space | ✅ | `has_faceup_activation` guard |
| Play a Movement card | ✅ | `"card"` branch + CardEffects |
| Pass | ✅ | `"pass"` branch |
| **Ranged Units attack within Range (support fire)** | ✅ | NEW this session — support-fire flow |

## Ch.9 Combat
| Rule | Status | Where |
|---|---|---|
| Play Attack cards in combat | ✅ | round provider (reroll/cancel/extra) |
| Sum Attack = dice; 4/5/6 hit; 6 crit-chains | ✅ | combat_resolver |
| Simultaneous rolling | ✅ | `_simultaneous_round` |
| Defender assigns own hits | ✅ | `async_assign_policy` |
| Damage → death at Defense | ✅ | `_check_deaths` |
| Killed unit's hits still apply | ✅ | simultaneous model |
| Damage persists within round | ✅ | damage on cell dicts |
| Heal all at Cleanup | ✅ | round_fsm cleanup |
| Control +1 / Shield Drone +1 (stack) | ✅ | `_ground_defense_bonus` |
| Darkness −1 / Sunstone-on-6 | ✅ | this session |

## Ch.10 Guardian Phase
| Rule | Status | Where |
|---|---|---|
| Victory check | ✅ | round_fsm |
| Spawn 1 (2 after breach) | ✅ | `spawn_into_center` + `center_breached` |
| Roll per Move, random direction, attack-and-stop | ✅ | `_move_one_guardian` / `_step_random` |
| Cleanup (remove activations, heal, recompute Control, pass token) | ✅ | round_fsm cleanup |

## Ch.11 Other Rules
| Rule | Status | Where |
|---|---|---|
| Ranged Units (Range stat) | ✅ | data fixed + support fire |
| Spawn from Guardian bag (8G+4 Scrap, skip-if-empty) | ✅ | guardian_manager |
| Central Chamber spawn-2 on entry | ✅ | `_handle_center_entry` |
| Old Tech drops on death; carry needs Control | ✅ | `finish_combat` + carriers |
| Rally Zone behaves as a space | ✅ | normal cell |
| Sticky Bombs (placed + Sapperteur) | ✅ | this session |
| Environment tokens (all 14) | ✅ | token_effects |
| Function tokens (all 4) | ✅ | token_effects + recruitment |
| Teleporters (free move, node network) | ✅ | hex_graph teleporter adjacency |

## Ch.12 Guardians (per-ability)
| Guardian | Ability | Status | Where |
|---|---|---|---|
| Blackout | −1 Attack die to all in space | ✅ | `reduces_attack` read in `_global_attack_penalty` |
| **The Ox** | **Attack 2 dice on move-in WITHOUT stopping** | 🔴 **ABSENT** | `attacks_on_move=true` in data + schema, but **never read** — the Ox stops on contact like every other Guardian; it never attacks-through |
| Blink | Move through walls | ✅ | `moves_through_walls` → `can_blink` |
| Blink | Under control: move between controlled spaces | ⚪ | Guardians-under-player-control is unimplemented overall (no mechanic to control a Guardian) — flag as scope question |
| Cutter | Crit on 5–6 | ✅ | `crit_on=5` |
| Typhoon | Hit only on 6 | ✅ | `hit_only_on=6` |
| Razor | Applies hits before others | ✅ | `applies_hits_first` |
| **Arachnid** | **Range 2; after it moves, Attacks 1 space within Range; multi-space → roll; multi-player → divide damage rounded up** | 🔴 **ABSENT** | Arachnid moves + stops like any Guardian; the **after-move ranged attack, target-roll, and damage-division are entirely missing**. `range=2` is set but the Guardian-movement path never fires a ranged attack. |
| Scrape | 2 rounds of attack | ✅ | `extra_attack_rounds=1` |

## Ch.13 Tokens — covered above (all env + function implemented this session)

## Ch.14 Special Units
| Unit | Ability | Status | Where |
|---|---|---|---|
| Sapperteur | Drop Sticky Bomb on stop | ✅ | this session |
| Infiltrator | Move through enemies; hit only on 6 | ✅ | `moves_through_enemies` + `hit_only_on` |
| Berserker | Crit on 5–6 | ✅ | `crit_on=5` |
| Manstopper | Move 2, spend 1 to set up before attacking | ✅ | `extra_setup_move` |

## Ch.15 Victory
| Rule | Status | Where |
|---|---|---|
| 3 Old Tech in Rally Zone wins | ✅ | round_fsm victory check |
| Tie-break fewest Cowards → Facility wins | ✅ | round_fsm |

## Ch.16/17 Glossary / Open notes — N/A (docs)

---

# THE GAPS THAT MATTER

### 🔴 1. The Ox — "attacks on move-in without stopping" is ABSENT
`attacks_on_move = true` is set on the token and declared in the schema, but **no code reads
it**. The Ox currently behaves like every other Guardian: it stops the instant it enters a
space with Units and fights there. Per Ch.12 it should roll 2 Attack dice at Units it moves
*into* and **keep moving** (it can plough through several spaces in one Guardian phase). This
is the same failure fingerprint as ranged: a data flag with zero readers.

### 🔴 2. Arachnid — Range-2 after-move ranged attack is ABSENT
Arachnid's whole signature ability is missing. After moving it should attack one space within
Range 2 (choosing randomly if several have Units, dividing damage across players rounded up).
Currently it just moves and stops like a melee Guardian. `range = 2` exists but the
Guardian-movement code never performs a ranged attack at all.

### 🟡 3. Guardian combat (sync/headless path) ignores defender Control / Darkness / Sunstone
The **deferred** (live) Guardian combat goes through `build_combat_context`, so it's correct.
But the **sync** `_guardian_attack` (headless FSM / AI-only games) builds a bare context with
`controller: &""`, `extra_defense: {}`, no Darkness/Sunstone, and prunes vs **base** Defense.
So in a headless/AI game, a defender's controlled-ground +1 and Shield Drones don't protect
against Guardians, and Darkness/Sunstone are ignored in Guardian fights. (Players-vs-players
combat is correct on both paths; this is Guardian-vs-player on the non-interactive path only.)

### 🟡 4. Recruitment-card type gate not enforced
`run_recruitment_phase` removes whatever hand index the intent names and applies it, without
checking the card is actually a *Recruitment*-type card. Likewise Movement vs Attack typing
isn't enforced at the action/combat windows. Low stakes (the UI only offers legal cards), but
the engine doesn't enforce the rulebook's card-type restriction.

### 🟡 5. First-Player opening die roll
Setup says highest die roll takes the First Player token; the code just starts at turn-order
index 0. Rotation thereafter is correct. Cosmetic.

### ⚪ Deferred (known, intentional)
2-player & 4-player layouts; FAQ; controlling a Guardian (Blink-under-control, and the general
"Guardian under a player's control" concept) — no mechanism exists to take control of a
Guardian, so the sub-abilities that depend on it are moot until that's designed.

---

## Recommended priority
1. **Arachnid** (🔴) — a flagship Guardian doing nothing of its kit is the most visible gap.
2. **The Ox** (🔴) — attack-through movement; second-most-visible.
3. **Guardian sync-combat context** (🟡) — correctness on the headless/AI path.
4. Card-type gate + opening die roll (🟡) — polish.

---

# ✅ ALL FIVE GAPS CLOSED (2026-06-20)

- **Arachnid** — `GuardianManager._arachnid_ranged_attack`: after it moves, finds every space
  within hex-distance ≤ Range (2) holding player Units, picks one (seeded random if several),
  rolls its Attack dice, divides hits across co-located players rounded up. New EventBus signal
  `guardian_ranged_attack(coord, hits)` for the UI.
- **The Ox** — `_move_one_guardian` now reads `attacks_on_move`: the Ox attacks the space it
  enters and KEEPS stepping (doesn't break the move loop) until out of moves; all other
  Guardians still stop on contact.
- **Guardian sync-combat** — `_guardian_attack` now builds the FULL context via
  `ActionResolver.build_combat_context` (control +1, Shield Drones, Darkness, Sunstone), and
  `_prune_dead_and_handle_guardians` prunes players vs base+bonus. Live + headless paths now agree.
- **Card-type gate** — `RoundFSM._card_is_type` + checks in both the Recruitment window
  (RECRUITMENT only) and the Action "card" window (MOVEMENT only), in FSM *and* GameController.
- **Opening die roll** — `GameController._roll_first_player`: highest die (deck_rng) takes the
  First Player token at match start, re-rolling ties.

Tests: `tests/test_guardian_abilities.gd` (Ox through-move, Arachnid range-2 kill + damage
split, Guardian-vs-controlled-ground, card-type gate).

**Separate finding logged (NOT in the original matrix):** in the **headless** action/recruitment
windows, a played Movement/Recruitment card is removed from hand but its **effect is never
applied** (only in-combat Attack cards resolve, via the round provider). The type gate is now
enforced, but full Movement/Recruitment effect application in headless play is still open — the
interactive UI path may differ. Flagged for a follow-up pass.

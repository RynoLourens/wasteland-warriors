# Section A — Step 5: `.tres` Authoring Checklist

**STATUS: 56 `.tres` files written** (8 units, 8 guardians, 4 leaders, 5 artefacts,
18 env/function tokens, 13 action cards). All effect/passive text is transcribed from the
rulebook (Ch.13) and the card art. The boxes below are ticked accordingly.

**One gap remaining — confirm from the printed token art:**
- Guardians' base combat numbers (`move`/`attack`/`defense`/`attack_dice`) are placeholder
  `1`s (except The Ox attack_dice=2, Arachnid range=2, which come from the rules). Read the
  real values off `GUARDIAN TOKEN *.png` and update.
- Special units' `attack`/`defense` are placeholder `1`s — confirm vs `SPECIAL UNIT TOKEN *.png`.
- Action card `card_type` was inferred from the highlighted RECRUIT/MOVE/ATTACK tab; spot-check
  card 06 (Sabotage Bag) — its tab was ambiguous, currently set RECRUITMENT.

Cards **08** and **12** remain deferred (art missing from the set).

---

## Units → `UnitData` (`data/units/`)

Token stat layout: blue = Move (top-left), red = Attack (bottom-left), green = Defense (bottom-right).

### Regular units

- [ ] **Warrior** — move 1, attack 2, defense 1, range 1
- [ ] **Heavy** — move 1, attack 1, defense 2, range 1
- [ ] **Gunner** — move 1, attack 1, defense 1, range 1
- [ ] **Scout** — move 2, attack 1, defense 1, range 1

### Special units (set the ability flags)

- [ ] **Sapperteur** — move 1, attack 1, defense 1, range 1 · `places_sticky_bomb = true`
- [ ] **Infiltrator** — move 1, attack 1, defense 1, range 1 · `moves_through_enemies = true`, `hit_only_on = 6`
- [ ] **Berserker** — move 1, attack 1, defense 1, range 1 · `crit_on = 5` (crits on 5–6)
- [ ] **Manstopper** — move 2, attack 1, defense 1, range 1 · `extra_setup_move = true` (spends 1 Move to set up before attacking)

> Note: confirm Special-unit base attack/defense against the printed tokens
> (`SPECIAL UNIT TOKEN *.png`) — memory has their abilities but not all three numbers.

---

## Guardians → `GuardianData` (`data/guardians/`)

8 Guardians. Bag = 8 Guardians + 4 Scrap (Scrap is not a GuardianData — handle in logic).
Set base stats from the printed `GUARDIAN TOKEN *.png` tokens; flags below are from the rulebook.

- [ ] **Blackout** — `reduces_attack = true` (all units in its space roll 1 fewer Attack die)
- [ ] **The Ox** — `attacks_on_move = true`, `attack_dice = 2` (rolls 2 Attack dice when moving into occupied space; doesn't stop movement)
- [ ] **Blink** — `moves_through_walls = true` (and may move between any spaces its controller Controls)
- [ ] **Cutter** — `crit_on = 5` (Attack dice crit on 5–6)
- [ ] **Typhoon** — `hit_only_on = 6` (can only be hit by a 6)
- [ ] **Razor** — `applies_hits_first = true`
- [ ] **Arachnid** — `range = 2` (shoots around corners; splits damage across players, rounded up — handle split in logic)
- [ ] **Scrape** — `extra_attack_rounds = 1` (2 rounds of Attack total)

> Fill each Guardian's `move`, `attack`, `defense`, `attack_dice` from its token art.

---

## Leaders → `LeaderData` (`data/leaders/`)

Author the **4 designed** only. The other 3 (The Samadhi, Lil' Minerva, +1) are DEFERRED.

- [ ] **General Stormfoot** — passive: +1 Move to Warriors & Scouts
- [ ] **The Rat's Eye** — passive: +1 Range to Warriors & Gunners
- [ ] **Lady Seraph** — passive: Recruit 5 Units / 3 Special (instead of 3/2)
- [ ] **Siyana the Shield** — passive: +1 Defense to Warriors & Heavies

Give each a `passive_effect_id` (e.g. `stormfoot_move`, `ratseye_range`, `seraph_recruit`,
`siyana_defense`) for the rules engine to dispatch on.

---

## Artefacts / Baubles → `ArtefactData` (`data/artefacts/`)

ONE deck (Artefact = Bauble). The 5 designed (front art in the source folder):

- [ ] **Medical Machine**
- [ ] **Psychic Control Belt**
- [ ] **Snooperbot 6000**
- [ ] **Sunstone Fragments**
- [ ] **The Jam Gobbar**

Copy each card's effect text into `text`; give each an `effect_id`.

---

## Environment tokens → `EnvironmentTokenData` (`data/tokens/`)

### Room Environments (orange) — `category = "Room"`

- [ ] **Guardian** — spawn 1 Guardian here and fight it immediately
- [ ] **Turrets** — roll 3 Attack dice against your Units
- [ ] **Falling Debris** — roll 1 Attack die against each Unit
- [ ] **Gang Press Survivors** — place 2 Warriors from supply here under your control
- [ ] **Dehydration** — at end of round, don't flip the last Activation token you placed
- [ ] **(6th room environment)** — confirm from `BAD ROOM *.png` / rulebook Ch.13

### Corridor Environments — `category = "Corridor"`

8 corridor environments. Known from art: Darkness, Local Fauna, Tough Terrain, Troubling Tales.
Set `persists_in_room = true` for ones that stay (Teleporter Node, Darkness, Tough Terrain).

- [ ] Author all 8 from `BAD CORRIDOR *.png` + rulebook Ch.13.

---

## Function tokens → `FunctionTokenData` (`data/tokens/`)

4 Function tokens (yellow). Known: Guardian Control Room.

- [ ] Author all 4 from the `FUNCTION TOKEN *.png` art + rulebook Ch.13.

---

## Action cards → `ActionCardData` (`data/cards/`)

Author **only finalized** cards. Cards 08 and 12 are MISSING from the art set (deferred) —
leave their slots un-authored. Available card art: 01–07, 09–11, 13–15.

- [ ] Cards 01–07, 09–11, 13–15 — for each, set `card_name`, `text`, `card_type`
      (RECRUITMENT / MOVEMENT / ATTACK), and an `effect_id`.
- [ ] Leave **08** and **12** un-authored (deferred).

---

## Done when

Every game noun above exists as an inspectable `.tres`, and the project opens clean with
`EventBus` and `GameState` autoloads registered (Project → Project Settings → Autoload).

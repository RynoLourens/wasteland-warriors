# UI Test Checklist — Section G + Rulebook-Coverage fixes

Manual walkthroughs to verify the rules behave correctly **in the running game** (GUT covers
the logic; this covers the things only a human watching the screen can confirm — prompts,
glows, animations, and the full live combat flow). Run the game (`run.bat` or play the main
scene). Suggested setup unless noted: **3 players, 1 human (you) + 2 AI**, so you can drive
the human prompts.

Mark each: ☐ pass · ✗ fail (note what you saw).

---

## A. Ranged support fire (the redesigned core mechanic)

**A1 — The prompt appears.** ☐
Move a melee Unit into a space holding an enemy Unit, with a **Gunner** of yours standing 1
space away (not on an Activated space, no enemy in its space). When you commit the move, a
prompt should appear *before* combat: *"…fire with any Ranged Units? This Activates their
space."* — with **FIRE / NONE** buttons.

**A2 — Eligible shooters glow.** ☐
In that prompt, the Gunner's space (and any other eligible Ranged Unit's space) shows a **faint
orange glow**. A melee Unit 1 space away does **not** glow. A Gunner 2+ spaces away does **not**
glow (Range 1). A Gunner whose space you already Activated does **not** glow.

**A3 — Firing adds dice and activates the shooter.** ☐
Select the Gunner, press **FIRE**. The combat readout should show **extra attack dice on your
side**, and after combat the **Gunner's space is now Activated** (face-up token of your colour).

**A4 — Shooter takes no return fire.** ☐
After the fight, the Gunner that fired from afar has **no damage** on it, even if your melee
Unit in the combat space took hits.

**A5 — NONE skips cleanly.** ☐
Repeat A1 and press **NONE** — combat proceeds with no extra dice and the Gunner's space is
**not** Activated.

**A6 — Manstopper gate.** ☐ (optional, needs a Manstopper)
A Manstopper that moved 0–1 spaces this turn and is within Range can fire; verify it's offered.

---

## B. Arachnid (range-2 after-move ranged attack) 🔴 was absent

**B1 — Arachnid shoots after moving.** ☐
Get an **Arachnid** onto the board (clear the Central Chamber until one spawns). Position one
of your Units within **2 spaces** of where the Arachnid will end its move, but **not** adjacent
(so it's a ranged shot, not a melee bump). On the Guardian phase, the Arachnid moves, then
**fires at your Unit's space from 2 away** — you should see damage applied there without the
Arachnid entering that space.

**B2 — Random target choice.** ☐
Put two separate Units of yours within range 2 of the Arachnid (in different spaces). Over a
few Guardian phases, confirm it doesn't always pick the same one (it rolls to choose).

**B3 — Damage divides across players.** ☐ (needs 2 players' Units in ONE targeted space)
If the space the Arachnid shoots holds Units from **two players**, the hits are split between
them (each takes its share, rounded up) — not all dumped on one player.

---

## C. The Ox (attacks while moving, doesn't stop) 🔴 was absent

**C1 — Ox ploughs through.** ☐
Get **The Ox** onto the board (Move 3). Line up one of your Units in its likely path with empty
spaces beyond. When the Ox moves into your Unit's space, it should **deal damage AND keep
moving** past it (ending further along), rather than stopping on contact like other Guardians.
Watch the move animation: the Ox should not halt at the first Unit it hits.

**C2 — Other Guardians still stop.** ☐
Confirm a non-Ox Guardian (e.g. Cutter) that moves into your Unit **stops** there and fights.

---

## D. Guardian combat respects your footing 🟡 was partial

**D1 — Controlled ground protects vs Guardians.** ☐
Have a Unit **Control** a space (hold it alone through a Cleanup so it gets a face-down Control
token). When a Guardian attacks it, the Unit should be **harder to kill** (effective Defense +1)
than the same Unit on uncontrolled ground. *(Note: this was already correct in the live game;
the fix was for AI-only games — but verify nothing regressed.)*

**D2 — Darkness / Sunstone in a Guardian fight.** ☐ (optional)
If a Guardian fights your Units on a **Darkness** space, all attackers there roll 1 fewer die.

---

## E. Action-card type gate 🟡 was partial

**E1 — Recruitment window rejects non-Recruitment cards.** ☐
During Recruitment, try to play a **Movement** or **Attack** card (if the UI lets you select
one). It should be **rejected / not playable** — only Recruitment-type cards work there.

**E2 — Action window rejects non-Movement cards.** ☐
During the Action phase's "play a card" option, only **Movement**-type cards should be playable.

*(If the UI only ever offers the legal cards in each window, that's the gate working at the UI
level — note that. The engine now also enforces it.)*

---

## F. First-player die roll 🟡 was cosmetic

**F1 — Opening first player varies.** ☐
Start several fresh matches. The first player to act should **vary between seats** across
matches (highest die roll wins it), not always be the same seat.

---

## G. Regression sweep (earlier Section-G fixes still working)

- **G1 Darkness** ☐ — Units fighting on a Darkness space roll 1 fewer die.
- **G2 Sunstone** ☐ — play Sunstone Fragments on your space; enemy **ranged** attackers into it
  hit only on 6 that round (melee unaffected).
- **G3 Dehydration** ☐ — after a Dehydration token resolves, your **last Activation token stays
  face-up** into the next round instead of clearing at Cleanup.
- **G4 Sticky Bomb** ☐ — a Sapperteur that stops drops a bomb; an enemy entering that space
  later takes 2 dice **before** combat, even after the Sapperteur has left.
- **G5 Artifacts** ☐ — flip a Function token / Ancient Artifact → you draw an Artifact; later
  discard one (e.g. Jam Gobbar removes Cowards; Medical Machine redeploys a killed Unit).
- **G6 Env tokens** ☐ — moving onto room/corridor tokens resolves their effect (Guardian
  spawn, Turrets dice, Supplies draw, etc.), not just a flip.

---

## H. Section G — Art, animation & juice (the graphics pass)

This is the build plan's **Section G** (graphics/feel), distinct from the rules-audit items above.
Setup: any 3-player match. "Done when a stranger watching can follow a combat without narration."

**H1 — Real art on the board.** ☐
Tiles show the room/corridor/center artwork (not grey hexes). Unit and Guardian tokens show their
real token art; action cards in hand show their card fronts; env/function tokens show their art
face-up and a token back face-down; Old Tech shows its token icon with a ×N count.

**H2 — Known greybox fallbacks are intentional.** ☐
The **Razor** Guardian, **Lil' Minerva** Leader, and the **Ancient Artifact / Falling Debris** env
tokens have no art yet and fall back to grey shapes / text chips. Nothing crashes or shows a
"missing texture" error. (Add those files later and they'll wire automatically.)

**H3 — Tokens slide when they move.** ☐
Moving a Unit slides it from its old space to the new one (a short ~0.3s glide), rather than
snapping. Token flips and control changes give a small "pop".

**H4 — Guardians step one at a time.** ☐
During the Guardian phase, Guardians move **one space at a time, one Guardian at a time**, with a
brief pause between hops — building tension before they attack.

**H5 — Combat plays back legibly.** ☐
The combat readout reveals events **one at a time** (not all at once). Crits and deaths **pop**
and linger. **SPEED** cycles 1x/2x/4x; **SKIP** jumps to the end; when finished, SKIP becomes
**REPLAY**.

**H6 — Cards deal in.** ☐
When a hand is shown, cards **rise and fade in**, slightly staggered, rather than appearing
instantly.

**H7 — Info panel surfaces hidden info.** ☐
The top-right **ℹ INFO** toggle opens a panel showing, per player: Old Tech (★ N/3), hand size,
bag size + Coward count, **next-draw Coward odds %**, artifacts, and the units left in the bag.

**H8 — Theme is consistent.** ☐
Buttons share one style (rounded, hover highlight); fonts/colors look uniform across HUD, hand,
panels, and dialogs.

**H9 — Accessibility (color is never the only cue).** ☐
Each unit token shows a small high-contrast **owner initial** (G/B/R). Activation = triangle,
Control = diamond (shape, not just color). The info panel uses a ◆ swatch + the color's name.
Check token numbers/icons are readable at arm's length on a phone.

**H10 — Haptics & audio hooks (optional audio).** ☐
On a phone, key actions (move, flip, combat, card play) give a short **vibration**. The game is
fully playable **muted** (no audio files ship in v1; the AudioManager is wired for drop-in later).

---

## Section I — WP1 exit-true tiles + player-colour tokens (2026-07-10)

**I1 — Painted doorways tell the truth.** ☐
On a fresh match, walk the whole board: every painted doorway leads to an edge a Unit can
actually move through, and every walkable edge shows a doorway. (Patched edges should be
invisible at arm's length — look for obvious seams and report the worst one.)

**I2 — No greybox leftovers under art.** ☐
No yellow exit bars, no white hex outlines, no darkened-poly tint under tiles. Rally zones show
a soft **gold glow ring** instead of a green tint, and the ring doesn't hide the tile art.

**I3 — Central Chamber.** ☐
The centre tile renders unrotated; its six painted doorways match its real exits (closed edges
are patched with rock).

**I4 — Player colours (wasteland trio).** ☐
P1 tokens = rust **amber**, P2 = steel **cyan**, P3 = blood **crimson** — the green/red source
backgrounds never show for owned units. Basic units are lighter, Specials darker/richer of the
same hue. Owner initials still show. Markers/badges/info-panel swatches use the same trio.

**I5 — Moving ghosts keep their colour.** ☐
A sliding move-ghost token uses the mover's palette art, not neutral green.

**I6 — Greybox fallback still works.** ☐
(Spot check) Rename `art/tiles` away and boot: greybox polys + yellow exit bars return, no
crashes. Rename back.

---

## Section J — WP2 readable tokens + tap-to-inspect (2026-07-10)

- [ ] J1. A lone unit on a tile renders ~48 px (clearly readable); 2–3 units ~40 px; 4+ ~30 px in a 3-wide grid.
- [ ] J2. A cell with 7+ units shows 5 tokens + a grey "+N" badge with the correct count.
- [ ] J3. Every token has a thin owner-colour border (amber/cyan/crimson) AND the owner initial — check a mixed-owner cell.
- [ ] J4. Damage a unit in combat, survive: red pips appear along the token's bottom edge (guardians too).
- [ ] J5. Stage a unit to move: it pops ~12% larger with a pulsing gold halo (no more rectangle outline); the "N→" count badge still shows.
- [ ] J6. Long-press (~half a second) a unit: bottom sheet slides up with 200 px art, name, M/A/D (+Range if ranged), a Defense breakdown line, Damage/Health, owner.
- [ ] J7. Defense breakdown is TRUE: on controlled ground with a Shield Drone present it reads base +1 controlled ground +1 Shield Drone (they stack, +2 total).
- [ ] J8. Long-press an env/func token chip: face-down says "Unexplored…"; face-up shows name + full rules text.
- [ ] J9. Long-press empty tile: shows tile type (Room/Corridor/Center, Rally Zone), exit count, Old Tech, control markers.
- [ ] J10. Sheet closes on: tap outside, swipe-down on the sheet, ✕ button. Board doesn't ALSO take the tap as a click (no accidental activation under the sheet, and no click fires after releasing a long-press).
- [ ] J11. Desktop hover tooltips still work and hide while the sheet is open. Pan/zoom/drag still work; a drag never opens the sheet.
- [ ] J12. Old Tech icon now 30 px and clearly visible at default zoom.

## Section K — WP3 markers, chips, atmosphere, theme (2026-07-10)

- [ ] K1. Activation markers now use the real token art (front = face-up ACTIVE, back = CONTROL), tinted the owner's colour, ~26 px, with a white triangle (active) / diamond (control) outline as the colour-blind cue.
- [ ] K2. Control markers read slightly translucent vs activation markers; three players' markers on one tile don't overlap illegibly.
- [ ] K3. Env/func token chips are 30 px; face-up chips show the art PLUS an outlined 11 px name caption beneath; face-down still shows the back art.
- [ ] K4. The board sits on a dark brown-black radial wasteland backdrop (no flat grey void); same backdrop on the setup screen.
- [ ] K5. Every tile casts a soft drop shadow (down-right) — the board reads as physical tiles on a table. Shadows pop in WITH the tile during the spiral reveal (no orphan shadows before reveal).
- [ ] K6. Buttons everywhere are dark steel with a rust border (hover = brighter rust); panels pick up the dark rounded style. Nothing became unreadable.
- [ ] K7. Setup screen: seat swatches now match the on-board amber/cyan/crimson, and a leader-art banner strip sits under the title (4 leaders until Minerva's art lands in WP4).
- [ ] K8. Overall screenshot test: a stranger glancing at the screen says "that's a game", not "that's a debug tool".

## Section L — movement walks + token-reveal moments (2026-07-11)

- [ ] L1. Move a unit 2-3 spaces: the ghost token WALKS one space at a time along a legal route (through doors, never walls), with a small beat between hops.
- [ ] L2. The route respects blocking: path detours around enemy-occupied spaces (Infiltrator excepted); a teleporter move slides between the two teleporter tiles.
- [ ] L3. Move onto a face-down Environment token: AFTER the unit arrives, the token flips (back art squashes, face art springs open), holds ~0.75 s with its name caption, then settles into the normal chip.
- [ ] L4. Function tokens flip the same way (incl. on pass-through) and the Artefact draw still happens.
- [ ] L5. Multiple units moved in one action walk one after another, not all at once; multiple reveals play in order after the walks.
- [ ] L6. The next player's turn (or the hotseat hand-off cover / combat readout) does NOT appear until every walk + reveal has finished. AI moves are now watchable too.
- [ ] L7. Guardian phase: guardians still stalk one space at a time, and their combats only start after the walk finishes.
- [ ] L8. Ghost tokens are 40 px (readable at default zoom) and never leave duplicates behind (source empties when the walk starts, destination fills when it ends).
- [ ] L9. Full-game sanity: no hangs — pass-heavy rounds, cards, combat, and game over all still advance (the barrier can't wedge the round loop).

## How to report
For any ✗, note: what you did, what you expected, what happened, and (if visible) any error in
the Godot output console. Paste those back and I'll fix them.

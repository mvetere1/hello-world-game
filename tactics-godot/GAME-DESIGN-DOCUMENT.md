# All Time At Once — Tactics
## Developer GDD (Godot Prototype Reference)

This document is the authoritative reference for implementing the tactics prototype.
Sections marked **[NEED DIRECTION]** require clarification before implementation.

---

## Core Concept

A turn-based tactics game where **deployment is the entire game**. Players take turns placing units. Before committing to a placement, the player sees the full projected battle play out as a looping animation — every unit moving, fighting, reacting — showing exactly what will happen if they place here. Moving their cursor to a different hex instantly recalculates and replays a different future.

Once all units are placed, the player watches the final battle as a looping replay. The puzzle is in reading how your placement changes enemy behavior and your own units' reactions, then finding the deployment that produces the outcome you want.

**The looping battle animation is not decoration — it is the core feedback mechanism the player uses to make decisions.**

---

## Design Philosophy: RNG as Terrain, Not Chaos

**RNG chaos is the enemy of this game.** Randomness exists to create unique, interesting game states — not to make the player feel helpless. Every design decision must reinforce this principle:

1. **RNG creates the landscape, the player navigates it.** Dice rolls produce a specific future for a given board state. The player's job is to read that future and change it by placing units intelligently.

2. **Outcomes must be predictable and stable.** If a player hasn't changed anything near a fight, that fight's outcome must not change. The per-combat RNG seed ensures this — only local changes produce local effects. The player can trust what they see.

3. **The player changes outcomes through strategy, not luck.** Placing a unit near a fight changes its seed, producing a different result. The player previews this before committing. They are not gambling — they are solving a puzzle with known information.

4. **No hidden randomness.** The preview shows the exact future. What you see is what you get. The player never feels cheated because they chose this outcome with full knowledge.

5. **Variety without volatility.** Different deployment configurations produce meaningfully different battles, but small changes produce proportional effects. Moving a unit one hex over doesn't flip the entire board — it shifts the nearby fight, which may cascade naturally.

This philosophy applies to ALL future features: new unit types, abilities, terrain effects, etc. If a feature introduces randomness, it must be previewable, local, and player-controllable.

---

## The Deployment Loop (Core Interaction)

### Alternating placement
- A coin flip determines who goes first
- Players alternate placing **one unit at a time**: P1 places 1 → P2 places 1 → repeat
- **CONFIRMED: 8 units per player (16 total)**

### Preview before placement — CONFIRMED DESIGN
- When a player **hovers** their cursor over a valid hex in their deployment zone:
  - The **entire simulation reruns** from scratch with that unit hypothetically placed there
  - This includes ALL units already confirmed by both players reacting to the new placement
  - Local butterfly effect: combat outcomes only change when the new unit enters within 2 hexes of an existing fight; distant fights are unaffected
  - The cascade is the game: changed fight → unit survives/dies → objectives flip → score shifts
  - The result plays as a **looping animation** (see Battle Animation below)
  - The preview unit is visually distinct (ghost/dimmer) from confirmed units
- Moving the cursor to a different hex **immediately** recalculates and replays a different future
- When the player **clicks to confirm**, the unit locks in; its trail becomes full opacity
- The animation continues looping — the player now sees the updated board state

### After all units are placed
- The full battle animation loops continuously
- **CONFIRMED: Timeline scrubber** — a slider the player can drag to freely scrub through turns 0–10 for review
- **CONFIRMED: Replay mode** — a REPLAY button appears; clicking it enters a clean turn-by-turn view with no ghost trails. Left/Right arrows navigate turns, Escape exits back to the looping animation.

---

## Visual Philosophy: Units Are Spacetime Worms

> Inspired by **block universe theory** (eternalism): all of time exists simultaneously as a 4D object. We experience it one slice at a time, but the whole "loaf" is already there. A person isn't a 3D thing that moves through time — they ARE a 4D shape stretching from birth to death. See: [spacetime sausage](https://4dtime.space/spacetime-sausage.html), [eternalism](https://en.wikipedia.org/wiki/Eternalism_(philosophy_of_time)), [perdurantism](https://en.wikipedia.org/wiki/Perdurantism).

**In this game, a unit is not "a token that moves across the board." A unit IS its entire trajectory through time — a spacetime worm.** The ghost trail isn't decoration or history. It IS the unit. The "current position" is just one cross-section of the worm that the animation happens to be scanning through.

This is the core visual identity of the game:
- **The animation loop scans through slices** of the 4D battlefield, like cutting through a salami
- **Ghost trails are the actual unit** — the full worm visible all at once
- **The player reshapes spacetime worms** by placing units that alter the 4D landscape
- **FULL view mode** should make units look like continuous objects stretching through time (thick trails, high opacity, connected path lines) — not discrete dots at different positions
- **CLEAN/CHANGED modes** are analytical tools that show slices or diffs, but FULL mode shows the true nature of the game

The visual goal is closer to Marcel Duchamp's "Nude Descending a Staircase" than to a chess replay — overlapping forms that create a unified shape from many time-positions.

**Every visual decision should reinforce this metaphor.** Trail rendering, token shapes, opacity gradients, animation speed — all should make units feel like one continuous object, not a thing that "was here, then here, then here."

---

## Battle Animation (THE Core Visual — Non-Negotiable)

The battle animation runs **at all times** during and after deployment. It is not a cutscene — it is the board state the player is always looking at.

### What it shows
- All confirmed units (both players) animated moving turn by turn
- Preview unit (if hovering) shown simultaneously in ghost style
- Ghost **trails** left behind at every previous position — semi-transparent, fading with age
- Combat events marked where they occur each turn (crossed swords)
- Objective control updated each turn (banner color changes)

### Animation loop
```
Turn 0 (initial positions)
  → Turn 1 (all units move, combat resolves)
  → Turn 2
  → Turn 3
  → Turn 4
  → Turn 10
  → [loop back to Turn 0]
```
- **Normal modes (CLEAN/CHANGED):** ~0.8 seconds per turn — slow enough to read individual positions
- **FULL mode:** ~0.3 seconds per turn (2x faster) — the scanner sweeps quickly, emphasizing the spacetime worm shape over individual positions
- The loop is **continuous** — it does not stop between deployment clicks
- When a new unit is placed or the hover preview changes, the simulation recalculates and the animation **restarts from Turn 0** with the new data

### Why this is critical
The player's entire puzzle is: "If I place my unit here, how does that change where the enemy goes, and how does THAT affect where my other units go?" They can only answer this by watching the motion. A static snapshot is not enough — units need to be seen **moving** toward objectives, **pivoting** when they detect an enemy, **stopping** to fight. The animation is the game.

### Ghost trails — THE SPACETIME WORM
- Each unit leaves a semi-transparent echo at every turn position simultaneously
- **These echoes ARE the unit** — the full 4D shape rendered on a 2D board
- The goal is a continuous, worm-like form — not discrete dots
- Trail opacity gradient: faint at birth, solid at death (or current turn)
- **FULL mode enhanced trails:** thicker path lines (4px), higher ghost opacity (0.25–0.75), stronger hex highlights — making the worm shape more prominent
- Trail stops at elimination turn (the worm ends where the unit dies)

---

## Map

- **Grid:** Flat-top hex, isometric rendering (Final Fantasy Tactics style)
- **CONFIRMED target dimensions: 120 cols × 88 rows** (requires zoom/pan controls)
- Tileset: `assets/hex tactics assets/tileset hex tommy.png` — 384×384px, ~8 tiles per column, each tile ~48×48px
- Isometric tile rendering: painter's algorithm (back-to-front row/col sort for z-ordering)
- Hex math switches from pointy-top odd-r to flat-top offset coordinates

### Deployment Zones
- **Player 1 (bottom):** Bottom 18 rows, columns 18–101
- **Player 2 (top):** Top 18 rows, columns 18–101
- Zone highlighted during active player's deployment turn

### Objectives
- 3 objectives in the center band (rows ~38–43 in 88-row grid)
- Default positions: center (60,43), left flank (30,38), right flank (90,38)
- **CONFIRMED control:** Most models within radius 2 at end of each turn. Ties = contested (no one controls).
- **CONFIRMED pathfinding priority:** Units ignore friendly-held objectives. Target nearest unclaimed or enemy-held objective. If all objectives friendly-held, advance toward nearest enemy.
- **CONFIRMED visual:** Radius 2 hexes subtly tinted around each objective

---

## Unit Behavior (State Machine)

Units act deterministically each turn using this priority order:

```
1. If in combat range of an enemy → stay and fight (do not move)
2. If not in combat → path toward nearest unclaimed / enemy-held objective
3. If all objectives controlled by friendly → path toward nearest enemy
```

- Units path using A* on the hex grid
- Units stop moving the moment they enter combat range of an enemy (currently 2 hexes)
- Units do not path through other units (blocked hex)
- Goal hex is never added to the blocked set so units can stand on objectives

**CONFIRMED combat range: 2 hexes.**

**CONFIRMED pathfinding priority:** Nearest unclaimed or enemy-held objective. Ignore friendly-held. If none available, advance toward nearest enemy.

---

## Combat System

Combat resolves after movement in two phases: **Ranged** then **Melee**. Each model shoots OR melees per turn, not both.

### Ranged Phase (one-way)

Units with a `range` stat (Artillery, Archer) fire if no enemy is within COMBAT_RANGE (silenced in melee).

```
For each ranged unit not in melee:
  Find target (artillery: furthest in range 20; archer: nearest in range 8)
  For each model × ranged_attacks:
    1. HIT ROLL:   roll 1d6 >= ranged_hit
    2. WOUND ROLL: roll 1d6 >= ranged_wound
    3. ARMOR SAVE: defender rolls 1d6 >= (defender.armor + ranged_rend)
    4. DAMAGE:     wounds per failed save = ranged_damage
  Target does NOT return fire (one-way)
```

### Melee Phase (simultaneous)

All pairs of opposing units within COMBAT_RANGE (2 hex) fight simultaneously.

```
For each model × melee_attacks (or regular attacks for infantry/cavalry/DS):
  1. HIT ROLL:   roll 1d6 >= melee_hit  (or regular hit)
  2. WOUND ROLL: roll 1d6 >= melee_wound (or regular wound)
  3. ARMOR SAVE: defender rolls 1d6 >= (defender.armor + melee_rend)
  4. DAMAGE:     wounds per failed save = melee_damage
Both sides' model counts are snapshotted before damage is applied.
```

### Archer Retreat Phase

After melee, any archer that was in melee and survived moves 5 hex away, choosing the hex that maximizes minimum distance from all other units and objectives.

### Wound Tracking

Partial damage carries over between turns. Each unit tracks accumulated wounds. When wounds >= hp_per_model, a model is removed and the remainder rolls over.

**CONFIRMED:** A unit fights the **nearest single enemy** within combat range each turn.

---

## Unit Roster

### Infantry
| Stat     | Value | Notes                        |
|----------|-------|------------------------------|
| Models   | 10    | 10 figures per unit          |
| HP       | 2     | wounds per model             |
| Move     | 6     | hexes per turn               |
| Attacks  | 2     | per model                    |
| Accuracy | 3+    | hit on 3 or higher           |
| Wound    | 3+    | wound on 3 or higher         |
| Rend     | 1     | subtracts from armor save    |
| Armor    | 4+    | save on 4 or higher          |
| Damage   | 1     | wounds per failed save       |
| Obj Weight | 1.0 | full capture weight          |

**AI:** Move toward nearest unclaimed/enemy objective. If all friendly, advance toward nearest enemy.

### Cavalry
| Stat     | Value | Notes                        |
|----------|-------|------------------------------|
| Models   | 5     | 5 figures per unit           |
| HP       | 5     | wounds per model             |
| Move     | 10    | hexes per turn               |
| Attacks  | 2     | per model                    |
| Accuracy | 4+    | hit on 4 or higher           |
| Wound    | 3+    | wound on 3 or higher         |
| Rend     | 2     | subtracts from armor save    |
| Armor    | 3+    | save on 3 or higher          |
| Damage   | 2     | wounds per failed save       |
| Obj Weight | 1.0 | full capture weight          |

**AI:** Hunt nearest enemy unit. If no enemies in range, move toward objectives.

### Artillery
| Stat     | Value | Notes                        |
|----------|-------|------------------------------|
| Models   | 1     | single model                 |
| HP       | 12    | tough but slow               |
| Move     | 4     | hexes per turn               |
| Ranged Attacks | 4 | per model                  |
| Ranged Accuracy | 4+ | hit on 4 or higher        |
| Ranged Wound | 2+ | wound on 2 or higher        |
| Ranged Rend | 1   | subtracts from armor save    |
| Ranged Damage | 3 | wounds per failed save       |
| Range    | 20    | hex range for shooting       |
| Melee Attacks | 1 | weak in melee               |
| Melee Hit | 5+   | poor melee accuracy          |
| Melee Wound | 4+ | poor melee wounding          |
| Melee Rend | 0   | no armor penetration         |
| Melee Damage | 1 | minimal melee output         |
| Armor    | 5+    | light armor                  |
| Obj Weight | 0.0 | cannot capture objectives    |

**AI:** If ranged target exists within 20 hexes, stay and shoot (targets furthest enemy). If no ranged target, walks straight forward toward enemy deployment side (does NOT chase objectives). **Silenced in melee** — cannot shoot when enemy is within COMBAT_RANGE. **Cannot capture objectives** (obj_weight 0.0).

### Deep Strike
| Stat     | Value | Notes                        |
|----------|-------|------------------------------|
| Models   | 6     | 6 figures per unit           |
| HP       | 2     | wounds per model             |
| Move     | 8     | hexes per turn               |
| Attacks  | 2     | per model                    |
| Accuracy | 4+    | hit on 4 or higher           |
| Wound    | 4+    | wound on 4 or higher         |
| Rend     | 0     | no armor penetration         |
| Damage   | 1     | wounds per failed save       |
| Armor    | 4+    | save on 4 or higher          |
| Obj Weight | 0.5 | half capture weight          |

**Delayed entry:** Deployed anywhere on the map (must be 9+ hexes from all enemies at chosen arrival turn). Player selects arrival turn (T2–T8) during deployment. Unit materializes on that turn.

**AI:** Same as infantry (objective-focused) once arrived.

### Archer
| Stat     | Value | Notes                        |
|----------|-------|------------------------------|
| Models   | 5     | 5 figures per unit           |
| HP       | 2     | wounds per model             |
| Move     | 5     | hexes per turn               |
| Ranged Attacks | 2 | per model                  |
| Ranged Accuracy | 3+ | hit on 3 or higher        |
| Ranged Wound | 2+ | wound on 2 or higher        |
| Ranged Rend | 0   | no armor penetration         |
| Ranged Damage | 1 | wounds per failed save       |
| Range    | 8     | hex range for shooting       |
| Melee Attacks | 1 | weak in melee               |
| Melee Hit | 5+   | poor melee accuracy          |
| Melee Wound | 5+ | poor melee wounding          |
| Melee Rend | 0   | no armor penetration         |
| Melee Damage | 1 | minimal melee output         |
| Armor    | 5+    | light armor                  |
| Retreat  | 5     | hex retreat after melee      |
| Obj Weight | 0.5 | half capture weight          |

**AI:** Kites at range 8 — approaches nearest enemy within 8 hex but avoids entering COMBAT_RANGE (2 hex). After taking melee combat, retreats 5 hex away from all units/objectives. Targets nearest enemy in range. If no enemies in range, moves toward nearest unclaimed/enemy objective.

### Universal Rules
- Each model shoots OR melees per turn, not both
- Ranged attacks are one-way (target does not return fire)
- Melee is simultaneous (both sides attack)
- Units with both ranged and melee profiles use melee stats when in COMBAT_RANGE

**CONFIRMED:** All 5 unit types implemented. Free pick, 8 units per side, no point budget (tabled for later).

### Future Unit Concept: Interceptor / Slicer
> **Not yet implemented — design exploration only.**
>
> A unit type that interacts with other units' **spacetime worm shapes** rather than their current position. It blocks or redirects the 4D trajectory of enemy units, forcing them to reroute through spacetime. This is the mechanical payoff for the spacetime worm visual language — the player must already be thinking in terms of worm shapes for this unit to make sense. Implementation depends on the worm rendering being visually legible first.

---

## Visual Language

### Trails
- Every hex a unit occupies across all 10 turns is rendered simultaneously
- **Opacity gradient:** older positions are more transparent, newest position is most opaque
  - Formula: `opacity = 0.15 + (turn_index / max_turns) * 0.60`
- Trail token **shrinks** proportionally with model count (thinner = more casualties)
- Trail **stops** at the turn the unit was eliminated (no ghost trail past death)

### Unit Tokens
- **Infantry:** Shield shape with cross emblem
- **Cavalry:** Diamond/kite shape
- **Artillery:** Trapezoid shape
- **Deep Strike:** 6-pointed star burst
- **Archer:** Circle/orb shape
- Blue for P1, Red for P2
- Model count shown on active (current-turn) token
- Ghost tokens (trail history): same shape, no model count, lower opacity
- Deep strike units off-map before arrival turn (not drawn)

### Combat Markers
- Crossed swords drawn at the midpoint between two fighting units
- Gold glow circle underneath the swords
- Markers appear for every turn that combat occurred

### Objectives
- Flagpole with triangular banner on the objective hex
- Banner color changes to reflect controlling player (or stays neutral gold if uncontested)
- **CONFIRMED:** Radius 2 hexes around each objective are subtly tinted to show the control zone.

### Deployment Phase
- Active player's deployment zone highlighted brightly
- Preview trail shown as ghost (dimmer) while hovering
- Confirmed units shown at full opacity
- Opponent's confirmed units visible (so you can react to their placement)
- **Preview clutter reduction:** During hover preview, units whose simulation is unaffected by the previewed placement are "frozen" — drawn statically at their final position with no trails, paths, or animation. Only affected units (whose timelines changed) get the full animated treatment. This makes it immediately clear what the placement changes.
- **[NEED DIRECTION]:** During P2's deployment turn, are P1's confirmed trails visible on the board? Assume yes — the whole board is visible at all times.

### View Modes (Keys 1–4)
During deployment, the player can toggle between four view modes to control information density:

| Key | Mode | Description |
|-----|------|-------------|
| 1 | CLEAN | All units shown at final position only. The preview unit gets a full timeline (path highlights, trail, ghosts). Ideal for reading the board at a glance. |
| 2 | CHANGED | Full timelines for units whose fate changed due to the current preview placement, plus the preview unit. Unaffected units shown at final position. Default analytical view. |
| 3 | FULL | Full timelines for ALL units simultaneously at 2x speed. Enhanced "snail trail" visuals (thicker lines, higher opacity) make units look like spacetime worms — continuous objects stretching through time. This is the game's true visual identity. |
| 4 | FINAL | Static end-state snapshot. All units at turn 10 positions (or elimination positions), final objective control, final score. No animation. Quick reference for "who won where." |

Combat sparks (crossed swords) are filtered per view mode — they only appear for fights where at least one participant has a visible timeline. This prevents confusing spark markers in CLEAN mode.

### Narrative Preview Panel
When hovering a valid deploy hex, a narrative text panel appears below the unit fate chart on the right side. It summarizes the preview unit's projected fate in plain text:
- Which objectives it contests and during which turns
- Which enemy units it fights
- Whether it survives or is eliminated (and on which turn)
- The VP score delta from this placement

This gives the player a quick textual summary without needing to parse the visual timeline.

### Visual Concern: Battlefield Clutter — ADDRESSED
- With 16 units, simultaneous ghost trails, path lines, combat sparks, and objective highlights, the map can be visually overwhelming
- **View mode system** (keys 1–4) gives the player full control over information density
- **Combat spark filtering** prevents irrelevant fight markers from cluttering quieter view modes
- **Narrative preview panel** provides textual alternative to visual parsing
- **Font sizes increased ~30%** for readability on high-resolution monitors
- The freeze-unaffected-units system during preview remains active in CHANGED mode

---

## RNG & Determinism

> See **"Design Philosophy: RNG as Terrain, Not Chaos"** above. Every RNG decision must be previewable, local, and player-controllable.

- **Per-combat seeding**: Each fight between two units gets its own RNG seed derived from:
  - The pair identity (attacker + defender indices)
  - The current turn number
  - Positions of all non-eliminated units within 2 hexes of either combatant
- **Local butterfly effect**: Moving or adding a unit only changes combat outcomes for fights within 2 hexes. Distant fights are completely unaffected.
- **Preview diff indicators**: When hovering a deployment hex, the UI highlights what changed vs the confirmed state:
  - Unit fate chart: green (now survives), red (now dies), yellow (shifted death turn)
  - Scoreboard: +/- VP delta per player
  - Map: golden glow on objectives whose control flipped
- **CONFIRMED:** Preview shows exact dice results. Moving to a different hex recalculates with a different seed for nearby fights, showing a genuinely different future. This is the core tension of the game.

---

## Turn Structure

```
DEPLOYMENT PHASE
  1. Unit selection popup (5 types)
  2. [Deep Strike only] Turn selector (T2-T8) + legal hex highlighting
  3. Hover to preview, click to place
  4. Alternate players, repeat until 8 units each
  ↓
DONE — animation loops, result HUD, REPLAY button
```

Each simulated turn:
```
1. DEEP STRIKE ARRIVAL: units with start_turn == current turn materialize at deploy position
2. MOVEMENT: per-type AI determines goal and unit walks toward it via A*
   - Infantry: nearest unclaimed/enemy objective; if all friendly, nearest enemy
   - Cavalry: nearest enemy; if none, objectives
   - Artillery: stay if ranged target in range 20; else advance toward center
   - Archer: kite at range 8 (approach enemy but avoid COMBAT_RANGE); else objectives
   - Deep Strike: same as infantry (once arrived)
3. RANGED PHASE: artillery/archer shoot if not in melee (one-way, target doesn't return fire)
   - Artillery: targets furthest enemy within 20 hex
   - Archer: targets nearest enemy within 8 hex
4. MELEE PHASE: all pairs within COMBAT_RANGE resolve simultaneously (melee profiles for artillery/archer)
5. ARCHER RETREAT: archers that were in melee move 5 hex away from all units/objectives
6. OBJECTIVE CHECK: weighted control (obj_weight × models per player within radius 2)
```

---

## Scoring System — CONFIRMED

- **Victory Points (VP):** 5 VP per objective held per turn
- Persistent objective control: weighted model count (obj_weight × models) within radius 2
  - Infantry/Cavalry: weight 1.0 (full)
  - Deep Strike/Archer: weight 0.5 (half)
  - Artillery: weight 0.0 (cannot capture)
- Ties in weighted presence = contested (no change in control)
- **10 turns total** — final score determines winner
- Tie VP = draw

## UI Elements (Prototype)

### Scoreboard
- Right-side panel showing cumulative VP per turn for both players
- Header row: Turn | BLUE | RED
- One row per turn showing running totals

### Unit Fate Chart
- Below scoreboard, shows per-unit stats after simulation
- Columns: Unit (type prefix + random name), Died (turn #), O1/O2/O3 (objective contribution: won/yes/-), Kills, Dmg
- Team-colored rows with divider between P1 and P2

### Combat Log
- Left-side scrollable panel (340px wide)
- Play-by-play: deployment listing, per-turn movement, combat detail (wounds, models killed, eliminations), objective status, VP score
- Color-coded lines (yellow=headers, blue=turns, red=eliminations, green=scores)
- Scroll with mouse wheel over log area
- Also written to `user://combat_log.txt` on each simulation run

### Replay Mode
- REPLAY button appears in HUD when game is DONE
- Enters clean turn-by-turn view: no ghost trails, no path lines
- Shows only current-turn unit positions with correct model counts
- Combat events shown for the current turn
- Turn pips at bottom, progress bar at top
- Navigation: Left/Right arrows, Escape to exit

### Timeline Shifted Popup (Post-Placement Feedback)
- After each unit placement, a "TIMELINE SHIFTED" popup appears showing what changed
- **Always includes placed unit's performance:** damage dealt (with per-target breakdown, e.g., "Deals 18 damage to I Ben (12), I Dan (6)"), kills, objectives held, survival status
- Other units whose fates changed are listed with before/after narratives (prior timeline vs new timeline)
- Ensures the player always gets immediate feedback on their placement, even when no other unit's fate changed

### Battle Summary
- SUMMARY button appears next to REPLAY when game is DONE
- Scrollable overlay showing structured report of the full battle
- Close with X button in top-right corner

---

## Prototype Build Priority (Godot)

In order — do not skip ahead:

1. ✅ Hex grid rendering with deployment zones and objectives
2. ✅ P1 deployment: click to place, preview trail on hover
3. ✅ Alternating deployment: P2 places after each P1 placement
4. ✅ Full butterfly effect on hover preview (all trails update in real time)
5. ✅ Combat range 2 hexes
6. ✅ Objective control logic and visual feedback
7. ✅ Win condition evaluation (VP scoring, 10 turns)
8. ✅ Cavalry unit type
9. ✅ VP Scoreboard, Unit Fate Chart, Combat Log
10. ✅ Replay mode (turn-by-turn clean view)
11. ✅ Unit selection popup (non-reversible, 5 types)
12. ✅ Artillery, Deep Strike, Archer unit types
13. ✅ Combat restructure: Ranged → Melee → Retreat phases
14. ✅ Deep strike delayed entry (T2–T8, 9-hex exclusion)
15. ✅ Weighted objective control
16. ⬜ Point budget / army composition constraints

---

## All Design Decisions — CONFIRMED

| # | Question | Answer |
|---|----------|--------|
| 1 | Total units per player | **8 per player (16 total)** |
| 2 | Preview sim includes enemy reactions | **Yes — local butterfly effect (only nearby fights change)** |
| 3 | Battle display mode | **Looping animation ~0.6s/turn + side panel scrubber** |
| 4 | Grid size | **120 × 88, flat-top isometric (FFT style)** |
| 5 | Objective control | **Most models within radius 2 at end of turn; ties = contested** |
| 6 | Combat range | **2 hexes** |
| 7 | Objective pathfinding priority | **Nearest unclaimed or enemy-held; ignore friendly-held; else advance to nearest enemy** |
| 8 | Damage carry-over | **Yes — wound accumulation persists across turns** |
| 9 | Multi-enemy combat | **Fight nearest single enemy only** |
| 10 | Unit types in prototype | **5 types: Infantry, Cavalry, Artillery, Deep Strike, Archer** |
| 11 | Army composition | **8 units, free pick from 5 types. Point budget tabled for later.** |
| 12 | Objective radius visual | **Yes — subtle tint on radius 2 hexes** |
| 13 | RNG seed method | **Per-combat seed from pair + turn + nearby unit positions (local butterfly effect)** |
| 14 | Preview dice | **Exact — player sees the precise future for this seed** |
| 15 | P2 control (prototype) | **Pass-the-mouse local 2-player. Future: online ELO matchmaking + AI** |
| 16 | Victory tiebreaker | **Draw — no winner** |
| 17 | Friendly unit blocking | **Yes — friendly units block each other's paths** |
| 18 | Camera during animation | **Stays where player left it — no auto-pan during battle loop** |
| 19 | Camera on deploy turn start | **Yes — auto-pan to active player's deployment zone** |
| 20 | Timeline scrubber location | **Side panel with per-turn score and event log** |
| 21 | Online architecture | **Prototype-first. Simulation is deterministic/seeded — good foundation for later.** |

---

## Developer Tools

### Headless Simulation CLI
Run the full simulation without the GUI for automated testing, batch experiments, or CI:
```
godot --headless --path tactics-godot res://HeadlessSim.tscn
```
- **Input:** `deploy.json` — specify army compositions (unit type, hex position) for both sides, or use `"random"` for AI placement
- **Output:** `user://results.json` (structured: winner, scores, per-unit stats including damage targets), `user://combat_log.txt`, stdout summary
- **Validation:** enforces deploy zones, hex overlap, unit types, max 8 per side
- Files: `HeadlessSim.gd`, `HeadlessSim.tscn`, `deploy.json`

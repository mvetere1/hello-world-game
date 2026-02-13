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

## The Deployment Loop (Core Interaction)

### Alternating placement
- A coin flip determines who goes first
- Players alternate placing **one unit at a time**: P1 places 1 → P2 places 1 → repeat
- **CONFIRMED: 8 units per player (16 total)**

### Preview before placement — CONFIRMED DESIGN
- When a player **hovers** their cursor over a valid hex in their deployment zone:
  - The **entire simulation reruns** from scratch with that unit hypothetically placed there
  - This includes ALL units already confirmed by both players reacting to the new placement
  - Full butterfly effect: enemy units reroute, friendly units react, combat outcomes change
  - The result plays as a **looping animation** (see Battle Animation below)
  - The preview unit is visually distinct (ghost/dimmer) from confirmed units
- Moving the cursor to a different hex **immediately** recalculates and replays a different future
- When the player **clicks to confirm**, the unit locks in; its trail becomes full opacity
- The animation continues looping — the player now sees the updated board state

### After all units are placed
- The full battle animation loops continuously
- **CONFIRMED: Timeline scrubber** — a slider the player can drag to freely scrub through turns 0–5 for review

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
  → Turn 5
  → [loop back to Turn 0]
```
- Each turn frame should be visible for approximately **0.5–0.8 seconds** — fast enough to feel like a battle, slow enough to read unit positions
- The loop is **continuous** — it does not stop between deployment clicks
- When a new unit is placed or the hover preview changes, the simulation recalculates and the animation **restarts from Turn 0** with the new data

### Why this is critical
The player's entire puzzle is: "If I place my unit here, how does that change where the enemy goes, and how does THAT affect where my other units go?" They can only answer this by watching the motion. A static snapshot is not enough — units need to be seen **moving** toward objectives, **pivoting** when they detect an enemy, **stopping** to fight. The animation is the game.

### Ghost trails
- Each unit leaves a semi-transparent echo at every turn position simultaneously
- This gives the "all time at once" aesthetic even during animation
- Trail opacity: `0.10 + (turn_index / 5) * 0.50` (very faint for early turns, more visible for recent)
- Trail stops at elimination turn

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

Combat resolves at the end of each movement phase for all pairs of opposing units within combat range.

### Sequence (simultaneous — both sides attack at the same time)

```
For each model in the attacking unit, for each of its Attacks:
  1. HIT ROLL:   roll 1d6 >= unit.accuracy  → hit
  2. WOUND ROLL: roll 1d6 >= unit.wound     → wound
  3. ARMOR SAVE: defender rolls 1d6 >= (unit.armor - attacker.rend)
                 → on SUCCESS: wound blocked
                 → on FAIL: damage applied
  4. DAMAGE:     each failed save deals unit.damage wounds to the target unit
                 wounds carry over between models (2 wounds = 1 infantry model dead)
```

Combat is **simultaneous**: both units' model counts are snapshotted before damage is applied, so a wiped unit still deals its attacks.

**CONFIRMED:** Partial damage carries over between turns. Each unit tracks accumulated wounds. When wounds >= hp_per_model, a model is removed and the remainder rolls over.

**CONFIRMED:** A unit fights the **nearest single enemy** within combat range each turn. If multiple enemies are in range, only the closest is engaged.

---

## Unit Roster

### Infantry
| Stat     | Value | Notes                        |
|----------|-------|------------------------------|
| Models   | 10    | 10 figures per unit          |
| HP       | 2     | wounds per model             |
| Move     | 10    | hexes per turn               |
| Attacks  | 2     | per model                    |
| Accuracy | 3+    | hit on 3 or higher           |
| Wound    | 3+    | wound on 3 or higher         |
| Rend     | 1     | subtracts from armor save    |
| Armor    | 4+    | save on 4 or higher (modified by rend → 5+) |
| Damage   | 1     | wounds per failed save       |

### Cavalry
| Stat     | Value | Notes                        |
|----------|-------|------------------------------|
| Models   | 5     | 5 figures per unit           |
| HP       | 5     | wounds per model             |
| Move     | 18    | hexes per turn               |
| Attacks  | 2     | per model                    |
| Accuracy | 4+    | hit on 4 or higher           |
| Wound    | 3+    | wound on 3 or higher         |
| Rend     | 2     | subtracts from armor save    |
| Armor    | 3+    | save on 3 or higher (modified by rend → 5+) |
| Damage   | 2     | wounds per failed save       |

**CONFIRMED:** Both Infantry and Cavalry are included in the Godot prototype.

**CONFIRMED:** Free pick from roster. Players select 8 units from the available types before deployment. Army selection screen required.

---

## Visual Language

### Trails
- Every hex a unit occupies across all 5 turns is rendered simultaneously
- **Opacity gradient:** older positions are more transparent, newest position is most opaque
  - Formula: `opacity = 0.15 + (turn_index / max_turns) * 0.60`
- Trail token **shrinks** proportionally with model count (thinner = more casualties)
- Trail **stops** at the turn the unit was eliminated (no ghost trail past death)

### Unit Tokens
- Shield shape with cross emblem
- Blue for P1, Red for P2
- Model count shown on active (current-turn) token
- Ghost tokens (trail history): same shield, no model count, lower opacity

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
- **[NEED DIRECTION]:** During P2's deployment turn, are P1's confirmed trails visible on the board? Assume yes — the whole board is visible at all times.

---

## RNG & Determinism

- Simulation uses a **seeded RNG** (seed = 42 currently hardcoded)
- **[NEED DIRECTION]:** How should the seed be determined?
  - Option A: Fixed seed always (fully deterministic, same game every time — useful for testing)
  - Option B: New random seed each match start
  - Option C: Seed derived from placement order/positions (so hovering a different hex shows a genuinely different future)
  - Original GDD intended Option C: moving the unit to a different hex generates a new seed
- **CONFIRMED:** Preview shows exact dice results for the seed derived from the placement position. Moving to a different hex recalculates with a different seed, showing a genuinely different future. This is the core tension of the game.

---

## Turn Structure

```
DEPLOYMENT PHASE (alternating, all units)
  ↓
[Optional] PLAYBACK PHASE — animation of turns 1-5
  ↓
RESULT SCREEN — winner declared, option to restart
```

Each simulated turn:
```
1. MOVEMENT: all living units move (skipped if in combat)
2. COMBAT: all pairs within combat range resolve simultaneously
3. OBJECTIVE CHECK: evaluate control of each objective
```

**[NEED DIRECTION]:** Is there a Phase 3 playback animation (current Godot prototype has this), or is the game purely "all time at once" with no sequential playback?

---

## Prototype Build Priority (Godot)

In order — do not skip ahead:

1. ✅ Hex grid rendering with deployment zones and objectives
2. ✅ P1 deployment: click to place, preview trail on hover
3. ⬜ Alternating deployment: P2 places after each P1 placement (AI or second player)
4. ⬜ Full butterfly effect on hover preview (all trails update in real time)
5. ⬜ Combat range confirmation (range 1 vs range 2)
6. ⬜ Objective control logic and visual feedback
7. ⬜ Win condition evaluation
8. ⬜ Cavalry unit type
9. ⬜ Army selection / point costs

---

## All Design Decisions — CONFIRMED

| # | Question | Answer |
|---|----------|--------|
| 1 | Total units per player | **8 per player (16 total)** |
| 2 | Preview sim includes enemy reactions | **Yes — full butterfly effect** |
| 3 | Battle display mode | **Looping animation ~0.6s/turn + side panel scrubber** |
| 4 | Grid size | **120 × 88, flat-top isometric (FFT style)** |
| 5 | Objective control | **Most models within radius 2 at end of turn; ties = contested** |
| 6 | Combat range | **2 hexes** |
| 7 | Objective pathfinding priority | **Nearest unclaimed or enemy-held; ignore friendly-held; else advance to nearest enemy** |
| 8 | Damage carry-over | **Yes — wound accumulation persists across turns** |
| 9 | Multi-enemy combat | **Fight nearest single enemy only** |
| 10 | Unit types in prototype | **Infantry + Cavalry both included** |
| 11 | Army composition | **Point budget: 100pts. Infantry = 10pts, Cavalry = 20pts. Army selection screen required.** |
| 12 | Objective radius visual | **Yes — subtle tint on radius 2 hexes** |
| 13 | RNG seed method | **Derived from placement position (different hex = genuinely different outcome)** |
| 14 | Preview dice | **Exact — player sees the precise future for this seed** |
| 15 | P2 control (prototype) | **Pass-the-mouse local 2-player. Future: online ELO matchmaking + AI** |
| 16 | Victory tiebreaker | **Draw — no winner** |
| 17 | Friendly unit blocking | **Yes — friendly units block each other's paths** |
| 18 | Camera during animation | **Stays where player left it — no auto-pan during battle loop** |
| 19 | Camera on deploy turn start | **Yes — auto-pan to active player's deployment zone** |
| 20 | Timeline scrubber location | **Side panel with per-turn score and event log** |
| 21 | Online architecture | **Prototype-first. Simulation is deterministic/seeded — good foundation for later.** |

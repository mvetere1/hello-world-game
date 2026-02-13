# GAME DESIGN DOCUMENT
## All Time At Once — Tactics

---

## Concept

A turn-based tactics game where the entire battle is presented as a **single frozen moment in time**. Players do not watch units move step by step. Instead, when a unit is deployed, its entire future — every position it will occupy, every fight it will have, every casualty it will take — is rendered simultaneously as a ghostly trail on the battlefield, similar to the ball cannon prototype.

The player's agency is in **deployment order and placement**. Once deployed, units follow deterministic state-based behavior. The butterfly effect of each placement ripples across all previously placed units, rewriting timelines in real time.

---

## Map

- **Grid type:** Hexagonal
- **Dimensions:** 88 hexes wide × 120 hexes tall
- **Orientation:** Pointy-top
- **Rendering:** Canvas-based HTML/JS, same stack as the prototype

### Deployment Zones
- **Player 1 (bottom):** Rows 0–17 (bottom 18 rows), columns 18–69 (excluding 18 hexes from each side)
- **Player 2 (top):** Rows 102–119 (top 18 rows), columns 18–69 (excluding 18 hexes from each side)
- Deployment zones are highlighted during the deployment phase

### Objectives
- **3 objective markers** placed on the map at fixed or semi-random positions
- Objective positions should be spread across the center band of the map (roughly rows 45–75)
- Suggested default positions:
  - Center: (44, 60)
  - Left flank: (22, 55)
  - Right flank: (66, 55)

---

## Game Structure

### Phase 1 — Army Selection
- Each player selects **8 units** from the available roster
- Units have a point cost (future feature — skip for prototype)
- For prototype: each player picks from the same unit list, no restrictions

### Phase 2 — Deployment (Alternating)
- A coin flip determines who deploys first
- Players alternate placing one unit at a time (Player A places 1, Player B places 1, repeat)
- **Before confirming placement**, the player sees a full visual preview:
  - The unit's projected path across all 5 turns
  - Projected combats and their outcomes (including RNG results)
  - How this unit's presence changes the existing timelines of already-deployed units
- The player can drag the unit to different hex positions within their deployment zone to see alternate futures
- Once confirmed, the unit is locked in and its timeline becomes part of the "frozen moment"

### Phase 3 — Simulation Playback
- After all 16 units are deployed, the full battle plays out simultaneously as a visual
- All timelines are shown at once — a single frozen moment containing the entire war
- Optional: a scrubber to step through turns for review

---

## Turns & Time

- **5 turns** total per battle
- Each turn is subdivided into **movement ticks** for simulation purposes (not shown to player directly)
- At the **end of each turn**, objective control is evaluated:
  - Count models within the objective hex radius (suggest radius 2)
  - The player with more models in that zone controls it
  - If tied, the objective remains contested (no one controls it)
- **Victory:** Most objectives controlled at the end of Turn 5 wins. Tiebreaker: total models remaining.

---

## Unit Behavior (State Machine)

Each unit follows a priority-ordered state machine each tick:

```
1. CONTEST OBJECTIVE
   └─ If an uncontrolled or enemy-controlled objective is reachable, move toward it
   └─ If already on/near objective, hold position

2. ENGAGE ENEMY
   └─ If no reachable objective, move toward nearest visible enemy unit
   └─ If within attack range, enter combat

3. ADVANCE
   └─ Fallback: move forward (toward enemy deployment zone)
```

Units do not deviate from this logic. The player's skill is in deployment positioning, not unit micromanagement.

### Movement
- Movement is resolved in hex steps per turn
- Units cannot pass through other units (friendly or enemy)
- Units that are in melee combat do not move that turn

| Unit Type  | Move (hexes/turn) |
|------------|-------------------|
| Infantry   | 10                |
| Cavalry    | 18                |

---

## Combat System

Combat is resolved when two enemy units are in adjacent hexes. Combat math is inspired by Warhammer Age of Sigmar.

### Combat Sequence (per attacking model)

Each model in the attacking unit generates a number of attacks equal to its **Attacks** characteristic.

#### Step 1 — Hit Roll
- Roll 1d6 per attack
- Result must equal or exceed the unit's **Accuracy** rating to score a hit
- Failed hits are discarded

#### Step 2 — Wound Roll
- Roll 1d6 per hit
- Result must equal or exceed the unit's **Wound** rating to score a wound
- Failed wounds are discarded

#### Step 3 — Armor Save
- Defender rolls 1d6 per wound
- Subtract attacker's **Rend** rating from defender's **Armor** rating to get the modified save
- If the roll equals or exceeds the modified save, the wound is blocked
- Failed saves proceed to damage

#### Step 4 — Damage
- Each failed save deals damage equal to attacker's **Damage** rating
- Damage is applied to individual models; excess carries over to the next model
- When a model's health reaches 0, it is removed; carry over remainder to next model

### Combat Formula Summary
```
attacks → [hit roll >= Accuracy] → hits
hits    → [wound roll >= Wound]   → wounds
wounds  → [armor roll >= (Armor - Rend)] → failed saves → damage
```

---

## Unit Roster (Prototype)

### Infantry Unit
| Stat       | Value |
|------------|-------|
| Models     | 10    |
| Move       | 10    |
| Attacks    | 2     |
| Accuracy   | 3+    |
| Wound      | 3+    |
| Rend       | 1     |
| Armor      | 4+    |
| Health     | 2     |
| Damage     | 1     |

### Cavalry Unit
| Stat       | Value |
|------------|-------|
| Models     | 5     |
| Move       | 18    |
| Attacks    | 2     |
| Accuracy   | 4+    |
| Wound      | 3+    |
| Rend       | 2     |
| Armor      | 3+    |
| Health     | 5     |
| Damage     | 2     |

---

## Visual Language

Borrowing directly from the cannon prototype:

- **Projected trail:** Semi-transparent colored path showing every hex the unit will occupy across all 5 turns
- **Opacity:** Fades from bright (present/near future) toward transparent (distant future) — time-proportional
- **Combat events:** Marked on the trail where conflicts occur (similar to collision markers in the prototype)
- **Model casualties:** Trail becomes thinner/dimmer as models are lost — visually the unit "diminishes" over time
- **Objective control:** Objective hexes pulse with the controlling player's color
- **Rewriting timelines:** When a new unit is dropped, existing trails visibly shift and update in real time

### Color Coding
- Player 1: Cool tones (blue, cyan)
- Player 2: Warm tones (red, orange)
- Objectives: Gold/yellow pulse
- Contested objectives: White pulse

---

## RNG & Determinism

- All dice rolls for the full simulation are **pre-seeded** when a unit is placed in preview mode
- The player sees the exact outcome of that seed before confirming
- Moving the unit to a different hex generates a new seed, producing a different (but equally deterministic) outcome
- Once a unit is confirmed, its seed is locked
- This is the core tension: you can see the future, but only for the trajectory you're currently previewing

---

## Prototype Scope (v0.1)

Build in this order:

1. Hex grid rendering (88×120, with deployment zones highlighted)
2. Place a single unit on the grid
3. Unit pathfinding toward an objective (A* or simple hex distance)
4. Movement simulation across 5 turns
5. Trail rendering (all positions simultaneously, opacity gradient)
6. Second unit — collision/melee detection
7. Combat math resolution
8. Full deployment loop (alternating, 8 units each)
9. Army selection screen
10. Full visual playback

---

## Open Questions (resolve as we build)

- Hex orientation: pointy-top vs flat-top?
- Should objectives have a capture radius or be single-hex?
- Line of sight rules for ranged units (future feature)?
- ~~Should the deployment preview show enemy units' reactions?~~ **Resolved: full butterfly effect — every unit's timeline reruns on each new placement.**
- ~~What happens when a unit is wiped out mid-simulation?~~ **Resolved: trail ends at the hex where the last model dies.**

# HexMoveDemo.gd — Code Guide for New Godot Users

This is a single-file Godot 4.6 prototype. Everything lives in `HexMoveDemo.gd` (~2500 lines), attached to a Node2D in `HexMoveDemo.tscn`. No other scripts, no UI nodes, no tilemaps — just one script drawing everything manually.

---

## Core Design Principle: RNG as Terrain, Not Chaos

**Every team member must understand this.** Randomness in this game exists to create unique, interesting board states — NOT to make the player feel helpless. The player sees the exact future before committing. RNG effects are local (only nearby changes affect nearby fights). The player controls outcomes through strategy, not luck. If you're adding a feature that involves randomness, it must be previewable, local, and player-controllable.

---

## How Godot Runs This File

Godot has a **scene tree**. Our scene is just one node:

```
HexMoveDemo (Node2D)  ← has HexMoveDemo.gd attached
```

Godot calls these functions on our script automatically:

| Function | When it runs | Our use |
|----------|-------------|---------|
| `_ready()` | Once, when scene loads | Center camera, run initial sim |
| `_input(event)` | Every mouse/key event | Handle clicks, hover, camera pan/zoom |
| `_process(delta)` | Every frame (~60/sec) | Advance animation timer, request redraw |
| `_draw()` | When `queue_redraw()` is called | Paint EVERYTHING on screen |

**Key concept:** We never move Godot nodes around. Instead, every frame we call `queue_redraw()` which triggers `_draw()`, and we paint the entire screen from scratch — hex grid, units, paths, HUD, everything. This is called **immediate-mode drawing**.

---

## File Structure (top to bottom)

### Lines 1–62: Configuration Constants

```
COLS/ROWS          → grid dimensions (28×20)
HEX_SIZE           → radius of each hex in pixels (20)
UNITS_PER_SIDE     → how many units each player places (8)
TURNS              → simulation length (10)
COMBAT_RANGE       → hexes away to trigger combat (2)
P1/P2_DEPLOY_ROWS  → which rows each player can click to place units
OBJECTIVES         → 3 hex coordinates in the middle of the map
INFANTRY/CAVALRY/ARTILLERY/DEEP_STRIKE/WIZARD → stat blocks
UNIT_TYPES         → ["infantry", "cavalry", "artillery", "deep_strike", "wizard"]
C_BG, C_P1, etc.   → color constants
```

**To change game balance:** edit the unit stat dictionaries. Use `_get_stats(unit_type)` to look up stats by type string.
**To resize the map:** change COLS, ROWS, and adjust deploy rows/objectives.

---

### Lines 64–150: Hex Math

This is the math that converts between **grid coordinates** (col, row) and **screen pixels**.

We use **flat-top hexagons** with **odd-q offset** coordinates:
- Columns go left→right
- Rows go top→bottom
- Odd-numbered columns are staggered DOWN by half a hex

```
   col 0    col 1    col 2    col 3
  /    \          /    \
 | 0,0  |  1,0  | 2,0  |  3,0       ← row 0
  \    / \      / \    / \
   | 0,1  |  1,1  | 2,1  |  3,1     ← row 1 (odd cols shifted down)
  / \    / \      / \    /
```

**Key functions:**

| Function | What it does |
|----------|-------------|
| `hex_to_pixel(col, row)` | Grid coord → screen position (applies camera zoom/pan) |
| `pixel_to_hex(pos)` | Screen click → nearest grid coord (brute-force nearest match) |
| `hex_corners(center)` | Returns 6 corner points for drawing a hex polygon |
| `hex_neighbors(col, row)` | Returns up to 6 adjacent hex coordinates |
| `hex_dist(c1,r1, c2,r2)` | Manhattan distance between two hexes (converts to cube coords internally) |
| `hex_id(col, row)` / `id_to_hex(id)` | Converts col,row ↔ single integer (for A* pathfinding) |

**The camera system** is simple: `cam_offset` (pixel shift) and `cam_zoom` (scale factor) are applied inside `hex_to_pixel()`. Every draw call goes through this, so pan/zoom "just works."

---

### Lines 151–186: A* Pathfinding

Uses Godot's built-in `AStar2D` class.

```
build_astar(blocked)  → Rebuilds the full graph, skipping hexes in the "blocked" dict
find_path(...)        → Returns array of Vector2i waypoints from start to goal
```

**Known performance issue:** `build_astar()` is called inside `find_path()` every time, which rebuilds the entire 28×20 graph for every unit every turn. This is a clear optimization target — rebuild once per turn with the current blocked set instead.

---

### Lines 187–368: Simulation Engine

This is the **core game logic**. The `simulate()` function takes placed units and returns the entire battle.

#### How `simulate()` works:

```
1. Copy input units into working array with full stats
2. For each turn (10 turns):
   a. DEEP STRIKE ARRIVAL: units with start_turn == turn materialize
   b. MOVEMENT: per-type AI picks goal, unit walks via A*
   c. RANGED PHASE: artillery/wizard shoot (one-way) if not in melee
   d. MELEE PHASE: pairs within COMBAT_RANGE fight simultaneously
   e. WIZARD RETREAT: wizards in melee move 5 hex away
   f. OBJECTIVE CHECK: weighted control calculation
3. Return {timelines, units, combat, ...} — the full history
```

#### Movement AI (per unit type):
- **Infantry/Deep Strike:** nearest unclaimed/enemy objective; if all friendly, nearest enemy
- **Cavalry:** hunt nearest enemy; if none, objectives
- **Artillery:** stay if ranged target within 20; else walk straight forward toward enemy side (does NOT chase objectives)
- **Wizard:** kite at range 8 (approach enemy but avoid COMBAT_RANGE 2); else objectives

#### Combat:
**Ranged** (`_find_ranged_target`, `_roll_combat`): one-way attack, target doesn't return fire.
**Melee** (`_roll_melee`): Warhammer-style simultaneous combat. Artillery/Wizard use melee_* stats.
```
For each model × attacks:
  Roll d6 → hit?  (need >= hit stat)
  Roll d6 → wound? (need >= wound stat)
  Roll d6 → armor save? (need >= armor + rend, if fail → take damage)
```

#### Wound tracking (`_apply_wounds`):
Wounds accumulate. When wounds >= model's HP, one model dies and leftover wounds carry over. Unit is "eliminated" when models reach 0.

#### The "Local Butterfly Effect":
Each combat pair gets its own RNG seed derived from the pair identity, turn number, and positions of all units within 2 hexes. Placing a unit near a fight changes that fight's outcome, but distant fights are unaffected. The cascade is the game: a changed fight → a unit survives/dies → objectives flip → the score shifts.

---

### Lines 369–524: Game State & Input

#### Phase system:
```
Phase.DEPLOY → unit selection → placement → alternate players
Phase.DONE   → all units placed, animation loops, REPLAY button
```

#### Deployment flow:
1. Unit selection popup appears (5 types: Infantry, Cavalry, Artillery, Deep Strike, Wizard)
2. Player clicks type → `deploy_unit_type` set, popup closes
3. [Deep Strike only] Turn selector popup (T2–T8) → legal hexes highlighted (9+ from all enemies at arrival turn)
4. Hover in deploy zone → preview sim runs with ghost unit
5. Click to confirm → adds unit to `placed_p1` or `placed_p2`, recalc confirmed sim
6. `active_player` flips, `selecting_unit = true`, repeat
7. After `UNITS_PER_SIDE * 2` total placements → Phase.DONE

#### Key state vars:
- `selecting_unit` — true when unit selection popup is showing
- `ds_selecting_turn` — true when deep strike turn selector is showing
- `ds_arrival_turn` — chosen arrival turn for deep strike (-1 if not set)
- `ds_legal_hexes` — dictionary of valid hex_ids for deep strike placement
- `view_mode` — current view mode (CLEAN/CHANGED/FULL/FINAL enum)

#### View modes (keys 1–4):
Players switch view modes during deployment to control visual information density:
- **1 = CLEAN**: all units at final position, preview unit gets full timeline
- **2 = CHANGED**: full timelines for affected units + preview unit, rest at final position
- **3 = FULL**: full timelines for ALL units at 2x speed with enhanced "snail trail" — units rendered as spacetime worms (thicker lines, higher opacity, faster scan)
- **4 = FINAL**: static end-state snapshot — all units at final/death positions, final objectives, no animation

#### Two simulation states + diff:
- `confirmed_sim` — based on actually placed units (solid rendering)
- `preview_sim` — includes the ghost unit under your cursor (faded rendering)
- `preview_diff` — fate changes, score delta, objective flips between confirmed/preview

This is what creates the live preview — as you move your mouse, the preview sim recalculates and you see all paths shift.

#### Camera controls (in `_input`):
- **Scroll wheel** → zoom in/out (0.3x to 4.0x)
- **Right-click drag** → pan camera
- **Mouse move** → update hover hex, recalc preview
- **Left click** → place unit

---

### Lines 525–534: Process Loop

```gdscript
func _process(delta):
    anim_frac += delta / TURN_DURATION   # advance animation clock
    if anim_frac >= 1.0:                 # wrapped past one turn
        anim_turn = (anim_turn + 1) % (TURNS + 1)
    queue_redraw()                        # repaint every frame
```

`anim_turn` and `anim_frac` together track which turn the animation is showing and how far between this turn and the next (for smooth interpolation). The animation loops forever.

---

### Lines 536–698: Drawing

All rendering happens in `_draw()` and its helpers. **Nothing uses Godot's scene tree for visuals** — it's all manual `draw_*` calls.

#### Draw order (back to front):

```
_draw()
  ├── [if replay_mode] → _draw_replay()  ← clean turn-by-turn view (early return)
  ├── [if show_summary] → _draw_battle_summary() ← scrollable overlay (early return)
  ├── draw background rect
  ├── _draw_tile() for each hex          ← grid, zones, objectives, DS legal hex highlights
  ├── _draw_sim()                         ← paths, units, combat (view-mode aware)
  │     ├── [FINAL mode] → _draw_final_state() (static end-state)
  │     ├── show_timeline_for_uid lambda  ← per-unit visibility by view mode
  │     ├── _draw_unit_final()            ← draws unit at final position only (for frozen units)
  │     ├── _draw_single_timeline()       ← full 5-layer timeline for one unit
  │     └── combat sparks (filtered by view mode)
  ├── _draw_hud()                         ← top bar + REPLAY/SUMMARY buttons (when DONE)
  ├── _draw_scoreboard()                  ← VP per turn table
  ├── _draw_unit_fate()                   ← per-unit stats chart
  ├── _draw_preview_narrative()           ← text summary of preview unit's fate
  ├── _draw_combat_log()                  ← scrollable play-by-play log
  ├── [if selecting_unit] → _draw_unit_select()      ← 5-button popup
  └── [if ds_selecting_turn] → _draw_ds_turn_select() ← T2-T8 popup
```

#### `_draw_tile(col, row)` — line 558:
1. Fill hex polygon (dark blue)
2. Draw hex outline
3. Tint deploy zones (blue for P1, red for P2 — brighter when it's your turn)
4. Tint objective radius (gold)
5. Hover highlight (white overlay)
6. Draw objective banner (flag on a pole)

#### `_draw_sim()`:
The simulation result contains `timelines` — an array per unit, where each entry is the unit's position at that turn. This function uses the current `view_mode` to decide what to show:

- A `show_timeline_for_uid` lambda determines per-unit visibility based on view mode
- **CLEAN**: preview unit gets `_draw_single_timeline()`; all others get `_draw_unit_final()` (final position only)
- **CHANGED**: `changed_uids` + preview unit get full timelines; rest get final position
- **FULL**: all units get full timelines via `_draw_single_timeline()`
- **FINAL**: handled by `_draw_final_state()` — static snapshot, no animation

For each visible unit timeline, `_draw_single_timeline()` draws 5 layers:
1. **Path hex highlights** — every hex a unit visits gets a subtle player-colored tint
2. **Path lines** — colored lines connecting each consecutive position (skips if stationary)
3. **Ghost tokens** — faded type-specific shapes at each turn position (NOT the current animated turn)
4. **Combat sparks** — gold circle + crossed swords where fights happened (filtered by view mode — only shown when at least one participant has a visible timeline)
5. **Current tokens** — solid unit shapes at the animated position, smoothly interpolated between turns

#### `_draw_unit_token()`:
Draws a unit-type-specific shape (shield/diamond/trapezoid/star/circle) with model count. Takes `is_ghost` and `alpha` params to control opacity for trail vs current positions. Shape determined by `unit_type` parameter.

---

## Data Flow Diagram

```
Player clicks hex
       │
       ▼
_handle_deploy_click()
       │
       ├── adds unit to placed_p1 or placed_p2
       ├── calls _recalc_confirmed_sim()
       │         │
       │         └── simulate(all_placed_units)
       │                    │
       │                    └── returns {timelines, units, combat}
       │                                stored in confirmed_sim
       └── swaps active_player

Player hovers hex
       │
       ▼
_recalc_preview_sim()
       │
       ├── creates ghost unit at hover position
       ├── simulate(all_placed + ghost)
       │         │
       │         └── returns {timelines, units, combat}
       │                     stored in preview_sim

Every frame
       │
       ▼
_process() → advances anim_turn/anim_frac → queue_redraw()
       │
       ▼
_draw() → picks preview_sim or confirmed_sim → renders everything
```

---

## Where to Start Working

These are the most likely areas your team will want to modify:

### Easy wins:
- **Tuning constants** (lines 7–28): grid size, unit count, turn count, deploy zones, objective positions
- **Unit stats** (lines 30–52): change balance by editing INFANTRY/CAVALRY dicts
- **Colors** (lines 54–62): change the visual palette
- **Animation speed** (line 14): TURN_DURATION controls how fast turns play

### Medium complexity:
- **Add an undo button** (pop last entry from placed_p1/p2, recalc sim)
- **Improve the HUD** (lines 753–789): add more info, make it prettier
- **Add a timeline scrubber** so players can drag to see specific turns instead of watching the loop

### Bigger changes:
- **P2 AI** — right now P2 is a human clicking the top zone. Could auto-place randomly or with heuristics
- **Switch to TileMapLayer** — replace the manual hex drawing with Godot's built-in tilemap system for better performance and editor integration
- **Split into multiple files** — extract hex math, simulation, and rendering into separate scripts
- **Performance**: `build_astar()` inside `find_path()` (line 176) rebuilds the graph per call — should rebuild once per turn
- **Larger maps**: the current 28×20 is a prototype; the design doc targets 120×88

---

## GDScript Gotchas for New Users

| Trap | Correct way |
|------|-------------|
| Ternary operator | `val if cond else fallback` (NOT `? :` like JS/C#) |
| `draw_*` calls | ONLY work inside `_draw()`. Call `queue_redraw()` to trigger a redraw. |
| Integer division | `5 / 2 = 2` in GDScript. Use `5.0 / 2` for float result. |
| Dictionary mutation | `units[uid] = u` after modifying `u` — dicts are copied on read, you must write back |
| `for i in 5` | Loops 0,1,2,3,4 (NOT 1-5). Same as `range(5)`. |
| Array typing | `var x: Array[Vector2i] = []` — typed arrays are stricter |
| `PackedVector2Array` | Required for `draw_colored_polygon` / `draw_polyline` — regular arrays won't work |

---

## Replay Mode

When all units are deployed (Phase.DONE), a REPLAY button appears. Clicking it enters replay mode:

- **State:** `replay_mode` (bool) and `replay_turn` (0-based turn index)
- **Data source:** `obj_ctrl_history` and `unit_snapshots` from simulate() — per-turn state snapshots
- **Drawing:** `_draw_replay()` takes over the entire `_draw()` call (early return)
- **No ghost trails** — only the current turn's unit positions are shown with correct model counts
- **Navigation:** Left/Right arrow keys, Escape to exit back to looping animation
- **Animation frozen:** `_process()` returns early when `replay_mode` is true

## Scoreboard, Unit Fate Chart, Combat Log

Three additional UI panels are drawn each frame:

| Panel | Location | Data source | Notes |
|-------|----------|------------|-------|
| Scoreboard | Top-right | `vp_per_turn` | Cumulative VP per turn, both players |
| Unit Fate Chart | Below scoreboard | `unit_names`, `unit_obj`, `unit_kills`, `unit_dmg` | Per-unit stats: death turn, objective contribution, kills, damage |
| Combat Log | Left side (340px) | `combat_log` (also saved to `user://combat_log.txt`) | Scrollable play-by-play, mouse wheel to scroll when cursor is over the panel |

---

## Glossary

| Term | Meaning |
|------|---------|
| **hex_id** | Single integer encoding a hex position: `col * 1000 + row` |
| **timeline** | Array of Vector2i positions, one per turn, tracking where a unit was |
| **confirmed_sim** | Simulation result based on actually-placed units |
| **preview_sim** | Simulation result including the ghost unit under cursor |
| **ghost/trail** | Faded visual showing where a unit WAS or WILL BE at other turns |
| **butterfly effect** | Placing a unit near a fight changes its per-combat RNG seed; distant fights are unaffected |
| **odd-q offset** | Hex coordinate system where odd columns are staggered down |
| **cube coords** | Alternative hex coordinate system used internally for distance calculation |

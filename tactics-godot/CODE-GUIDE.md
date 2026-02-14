# HexMoveDemo.gd — Code Guide for New Godot Users

This is a single-file Godot 4.6 prototype. Everything lives in `HexMoveDemo.gd` (~1300 lines), attached to a Node2D in `HexMoveDemo.tscn`. No other scripts, no UI nodes, no tilemaps — just one script drawing everything manually.

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
INFANTRY/CAVALRY   → stat blocks (models, hp, move, attacks, hit, wound, rend, armor, damage)
C_BG, C_P1, etc.   → color constants
```

**To change game balance:** edit the INFANTRY/CAVALRY dictionaries.
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

#### How `simulate()` works (line 267):

```
1. Create RNG seeded from unit positions (deterministic — same placement = same result)
2. Copy input units into working array with full stats
3. For each turn (12 turns):
   a. MOVEMENT PHASE: each unit picks a goal and walks toward it via A*
   b. COMBAT PHASE: adjacent enemies fight simultaneously
4. Return {timelines, units, combat} — the full history
```

#### Movement AI (`_pick_target_objective`, line 191):
1. Look at 3 objectives → who controls each? (count nearby models)
2. Move toward nearest objective that ISN'T already friendly-held
3. If all objectives are friendly → move toward nearest enemy
4. If enemy is within COMBAT_RANGE → STOP and stay to fight

#### Combat (`_roll_combat`, line 254):
Warhammer-style dice rolling for each attack:
```
For each model × attacks_per_model:
  Roll d6 → hit?  (need >= hit stat)
  Roll d6 → wound? (need >= wound stat)
  Roll d6 → armor save? (need >= armor + rend, if fail → take damage)
```
Both sides roll before wounds are applied (simultaneous).

#### Wound tracking (`_apply_wounds`, line 357):
Wounds accumulate. When wounds >= model's HP, one model dies and leftover wounds carry over. Unit is "eliminated" when models reach 0.

#### The "Butterfly Effect":
Because the RNG seed is derived from unit positions (`seed_val ^ (col * 31 + row * 97 + ...)`), placing a unit on a DIFFERENT hex produces completely different dice rolls for the ENTIRE battle. This is the core mechanic — every placement decision ripples through the whole simulation.

---

### Lines 369–524: Game State & Input

#### Phase system:
```
Phase.DEPLOY → players take turns clicking to place units
Phase.DONE   → all units placed, just watching the animation loop
```

#### Deployment flow:
1. `active_player` alternates between 1 and 2
2. Click in your deploy zone → adds unit to `placed_p1` or `placed_p2`
3. On every click: `_recalc_confirmed_sim()` reruns full simulation
4. On every hover: `_recalc_preview_sim()` adds a ghost unit and reruns simulation
5. After `UNITS_PER_SIDE * 2` total placements → Phase.DONE

#### Two simulation states:
- `confirmed_sim` — based on actually placed units (solid rendering)
- `preview_sim` — includes the ghost unit under your cursor (faded rendering)

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
  ├── draw background rect
  ├── _draw_tile() for each hex          ← grid, zones, objectives
  ├── _draw_sim()                         ← paths, units, combat
  │     ├── 1) hex highlights along paths
  │     ├── 2) path lines connecting turns
  │     ├── 3) ghost tokens at each turn position
  │     ├── 4) combat spark icons
  │     └── 5) current animated unit tokens (interpolated)
  ├── _draw_hud()                         ← top bar + REPLAY button (when DONE)
  ├── _draw_scoreboard()                  ← VP per turn table
  ├── _draw_unit_fate()                   ← per-unit stats chart
  └── _draw_combat_log()                  ← scrollable play-by-play log
```

#### `_draw_tile(col, row)` — line 558:
1. Fill hex polygon (dark blue)
2. Draw hex outline
3. Tint deploy zones (blue for P1, red for P2 — brighter when it's your turn)
4. Tint objective radius (gold)
5. Hover highlight (white overlay)
6. Draw objective banner (flag on a pole)

#### `_draw_sim()` — line 606:
The simulation result contains `timelines` — an array per unit, where each entry is the unit's position at that turn. This function draws:

1. **Path hex highlights** — every hex a unit visits gets a subtle player-colored tint
2. **Path lines** — colored lines connecting each consecutive position (skips if stationary)
3. **Ghost tokens** — faded shield icons at each turn position (NOT the current animated turn)
4. **Combat sparks** — gold circle + crossed swords where fights happened
5. **Current tokens** — solid unit shields at the animated position, smoothly interpolated between turns

#### `_draw_unit_token()` — line 704:
Draws a shield-shaped polygon with a cross emblem and model count. Takes `is_ghost` and `alpha` params to control opacity for trail vs current positions.

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
- **Add unit type selection** during deployment (currently hardcoded to infantry — see line 470/477)
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
| **butterfly effect** | Changing one unit's placement changes the RNG seed, altering the entire battle |
| **odd-q offset** | Hex coordinate system where odd columns are staggered down |
| **cube coords** | Alternative hex coordinate system used internally for distance calculation |

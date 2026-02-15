# HexMoveDemo.gd — Code Guide for New Godot Users

This is a single-file Godot 4.6 prototype. Everything lives in `HexMoveDemo.gd` (~3700 lines), attached to a Node2D in `HexMoveDemo.tscn`. No other scripts, no UI nodes, no tilemaps — just one script drawing everything manually.

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

### Lines 1–95: Configuration Constants

```
COLS/ROWS          → grid dimensions (56×40)
HEX_SIZE           → radius of each hex in pixels (20)
UNITS_PER_SIDE     → how many units each player places (8)
TURNS              → simulation length (10)
COMBAT_RANGE       → hexes away to trigger combat (2)
OC_RADIUS          → hexes for objective control check (4)
CAVALRY_AGGRO      → cavalry hunt range (16)
P1/P2_DEPLOY_ROWS  → which rows each player can click to place units
OBJECTIVES         → 3 hex coordinates: (14,20), (28,18), (42,20)
INFANTRY/CAVALRY/ARTILLERY/DEEP_STRIKE/ARCHER → stat blocks (models, hp, move, oc, footprint, attacks, armor)
UNIT_TYPES         → ["infantry", "cavalry", "artillery", "deep_strike", "archer"]
C_BG, C_P1, etc.   → color constants
```

**To change game balance:** edit the unit stat dictionaries. Use `_get_stats(unit_type)` to look up stats by type string. Key fields: `models`, `hp`, `move`, `oc` (objective control per model), `footprint` (fixed, artillery only).
**To resize the map:** change COLS, ROWS, and adjust deploy rows/objectives.

---

### Lines 96–195: Hex Math

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

### Lines 196–230: A* Pathfinding

Uses Godot's built-in `AStar2D` class.

```
build_astar(blocked)  → Rebuilds the full graph, skipping hexes in the "blocked" dict
find_path(...)        → Returns array of Vector2i waypoints from start to goal
```

**Known performance issue:** `build_astar()` is called inside `find_path()` every time, which rebuilds the entire 56×40 graph for every unit every turn. This is a clear optimization target — rebuild once per turn with the current blocked set instead.

---

### Lines 232–430: Formation Helpers & Targeting Functions

Multi-hex formation system — units occupy multiple hexes based on model count.

```
_compute_footprint(unit_type, models) → ceil(models/2), or fixed footprint for artillery
compute_compact_cluster(anchor, size, blocked) → BFS from anchor to build compact hex cluster
formation_dist(form_a, form_b) → min hex distance between any pair of hexes across two formations
formation_dist_to_hex(formation, target) → min hex distance from any formation hex to target
_build_blocked_from_units(units, exclude_uid, turn) → blocked dict from all unit formations
_pick_target(uid, units, ...) → AI target selection (objectives vs enemies)
_nearest_enemy_in_range(uid, units, range) → find closest enemy within range
_pick_trail_target(uid, units, timelines, formations_timeline, turn) → DS trail hex targeting
_find_trail_uid_at_hex(hex, sim) → find which unit's trail occupies a hex (for hover tooltip)
```

---

### Deploy Formation Cache

During deployment, `_recompute_deploy_cache()` builds `_deploy_blocked_cache` — a Dictionary of hex IDs that formations cannot grow into. It contains:
1. All formation hexes from already-placed units (prevents stacking)
2. All hexes outside the current player's deploy zone (prevents zone bleed)
3. For deep strike: all hexes not in `ds_legal_hexes`

This cache is rebuilt when a unit type is selected or a DS turn is chosen. `compute_compact_cluster()` uses it as its `blocked` parameter, so formations naturally compact within the legal zone.

**Stored formations:** When a unit is placed, `_handle_deploy_click()` computes the formation via `compute_compact_cluster()` against the blocked cache and stores it as a `formation` field (Array[Vector2i]) in the placed unit dict. `simulate()` reuses stored formations when available (with a zone-constrained fallback for headless sim where formations may not be pre-stored).

**Heatmap toggle:** `_heatmap_enabled` (default false) is toggled by H key. `_compute_deploy_heatmap()` exits early when disabled. When enabled, it queues all valid deploy hexes (filtered by `_deploy_blocked_cache`) and processes 2-3 sims per frame via `_process_heatmap_batch()`.

---

### Lines 303–1100: Simulation Engine (including targeting & combat helpers)

This is the **core game logic**. The `simulate()` function takes placed units and returns the entire battle.

#### How `simulate()` works:

```
1. Copy input units into working array with full stats
2. For each turn (10 turns):
   a. DEEP STRIKE ARRIVAL: units with start_turn == turn materialize
   b. MOVEMENT: per-type AI picks goal, unit walks via A*
   c. TEMPORAL DISRUPTION CHECK: DS within COMBAT_RANGE of target trail hex →
      enemy yanked back, formation recomputed, cavalry lose charge bonus.
      Wasted on dead unit trails. DS reverts to infantry AI after.
   d. RANGED PHASE: artillery/archer shoot (one-way) if not in melee
   e. MELEE PHASE: pairs within COMBAT_RANGE fight simultaneously
      (disrupted cavalry lose charge bonus)
   f. ARCHER RETREAT: archers in melee move 16 hex away
   g. OBJECTIVE CHECK: OC-based control (models × oc within formation OC_RADIUS 4)
3. Return {timelines, formations_timeline, units, combat, ...} — the full history
```

#### Movement AI (per unit type):
- **Infantry:** nearest unclaimed/enemy objective; if all friendly, nearest enemy
- **Deep Strike (pre-disruption):** pathfinds toward nearest enemy trail hex via `_pick_trail_target()` — scans `formations_timeline` for any past-turn position of any enemy (including eliminated units and other DS). Hunts across multiple turns if needed.
- **Deep Strike (post-disruption):** same as infantry (objective-focused) after disruption is used or wasted
- **Cavalry:** hunt nearest enemy; if none, objectives
- **Artillery:** stay if ranged target within 40; else walk straight forward toward enemy side (does NOT chase objectives)
- **Archer:** kite at range 24 (approach enemy but avoid COMBAT_RANGE 2); else objectives. Always retreats 16 hex from melee. First melee = half damage both ways; subsequent = full damage, still retreats.

#### Combat:
**Ranged** (`_find_ranged_target`, `_roll_combat`): one-way attack, target doesn't return fire.
**Melee** (`_roll_melee`): Warhammer-style simultaneous combat. Artillery/Archer use melee_* stats. Cavalry charge bonus: dmg 2→1 if started turn in melee range (tracked via `cav_no_charge` dict).
```
For each model × attacks:
  Roll d6 → hit?  (need >= hit stat)
  Roll d6 → wound? (need >= wound stat)
  Roll d6 → armor save? (need >= armor + rend, if fail → take damage)
```

#### Wound tracking (`_apply_wounds`):
Wounds accumulate. When wounds >= model's HP, one model dies and leftover wounds carry over. Unit is "eliminated" when models reach 0. **Formation shrinks** when models die — `_shrink_formation()` releases hexes closest to enemies first.

#### Temporal Disruption (Deep Strike special ability):
Each DS unit arrives with one disruption charge. Between movement and ranged phases, the sim checks if any DS is within COMBAT_RANGE (2) of its target trail hex. If so:
1. The targeted enemy is teleported to the trail hex position
2. Their formation is recomputed at the new location
3. Disrupted cavalry lose their charge bonus (yanked = lost momentum)
4. If the target was already dead, the disruption is wasted (logged as "disruption wasted")
5. The DS's `has_disrupted` flag is set to true, and it switches to infantry AI

**New unit state fields:** `has_disrupted`, `disrupted`, `disrupted_turn`, `disrupted_from`
**New function:** `_pick_trail_target()` — scans `formations_timeline` for nearest enemy trail hex

**Visual:** Worm fractures at disruption point — purple jagged line from old position to yanked position, X mark at severed old fate, ribbon gap in worm trail.

#### The "Local Butterfly Effect":
Each combat pair gets its own RNG seed derived from the pair identity, turn number, and positions of all units within 2 hexes. Placing a unit near a fight changes that fight's outcome, but distant fights are unaffected. The cascade is the game: a changed fight → a unit survives/dies → objectives flip → the score shifts.

---

### Lines 1144–1470: Game State & Input

#### Phase system:
```
Phase.DEPLOY → unit selection → placement → alternate players
Phase.DONE   → all units placed, animation loops, REPLAY button
```

#### Deployment flow:
1. Unit selection popup appears (5 types: Infantry, Cavalry, Artillery, Deep Strike, Archer)
2. Player clicks type → `deploy_unit_type` set, popup closes
3. [Deep Strike only] Turn selector popup (T2–T8) → legal hexes highlighted (17+ from all enemies at arrival turn)
4. Hover in deploy zone → preview sim runs with ghost unit (formation validated against `_deploy_blocked_cache`)
5. Click to confirm → computes and stores formation, adds unit (with `formation` field) to `placed_p1` or `placed_p2`, recalc confirmed sim
6. `active_player` flips, `selecting_unit = true`, repeat
7. After `UNITS_PER_SIDE * 2` total placements → Phase.DONE

#### Key state vars:
- `selecting_unit` — true when unit selection popup is showing
- `ds_selecting_turn` — true when deep strike turn selector is showing
- `ds_arrival_turn` — chosen arrival turn for deep strike (-1 if not set)
- `ds_legal_hexes` — dictionary of valid hex_ids for deep strike placement
- `view_mode` — current view mode (CLEAN/CHANGED/FULL/FINAL enum)
- `_heatmap_enabled` — deploy heatmap on/off (toggled by H key, off by default)
- `_deploy_blocked_cache` — Dictionary of blocked hex IDs for deploy formation validation

#### View modes (keys 1–4):
Players switch view modes during deployment to control visual information density:
- **1 = CLEAN**: all units at final position, preview unit gets full timeline
- **2 = CHANGED**: 70% dark fog overlay; changed units' old/new paths crossfade (1s/phase): pale purple = old timeline ("WITHOUT"), pale yellow = new timeline ("WITH UNIT"); preview unit keeps team trail; unchanged units as dim silhouettes (20% alpha); falls back to CLEAN when no preview active
- **3 = FULL**: full timelines for ALL units at 2x speed with enhanced "snail trail" — units rendered as spacetime worms (thicker lines, higher opacity, faster scan)
- **4 = FINAL**: static end-state snapshot — all units at final/death positions, final objectives, no animation
- **H = HEATMAP**: toggle deploy heatmap overlay (off by default) — VP delta per hex

#### Two simulation states + diff:
- `confirmed_sim` — based on actually placed units (solid rendering)
- `preview_sim` — includes the ghost unit under your cursor (faded rendering)
- `preview_diff` — fate changes, score delta, objective flips between confirmed/preview

This is what creates the live preview — as you move your mouse, the preview sim recalculates and you see all paths shift.

#### Timeline shifted popup (after placement):
After each unit is placed, a "TIMELINE SHIFTED" popup summarizes what changed. It always includes the placed unit's performance: damage dealt (with per-target breakdown), kills, objectives held, and survival. Other units whose fates changed are listed below with before/after comparisons.

#### Trail hover tooltip (in `_input`):
When the mouse moves over a hex during DEPLOY or DONE phases, `_find_trail_uid_at_hex()` scans `formations_timeline` to check if any unit occupied that hex in any turn. If found, `hover_trail_uid` is set and `_draw_trail_tooltip()` renders a stats panel near the cursor. The hovered unit's entire trail is highlighted with a bright team-colored glow in `_draw_sim()`.

#### Camera controls (in `_input`):
- **Scroll wheel** → zoom in/out (0.3x to 4.0x)
- **Right-click drag** → pan camera
- **Mouse move** → update hover hex, recalc preview
- **Left click** → place unit

---

### Lines 2210–2230: Process Loop

```gdscript
func _process(delta):
    anim_frac += delta / TURN_DURATION   # advance animation clock
    if anim_frac >= 1.0:                 # wrapped past one turn
        anim_turn = (anim_turn + 1) % (TURNS + 1)
    queue_redraw()                        # repaint every frame
```

`anim_turn` and `anim_frac` together track which turn the animation is showing and how far between this turn and the next (for smooth interpolation). The animation loops forever.

**IMPORTANT: Turn Indexing Pattern**
- The sim loop uses 0-based turns (0-9): `for turn in TURNS`
- ALL display strings must use `turn + 1` to show user-facing turns 1-10 (e.g., combat log headers)
- ALL internal logic (timeline indexing, snapshot lookups, elimination turn tracking) uses raw 0-based values
- Example: `elim_turn = 3` means the unit died on 0-based turn 3 (display "Turn 4"). Always format as `elim_turn + 1` in UI strings.
- Deep strike `start_turn` parameter: deployed 0-based, but user selects 2-8 (display T2–T8). Convert with `+1` / `-1` at boundaries.

---

### Lines 2235–2805+: Drawing

All rendering happens in `_draw()` and its helpers. **Nothing uses Godot's scene tree for visuals** — it's all manual `draw_*` calls.

#### Draw order (back to front):

```
_draw()
  ├── [if replay_mode] → _draw_replay()  ← clean turn-by-turn view (early return)
  ├── [if show_summary] → _draw_battle_summary() ← scrollable overlay (early return)
  ├── draw background rect
  ├── _draw_tile() for each hex          ← grid, zones, objectives, DS legal hex highlights
  ├── [CHANGED mode] dark fog overlay    ← 70% black rect dims tiles for spotlight effect
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
  ├── [if hover_trail_uid >= 0] → _draw_trail_tooltip() ← unit stats near cursor
  ├── [if selecting_unit] → _draw_unit_select()      ← 5-button popup
  └── [if ds_selecting_turn] → _draw_ds_turn_select() ← T2-T8 popup
```

#### `_draw_tile(col, row)` — line ~2301:
1. Fill hex polygon (dark blue)
2. Draw hex outline
3. Tint deploy zones (blue for P1, red for P2 — brighter when it's your turn)
4. Tint objective radius (gold)
5. Hover highlight (white overlay)
6. Draw objective banner (flag on a pole)

#### `_draw_sim()`:
The simulation result contains `timelines` (anchor positions) and `formations_timeline` (full formation hex snapshots) — arrays per unit per turn. This function uses the current `view_mode` to decide what to show:

- A `show_timeline_for_uid` lambda determines per-unit visibility based on view mode
- **CLEAN**: preview unit gets `_draw_single_timeline()`; all others get `_draw_unit_final()` (final position only)
- **CHANGED**: 70% dark fog overlay drawn after tiles; changed units' old/new paths crossfade via `_diff_flash_time` (pale purple → pale yellow, 1s/phase, sine blend); preview unit gets team trail; rest get dim silhouettes via `_draw_unit_final()` at 20% alpha; falls back to CLEAN when no preview active
- **FULL**: all units get full timelines via `_draw_single_timeline()`
- **FINAL**: handled by `_draw_final_state()` — static snapshot, no animation

For each visible unit timeline, `_draw_single_timeline()` draws 5 layers:
1. **Path hex highlights** — every hex a unit visits gets a subtle player-colored tint
2. **Path lines** — colored lines connecting each consecutive position (skips if stationary)
3. **Ghost tokens** — faded type-specific shapes at each turn position (NOT the current animated turn)
4. **Combat sparks** — gold circle + crossed swords where fights happened (filtered by view mode — only shown when at least one participant has a visible timeline)
5. **Current tokens** — solid unit shapes at the animated position, smoothly interpolated between turns

#### `_draw_unit_token()`:
Draws a unit-type-specific sprite (or fallback shape) with model count. Takes `is_ghost` and `alpha` params to control opacity for trail vs current positions. **Multi-hex formations** draw one sprite per formation hex — ghost tokens and current tokens iterate all formation hexes from `formations_timeline`.

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
- **Tuning constants** (lines 7–30): grid size, unit count, turn count, deploy zones, objective positions
- **Unit stats** (lines 32–80): change balance by editing INFANTRY/CAVALRY/etc. dicts (models, hp, move, oc, footprint, attacks, armor)
- **Colors** (lines 82–95): change the visual palette
- **Animation speed** (line 14): TURN_DURATION controls how fast turns play

### Medium complexity:
- **Add an undo button** (pop last entry from placed_p1/p2, recalc sim)
- **Improve the HUD** (lines 2978–3040): add more info, make it prettier
- **Add a timeline scrubber** so players can drag to see specific turns instead of watching the loop

### Bigger changes:
- **P2 AI** — right now P2 is a human clicking the top zone. Could auto-place randomly or with heuristics
- **Switch to TileMapLayer** — replace the manual hex drawing with Godot's built-in tilemap system for better performance and editor integration
- **Split into multiple files** — extract hex math, simulation, and rendering into separate scripts
- **Performance**: `build_astar()` inside `find_path()` (line ~220) rebuilds the graph per call — should rebuild once per turn
- **Larger maps**: the current 56×40 grid could scale further if needed

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

## Headless Simulation (CLI Tool)

You can run the full simulation without the Godot GUI using the headless sim tool. This is useful for automated testing, batch experiments, and CI pipelines.

### Files
| File | Purpose |
|------|---------|
| `HeadlessSim.gd` | Node script — reads `deploy.json`, runs `simulate()`, writes output |
| `HeadlessSim.tscn` | Minimal scene with `HeadlessSim.gd` attached |
| `deploy.json` | Deployment config — army compositions and hex positions |

### How to run
```powershell
& 'C:\Users\bigto\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe' --headless --path 'C:\Users\bigto\Documents\GitHub\hello-world-game\tactics-godot' res://HeadlessSim.tscn
```

### deploy.json format
```json
{
  "blue": [
    { "unit_type": "infantry", "col": 60, "row": 70 },
    { "unit_type": "cavalry", "col": 55, "row": 72 }
  ],
  "red": "random"
}
```
- Each side is either an array of unit dicts (`unit_type`, `col`, `row`, optional `start_turn` for deep strike) or the string `"random"` for AI-generated placement.
- **Validation**: deploy zones enforced, no hex overlap, valid unit types, max 8 units per side.

### Output
- **`user://results.json`** — structured JSON containing:
  - `winner` — "blue", "red", or "draw"
  - `scores` — final VP totals
  - `score_by_turn` — cumulative VP per turn
  - `obj_control_final` — which player holds each objective
  - Per-unit stats: damage dealt, kills, objectives held, damage_targets (per-enemy breakdown), survival
- **`user://combat_log.txt`** — full text combat log (same format as the in-game log)
- **stdout** — one-line summary of the result

On Windows, `user://` resolves to `C:\Users\bigto\AppData\Roaming\Godot\app_userdata\Hex Move Demo\`.

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
| **trail hover tooltip** | Hover any unit's trail hex to see a tooltip with their stats (name, survival, damage, kills, objectives, disruption). Entire trail glows with team color. Uses `_find_trail_uid_at_hex()` and `hover_trail_uid` state var |
| **odd-q offset** | Hex coordinate system where odd columns are staggered down |
| **cube coords** | Alternative hex coordinate system used internally for distance calculation |
| **temporal disruption** | DS special ability — yank an enemy back to a past trail position, fracturing their spacetime worm |
| **trail hex** | A hex from `formations_timeline` representing where a unit was in a past turn — DS targets these |
| **has_disrupted** | Bool on DS units — true after disruption is used or wasted |
| **disrupted** | Bool on any unit — true if it was yanked by a DS disruption |

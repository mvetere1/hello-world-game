# HexMoveDemo — Developer Testing Toolkit Guide

This is a Godot 4.6 **developer testing toolkit** for a hex tactics game. It's not the final game — it's a tool for the team to rapidly test game feel, balance, and visual presentation. The final game design is uncertain; this tool lets us explore variations without committing.

**Architecture is in active migration** toward Godot-native patterns. See `REFACTOR-NOTES.md` for the full plan (Phases 0-5, 7, 8, 9.1-9.3 done; Phases 9.4-12 planned).

---

## Team Workflow

### Who Edits What

| Role | What you do | Files you touch |
|------|-------------|-----------------|
| **Designer** | Tune unit stats, grid size, deploy zones, combat rules, terrain | `.tres` files in `resources/` (Inspector only — no code) |
| **Artist** | Swap sprites, adjust tileset, create UI theme | `sprites/`, `terrain/`, texture fields in `.tres` files |
| **Programmer** | Simulation logic, AI, new systems, architecture | `scripts/*.gd`, controller scripts |
| **Tester** | Run headless sims, compare benchmarks, deploy configs | `deploy.json`, `sim_results/`, headless CLI |

### Quick Start by Role

**Designer — tuning balance:**
1. Open Godot, navigate to `resources/units/` in FileSystem dock
2. Click any `.tres` file (e.g., `infantry.tres`) — Inspector shows all editable stats
3. Change values (models, move speed, damage, armor) — save
4. Run the game (F5) to see changes immediately

**Artist — swapping sprites:**
1. Drop new sprite sheets into `sprites/blue/` and `sprites/red/`
2. Open the unit's `.tres` file, drag new texture into `sprite_idle` field
3. Adjust `idle_frames`, `sprite_size` if frame count or size changed

**Programmer — modifying simulation:**
1. Edit `scripts/combat_simulator.gd` for AI, combat, pathfinding changes
2. Run `run_tests.ps1` after every edit
3. Run headless sim to verify: `godot --headless --path . res://HeadlessSim.tscn`

**Tester — running experiments:**
1. Edit `deploy.json` with army compositions
2. Run headless sim, check `results.json`
3. Compare results across deployments using `sim_results/` folder

---

## File Overview

| File | Lines | Role |
|------|-------|------|
| `HexMoveDemo.gd` | ~1,858 | Orchestrator: input, deploy, remaining HUD draw_* |
| `scripts/game_state.gd` | 122 | Centralized mutable state (46 vars, 2 enums, 6 signals) |
| `scripts/battle_renderer.gd` | 865 | Child Node2D: tiles, trails, tokens, sim rendering |
| `scripts/hud/top_bar.gd` | 124 | TopBar Control node: phase text, view modes, progress bar |
| `scripts/hud/unit_select_popup.gd` | 60 | UnitSelectPopup: unit type selection modal |
| `scripts/hud/ds_turn_popup.gd` | 55 | DSTurnPopup: DS arrival turn selection modal |
| `scripts/hud/scoreboard.gd` | 98 | Scoreboard: VP per turn table with preview delta |
| `scripts/hud/fate_chart.gd` | 231 | FateChart: per-unit stats table with fate change highlighting |
| `scripts/combat_simulator.gd` | 948 | Simulation engine, AI, pathfinding, combat rolls |
| `scripts/hex_math.gd` | 94 | Pure hex math (static class — `HexMath.hex_to_pixel()`, etc.) |
| `scripts/resources/*.gd` | 5 files | Resource class definitions (UnitStats, GridConfig, BattleConfig, TerrainType, VisualConfig) |
| `resources/**/*.tres` | 13 files | 5 unit configs + 3 game configs + 3 terrain types + 1 theme + 1 visual config |
| `scenes/hud/*.tscn` | 5 files | TopBar, UnitSelectPopup, DSTurnPopup, Scoreboard, FateChart scene files |
| `HeadlessSim.gd` | 304 | CLI simulation runner (uses CombatSimulator directly) |

---

## Core Design Principle: RNG as Terrain, Not Chaos

**Every team member must understand this.** Randomness creates unique board states — NOT helplessness. The player sees the exact future before committing. RNG effects are local (only nearby changes affect nearby fights). The player controls outcomes through strategy, not luck.

---

## How Godot Runs This

### Current Scene Tree
```
HexMoveDemo (Node2D)               ← has HexMoveDemo.gd attached
├── GameState (Node)               ← centralized mutable state + signals (created in _ready)
├── TerrainMap (TileMapLayer)       ← terrain data (visual rendering planned)
├── BattleRenderer (Node2D)         ← created in _ready(), draws battle visuals
└── HUD (CanvasLayer, layer=10)    ← HUD Control nodes (created in _ready)
     ├── TopBar (PanelContainer)   ← phase text, view mode buttons, progress bar
     ├── UnitSelectPopup (ColorRect) ← unit type selection modal (dim overlay + buttons)
     ├── DSTurnPopup (ColorRect)   ← DS arrival turn selection modal
     └── AnalyticsPanel (VBoxContainer) ← right-side stacking container
          ├── Scoreboard (PanelContainer) ← VP per turn table
          └── FateChart (PanelContainer)  ← per-unit stats with fate highlighting
```

### Target Scene Tree (migration in progress)
```
BattleTestbed (Node2D)              — thin orchestrator
├── GameState (Node)                — all mutable state + signals
├── HexGrid (Node2D, @tool)         — hex grid visualization
│   ├── TerrainLayer (TileMapLayer)  — GPU-batched hex tiles
│   └── OverlayLayer (Node2D)       — deploy zones, highlights
├── BattleRenderer (Node2D)         — trails, tokens, sparks (draw_*)
├── SimulationBridge (Node)         — wraps CombatSimulator
├── DeployController (Node)         — input, placement
├── ReplayController (Node)         — replay navigation
├── HUD (CanvasLayer)               — all UI as Control nodes
│   ├── TopBar, Scoreboard, FateChart, CombatLog, ...
│   └── Popups (UnitSelect, DSTurnSelect, ShiftSummary, ...)
└── Config (Node)                   — preloads .tres resources
```

See `REFACTOR-NOTES.md` for the full migration plan.

### Godot Lifecycle

| Function | When it runs | Our use |
|----------|-------------|---------|
| `_ready()` | Once, when scene loads | Center camera, run initial sim |
| `_input(event)` | Every mouse/key event | Handle clicks, hover, camera pan/zoom |
| `_process(delta)` | Every frame (~60/sec) | Advance animation timer, request redraw |
| `_draw()` | When `queue_redraw()` is called | Paint battle visuals and HUD overlays |

---

## Configuration (Resource Files)

Game constants live in `.tres` resource files editable in the Godot Inspector:

- **`resources/config/grid_config.tres`** — COLS, ROWS, HEX_SIZE, deploy zones, objectives, initial zoom
- **`resources/config/battle_config.tres`** — COMBAT_RANGE, OC_RADIUS, CAVALRY_AGGRO, VP rules, TURNS
- **`resources/config/visual_config.tres`** — 91 visual params: colors, trail alphas/widths, animation speeds, sprite scales, terrain outlines, combat aura, fate icons, disruption visuals
- **`resources/units/*.tres`** — per-unit stats (models, hp, move, oc, attacks, armor, etc.)
- **`resources/terrain/*.tres`** — terrain types (grass, forest, water)

**To change game balance:** edit the `.tres` files in the Inspector.
**To resize the map:** edit `grid_config.tres` and adjust deploy zones/objectives.
**To add a new unit type:** duplicate an existing `.tres` file, adjust stats, add to the unit type registry.

---

## Hex Math (`scripts/hex_math.gd`)

**Flat-top hexagons** with **odd-q offset** coordinates. Extracted into a static class.

```
   col 0    col 1    col 2    col 3
  /    \          /    \
 | 0,0  |  1,0  | 2,0  |  3,0       ← row 0
  \    / \      / \    / \
   | 0,1  |  1,1  | 2,1  |  3,1     ← row 1 (odd cols shifted down)
  / \    / \      / \    /
```

| Function | What it does |
|----------|-------------|
| `hex_to_pixel(col, row)` | Grid coord → screen position (applies camera) |
| `pixel_to_hex(pos)` | Screen click → nearest grid coord |
| `hex_corners(center)` | Returns 6 corner points for hex polygon |
| `hex_neighbors(col, row)` | Returns up to 6 adjacent hex coordinates |
| `hex_dist(c1,r1, c2,r2)` | Manhattan distance (cube coords internally) |
| `hex_id(col, row)` / `id_to_hex(id)` | col,row ↔ single integer (for A*) |

---

## Simulation Engine (`scripts/combat_simulator.gd`)

Pure logic, no scene tree dependency. `CombatSimulator extends RefCounted`.

### How `simulate()` works:
```
1. Copy input units into working array with full stats
2. For each turn (10 turns):
   a. DEEP STRIKE ARRIVAL
   b. MOVEMENT (per-type AI)
   c. TEMPORAL DISRUPTION CHECK
   d. RANGED PHASE
   e. MELEE PHASE
   f. ARCHER RETREAT
   g. OBJECTIVE CHECK
3. Return full history dict
```

### Movement AI:
- **Infantry:** nearest unclaimed/enemy objective; if all friendly, nearest enemy
- **DS (pre-disruption):** pathfinds toward nearest enemy trail hex
- **DS (post-disruption):** same as infantry
- **Cavalry:** hunt nearest enemy; if none, objectives
- **Artillery:** stay if target in range; else walk forward
- **Archer:** kite at range 24; retreats from melee

### Combat:
Warhammer-style: hit roll → wound roll → armor save (with rend) → damage. Cavalry charge bonus: dmg 2→1 if already in melee.

### Local Butterfly Effect:
Per-combat RNG seeded from pair identity + turn + nearby unit positions (within 2 hexes). Placing a unit near a fight changes that fight's outcome; distant fights are unaffected.

---

## Game State & Input

### Phases
```
DEPLOY  → unit selection popup → place unit → alternating P1/P2
DONE    → all units placed; animation loops; REPLAY button
```

### Two Sim States + Diff (stored in GameState)
- `_state.confirmed_sim` — based on placed units
- `_state.preview_sim` — placed + ghost unit at hover position
- `_state.preview_diff` — fate changes, score delta, objective flips

### View Modes (keys 1-4)
| Key | Mode | Shows |
|-----|------|-------|
| 1 | CLEAN | Final positions + preview unit trail |
| 2 | CHANGED | Dark fog + old/new crossfade for affected units |
| 3 | FULL | All timelines — spacetime worm view |
| 4 | FINAL | Static end-state snapshot |

### Turn Indexing
- Sim uses 0-based turns (0-9)
- Display strings use `turn + 1` (turns 1-10)
- `elim_turn = 3` means died on turn 4 in display

---

## Headless Simulation (CLI Tool)

Run simulations without the GUI:

```powershell
& 'C:\...\Godot_v4.6-stable_win64_console.exe' --headless --path 'tactics-godot' res://HeadlessSim.tscn
```

### deploy.json format
```json
{
  "blue": [
    { "unit_type": "infantry", "col": 14, "row": 35 },
    { "unit_type": "cavalry", "col": 20, "row": 36 }
  ],
  "red": "random"
}
```

### Output
- `user://results.json` — winner, scores, per-unit stats
- `user://combat_log.txt` — play-by-play text log

---

## GDScript Gotchas

| Trap | Correct way |
|------|-------------|
| Ternary operator | `val if cond else fallback` (NOT `?:`) |
| `draw_*` calls | ONLY work inside `_draw()`. Call `queue_redraw()` to trigger. |
| Integer division | `5 / 2 = 2`. Use `5.0 / 2` for float. |
| Dictionary mutation | Must write back: `units[uid] = u` after modifying `u` |
| `for i in 5` | Loops 0,1,2,3,4 (NOT 1-5) |
| `PackedVector2Array` | Required for `draw_colored_polygon` / `draw_polyline` |

---

## Where to Start Working

### Easy wins (no code):
- **Tuning constants** — edit `.tres` files in Inspector (grid size, unit stats, combat config)
- **Terrain** — paint terrain in TileMapLayer, add new terrain types as `.tres` files

### Medium complexity:
- **Add an undo button** — pop last entry from placed_p1/p2, recalc sim
- **P2 AI** — auto-place randomly or with heuristics
- **New unit types** — duplicate a `.tres` file, adjust stats

### Architecture work (in progress):
- **Phase 7: GameState extraction** — DONE. 46 state vars, 2 enums, 6 signals in `scripts/game_state.gd`
- **Phase 8: VisualConfig resource** — DONE. 102 @export vars in `visual_config.tres`
- **Phase 9.1: TopBar → Control node** — DONE. CanvasLayer + Theme + TopBar with signal-driven updates
- **Phase 9.2: Deploy popups → Control nodes** — DONE. UnitSelectPopup + DSTurnPopup as ColorRect overlays with Buttons
- **Phase 9.3: Scoreboard → Control node** — DONE. PanelContainer + GridContainer, signal-driven updates
- **Phase 9.4: FateChart → Control node** — DONE. Per-unit stats table with fate highlighting, VBox wrapper for Scoreboard+FateChart stacking
- **Phase 9.5+: Remaining HUD panels** — TODO. Combat log, tooltips, summaries
- **Phase 11: TileMapLayer rendering** — GPU-batched tiles

See `REFACTOR-NOTES.md` for full details.

---

## Glossary

| Term | Meaning |
|------|---------|
| **hex_id** | `col * 1000 + row` — single integer encoding a hex position |
| **timeline** | Array of Vector2i positions per turn, tracking unit movement |
| **confirmed_sim** | Simulation result from actually-placed units |
| **preview_sim** | Simulation including ghost unit under cursor |
| **spacetime worm** | Visual philosophy — ghost trails ARE the unit, not history |
| **butterfly effect** | Nearby placement changes nearby combat RNG; distant fights unaffected |
| **temporal disruption** | DS ability — yank enemy to past trail position |
| **.tres file** | Godot Resource file — editable in Inspector, version-control friendly |
| **@export** | GDScript annotation exposing a variable to the Godot Inspector |
| **CanvasLayer** | Godot node that draws UI in screen space, unaffected by camera |

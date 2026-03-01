# CLAUDE.md — tactics-godot

## PROJECT FOCUS: Developer Testing Tool

This is a **developer testing tool**, not a game. The final game design is uncertain — we don't know which variation or permutation will be the product. This tool lets a 4-person team rapidly experiment with game feel and balance within Godot's structure, using Godot best practices.

**The tool must use Godot-native features:** TileMapLayer for hex grids, Control nodes for HUD, @export for configuration, @tool for editor preview, signals for decoupling, Resources for data. See `REFACTOR-NOTES.md` for the target architecture and migration plan.

## CORE DESIGN PRINCIPLE: RNG as Terrain, Not Chaos
**RNG chaos is BAD in this game.** Randomness creates unique game states, but the player must make intelligent decisions to alter outcomes in their favor. Every feature must follow:
- Outcomes are **previewable** — the player sees the exact future before committing
- RNG effects are **local** — only nearby changes affect nearby fights
- The player **controls** outcomes through strategy, not luck
- No hidden randomness — what you see is what you get

**If a new feature introduces randomness, it must be previewable, local, and player-controllable. No exceptions.**

## Architecture

### Current State (post Phase 8)
```
HexMoveDemo (Node2D, z_index=0)        — orchestrator: state, input, deploy, HUD drawing
├── TerrainMap (TileMapLayer, z_index=-1)  — terrain data (visual rendering planned)
└── BattleRenderer (Node2D, z_index=-1)    — tiles, trails, tokens, sim (created in _ready)
```

| File | Lines | Role |
|------|-------|------|
| `HexMoveDemo.gd` | 2,171 | Orchestrator: state, input, deploy, HUD drawing |
| `scripts/battle_renderer.gd` | 863 | Child Node2D: tiles, trails, tokens, sim rendering |
| `scripts/hex_math.gd` | 94 | Pure hex math (static class) |
| `scripts/combat_simulator.gd` | 948 | Simulation, AI, pathfinding, combat |
| `scripts/resources/*.gd` | 5 files | UnitStats, GridConfig, BattleConfig, TerrainType, VisualConfig |
| `resources/**/*.tres` | 11 files | 5 units + 3 config + 3 terrain |
| `HeadlessSim.gd` | 304 | CLI simulation runner (uses CombatSimulator directly) |

### Target Architecture
See `REFACTOR-NOTES.md` for the full target scene tree. Key changes:
- **GameState node** — centralized mutable state with signals (replaces `_parent.xxx` pattern)
- **HUD via CanvasLayer + Control nodes** — replaces all draw_* HUD code
- **VisualConfig resource** — DONE. 91 @export vars in `resources/config/visual_config.tres`. Both HexMoveDemo and BattleRenderer preload independently.
- **TileMapLayer for rendering** — GPU-batched tiles replace 2,240 draw calls/frame
- **Controller nodes** — deploy and replay logic extracted from HexMoveDemo

### Migration Status
- Phases 0-5: DONE (resources, terrain, hex math, simulator, battle renderer)
- Phase 6 (Node2D HUDRenderer): SKIPPED — going directly to Control nodes
- Phase 8: DONE (VisualConfig resource — 91 exports, colors/alphas/widths/animation in `.tres`)
- Phases 7, 9-12: TODO (GameState, HUD Controls, Controllers, TileMap, @tool)

## Game Design Summary
- Grid: **56 cols × 40 rows**, **FLAT-TOP hex, odd-q offset**
- 8 units per player, free pick from 5 types: Infantry, Cavalry, Artillery, Deep Strike, Archer
- Multi-hex formations: units occupy ceil(models/2) hexes (compact cluster). Artillery has fixed 5-hex footprint.
- Non-reversible unit selection popup before each placement (blind commitment)
- Combat phases per turn: Movement → Temporal Disruption → Ranged → Melee → Retreat (archer)
- Combat range: COMBAT_RANGE = 2 hexes (melee); Artillery range 40, Archer range 24
- Objectives: 3 at (14,20), (28,18), (42,20); controlled by most OC within OC_RADIUS (4) per turn
- Named constants: OC_RADIUS=4, CAVALRY_AGGRO=16, COMBAT_RANGE=2
- Deploy zones: P1 rows 32-39 cols 4-51, P2 rows 0-7 cols 4-51
- DS temporal disruption: DS pathfinds to nearest enemy trail hex; at COMBAT_RANGE triggers yank. One charge per DS.
- VP scoring: 5 VP per objective held per turn (persistent control)
- RNG seed: per-combat (seeded from pair + turn + nearby unit positions within 2 hexes)

## Hex Math
- **FLAT-TOP hex, odd-q offset** coordinates
- Z-ordering: draw tiles back-to-front (row 0, col 0 first)
- `hex_id()` is `col * 1000 + row` — NEVER reverse with `% COLS` / `/ COLS`

## Godot Executable
```
GODOT_CONSOLE = C:\Users\bigto\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe
PROJECT_PATH  = C:\Users\bigto\Documents\GitHub\hello-world-game\tactics-godot
```

## How to Run Tests (do this after EVERY edit)
```powershell
powershell -File "C:\Users\bigto\Documents\GitHub\hello-world-game\tactics-godot\run_tests.ps1"
```
This runs: `--check-only --quit` (syntax), `--headless --quit` (runtime init), any `*.test.gd` files.

## How to Open the Game
```powershell
& 'C:\Users\bigto\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64.exe' --path 'C:\Users\bigto\Documents\GitHub\hello-world-game\tactics-godot'
```

## GDScript Rules

### Syntax
- Ternary operator: `value if condition else fallback` — NOT `condition ? value : fallback`
- String format: `"text %d" % value` or `"text %s %d" % [a, b]`
- `match` not `switch`

### Drawing
- `draw_*` calls are ONLY valid inside `_draw()`. Never call them from `_process()`.
- To trigger a redraw: `queue_redraw()`
- `PackedVector2Array` required for draw functions — plain `Array` will not work

### Types
- `roundi(x)` returns int in Godot 4
- Dictionary const values are Variant — access with `.key` syntax or `["key"]`

### Performance
- `in` on Array is O(n). Use Dictionary for membership checks in loops.
- AStar2D: `build_astar()` is expensive — don't call it inside per-unit loops

## Godot-Native Patterns (migration targets)

### Control Nodes for HUD (Phase 9)
Instead of `draw_rect()` + `draw_string()`, use:
- **PanelContainer** for bordered panels with automatic sizing
- **RichTextLabel** for colored text (combat log, summaries)
- **GridContainer** for tabular data (scoreboard, fate chart)
- **ScrollContainer** for scrollable content
- **CanvasLayer** to separate UI from world coordinates

### Signals for Decoupling (Phase 7)
Instead of `_parent.xxx` references:
```gdscript
# GameState emits signals
signal sim_changed()
signal phase_changed(phase: int)
# Nodes connect to react
game_state.sim_changed.connect(_on_sim_changed)
```

### @export for Inspector (already in use)
```gdscript
@export_group("Grid Dimensions")
@export_range(8, 100) var cols: int = 56
```

## Game Phases
```
DEPLOY  → unit selection popup → place unit → alternating P1/P2
DONE    → all units placed; animation loops; REPLAY button available
```

### Per-turn Simulation
```
1. DEEP STRIKE ARRIVAL
2. MOVEMENT (per-type AI)
3. TEMPORAL DISRUPTION CHECK
4. RANGED PHASE
5. MELEE PHASE
6. ARCHER RETREAT
7. OBJECTIVE CHECK
```

## View Modes (keys 1-4)
| Key | Mode | What it shows |
|-----|------|---------------|
| 1 | CLEAN | Final positions + preview unit trail |
| 2 | CHANGED | Dark fog + old/new path crossfade for changed units |
| 3 | FULL | All timelines, spacetime worm view |
| 4 | FINAL | Static end-state |

**H key** — Toggle deploy heatmap overlay.

## Simulation Architecture
- `simulate(all_units: Array) -> Dictionary` — pure function, input in / result out
- Returns: `{ timelines, formations_timeline, units, combat, obj_control, vp_per_turn, unit_names, unit_obj, unit_kills, unit_dmg, combat_log, obj_ctrl_history, unit_snapshots }`
- Two states: `confirmed_sim` (placed units) and `preview_sim` (placed + hover ghost)
- `preview_diff` compares confirmed vs preview — fate changes, score delta, objective flips

## Headless Simulation CLI
```powershell
& 'C:\...\Godot_v4.6-stable_win64_console.exe' --headless --path 'tactics-godot' res://HeadlessSim.tscn
```
Reads `deploy.json`, outputs `user://results.json` and `user://combat_log.txt`.

## Housekeeping Rules
- **Never leave temporary prompt files behind** (e.g., `PHASE5-PROMPT.md`, `PHASE6-PROMPT.md`). When a phase is done or skipped, delete its handoff prompt. The only persistent planning doc is `REFACTOR-NOTES.md`.
- **REFACTOR-NOTES.md is the single source of truth** for architecture and migration status. Do not create separate plan files that duplicate or contradict it.

## Known Mistakes (do not repeat)
1. **Ternary with `?:`** — GDScript uses `value if cond else fallback`
2. **`build_astar()` inside `find_path()`** — rebuilds on every call. Fix: rebuild once per turn.
3. **Damage as integer division** — track accumulated wounds, remove model when >= hp
4. **Units fighting multiple enemies** — fight NEAREST only
5. **Deep strike units targetable before arrival** — check `arrived` flag
6. **Artillery chasing objectives** — walks forward when no target in range
7. **Combat sparks in wrong view modes** — filter by `show_timeline_for_uid`
8. **Shift summary wrong name** — compute UID based on active player
9. **elim_turn off-by-one** — display strings use `elim_turn + 1`
10. **DS start_turn off-by-one** — popup T3 sets 0-based turn 2
11. **Deploy formation zone bleed** — `_deploy_blocked_cache` marks non-deploy hexes as blocked
12. **Deploy formation stacking** — blocked cache includes all existing formation hexes

## Known Concerns
1. **Visual clutter** — mitigated by 4 view modes (player controls information density)
2. **Performance** — `build_astar()` per find_path(), 2,240 tile draw calls/frame, trail hover O(UIDs × turns)

# Godot Refactor Notes — Developer Toolkit Architecture

> **Branch:** `godot-refactor` (branched from `tactics-prototype` at tag `prototype-v1`)
> **Started:** 2026-02-22
> **Goal:** Transform the single-file prototype into a proper Godot-native developer toolkit

---

## The Three Goals

### 1. Everything Tweakable by Developers
Every gameplay value — hex grid size, deployment zones, melee range, unit stats, formation sizes, objective positions, VP scoring — must be editable from the Godot Inspector without touching code.

**Godot tools:** Custom Resources (`.tres` files), `@export` annotations with ranges/groups, `@tool` scripts for live preview.

### 2. Collidable Terrain
The hex grid needs terrain types that affect gameplay: blocking movement, modifying combat, creating tactical decisions. Terrain is painted in the editor, not hardcoded.

**Godot tools:** TileMapLayer with hex tileset, custom data layers (terrain_type, move_cost, cover_bonus), AStar2D weight integration.

### 3. Team Collaboration
The architecture must let multiple developers work simultaneously without merge conflicts. Designers edit data, programmers edit logic, artists edit visuals — all independently.

**Godot tools:** Scene composition (one person per scene), Resources as the data bridge, signals for decoupling, separate `.tres` files for balance data.

---

## Current State (post Phase 4)

| File | Lines | Role |
|------|-------|------|
| `HexMoveDemo.gd` | 2,965 | Orchestrator: state, input, deploy, rendering, HUD |
| `scripts/hex_math.gd` | 94 | Pure hex math (static class) |
| `scripts/combat_simulator.gd` | 948 | Simulation, AI, pathfinding, combat |
| `scripts/resources/*.gd` | 4 files | UnitStats, GridConfig, BattleConfig, TerrainType |
| `resources/**/*.tres` | 10 files | 5 units + 2 config + 3 terrain |
| `HeadlessSim.gd` | 304 | CLI simulation runner (uses CombatSimulator directly) |

**Solved:** Unit stats editable in Inspector, config values in `.tres` files, simulation engine decoupled.
**Remaining:** Rendering and HUD still inline in HexMoveDemo.gd (~1,900 lines). Need Phases 5-6.

---

## Target Architecture

### Scene Tree
```
BattleScene (Node2D)
├── HexGrid (Node2D, @tool)
│   ├── TerrainLayer (TileMapLayer)      — hex tiles, terrain types
│   ├── OverlayLayer (TileMapLayer)      — deploy zones, movement highlights
│   └── Pathfinder (Node)                — owns AStar2D, rebuilds per turn
├── UnitManager (Node2D)
│   └── [Unit instances as children]     — Unit.tscn scenes
├── CombatManager (Node)                 — simulate(), combat rolls, AI
├── HUDLayer (CanvasLayer)
│   ├── Scoreboard.tscn
│   ├── FateChart.tscn
│   ├── CombatLog.tscn
│   └── DeployPopup.tscn
├── TrailRenderer (Node2D)               — ghost trails, disruption visuals
├── DeployController (Node)              — input handling, placement
└── ReplayController (Node)              — replay mode
```

### Custom Resources (`.tres` files)
```
resources/
├── config/
│   ├── grid_config.tres        — COLS, ROWS, HEX_SIZE, deploy zones
│   ├── battle_config.tres      — COMBAT_RANGE, OC_RADIUS, CAVALRY_AGGRO, VP rules
│   └── camera_config.tres      — initial zoom, pan speed, bounds
├── units/
│   ├── infantry.tres           — all Infantry stats
│   ├── cavalry.tres
│   ├── artillery.tres
│   ├── deep_strike.tres
│   └── archer.tres
└── terrain/
    ├── grass.tres              — move_cost=1, cover=0, passable=true
    ├── forest.tres             — move_cost=2, cover=1, passable=true
    ├── water.tres              — passable=false
    ├── mountain.tres           — passable=false, blocks_los=true
    └── ruins.tres              — move_cost=1, cover=2, passable=true
```

### Resource Class Definitions
```
scripts/resources/
├── unit_stats.gd              — class_name UnitStats extends Resource
├── grid_config.gd             — class_name GridConfig extends Resource
├── battle_config.gd           — class_name BattleConfig extends Resource
├── terrain_type.gd            — class_name TerrainType extends Resource
└── camera_config.gd           — class_name CameraConfig extends Resource
```

### Autoloads (global singletons)
```
GameState (autoload)           — current phase, turn, active player, placed units
HexMath (autoload)             — pure hex coordinate math (reads GridConfig)
```

---

## Key Godot Patterns We'll Use

### Custom Resources with @export
```gdscript
class_name UnitStats
extends Resource

@export_group("Identity")
@export var display_name: String = ""
@export var sprite_idle: Texture
@export var sprite_run: Texture

@export_group("Formation")
@export_range(1, 20) var models: int = 10
@export_range(1, 10, 1, "suffix:hex") var formation_hexes: int = 5

@export_group("Movement")
@export_range(0, 50, 1, "suffix:hex") var move_speed: int = 10

@export_group("Combat — Offense")
@export_range(1, 6) var weapon_skill: int = 3
@export_range(1, 6) var ballistic_skill: int = 4
@export_range(1, 10) var strength: int = 3
@export_range(1, 6) var attacks: int = 1
@export_range(0, 3) var rend: int = 0
@export_range(1, 3) var damage: int = 1
@export_range(0, 50, 1, "suffix:hex") var attack_range: int = 0

@export_group("Combat — Defense")
@export_range(1, 10) var toughness: int = 3
@export_range(1, 6) var armor_save: int = 5
@export_range(1, 5) var wounds: int = 1

@export_group("Special Rules")
@export var can_deep_strike: bool = false
@export var can_retreat: bool = false
@export_range(0, 50, 1, "suffix:hex") var retreat_range: int = 0
@export_range(0, 50, 1, "suffix:hex") var aggro_range: int = 0
```

### TileMapLayer for Hex Grid
- Tile Shape: Hexagon, Flat Top, Odd Column offset
- Custom Data Layers: `terrain_type` (Resource), `move_cost` (float), `cover_bonus` (int)
- `local_to_map()` / `map_to_local()` replace manual `pixel_to_hex()` / `hex_to_pixel()`
- GPU-batched rendering replaces 2,240 per-frame draw calls

### @tool for Editor Preview
- HexGrid.gd as `@tool` — see grid in editor, adjust size live
- Deploy zone visualization without running the game
- Objective position preview

### Signals for Decoupling
```
GameState.phase_changed(phase)
GameState.turn_started(turn)
GameState.unit_placed(uid)
GameState.sim_changed()
GameState.hover_changed(hex)
```

---

## Terrain System Design

### Terrain Types (as Custom Resources)
Each hex tile has a `TerrainType` resource attached via TileMapLayer custom data:

| Terrain | Move Cost | Cover | Passable | Blocks LoS | Visual |
|---------|-----------|-------|----------|------------|--------|
| Grass | 1.0 | 0 | yes | no | Green hex |
| Forest | 2.0 | +1 save | yes | no | Trees overlay |
| Water | — | — | no | no | Blue hex |

> **v1 ships with these 3.** Mountain, ruins, and other terrain types added later.

### Integration with Pathfinding
- AStar2D reads `move_cost` from TileMapLayer custom data
- Impassable terrain → `astar.set_point_disabled(hex_id, true)`
- Variable cost terrain → `astar.set_point_weight_scale(hex_id, move_cost)`

### Integration with Combat
- Cover bonus modifies armor save during wound rolls
- LoS blocking affects ranged attacks (future)

---

## Refactor Phases

### Phase 0: Resource Definitions — DONE
Created 4 Resource class scripts (`UnitStats`, `GridConfig`, `BattleConfig`, `TerrainType`) and 10 `.tres` files (5 units + 2 config + 3 terrain). All pass syntax check.

### Phase 1: Resource Bridge — DONE
Replaced all `const` blocks at the top of HexMoveDemo.gd with resource-backed property getters. Game logic unchanged — still references `COLS`, `COMBAT_RANGE`, etc., but values now come from `.tres` files.

### Phase 2: Terrain System — DONE
Added `terrain_data.json`, terrain query functions, terrain tint overlay in `_draw_tile()`, passability checks in deploy logic. TileMapLayer child node added to scene (placeholder for future tile-based rendering).

### Phase 3: Extract HexMath — DONE
Extracted pure hex math into `scripts/hex_math.gd` (94 lines). Static `class_name HexMath` — no scene tree dependency. HexMoveDemo keeps one-line wrapper functions so call sites don't change.

### Phase 4: Extract CombatSimulator — DONE
Extracted simulation engine into `scripts/combat_simulator.gd` (948 lines). `class_name CombatSimulator extends RefCounted` — owns AStar2D, AI targeting, combat rolls, and the main `simulate()` loop. HeadlessSim.gd now uses CombatSimulator directly. HexMoveDemo keeps thin wrappers.

**Current state:** HexMoveDemo.gd is 2,965 lines (down from 3,926). All tests pass, headless sim produces identical results.

### Phase 5: Extract BattleRenderer — TODO
Move ~670 lines of battle drawing code (`_draw_tile`, `_draw_sim`, `_draw_replay`, `_draw_single_timeline`, token rendering, etc.) into `scripts/battle_renderer.gd` as a child Node2D at z_index=0. Pre-step: move `_obj_control` writes from `_draw()` to `_process()`.

### Phase 6: Extract HUDRenderer — TODO
Move ~1250 lines of UI drawing code (`_draw_hud`, `_draw_scoreboard`, `_draw_unit_fate`, `_draw_combat_log`, `_draw_battle_summary`, `_draw_unit_select`, popups, tooltips, and data generation helpers) into `scripts/hud_renderer.gd` as a child Node2D at z_index=10. Pre-step: move scroll clamp logic from `_draw()` to `_process()`.

### Future: TileMapLayer Rendering
Replace `_draw_tile()` with GPU-batched TileMapLayer rendering. Set up hex tileset with terrain custom data layers. Currently hex tiles are drawn per-frame in code; TileMapLayer would eliminate 2,240 draw calls.

### Future: Extract Controllers
Move input handling, deploy logic, replay logic into separate nodes for full scene composition.

---

## Developer Toolkit Philosophy

This isn't just a game — it's a **prototyping toolkit** for the design team:

- **Designers** tweak `.tres` files in the Inspector to balance units, adjust grid size, modify terrain
- **Artists** swap sprites by dragging textures into resource fields
- **Programmers** work on systems (combat, AI, pathfinding) in isolated scripts
- **Everyone** can branch off `godot-refactor` and experiment without breaking each other's work

The goal is that creating a new unit type, changing the grid dimensions, or adding a terrain type requires **zero code changes** — just editor work.

---

## Decisions (2026-02-22)
- **simulate() stays pure** — single function, input in / result out. Event logging can wrap it later.
- **No custom map editor** — objectives and deploy zones live in GridConfig.tres, edited in Inspector.
- **HeadlessSim updated** — now uses `CombatSimulator.new()` directly instead of loading HexMoveDemo.gd.
- **Terrain v1: grass, forest, water** — grass = normal, forest = slow + cover, water = impassable. More types later.
- **Terrain tiles painted in TileMapLayer** — editor workflow, not code.

---

## Reference Links
- [Godot Scene Organization](https://docs.godotengine.org/en/stable/tutorials/best_practices/scene_organization.html)
- [Custom Resources](https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html)
- [GDScript Exports](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_exports.html)
- [TileMapLayer](https://docs.godotengine.org/en/stable/classes/class_tilemaplayer.html)
- [AStar2D](https://docs.godotengine.org/en/stable/classes/class_astar2d.html)
- [@tool Scripts](https://docs.godotengine.org/en/stable/tutorials/plugins/running_code_in_the_editor.html)

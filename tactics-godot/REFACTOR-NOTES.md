# Godot Refactor Notes — Developer Testing Toolkit

> **Branch:** `godot-refactor` (branched from `tactics-prototype` at tag `prototype-v1`)
> **Started:** 2026-02-22
> **Focus shift:** 2026-02-27 — reframed as **developer testing tool**, not game prototype
> **Goal:** A Godot-native toolkit that 4 teammates can use to test game feel and balance

---

## Project Focus

This is a **developer testing tool**, not a shipped game. The final game design is uncertain — we don't know which variation or permutation will be the product. This tool lets the team rapidly experiment with:

- Grid dimensions, deployment zones, objective positions
- Unit stats, formation rules, combat mechanics
- Terrain types and their gameplay effects
- AI behavior, pathfinding, movement patterns
- Visual presentation (view modes, trails, animations)

**The tool must work within Godot's structure** using Godot best practices: TileMapLayer for hex grids, Control nodes for HUD, @export for configuration, @tool for editor preview, signals for decoupling, Resources for data.

---

## The Three Goals

### 1. Everything Tweakable Without Code
Every gameplay value — hex grid size, deployment zones, melee range, unit stats, formation sizes, objective positions, VP scoring, colors, animation speeds — must be editable from the Godot Inspector without touching code.

**Godot tools:** Custom Resources (`.tres` files), `@export` annotations with ranges/groups, `@tool` scripts for live preview.

### 2. Godot-Native Architecture
Use Godot's built-in tools instead of reinventing them:
- **TileMapLayer** for hex grid rendering (not draw_* calls for 2,240 tiles/frame)
- **Control nodes** for HUD panels (not draw_rect/draw_string)
- **CanvasLayer** for UI (separate coordinate space from world)
- **Signals** for node communication (not parent references)
- **Scenes** for composable UI components

**Exception:** Dynamic per-frame visuals (trails, tokens, combat sparks) stay as draw_* — Control nodes aren't suited for this.

### 3. Team Collaboration
4 teammates work simultaneously without merge conflicts:

| Role | Edits | Files touched |
|------|-------|---------------|
| **Designer** | Unit stats, grid size, terrain, combat rules | `.tres` files in `resources/` |
| **Artist** | Sprites, tileset, UI theme | `sprites/`, `terrain/`, `.tres` texture fields, theme resource |
| **Programmer** | Simulation logic, AI, new systems | `scripts/*.gd`, controller scripts |
| **Tester** | Deploy configs, headless sim runs, benchmarks | `deploy.json`, `sim_results/` |

---

## Current State (post Phase 8)

| File | Lines | Role |
|------|-------|------|
| `HexMoveDemo.gd` | ~1,858 | Orchestrator: input, deploy, remaining HUD draw_* |
| `scripts/game_state.gd` | 122 | Centralized mutable state (46 vars, 2 enums, 6 signals) |
| `scripts/battle_renderer.gd` | 865 | Child Node2D: tiles, trails, tokens, sim rendering |
| `scripts/hud/top_bar.gd` | 124 | TopBar: phase text, view modes, progress bar, replay/summary |
| `scripts/hud/unit_select_popup.gd` | 60 | UnitSelectPopup: unit type selection modal |
| `scripts/hud/ds_turn_popup.gd` | 55 | DSTurnPopup: DS arrival turn selection modal |
| `scripts/hud/scoreboard.gd` | 98 | Scoreboard: VP per turn table with preview delta |
| `scripts/hud/fate_chart.gd` | 231 | FateChart: per-unit stats with fate change highlighting |
| `scripts/hex_math.gd` | 94 | Pure hex math (static class) |
| `scripts/combat_simulator.gd` | 948 | Simulation, AI, pathfinding, combat |
| `scripts/resources/*.gd` | 5 files | UnitStats, GridConfig, BattleConfig, TerrainType, VisualConfig |
| `resources/**/*.tres` | 13 files | 5 units + 3 config + 3 terrain + 1 theme |
| `scenes/hud/*.tscn` | 5 files | TopBar, UnitSelectPopup, DSTurnPopup, Scoreboard, FateChart scenes |
| `HeadlessSim.gd` | 304 | CLI simulation runner (uses CombatSimulator directly) |

**Solved:** Unit stats editable in Inspector, config values in `.tres` files, simulation engine decoupled, battle rendering extracted, all visual params (colors, alphas, widths, animation speeds) in VisualConfig resource, mutable state centralized in GameState with signals defined.

**Anti-patterns remaining:**
1. Most HUD still drawn via draw_* calls — TopBar, popups, scoreboard, fate chart migrated; 6 panels remain
2. Tiles drawn per-frame in code (2,240 draw calls) — TileMapLayer exists but unused visually
3. Most signals not yet wired — TopBar connects to 4 signals; other nodes still call methods directly

---

## Target Architecture

### Scene Tree

```
BattleTestbed (Node2D)                    — root scene, thin orchestrator
│
├── GameState (Node)                      — all mutable state + signals
│   Signals:
│     sim_changed()
│     phase_changed(phase: int)
│     hover_changed(hex: Vector2i)
│     view_mode_changed(mode: int)
│     unit_placed(uid: int)
│     replay_changed(turn: int)
│
├── HexGrid (Node2D, @tool)              — hex grid visualization
│   ├── TerrainLayer (TileMapLayer)      — hex tiles, terrain types (GPU-batched)
│   └── OverlayLayer (Node2D)           — deploy zones, obj auras, hover, heatmap
│
├── BattleRenderer (Node2D)              — trails, tokens, combat sparks
│   (keeps draw_* — highly dynamic per-frame rendering)
│
├── SimulationBridge (Node)              — wraps CombatSimulator, manages sim lifecycle
│
├── DeployController (Node)              — input handling, placement, preview
│
├── ReplayController (Node)              — replay mode state + navigation
│
├── HUD (CanvasLayer)                    — all UI in separate coordinate space
│   ├── TopBar (HBoxContainer)           — phase info, VP, view mode buttons
│   ├── Scoreboard (PanelContainer)      — VP per turn table
│   ├── FateChart (PanelContainer)       — per-unit stats chart
│   ├── CombatLog (PanelContainer)       — scrollable play-by-play
│   │   └── ScrollContainer + RichTextLabel
│   ├── NarrativePanel (PanelContainer)  — preview unit's projected fate
│   ├── TrailTooltip (PanelContainer)    — hover tooltip (follows cursor)
│   ├── UnitSelectPopup (CenterContainer) — unit type selection modal
│   ├── DSTurnSelectPopup (CenterContainer) — deep strike turn selection
│   ├── ShiftSummaryPopup (CenterContainer) — timeline shifted popup
│   │   └── ScrollContainer + RichTextLabel
│   ├── BattleSummaryPopup (CenterContainer) — full battle summary
│   │   └── ScrollContainer + RichTextLabel
│   └── ViewModeTooltip (PanelContainer) — cursor-following hint
│
└── Config (Node)                        — preloads .tres resources, exposes API
```

### Signal Flow

```
DeployController ──writes──▶ GameState ◀──reads── BattleRenderer
      │                          │                       │
      │ calls                    │ signals:              │
      ▼                          │                       ▼
SimulationBridge                 │ sim_changed ───▶ Scoreboard, FateChart,
      │                          │                  CombatLog, BattleRenderer
      ▼                          │
CombatSimulator                  │ phase_changed ──▶ TopBar, DeployController
(RefCounted)                     │
                                 │ hover_changed ──▶ BattleRenderer,
                                 │                    TrailTooltip
                                 │
                                 │ view_mode_changed ──▶ BattleRenderer
                                 │
                                 │ unit_placed ──▶ ShiftSummaryPopup
                                 │
                                 │ replay_changed ──▶ BattleRenderer,
                                 │                     TopBar
```

### Custom Resources

```
resources/
├── config/
│   ├── grid_config.tres        — COLS, ROWS, HEX_SIZE, deploy zones, objectives
│   ├── battle_config.tres      — COMBAT_RANGE, OC_RADIUS, CAVALRY_AGGRO, VP rules
│   └── visual_config.tres      — colors, font sizes, trail opacities, animation speeds (NEW)
├── units/
│   ├── infantry.tres           — all Infantry stats
│   ├── cavalry.tres
│   ├── artillery.tres
│   ├── deep_strike.tres
│   └── archer.tres
└── terrain/
    ├── grass.tres              — move_cost=1, cover=0, passable=true
    ├── forest.tres             — move_cost=2, cover=1, passable=true
    └── water.tres              — passable=false
```

### Resource: VisualConfig (Phase 8 — DONE)

`scripts/resources/visual_config.gd` — 207 lines, 91 `@export` vars in 16 groups. Both HexMoveDemo and BattleRenderer `preload()` independently.

```gdscript
class_name VisualConfig extends Resource

@export_group("Team Colors")
@export var color_p1: Color = Color(0.28, 0.58, 1.00, 1.0)
@export var color_p2: Color = Color(1.00, 0.35, 0.28, 1.0)

@export_group("Trail Ribbon")
@export_range(0.0, 1.0) var ribbon_alpha: float = 0.6
@export_range(0.1, 2.0) var ribbon_width: float = 0.7

@export_group("Animation")
@export_range(0.1, 2.0, 0.1, "suffix:s") var full_mode_speed: float = 0.3
@export_range(0.1, 2.0, 0.1, "suffix:s") var shift_pulse_period: float = 0.6
# ... 91 total exports covering colors, alphas, widths, radii,
#     animation speeds, disruption visuals, fate icons, terrain, etc.
```

---

## Key Godot Patterns

### TileMapLayer for Hex Grid
- Tile Shape: Hexagon, Flat Top, Odd Column offset
- Custom Data Layers: `terrain_type` (String), `move_cost` (float), `cover_bonus` (int)
- `local_to_map()` / `map_to_local()` replace manual `pixel_to_hex()` / `hex_to_pixel()`
- GPU-batched rendering replaces 2,240 per-frame draw calls

### Control Nodes for HUD
- **CanvasLayer** separates UI from world — no cam_offset/cam_zoom math needed
- **PanelContainer** for bordered panels with automatic sizing
- **RichTextLabel** for colored text (combat log, summary popups)
- **GridContainer** for tabular data (scoreboard, fate chart)
- **ScrollContainer** for scrollable content (combat log, summaries)
- **Godot Theme resource** for consistent styling across all panels

### @export for Inspector Editability
```gdscript
@export_category("Grid")
@export_range(8, 100) var cols: int = 56
@export_range(8, 100) var rows: int = 40
```

### @tool for Editor Preview
- HexGrid.gd as `@tool` — see grid and deploy zones in editor
- Objective positions preview without running the game

### Signals for Decoupling
```gdscript
# GameState.gd
signal sim_changed()
signal phase_changed(phase: int)
signal hover_changed(hex: Vector2i)
signal view_mode_changed(mode: int)
signal unit_placed(uid: int)
signal replay_changed(turn: int)
```

---

## What STAYS as draw_* Code

These are highly dynamic, per-frame rendering — Control nodes would make them worse:

- **Spacetime worm trails** — ribbons, ghost tokens, caterpillar taper
- **Combat sparks** — crossed swords at combat locations
- **Disruption visuals** — jagged purple lines, X marks
- **Trail hover glow** — bright formation hex highlights
- **Changed mode crossfade** — old/new path animation
- **Fate icons during preview** — sword/death/survival on map
- **Unit tokens** — sprite-based rendering with frame animation
- **Deploy overlay tints** — objective auras, zone highlights, heatmap

All of these stay in BattleRenderer (Node2D with draw_*).

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

### Completed Phases (Foundation)

#### Phase 0: Resource Definitions — DONE
Created 4 Resource class scripts (`UnitStats`, `GridConfig`, `BattleConfig`, `TerrainType`) and 10 `.tres` files (5 units + 2 config + 3 terrain). All pass syntax check.

#### Phase 1: Resource Bridge — DONE
Replaced all `const` blocks at the top of HexMoveDemo.gd with resource-backed property getters. Game logic unchanged — still references `COLS`, `COMBAT_RANGE`, etc., but values now come from `.tres` files.

#### Phase 2: Terrain System — DONE
Added `terrain_data.json`, terrain query functions, terrain tint overlay in `_draw_tile()`, passability checks in deploy logic. TileMapLayer child node added to scene (placeholder for future tile-based rendering).

#### Phase 3: Extract HexMath — DONE
Extracted pure hex math into `scripts/hex_math.gd` (94 lines). Static `class_name HexMath` — no scene tree dependency. HexMoveDemo keeps one-line wrapper functions so call sites don't change.

#### Phase 4: Extract CombatSimulator — DONE
Extracted simulation engine into `scripts/combat_simulator.gd` (948 lines). `class_name CombatSimulator extends RefCounted` — owns AStar2D, AI targeting, combat rolls, and the main `simulate()` loop. HeadlessSim.gd now uses CombatSimulator directly. HexMoveDemo keeps thin wrappers.

#### Phase 5: Extract BattleRenderer — DONE
Extracted 862 lines of battle drawing code into `scripts/battle_renderer.gd` as a child Node2D at z_index=-1. BattleRenderer reads state from `_parent` (HexMoveDemo). HexMoveDemo._draw() now only handles HUD overlays.

#### Phase 6: Extract HUDRenderer (Node2D) — SKIPPED
> Originally planned as another Node2D child with draw_* calls. **Skipped in favor of Phase 7** (Control nodes). The draw_*-based HUD was an intermediate step that would have been thrown away. Going directly to Control nodes is the right approach.

### Migration Phases (Godot-Native Architecture)

#### Phase 7: GameState Extraction — DONE
- Created `scripts/game_state.gd` (122 lines, `class_name GameState extends Node`)
- Moved 46 mutable state vars + 2 enums (Phase, ViewMode) from HexMoveDemo.gd into GameState
- Added 6 signals: `sim_changed`, `phase_changed`, `hover_changed`, `view_mode_changed`, `unit_placed`, `replay_changed`
- HexMoveDemo: state access via `_state.xxx`, enums via `GameState.Phase.XXX` / `GameState.ViewMode.XXX`
- BattleRenderer: 71 state refs changed from `_parent.xxx` to `_state.xxx`, 20 enum refs updated; 137 config/method refs stay as `_parent.xxx`
- Signal emissions added at 11 state transition points (guarded with old != new checks where appropriate)
- All tests pass. Zero behavior change.

#### Phase 8: VisualConfig Resource — DONE
- Created `scripts/resources/visual_config.gd` (207 lines, 91 @export vars in 16 groups)
- Created `resources/config/visual_config.tres` with all defaults
- HexMoveDemo.gd: 8 `const C_xxx` → property getters backed by `_visual`, animation params wired
- battle_renderer.gd: ~80+ inline Color/alpha/width values → `_v.xxx` references
- Both files preload the resource independently (decoupled)
- **Pure data extraction — no logic changes, all tests pass.**

#### Phase 9: HUD → Control Nodes — IN PROGRESS

##### Phase 9.1: TopBar + Infrastructure — DONE
- Created `scenes/hud/`, `scripts/hud/`, `resources/themes/` directories
- Created `resources/themes/hud_theme.tres` — shared Godot Theme (PanelContainer, Label, Button styles)
- Added 11 HUD @export vars to VisualConfig (hud_bg, text colors, button colors, view mode colors)
- Created `scripts/hud/top_bar.gd` (124 lines, `class_name TopBar extends PanelContainer`)
- Created `scenes/hud/top_bar.tscn` — PanelContainer with VBox, MainRow, ViewModes, ProgressBar, ButtonRow
- TopBar connects to 4 GameState signals: `phase_changed`, `sim_changed`, `view_mode_changed`, `unit_placed`
- TopBar emits `replay_requested` and `summary_requested` signals (HexMoveDemo connects to these)
- View mode buttons are clickable + keyboard shortcuts (1-4) both work
- TopBar hides during replay mode (BattleRenderer has its own replay HUD)
- CanvasLayer at layer=10, created in HexMoveDemo._ready() after BattleRenderer
- `_draw_hud()` hollowed out (body → `pass`), REPLAY/SUMMARY click rects removed from `_input()`
- HexMoveDemo.gd: 2,136 → 2,088 lines (net -48)

##### Phase 9.2: Deploy Popups — DONE
- Created `scripts/hud/unit_select_popup.gd` (60 lines, `class_name UnitSelectPopup extends ColorRect`)
- Created `scripts/hud/ds_turn_popup.gd` (55 lines, `class_name DSTurnPopup extends ColorRect`)
- Created `scenes/hud/unit_select_popup.tscn` and `scenes/hud/ds_turn_popup.tscn`
- ColorRect root = dim overlay (`Color(0,0,0,0.6)`, `mouse_filter=STOP` blocks clicks behind)
- CenterContainer → PanelContainer → VBox (header Label + HBox of Buttons)
- Both use `init(state: GameState)`, sync visibility via `_process()` checking state flags
- UnitSelectPopup emits `unit_selected(type: String)`, DSTurnPopup emits `turn_selected(turn: int)`
- HexMoveDemo connects signals → `_on_unit_selected()` / `_on_ds_turn_selected()` handlers
- Removed: `_draw_unit_select()`, `_draw_ds_turn_select()`, `_handle_unit_select_click()`, `_handle_ds_turn_click()`, popup draw calls in `_draw()`, popup input routing in `_input()`
- HexMoveDemo.gd: 2,088 → ~1,988 lines (net -100)
- **Pure UI extraction — no logic changes, all tests pass.**

##### Phase 9.3: Scoreboard — DONE
- Created `scripts/hud/scoreboard.gd` (98 lines, `class_name Scoreboard extends PanelContainer`)
- Created `scenes/hud/scoreboard.tscn` — PanelContainer anchored top-right, GridContainer with 3 columns
- Dynamic row creation in `_build_grid()` based on `_battle.turns` (config-driven)
- Connects to `sim_changed` signal, reads `confirmed_sim`/`preview_sim` VP data
- Preview delta row shows +/- from `_state.preview_diff.score_delta`
- Visibility synced with `show_analytics_ui` (TAB toggle) and `replay_mode`
- `mouse_filter=IGNORE` — clicks pass through to map
- Removed `_draw_scoreboard()` function and 2 call sites from HexMoveDemo.gd
- HexMoveDemo.gd: ~1,988 → ~1,943 lines (net -45)
- **Pure UI extraction — no logic changes, all tests pass.**

##### Phase 9.4: FateChart — DONE
- Created `scripts/hud/fate_chart.gd` (231 lines, `class_name FateChart extends PanelContainer`)
- Created `scenes/hud/fate_chart.tscn` — PanelContainer with VBoxContainer of dynamic rows
- Each unit row = PanelContainer (bg highlight) → HBoxContainer → 7 Labels (Unit, Died, O1-O3, Kills, Dmg)
- Row highlighting via StyleBoxFlat: green (now_survives), red (now_dies), yellow (shifted)
- Team divider (HSeparator) between P1 and P2 unit rows
- Connects to `sim_changed` signal, reads sim data + `preview_diff.fate_changes`
- Duplicated `_unit_prefix()` helper (5-value match from UnitStats.prefix)
- Added VBoxContainer wrapper ("AnalyticsPanel") to auto-stack Scoreboard + FateChart on right side
- Modified `scoreboard.tscn` — removed anchor/offset (VBox wrapper handles positioning)
- Removed `_draw_unit_fate()` function (98 lines) and 2 call sites from HexMoveDemo.gd
- HexMoveDemo.gd: ~1,943 → ~1,858 lines (net -85)
- **Pure UI extraction — no logic changes, all tests pass.**

##### Phase 9.5+: Remaining Panels — TODO
Build each panel as a Godot Control node tree, connect to GameState signals, remove corresponding draw_* code.

Panels in priority order:
1. ~~TopBar~~ — **DONE** (Phase 9.1)
2. ~~UnitSelectPopup + DSTurnPopup~~ — **DONE** (Phase 9.2)
3. ~~Scoreboard~~ — **DONE** (Phase 9.3)
4. ~~FateChart~~ — **DONE** (Phase 9.4)
5. CombatLog — ScrollContainer + RichTextLabel
6. TrailTooltip — small, cursor-following
7. NarrativePanel — text list
8. ShiftSummaryPopup — modal with scroll
9. BattleSummaryPopup — modal with scroll
10. ViewModeTooltip — cursor-following

#### Phase 10: Controller Extraction — TODO
- Create `scripts/deploy_controller.gd` — input handling, placement logic
- Create `scripts/replay_controller.gd` — replay navigation
- Move `_input()` logic out of HexMoveDemo.gd
- Controllers write to GameState, other nodes react via signals

#### Phase 11: TileMapLayer Visual Migration — TODO
- Configure existing TerrainLayer TileMapLayer for visual rendering
- Set up hex tileset with terrain-specific tiles in Godot editor
- Remove `_draw_tile()` from battle_renderer.gd (~95 lines)
- Eliminate 2,240 per-frame draw calls
- Keep OverlayLayer (Node2D) for dynamic highlights (deploy zones, hover, heatmap)

#### Phase 12: @tool Editor Preview — TODO
- Add `@tool` to HexGrid script — see grid in editor
- Deploy zone visualization without running game
- Objective position preview in editor

---

## Decisions Log

### 2026-02-22
- **simulate() stays pure** — single function, input in / result out
- **No custom map editor** — objectives and deploy zones in GridConfig.tres, edited in Inspector
- **HeadlessSim updated** — uses `CombatSimulator.new()` directly
- **Terrain v1: grass, forest, water** — more types later
- **Terrain tiles painted in TileMapLayer** — editor workflow, not code

### 2026-02-27
- **Project reframed as developer testing tool** — not a game prototype
- **Phase 6 (Node2D HUDRenderer) skipped** — going directly to Control nodes
- **All visual features preserved** — 4 view modes, spacetime worms, all UI panels
- **Docs updated first, then architecture** — align team before writing code
- **Dynamic rendering stays as draw_*** — trails, tokens, sparks not suited for Control nodes

---

## Reference Links
- [Godot Scene Organization](https://docs.godotengine.org/en/stable/tutorials/best_practices/scene_organization.html)
- [Custom Resources](https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html)
- [GDScript Exports](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_exports.html)
- [TileMapLayer](https://docs.godotengine.org/en/stable/classes/class_tilemaplayer.html)
- [AStar2D](https://docs.godotengine.org/en/stable/classes/class_astar2d.html)
- [@tool Scripts](https://docs.godotengine.org/en/stable/tutorials/plugins/running_code_in_the_editor.html)
- [Control Nodes](https://docs.godotengine.org/en/stable/tutorials/ui/index.html)
- [CanvasLayer](https://docs.godotengine.org/en/stable/classes/class_canvaslayer.html)
- [Signals](https://docs.godotengine.org/en/stable/getting_started/step_by_step/signals.html)

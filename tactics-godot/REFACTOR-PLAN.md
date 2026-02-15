# Refactor Plan: Single-File → Godot Node Architecture

## Why this exists
`HexMoveDemo.gd` is a ~1,400-line single file containing all game logic, rendering, input, and UI. This works for prototyping but blocks the team from:
- Working on UI without risking simulation code
- Using the Godot editor's scene tree to inspect/toggle/rearrange components
- Visually tweaking panel positions or exported vars in the inspector

This document is the plan for when we're ready to break it apart.

---

## Target Scene Tree

```
HexMoveDemo (Node2D)
├── HexGridRenderer (Node2D)      ← grid, tokens, trails, camera
├── HUDLayer (CanvasLayer)        ← scoreboard, fate chart, combat log, HUD bar
├── DeployController (Node)       ← input handling, placement, sim orchestration
└── ReplayController (Node)       ← replay mode drawing + navigation
```

Plus three autoloads (global singletons):
```
HexMath          ← pure hex math functions
Pathfinder       ← A* pathfinding, owns AStar2D
BattleSimulator  ← simulate(), combat rolls, AI targeting
```

And one shared data object:
```
GameState (Resource or autoload)  ← all mutable runtime state
```

---

## Extraction Order (safest first)

### Phase 1: Autoloads (low risk, no visual changes)

**1a. HexMath → `hex_math.gd`**
- Lines: 70–155 (current file)
- Functions: `hex_to_pixel`, `pixel_to_hex`, `hex_corners`, `is_valid_hex`, `hex_id`, `id_to_hex`, `hex_neighbors`, `hex_dist`, `_offset_to_cube`
- Constants to move: `COLS`, `ROWS`, `HEX_SIZE`, `FLAT_DIRS_EVEN`, `FLAT_DIRS_ODD`
- Dependencies: none (pure math)
- Camera state (`cam_offset`, `cam_zoom`) stays OUT — it belongs to the renderer. Pass as args to `hex_to_pixel`/`pixel_to_hex`.
- Register as autoload in Project Settings

**1b. Pathfinder → `pathfinder.gd`**
- Lines: 157–191
- Functions: `build_astar`, `find_path`
- Owns: `astar: AStar2D`
- Dependencies: reads from HexMath autoload
- Known perf issue: `build_astar()` called inside `find_path()` — rebuild once per turn instead

**1c. BattleSimulator → `battle_simulator.gd`**
- Lines: 193–531
- Functions: `simulate`, `_pick_target`, `_nearest_enemy_in_range`, `_roll_combat`, `_apply_wounds`
- Constants to move: `INFANTRY`, `CAVALRY`, `OBJECTIVES`, `TURNS`, `COMBAT_RANGE`, `UNIT_NAMES`
- Dependencies: reads HexMath (`hex_dist`, `hex_id`), calls Pathfinder (`find_path`)
- This is already a pure function — takes input array, returns result dict. Zero scene access.

**Validation:** After each extraction, run `run_tests.ps1` and playtest. Behavior must be identical.

---

### Phase 2: GameState (medium risk)

**2. GameState → `game_state.gd`**

Extract all mutable runtime state into a shared Resource or autoload:

```
phase, active_player, deploy_unit_type
placed_p1, placed_p2
confirmed_sim, preview_sim, preview_diff
hover_hex
anim_turn, anim_frac
log_lines, log_scroll
replay_mode, replay_turn
drag_active, drag_start, cam_start
```

Every node reads/writes through this object instead of local vars. This is the prerequisite for separating input from rendering.

---

### Phase 3: Rendering split (the hard part)

**3a. HexGridRenderer → `hex_grid_renderer.gd` (Node2D)**
- Owns: `cam_offset`, `cam_zoom`, `tile_tex`, `_obj_control`
- Functions to move: `_draw_tile`, `_draw_sim`, `_draw_unit_token`, `_draw_banner`, `_draw_swords`, `_zoom`
- Must call `queue_redraw()` when GameState changes (connect via signal)

**Surgery required on `_draw_tile`:** Currently mixes base hex rendering with game overlays (zone tints, objective control colors, preview diff glow, hover highlight). Split into:
1. `_draw_hex_base(col, row)` — polygon fill, outline, tile texture
2. `_draw_hex_overlays(col, row)` — zone tints, objective aura, hover, diff glow, banner

This separation lets future work swap rendering approaches (e.g., TileMap, 3D) without touching game logic.

**3b. HUDLayer → `hud_layer.gd` (CanvasLayer)**
- Functions to move: `_draw_hud`, `_draw_scoreboard`, `_draw_unit_fate`, `_draw_combat_log`
- Reads: GameState (phase, placed counts, active_player, deploy_unit_type, anim_turn, preview_diff, log_lines, log_scroll)
- Reads: whichever sim dict is active (confirmed or preview)
- CanvasLayer means it draws on top regardless of camera — no coordinate transforms needed

---

### Phase 4: Controllers (medium risk)

**4a. DeployController → `deploy_controller.gd` (Node)**
- Functions: `_input`, `_handle_deploy_click`, `_is_deploy_hex`, `_recalc_confirmed_sim`, `_recalc_preview_sim`, `_compute_sim_diff`
- Writes to GameState: phase, placed_p1/p2, active_player, hover_hex, confirmed_sim, preview_sim, preview_diff, anim_turn/frac
- Emits signals when sim changes (HexGridRenderer and HUDLayer connect to redraw)

**4b. ReplayController → `replay_controller.gd` (Node)**
- Functions: `_draw_replay` and replay input handling (left/right/escape)
- Reads: GameState (confirmed_sim, replay_turn)
- Mostly self-contained — lowest coupling of all components

---

## Data Flow After Refactor

```
User Input
    │
    ▼
DeployController ──writes──▶ GameState ◀──reads── HexGridRenderer
    │                            │                        │
    │ calls                      │                   queue_redraw()
    ▼                            │                        │
BattleSimulator ◀── Pathfinder   ▼                        ▼
    │               ◀── HexMath  signals ──▶ HUDLayer    screen
    │                                              │
    └── returns sim dict ──▶ GameState             ▼
                                                  screen
```

Signals to define:
- `GameState.sim_changed` → HexGridRenderer, HUDLayer redraw
- `GameState.phase_changed` → HUDLayer updates text
- `GameState.hover_changed` → HexGridRenderer redraws hover highlight
- `DeployController.unit_placed` → for future audio/VFX hooks

---

## What NOT to change

- **Unit stat definitions** (`INFANTRY`, `CAVALRY`) stay as const dicts, not custom Resources. They're simple and readable as-is.
- **`simulate()` stays as a pure function** returning a dict. Do not make it stateful or event-driven. Its purity is a feature.
- **No custom classes for units.** Dicts work fine at this scale. If we hit 10+ unit types, reconsider.
- **No TileMap migration yet.** The draw_* approach is fine for the prototype. TileMap is a separate decision.

---

## Risk Checklist

| Risk | Mitigation |
|------|-----------|
| Breakage during extraction | Run `run_tests.ps1` + playtest after every phase |
| Autoload initialization order | HexMath first, then Pathfinder, then BattleSimulator |
| Signal spaghetti | Keep signals minimal — only `sim_changed`, `phase_changed`, `hover_changed` |
| Performance regression | Profile if sim recalc feels slower after indirection |
| Merge conflicts with in-progress work | Do the refactor on a dedicated branch, merge when stable |

---

## When to Pull the Trigger

Do this refactor when any of these become true:
- Two or more team members need to edit different parts simultaneously
- A new feature requires a second scene or node type (e.g., army selection screen)
- The file exceeds ~2,000 lines and becomes hard to navigate
- Someone needs to use the Godot inspector to tweak visual properties

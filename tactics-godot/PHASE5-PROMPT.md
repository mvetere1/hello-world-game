# Phase 5 Handoff Prompt — BattleRenderer Extraction (Node2D Child)

**Task: Continue the HexMoveDemo.gd refactor — Phase 5 (BattleRenderer extraction)**

**Context:** You're continuing a multi-phase refactor of `tactics-godot/HexMoveDemo.gd` (currently 2,996 lines). Phases 0–4 are done and committed on branch `godot-refactor`. Read `tactics-godot/REFACTOR-NOTES.md` for the full plan and target architecture. Read `tactics-godot/CLAUDE.md` for dev rules.

**Your job: Phase 5 only.** Extract ~670 lines of battle drawing code into `scripts/battle_renderer.gd` as a **child Node2D** with its own `_draw()`. Stop after Phase 5 is working. Do NOT start Phase 6.

---

## Why Node2D, not RefCounted

The target architecture (REFACTOR-NOTES.md) calls for proper Godot scene tree composition:
- BattleRenderer draws battle visuals (tiles, trails, tokens) on its own canvas via `_draw()`
- HUDLayer (Phase 6) will be a CanvasLayer for screen-space UI
- Z-ordering handled by the scene tree, not draw call order
- Each node owns its own drawing — no `_parent.draw_*()` passthrough
- Sets up for future: visibility toggling, shader effects, TileMapLayer migration

## Pre-step: Move state mutations out of `_draw()`

Drawing functions must be pure — no state writes. These need to move to `_process()`:

1. **Line 1422** — `_obj_control = _compute_obj_control(draw_sim)` inside `_draw()`. Move to `_process()`.
2. **Line 2759** — `_obj_control = sim.get("obj_control", [0, 0, 0])` inside `_draw_final_state()`. Move to `_process()`.
3. **Line 2795** — `_obj_control = obj_hist[replay_turn]` inside `_draw_replay()`. Move to `_process()`.

Gate them in `_process()` the same way their draw calls are gated (check phase, view_mode, replay_mode). After this pre-step, `_draw()` and all draw functions only **read** state.

## Functions to extract into BattleRenderer

These are the battle/map drawing functions (NOT HUD). Move them into `scripts/battle_renderer.gd`:

| Function | Line | What it does |
|----------|------|--------------|
| `_draw_tile()` | 1499 | Single hex tile rendering (terrain, zones, objectives, heatmap, hover) |
| `_draw_unit_final()` | 1602 | End-state unit token (eliminated X or live token) |
| `_draw_single_timeline()` | 1629 | One unit's ghost trail for one turn (ribbon, formation hexes, combat sparks) |
| `_draw_sim()` | 1722 | Main sim renderer (hover glow, changed crossfade, timelines, tokens, combat icons) |
| `_draw_unit_token()` | 2111 | Unit sprite at position (spritesheet frame selection, fallback circle) |
| `_draw_unit_token_scaled()` | 2151 | Scaled variant for caterpillar taper segments |
| `_draw_banner()` | 2256 | Objective flag icon |
| `_draw_swords()` | 2269 | Crossed swords combat indicator |
| `_draw_final_state()` | 2751 | FINAL view mode (end positions + preview unit trail) |
| `_draw_replay()` | 2778 | Replay mode (snapshots at replay_turn + replay HUD bar) |

**Total:** ~670 lines.

**NOT extracted (stays in HexMoveDemo.gd):** `_draw_hud()`, `_draw_scoreboard()`, `_draw_unit_fate()`, `_draw_combat_log()`, `_draw_preview_narrative()`, `_draw_trail_tooltip()`, `_draw_shift_summary()`, `_draw_battle_summary()`, `_draw_unit_select()`, `_draw_ds_turn_select()`. These are HUD — they'll move to a CanvasLayer in Phase 6.

## Architecture

### BattleRenderer (Node2D child)

```gdscript
# scripts/battle_renderer.gd
class_name BattleRenderer
extends Node2D

# Reference to parent for reading state
var _parent: Node2D

func init(parent: Node2D):
    _parent = parent

func _draw():
    # BattleRenderer owns all battle/map drawing.
    # It reads state from _parent and draws on its own canvas.
    # HexMoveDemo._draw() no longer calls any battle draw functions.
    #
    # The drawing logic that currently lives in HexMoveDemo._draw()
    # (lines 1360-1498 approximately) must be split:
    #   - Battle portion (tile loop, fog overlay, _draw_sim, _draw_final_state,
    #     _draw_replay, background rect) → moves here
    #   - HUD portion (_draw_hud, _draw_scoreboard, etc.) → stays in HexMoveDemo._draw()

func draw_battle(sim: Dictionary, is_preview: bool):
    # Called from _draw(). Replaces the battle portion of HexMoveDemo._draw().
    pass

# All 10 extracted functions live here, calling self.draw_* (NOT _parent.draw_*)
# since this Node2D has its own canvas.
```

### Camera transform — CRITICAL CHANGE

Currently `hex_to_pixel()` bakes `cam_zoom` and `cam_offset` into every coordinate:
```gdscript
func hex_to_pixel(col, row) -> Vector2:
    ...
    return Vector2(x, y) * cam_zoom + cam_offset
```

And `hex_corners()` multiplies by `cam_zoom`. This means every draw call produces screen-space coordinates.

For a child Node2D, the **proper Godot way** is:
1. BattleRenderer sets its own `position = cam_offset` and `scale = Vector2(cam_zoom, cam_zoom)` in `_process()`
2. Draw functions use **world-space coordinates** (no cam_zoom/cam_offset multiplication)
3. Godot's transform pipeline handles the screen mapping

**However, this is a large change** that would touch hex_to_pixel(), hex_corners(), and every draw call that uses cam_zoom. It would also affect HUD drawing which must NOT be camera-transformed.

**Recommended approach for Phase 5:** Keep the existing camera math as-is. BattleRenderer draws at identity transform (position=0, scale=1) using the same screen-space coordinates HexMoveDemo currently uses. This is a pure code extraction — same visual output, zero rendering changes. Camera transform refactoring can happen later (or in Phase 6 when HUD moves to CanvasLayer, which is inherently screen-space).

### Scene tree setup

In HexMoveDemo._ready():
```gdscript
_battle_renderer = BattleRenderer.new()
_battle_renderer.init(self)
_battle_renderer.z_index = 0  # battle layer draws first
add_child(_battle_renderer)
# HexMoveDemo itself draws HUD on top (z_index default = 0, but drawn after child)
```

`queue_redraw()` in HexMoveDemo._process() should also call `_battle_renderer.queue_redraw()`.

### Draw orchestration split

Currently HexMoveDemo._draw() (line 1360) does everything. After extraction:

**BattleRenderer._draw()** handles:
- Background rect (if no terrain map)
- Replay mode → call `draw_replay()`
- FINAL view mode → call `draw_final_state()`, return
- Viewport culling + tile loop → call `draw_tile()` per hex
- Dark fog overlay (CHANGED mode)
- Sim rendering → call `draw_sim()`

**HexMoveDemo._draw()** keeps:
- `_draw_hud()`
- `_draw_scoreboard()`, `_draw_unit_fate()`, `_draw_combat_log()` (analytics)
- `_draw_preview_narrative()`, `_draw_trail_tooltip()`
- `_draw_shift_summary()`
- `_draw_battle_summary()`, `_draw_unit_select()`, `_draw_ds_turn_select()`
- "Change view" cursor tooltip
- Overlay popups

This means HexMoveDemo._draw() shrinks from ~140 lines of orchestration to ~60 lines (HUD only). The battle orchestration logic moves into BattleRenderer._draw().

## State BattleRenderer reads from _parent

| Category | Variables/Functions |
|----------|-------------------|
| Camera | `cam_offset`, `cam_zoom` |
| Grid | `HEX_SIZE`, `COLS`, `ROWS`, `TURNS` |
| Hex math | `hex_to_pixel()`, `hex_corners()`, `hex_id()`, `hex_dist()` |
| Animation | `anim_turn`, `anim_frac`, `_diff_flash_time` |
| Phase/Mode | `view_mode`, `ViewMode` enum, `phase`, `Phase` enum |
| Visuals | `unit_sprites`, `tile_tex`, `_terrain_data`, `_terrain_resources`, `_terrain_sprites`, `_get_terrain_at()`, `SPRITE_FRAMES` |
| Game state | `_obj_control`, `_team_color()`, `active_player`, `deploy_unit_type` |
| Sim data | `confirmed_sim`, `preview_sim`, `preview_diff` |
| Replay | `replay_mode`, `replay_turn` |
| Deploy | `hover_hex`, `deploy_heatmap`, `_heatmap_min`, `_heatmap_max`, `ds_legal_hexes`, `ds_arrival_turn`, `selecting_unit`, `ds_selecting_turn` |
| Hover | `hover_trail_uid` |
| Config | `_battle` resource (objectives), deploy zone constants |
| Colors | `C_BG`, `C_FIELD`, `C_STROKE`, `C_P1`, `C_P2`, `C_BANNER`, `C_COMBAT`, `C_SWORD`, `TURN_DURATION` |
| Icons | `_icon_death`, `_icon_survive` (used in shift summary fate icons drawn during battle) |
| Terrain map | `_terrain_map` (for background rect gating) |

## Steps

1. **Read** `tactics-godot/CLAUDE.md` and `tactics-godot/REFACTOR-NOTES.md` for full context
2. **Pre-step**: Move `_obj_control` writes from `_draw()`/`_draw_final_state()`/`_draw_replay()` into `_process()`. Run syntax check.
3. **Create** `tactics-godot/scripts/battle_renderer.gd` — `class_name BattleRenderer extends Node2D`
4. **Move orchestration**: Split HexMoveDemo._draw() — battle portion goes into BattleRenderer._draw(), HUD portion stays
5. **Move the 10 functions** listed above into BattleRenderer. All `draw_*` calls become `self.draw_*` (they already are implicitly — just remove any `_parent.` if you accidentally add it). State reads become `_parent.xxx`.
6. **Wire up** in HexMoveDemo:
   - `var _battle_renderer: BattleRenderer`
   - In `_ready()`: create, init, add_child
   - In `_process()`: call `_battle_renderer.queue_redraw()`
   - Remove battle orchestration from `_draw()` (keep HUD orchestration)
7. **Do NOT add wrapper functions** — unlike CombatSimulator, BattleRenderer owns its own _draw(). HexMoveDemo no longer calls battle draw functions directly.
8. **Run** `--import --quit` then `--check-only --quit`
9. **Run** headless sim to verify identical results (headless sim doesn't draw, so this confirms no state logic was broken)
10. **Visual playtest**: Tell the user to run the game and verify all view modes (1-4), replay, hover trails, deploy heatmap, objective banners look correct
11. **Do NOT commit** — ask the user first

## Key gotchas

- **When removing large code blocks (500+ lines), use a Python script to delete by line range, NOT the Edit tool.** The Edit tool can't handle old_strings that large.
- **After creating a new `class_name` file, run `--import --quit` before `--check-only`** to register the class.
- **BattleRenderer is a Node2D** — its `draw_*` calls draw on its own canvas. No `_parent.draw_*()` needed.
- **HexMoveDemo._draw() still runs** — Godot calls `_draw()` on both parent and child. HexMoveDemo draws HUD, BattleRenderer draws battle. Both draw every frame.
- **Draw order**: Child nodes draw after parent by default. Since BattleRenderer should draw UNDER the HUD, either: (a) set `_battle_renderer.z_index = -1`, or (b) have HexMoveDemo draw HUD in `_draw()` which runs after child draw. Test to confirm correct layering.
- **Dict mutation**: after modifying a dict from parent, write it back (`_parent.foo = foo`).
- **GDScript ternary**: `val if cond else fallback` (not `?:`).
- **hex_id()** is `col * 1000 + row` — never reverse with `% COLS`.
- **Godot executable**: `C:\Users\bigto\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe`
- **Syntax check**: `--headless --path tactics-godot --check-only --quit`
- **Import**: `--headless --path tactics-godot --import --quit`
- **Never auto-commit.** Ask before committing.
- **Always analyze before implementing** — present analysis and wait for approval.

## When to stop

Stop after Phase 5 is fully working (syntax check passes, headless sim identical, user has visually playtested). Then write a `PHASE6-PROMPT.md` handoff for HUDRenderer extraction (~1,250 lines → CanvasLayer with Control children). Do NOT start Phase 6.

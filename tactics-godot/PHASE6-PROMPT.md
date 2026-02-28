# Phase 6 Handoff Prompt — HUDRenderer Extraction (Node2D Child)

**Task: Continue the HexMoveDemo.gd refactor — Phase 6 (HUDRenderer extraction)**

**Context:** You're continuing a multi-phase refactor of `tactics-godot/HexMoveDemo.gd` (currently 2,171 lines). Phases 0–5 are done and committed on branch `godot-refactor`. Read `tactics-godot/REFACTOR-NOTES.md` for the full plan and target architecture. Read `tactics-godot/CLAUDE.md` for dev rules.

**Your job: Phase 6 only.** Extract ~670 lines of HUD drawing code into `scripts/hud_renderer.gd` as a **child Node2D** with its own `_draw()`. Stop after Phase 6 is working. Do NOT start further phases.

---

## Current Architecture (post Phase 5)

```
HexMoveDemo.gd (2,171 lines) — orchestrator: state, input, deploy, HUD drawing
scripts/battle_renderer.gd (862 lines) — child Node2D at z_index=-1: tiles, trails, tokens, sim
scripts/combat_simulator.gd (948 lines) — RefCounted: simulation engine
scripts/hex_math.gd (94 lines) — static hex math
```

BattleRenderer draws at z_index=-1 (under HUD). HexMoveDemo._draw() handles HUD overlay drawing.

## Pre-step: Move scroll clamp logic from `_draw()` to `_process()`

Drawing functions must be pure — no state writes. These need to move to `_process()`:

1. **Line 1519** — `shift_summary_scroll = clampi(...)` inside `_draw_shift_summary()`. Move to `_process()`.
2. **Line 2087** — `summary_scroll = clampi(...)` inside `_draw_battle_summary()`. Move to `_process()`.

Gate them in `_process()` the same way their draw calls are gated (check active states).

## Functions to extract into HUDRenderer

These are all HUD/UI drawing functions. Move them into `scripts/hud_renderer.gd`:

| Function | Line | What it does |
|----------|------|--------------|
| `_draw_hud()` | 1581 | Top bar (phase info, VP, view mode indicator, turn bar, buttons) |
| `_draw_shift_summary()` | 1502 | Timeline shifted popup + fate icons on map |
| `_generate_preview_narrative()` | 1642 | Builds narrative text array (data, not draw) |
| `_draw_preview_narrative()` | 1742 | Preview narrative panel |
| `_draw_trail_tooltip()` | 1771 | Trail hover tooltip |
| `_draw_scoreboard()` | 1852 | VP scoreboard |
| `_draw_unit_fate()` | 1901 | Unit fate chart |
| `_draw_combat_log()` | 1999 | Combat log panel |
| `_draw_battle_summary()` | 2053 | Full battle summary overlay |
| `_draw_unit_select()` | 2111 | Unit type selection popup |
| `_draw_ds_turn_select()` | 2143 | Deep strike turn selection popup |

Also move the data generation helpers that only serve HUD display:

| Function | Line | What it does |
|----------|------|--------------|
| `_generate_battle_summary()` | 1192 | Builds summary_lines array |

**Total:** ~670 lines of draw functions + ~100 lines of data helpers.

**NOT extracted:** `_draw()` orchestration stays in HexMoveDemo — it calls HUDRenderer methods instead of local ones.

## Architecture

### HUDRenderer (Node2D child)

```gdscript
# scripts/hud_renderer.gd
class_name HUDRenderer
extends Node2D

var _parent: Node2D

func init(parent: Node2D):
    _parent = parent

func _draw():
    # HUDRenderer draws HUD overlays on its own canvas.
    # Called by Godot after parent's _draw().
    # The orchestration logic stays in HexMoveDemo._draw() which calls
    # HUDRenderer methods (or HexMoveDemo._draw() could delegate to
    # HUDRenderer._draw() entirely).
    pass

# All extracted HUD functions live here.
# State reads become _parent.xxx.
# draw_* calls are self.draw_* (own canvas).
```

### Scene tree setup

In HexMoveDemo._ready():
```gdscript
_hud_renderer = HUDRenderer.new()
_hud_renderer.init(self)
_hud_renderer.z_index = 10  # HUD draws on top of battle layer
add_child(_hud_renderer)
```

### Draw orchestration

**Option A (recommended):** HexMoveDemo._draw() becomes a thin dispatcher that calls `_hud_renderer.draw_xxx()` methods. HexMoveDemo._draw() still decides WHAT to draw; HUDRenderer methods handle HOW.

**Option B:** Move all orchestration into HUDRenderer._draw(). HexMoveDemo._draw() becomes empty (or removed). This is cleaner but means HUDRenderer needs to know about phase, view_mode, etc. (it already reads them from `_parent`).

Choose whichever feels cleaner after reading the code.

### Z-ordering

- BattleRenderer: z_index = -1 (tiles, trails, tokens)
- HexMoveDemo: z_index = 0 (parent, draws nothing or minimal)
- HUDRenderer: z_index = 10 (all HUD on top)

## State HUDRenderer reads from _parent

| Category | Variables/Functions |
|----------|-------------------|
| Phase/Mode | `phase`, `Phase` enum, `view_mode`, `ViewMode` enum |
| Sim data | `confirmed_sim`, `preview_sim`, `preview_diff` |
| Deploy | `active_player`, `deploy_unit_type`, `selecting_unit`, `ds_selecting_turn`, `showing_shift_summary`, `shift_summary_lines`, `shift_summary_scroll`, `shift_summary_timer`, `shift_summary_diff`, `show_summary`, `summary_lines`, `summary_scroll` |
| Animation | `anim_turn`, `anim_frac` |
| Config | `TURNS`, `UNITS_PER_SIDE`, `UNIT_TYPES`, `OBJECTIVES`, `COMBAT_RANGE`, `OC_RADIUS` |
| Colors | `C_P1`, `C_P2`, `C_COMBAT`, `C_BANNER` |
| Icons | `_icon_death`, `_icon_survive`, `_icon_sword` |
| Mouse | `_mouse_pos`, `hover_hex`, `hover_trail_uid` |
| Placement | `placed_p1`, `placed_p2` |
| Analytics | `show_analytics_ui`, `_log_visible`, `log_lines`, `log_scroll` |
| Replay | `replay_mode`, `replay_turn` |
| Camera | `cam_zoom`, `cam_offset`, `hex_to_pixel()` |
| Hex math | `hex_id()`, `hex_dist()` |
| Unit sprites | `unit_sprites`, `SPRITE_FRAMES` |
| HEX_SIZE | `HEX_SIZE` |

## Special: _draw_shift_summary draws on battle canvas

`_draw_shift_summary()` (line 1502) draws BOTH:
- A text box (HUD, screen-space) — lines 1502-1551
- Fate icons on the map (battle-space, uses `hex_to_pixel`) — lines 1553-1580

Since the fate icons use `hex_to_pixel` and need to appear in battle-space, consider either:
- Keeping the fate icon drawing as a helper called by BattleRenderer during shift summary mode
- Or letting HUDRenderer draw them in screen-space too (since hex_to_pixel already bakes cam_zoom/cam_offset)

The simplest approach: move the entire function to HUDRenderer since all coordinates are already screen-space (hex_to_pixel includes camera transform).

## Steps

1. **Read** `tactics-godot/CLAUDE.md` and `tactics-godot/REFACTOR-NOTES.md` for full context
2. **Pre-step**: Move scroll clamp logic from draw functions into `_process()`. Run syntax check.
3. **Create** `tactics-godot/scripts/hud_renderer.gd` — `class_name HUDRenderer extends Node2D`
4. **Move the 11 draw functions + 2 data generators** listed above into HUDRenderer
5. **Update HexMoveDemo._draw()**: Replace local calls with `_hud_renderer.xxx()` calls
6. **Wire up** in HexMoveDemo:
   - `var _hud_renderer: HUDRenderer`
   - In `_ready()`: create, init, add_child with z_index=10
   - In `_process()`: call `_hud_renderer.queue_redraw()`
7. **Run** `--import --quit` then `--check-only --quit`
8. **Run** headless sim to verify identical results
9. **Visual playtest**: Tell user to verify ALL view modes (1-4), replay, hover trails, deploy heatmap, popups, tooltips, shift summary, battle summary
10. **Do NOT commit** — ask the user first

## Key gotchas

- **When removing large code blocks (500+ lines), use a Python script to delete by line range, NOT the Edit tool.**
- **After creating a new `class_name` file, run `--import --quit` before `--check-only`** to register the class.
- **HUDRenderer is a Node2D** — its `draw_*` calls draw on its own canvas. No `_parent.draw_*()` needed.
- **Godot draw order**: Parent draws first, then children by z_index. With z_index=10, HUDRenderer always draws on top.
- **_draw_shift_summary fate icons**: These use hex_to_pixel which already includes camera transform, so they work fine from HUDRenderer's canvas (same screen-space coordinates).
- **"Change view" tooltip**: Currently inline in _draw() — extract it as a function in HUDRenderer.
- **Dict mutation**: after modifying a dict from parent, write it back (`_parent.foo = foo`).
- **GDScript ternary**: `val if cond else fallback` (not `?:`).
- **Godot executable**: `C:\Users\bigto\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe`
- **Syntax check**: `--headless --path tactics-godot --check-only --quit`
- **Import**: `--headless --path tactics-godot --import --quit`
- **Never auto-commit.** Ask before committing.
- **Always analyze before implementing** — present analysis and wait for approval.

## When to stop

Stop after Phase 6 is fully working (syntax check passes, headless sim identical, user has visually playtested). Then update REFACTOR-NOTES.md to mark Phase 6 as DONE and note the new line counts. Do NOT start further phases.

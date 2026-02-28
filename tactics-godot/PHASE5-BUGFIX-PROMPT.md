# Phase 5 Bugfix — BattleRenderer Visual Playtest

**Task: Fix any visual bugs introduced by the Phase 5 BattleRenderer extraction**

**Context:** Phase 5 just extracted ~862 lines of battle drawing code from `HexMoveDemo.gd` into `scripts/battle_renderer.gd` (a child Node2D at z_index=-1). The headless simulation produces identical results, but the user reports a visual issue when switching to view mode 2 (CHANGED mode). The exact error hasn't been captured yet — **your first step is to investigate**.

---

## What was done in Phase 5

1. **Pre-step**: Moved `_obj_control` state mutations from `_draw()` into `_process()`, gated by phase/mode conditions
2. **Created** `scripts/battle_renderer.gd` (862 lines) — `class_name BattleRenderer extends Node2D`
3. **Extracted 10 functions** from HexMoveDemo.gd into BattleRenderer:
   - `_draw_tile`, `_draw_unit_final`, `_draw_single_timeline`, `_draw_sim`
   - `_draw_unit_token`, `_draw_unit_token_scaled`, `_draw_banner`, `_draw_swords`
   - `_draw_final_state`, `_draw_replay`
4. **BattleRenderer._draw()** now orchestrates: background rect, replay dispatch, FINAL mode dispatch, viewport-culled tile loop, fog overlay, sim drawing
5. **HexMoveDemo._draw()** now only handles HUD overlays (scoreboard, fate chart, tooltips, popups, etc.)
6. **Wiring**: BattleRenderer created in `_ready()`, `queue_redraw()` called in `_process()`

### Architecture

```
HexMoveDemo (Node2D, z_index=0) — state, input, HUD drawing
  ├── TerrainMap (TileMapLayer, z_index=-1) — terrain tiles (WIP)
  └── BattleRenderer (Node2D, z_index=-1) — tiles, trails, tokens, sim
```

BattleRenderer reads all state from `_parent` (reference to HexMoveDemo). All variable accesses are `_parent.xxx`. Draw calls use BattleRenderer's own canvas (no `_parent.draw_*`).

### Key files
- `tactics-godot/HexMoveDemo.gd` (2,171 lines) — orchestrator
- `tactics-godot/scripts/battle_renderer.gd` (862 lines) — battle drawing
- `tactics-godot/scripts/combat_simulator.gd` (948 lines) — simulation engine
- `tactics-godot/REFACTOR-NOTES.md` — full refactor plan and progress

## Known issue

**View mode 2 (CHANGED mode)** may have a bug. The user saw something wrong when pressing 2 during deployment with an active preview. Possible causes:

1. **`_parent.` prefix missed** — some variable in `_draw_sim()` CHANGED-mode section still references a bare name instead of `_parent.xxx`
2. **Lambda closure** — the `show_timeline_for_uid` lambda inside `_draw_sim()` references `_parent.ViewMode.CHANGED` etc. — verify all enum refs are correct
3. **Dark fog overlay** — the `draw_rect()` for CHANGED mode fog is in BattleRenderer._draw(), but HexMoveDemo._draw() no longer draws the background rect — verify the fog still renders correctly
4. **`_diff_flash_time`** — used for CHANGED mode crossfade animation, accessed as `_parent._diff_flash_time` — verify it's being incremented in `_process()`

## Steps

1. **Read** `tactics-godot/CLAUDE.md` for dev rules
2. **Read** `scripts/battle_renderer.gd` — focus on `_draw_sim()` CHANGED mode section (~lines 220-320)
3. **Read** `HexMoveDemo.gd` — focus on `_draw()` (~line 1388) and `_process()` (~line 1340)
4. **Run the game** using the `/playtest` skill to reproduce the bug
5. **Check Godot console output** for `SCRIPT ERROR:` lines when pressing 2
6. **Fix** any issues found
7. **Run syntax check** after every edit: `--headless --path tactics-godot --check-only --quit`
8. **Visual playtest** all view modes (1-4), replay, hover trails, deploy heatmap, popups
9. **Run headless sim** to verify no state logic was broken
10. **Do NOT commit** — ask the user first

## Godot executable
- Console: `C:\Users\bigto\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe`
- Syntax check: `--headless --path tactics-godot --check-only --quit`
- Import (after new class_name): `--headless --path tactics-godot --import --quit`

## Dev rules
- **Always analyze before implementing** — present analysis, wait for answers
- **Never auto-commit**
- **Run syntax check after every .gd edit**
- **GDScript ternary**: `val if cond else fallback` (NOT `?:`)
- **hex_id()** is `col * 1000 + row` — never reverse with `% COLS`

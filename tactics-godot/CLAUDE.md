# CLAUDE.md — tactics-godot

## Project
Godot 4.6 hex tactics demo. Single-file architecture for now.
- Main scene: `HexMoveDemo.tscn` → `HexMoveDemo.gd`
- Grid: **120 cols × 88 rows**, **FLAT-TOP hex, isometric rendering** (FFT style)
- Tileset: `res://../../assets/hex tactics assets/tileset hex tommy.png` (~48px per tile)
- 8 units per player, free army pick (Infantry + Cavalry)
- Combat range: 2 hexes
- Objectives: 3, controlled by most models within radius 2 per turn
- RNG seed: derived from placement position hash

## IMPORTANT: Hex math changed to flat-top
- Old (pointy-top): `x = sqrt(3)*size*(col + 0.5*(row&1))`, `y = 1.5*size*row`
- New (flat-top iso): screen_x = (col - row) * tile_w/2, screen_y = (col + row) * tile_h/4
- Neighbor directions differ between pointy-top and flat-top — update AXIAL_DIRS
- Z-ordering: draw tiles back-to-front (row 0, col 0 first; highest row+col last)
- Units must be drawn AFTER their tile, before the next row's tiles

## Godot executable
```
GODOT_GUI     = C:\Users\bigto\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64.exe
GODOT_CONSOLE = C:\Users\bigto\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe
PROJECT_PATH  = C:\Users\bigto\Documents\GitHub\hello-world-game\tactics-godot
```

## How to run tests (do this after EVERY edit)
```powershell
powershell -File "C:\Users\bigto\Documents\GitHub\hello-world-game\tactics-godot\run_tests.ps1"
```
This runs:
1. `--check-only --quit` — parse/syntax errors (--quit required or it hangs)
2. `--headless --quit` — runtime init errors
3. Any `*.test.gd` files found in the project

## How to open the game visually
```powershell
& 'C:\Users\bigto\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64.exe' --path 'C:\Users\bigto\Documents\GitHub\hello-world-game\tactics-godot'
```

## GDScript rules — IMPORTANT

### Syntax
- Ternary operator: `value if condition else fallback`  — NOT `condition ? value : fallback`
- String format: `"text %d" % value` or `"text %s %d" % [a, b]`
- For loops with unused var: `for _i in range(n):` (underscore suppresses warning)
- `match` not `switch`

### Drawing
- `draw_*` calls are ONLY valid inside `_draw()`. Never call them from `_process()`.
- To trigger a redraw: `queue_redraw()`
- Polygon fill: `draw_colored_polygon(PackedVector2Array, Color)`
- Outline: `draw_polyline(PackedVector2Array, Color, width)` — first point must be repeated at end to close

### Types
- `roundi(x)` returns int in Godot 4
- Typed arrays: `var result: Array[Vector2i] = []`
- `PackedVector2Array` required for draw functions — plain `Array` will not work
- Dictionary const values are Variant — access with `.key` syntax or `["key"]`
- `Color.lightened(f)` and `.darkened(f)` take 0.0–1.0, not percentage

### Performance
- `in` on Array is O(n). Use Dictionary for membership checks in loops.
- AStar2D: `build_astar()` is expensive — don't call it inside per-unit loops if possible

## Known mistakes (do not repeat)
1. **Ternary with `?:`** — GDScript does not support `?:`. Always use `value if cond else fallback`.
2. **`build_astar()` inside `find_path()`** — currently rebuilds on every call during simulate(). Fix: rebuild once per turn with that turn's blocked set.
3. ~~simulate() using hardcoded positions~~ — FIXED.
4. ~~Dead assignment~~ — FIXED.
5. ~~Ghost trails for eliminated units~~ — FIXED.
6. **Damage as integer division** — `kills = damage / hp` discards partial wounds. Units must track accumulated wounds across turns; only remove model when accumulated >= hp.
7. **Units fighting multiple enemies** — only fight the NEAREST enemy within range. Do not split attacks or fight all in range simultaneously.
8. **Objective AI priority** — units must check if an objective is friendly-held before pathing to it. Skip friendly-held; target nearest unclaimed or enemy-held. If all objectives friendly-held, path to nearest enemy.

## Game phases — UPDATED
```
DEPLOY  → alternating P1/P2 placement; looping animation runs the entire time
DONE    → all units placed; animation loops; result HUD shown; REPLAY button available
```
NO separate BATTLE phase. Animation is always running.

## Replay mode
- Entered via REPLAY button (shown when Phase.DONE)
- Clean turn-by-turn view: no ghost trails, no path lines
- Shows unit positions and model counts from per-turn snapshots
- Objective control updated from `obj_ctrl_history`
- Navigation: Left/Right arrows, Escape to exit
- Animation frozen during replay (`_process` returns early)
- Turn pips at bottom, VP score in HUD

## Animation behavior — CONFIRMED
- Loops Turn 0 → 1 → 2 → ... → 10 → back to 0, forever
- TURN_DURATION ~0.6s per frame
- Hover over deploy zone: show preview_sim on loop
- Hover leaves zone or no hover: show confirmed_sim on loop
- Any change (hover move, unit placed): recalc sim, restart anim_turn = 0

## Two simulation states
- `confirmed_sim`: simulate() with all placed units so far
- `preview_sim`: simulate() with placed units + hypothetical hover unit
- Draw preview_sim when hovering valid deploy hex; else draw confirmed_sim
- Preview unit token drawn as ghost (50% opacity) on top

## Simulation architecture
- `simulate(all_units: Array) -> Dictionary`
  - `all_units` = array of {player, col, row, unit_type} dicts for every unit in the sim
  - returns `{ timelines, units, combat, obj_control, vp_per_turn, unit_names, unit_obj, unit_kills, unit_dmg, combat_log, obj_ctrl_history, unit_snapshots }`
  - `timelines[uid]` = `Array[Vector2i]` of positions, index 0 = initial
  - `units[uid]` = final state dict `{ player, col, row, unit_type, models, eliminated, elim_turn }`
  - `combat[turn]` = Array of `{ a, b, ac, ar, bc, br }` pairs
  - `obj_control` = final objective control array [0/1/2 per objective]
  - `vp_per_turn[t]` = [p1_cumulative_vp, p2_cumulative_vp]
  - `unit_names[uid]` = random name string (separate RNG seed 7777)
  - `unit_obj[uid]` = ["no"/"yes"/"won" per objective] — contribution tracking
  - `unit_kills[uid]` = kill count; `unit_dmg[uid]` = total damage dealt
  - `combat_log` = Array of strings, play-by-play text log
  - `obj_ctrl_history[turn]` = duplicate of obj_control at end of turn (for replay)
  - `unit_snapshots[turn][uid]` = { models, eliminated, col, row } at end of turn (for replay)

## Additional confirmed rules
- Friendly units block each other's paths (same as enemy blocking)
- Army = 100 point budget. Infantry = 10pts, Cavalry = 20pts. Max 8 units.
- Tie at end of turn 10 = draw (no winner)
- VP scoring: 5 VP per objective held per turn (persistent control)
- Camera: no auto-pan during animation. Auto-pan to active player's zone when their deploy turn starts.
- Side panel: shows per-turn score + event log + timeline scrubber
- Prototype = pass-the-mouse local 2-player. Online/AI = future scope.

## Art style
- Isometric pixel art (FFT / Advance Wars style)
- Tileset: `assets/hex tactics assets/tileset hex tommy.png`
- Unit tokens: pixel art sprites (to be added to assets folder)
- Banners on objectives, crossed swords at combat, color-coded P1 (blue) / P2 (red)
- Ghost trails: same unit sprite at lower opacity at each historical turn position
- Trail opacity: 0.15 (oldest) → 0.75 (newest)
- Color palette: dark parchment BG, blue P1, red P2, gold objectives

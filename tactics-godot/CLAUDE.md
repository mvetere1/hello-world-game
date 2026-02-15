# CLAUDE.md — tactics-godot

## CORE DESIGN PRINCIPLE: RNG as Terrain, Not Chaos
**RNG chaos is BAD in this game.** Randomness creates unique game states, but the player must make intelligent decisions to alter outcomes in their favor. Every feature must follow:
- Outcomes are **previewable** — the player sees the exact future before committing
- RNG effects are **local** — only nearby changes affect nearby fights
- The player **controls** outcomes through strategy, not luck
- No hidden randomness — what you see is what you get

**If a new feature introduces randomness, it must be previewable, local, and player-controllable. No exceptions.**

## Project
Godot 4.6 hex tactics demo. Single-file architecture for now.
- Main scene: `HexMoveDemo.tscn` → `HexMoveDemo.gd`
- Grid: **120 cols × 88 rows**, **FLAT-TOP hex, isometric rendering** (FFT style)
- Tileset: `res://../../assets/hex tactics assets/tileset hex tommy.png` (~48px per tile)
- 8 units per player, free pick from 5 types: Infantry, Cavalry, Artillery, Deep Strike, Wizard
- Non-reversible unit selection popup before each placement (blind commitment)
- Combat phases per turn: Movement → Ranged (one-way) → Melee (simultaneous) → Retreat (wizard)
- Combat range: 2 hexes (melee); Artillery range 20, Wizard range 8
- Objectives: 3, controlled by most models within radius 2 per turn
- RNG seed: per-combat (seeded from pair + turn + nearby unit positions within 2 hexes)

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
9. **Deep strike units targetable before arrival** — FIXED. Units with `start_turn > 0` existed at their deploy coordinates before materializing, so artillery/melee could kill them pre-arrival. Fix: added `arrived` flag, checked in all targeting/control functions. The old `e.col == -1` check was wrong because units keep their deploy coords in the unit dict.
10. **Artillery chasing objectives** — FIXED. When artillery had no ranged target, it fell through to `_pick_target()` which chased objectives. Fix: artillery now walks straight forward toward enemy side (`fwd_row ± 1`) when no target is in range.
11. **Combat sparks appearing in wrong view modes** — FIXED. Sparks now filtered by `show_timeline_for_uid` lambda — only render when at least one combat participant has a visible timeline in the current view mode.
12. **Summary X button not working** — FIXED. The early-return catch-all in `_input()` consumed all mouse events before the close button handler. Fix: moved close button check inside the summary input block before the catch-all.

## Known concerns
1. **Visual clutter on the battlefield** — with 16 units, ghost trails, path lines, combat sparks, and objective highlights, the map can be visually noisy. Mitigations in place:
   - **View mode system** (keys 1–4): CLEAN (final positions only + preview unit path), CHANGED (only affected timelines), FULL (all timelines, 2x speed, snail-trail), FINAL (static end-state). Player controls information density.
   - **Combat spark filtering**: sparks only render when at least one participant has a visible timeline in the current view mode.
   - **Narrative preview panel**: text summary of what the preview unit will do (fights, objectives, death), displayed below the fate chart.
   - **Font sizes increased ~30%** across all UI for high-resolution monitors.

## Game phases — UPDATED
```
DEPLOY  → unit selection popup → place unit → alternating P1/P2; looping animation runs
DONE    → all units placed; animation loops; result HUD shown; REPLAY button available
```
NO separate BATTLE phase. Animation is always running.

### Deployment sub-flow
1. Unit selection popup appears (5 buttons: Infantry, Cavalry, Artillery, Deep Strike, Wizard)
2. Player clicks a unit type → popup closes, deployment mode begins
3. For Deep Strike: turn selector popup (T2–T8) appears first, then legal hexes highlighted
4. Player hovers/clicks to place → unit locked in, next player's turn starts

### Per-turn simulation structure
```
1. DEEP STRIKE ARRIVAL: units with start_turn == current turn materialize
2. MOVEMENT: per-type AI (infantry→objectives, cavalry→enemies, artillery→stay/advance, wizard→kite, DS→objectives)
3. RANGED PHASE: artillery/wizard shoot (one-way, skipped if in melee)
4. MELEE PHASE: all pairs within COMBAT_RANGE fight simultaneously (melee profiles for artillery/wizard)
5. WIZARD RETREAT: wizards that were in melee move 5 hex away from all units/objectives
6. OBJECTIVE CHECK: weighted control (infantry/cavalry 1.0, DS/wizard 0.5, artillery 0.0)
```

## Replay mode
- Entered via REPLAY button (shown when Phase.DONE)
- Clean turn-by-turn view: no ghost trails, no path lines
- Shows unit positions and model counts from per-turn snapshots
- Objective control updated from `obj_ctrl_history`
- Navigation: Left/Right arrows, Escape to exit
- Animation frozen during replay (`_process` returns early)
- Turn pips at bottom, VP score in HUD

## Visual Philosophy: Spacetime Worms
Units are NOT tokens that move across a board. **Units ARE spacetime worms** — 4D objects stretching from deployment to death/turn 10. The ghost trail IS the unit. The animation scans through slices. FULL mode renders the true shape. See GDD for full philosophy (block universe / eternalism).

## View Modes (keys 1–4)
During deployment, the player can switch between four view modes to control visual information density:

| Key | Mode | What it shows |
|-----|------|---------------|
| 1 | CLEAN | All units at final position only. Preview unit gets full timeline (path, ghosts, trail). |
| 2 | CHANGED | Full timelines for units whose fate changed due to preview placement + preview unit. Rest at final position. |
| 3 | FULL | Full timelines for ALL units at 2x speed. Enhanced snail-trail visuals (thicker lines, higher opacity) — the spacetime worm view. |
| 4 | FINAL | Static end-state. All units at final/death positions, final objective control. No animation. |

Combat sparks are filtered per view mode — only shown when at least one participant has a visible timeline.

## Narrative Preview Panel
When hovering a deploy hex, a text panel appears below the fate chart summarizing the preview unit's projected fate:
- Objective contesting (which objectives, which turns)
- Combat partners (who it fights)
- Survival or elimination (and which turn)
- VP impact (score delta from this placement)

## Animation behavior — CONFIRMED
- Loops Turn 0 → 1 → 2 → ... → 10 → back to 0, forever
- TURN_DURATION ~0.6s per frame
- Hover over deploy zone: show preview_sim on loop
- Hover leaves zone or no hover: show confirmed_sim on loop
- Any change (hover move, unit placed): recalc sim, restart anim_turn = 0

## Two simulation states + diff
- `confirmed_sim`: simulate() with all placed units so far
- `preview_sim`: simulate() with placed units + hypothetical hover unit
- `preview_diff`: `_compute_sim_diff()` compares confirmed vs preview — tracks fate changes, score delta, objective flips
- Draw preview_sim when hovering valid deploy hex; else draw confirmed_sim
- Preview unit token drawn as ghost (50% opacity) on top
- Diff indicators: fate chart row tints (green/red/yellow), score +/- delta, objective hex glow

## Simulation architecture
- `simulate(all_units: Array) -> Dictionary`
  - `all_units` = array of {player, col, row, unit_type, start_turn (optional)} dicts for every unit in the sim
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
- Army = 8 units, free pick from 5 types (point budget tabled for later).
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

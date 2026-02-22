# CLAUDE.md — tactics-godot

## CORE DESIGN PRINCIPLE: RNG as Terrain, Not Chaos
**RNG chaos is BAD in this game.** Randomness creates unique game states, but the player must make intelligent decisions to alter outcomes in their favor. Every feature must follow:
- Outcomes are **previewable** — the player sees the exact future before committing
- RNG effects are **local** — only nearby changes affect nearby fights
- The player **controls** outcomes through strategy, not luck
- No hidden randomness — what you see is what you get

**If a new feature introduces randomness, it must be previewable, local, and player-controllable. No exceptions.**

## Project
Godot 4.6 hex tactics demo. Multi-file architecture (refactor in progress — see `REFACTOR-NOTES.md`).
- Main scene: `HexMoveDemo.tscn` → `HexMoveDemo.gd` (2,965 lines — orchestrator, state, input, rendering, HUD)
- `scripts/hex_math.gd` — static pure hex math (94 lines)
- `scripts/combat_simulator.gd` — simulation, AI, pathfinding, combat (948 lines)
- `scripts/resources/*.gd` — UnitStats, GridConfig, BattleConfig, TerrainType resource classes
- `resources/**/*.tres` — 5 unit configs + 2 game configs + 3 terrain types (editable in Inspector)
- `HeadlessSim.gd` — CLI simulation runner (uses CombatSimulator directly)
- Grid: **56 cols × 40 rows**, **FLAT-TOP hex, odd-q offset**
- 8 units per player, free pick from 5 types: Infantry, Cavalry, Artillery, Deep Strike, Archer
- Multi-hex formations: units occupy ceil(models/2) hexes (compact cluster). Artillery has fixed 5-hex footprint. Formations shrink as models die (front-line hexes released first).
- Non-reversible unit selection popup before each placement (blind commitment)
- Combat phases per turn: Movement → Ranged (one-way) → Melee (simultaneous) → Retreat (archer)
- Combat range: COMBAT_RANGE = 2 hexes (melee); Artillery range 40, Archer range 24
- Archer retreat: 16 hex; always retreats from melee; first melee = half damage both ways, subsequent = full damage
- Cavalry charge bonus: damage 2→1 per hit if cavalry started the turn already in melee range of any enemy
- Objectives: 3 at (14,20), (28,18), (42,20); controlled by most OC (models × oc stat) within OC_RADIUS (4) per turn
- Named constants: OC_RADIUS=4, CAVALRY_AGGRO=16, COMBAT_RANGE=2
- Deploy zones: P1 rows 32-39 cols 4-51, P2 rows 0-7 cols 4-51
- DS exclusion zone: CAVALRY_AGGRO + 1 = 17 hexes from enemies
- **DS temporal disruption:** DS pathfinds to nearest enemy trail hex; at COMBAT_RANGE triggers yank (enemy teleported back, formation recomputed, cavalry lose charge). One charge per DS. Wasted on dead unit trails. Reverts to infantry AI after.
- Camera initial zoom: 0.5 (HEX_SIZE stays at 20.0)
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
13. **Shift summary placed unit name wrong** — FIXED. When Blue placed a unit after Red already had units, the shift summary showed the wrong unit name. Root cause: `placed_p1 + placed_p2` puts P1 units first, so the last element wasn't always the placed unit. Fix: compute correct UID based on which player placed (`placed_p1.size() - 1` for P1, `placed_p1.size() + placed_p2.size() - 1` for P2). The `_build_shift_summary_lines` function now takes a `placed_uid` parameter.
14. **elim_turn off-by-one** — FIXED. The sim loop uses 0-based turns (0-9) via `for turn in TURNS`. The combat log header correctly prints `turn + 1` (display turns 1-10), but `elim_turn` was stored 0-based and displayed without `+1` in 9 locations (shift summary, battle summary, key moments). Fixed all display strings to use `elim_turn + 1`. Also fixed a pre-existing bug where one line had `" died on turn %d."` without the `%` format operator. Timeline indexing code correctly uses raw 0-based `elim_turn` (unchanged).
15. **Deep strike start_turn off-by-one** — FIXED. The DS turn popup labeled "T3" set `ds_arrival_turn = i + 2 = 3` (0-based turn 3 = display Turn 4). Unit arrived one turn later than the label indicated. Fixed to `i + 1`. HeadlessSim.gd now converts deploy.json `start_turn` (user-facing 2-8) to 0-based by subtracting 1.
16. **Deploy formation zone bleed** — FIXED. Formations could grow outside the deploy zone via `compute_compact_cluster()`. Now `_deploy_blocked_cache` marks all non-deploy-zone hexes (plus existing formation hexes) as blocked, so formations compact within the legal zone only. `_recompute_deploy_cache()` rebuilds the cache when unit type is selected or DS turn is chosen.
17. **Deploy formation stacking** — FIXED. `_handle_deploy_click()` and `_recalc_preview_sim()` previously only checked anchor hex overlap. Now they use `_deploy_blocked_cache` which includes all formation hexes from already-placed units, preventing multi-hex formations from overlapping.

## Known concerns
1. **Visual clutter on the battlefield** — with 16 units, ghost trails, path lines, combat sparks, and objective highlights, the map can be visually noisy. Mitigations in place:
   - **View mode system** (keys 1–4): CLEAN (final positions only + preview unit path), CHANGED (70% dark fog overlay + spotlight on changed trails, dim silhouettes for unchanged units), FULL (all timelines, 2x speed, snail-trail), FINAL (static end-state). Player controls information density.
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
1. Unit selection popup appears (5 buttons: Infantry, Cavalry, Artillery, Deep Strike, Archer)
2. Player clicks a unit type → popup closes, deployment mode begins
3. For Deep Strike: turn selector popup (T2–T8) appears first, then legal hexes highlighted
4. Player hovers/clicks to place → unit locked in, next player's turn starts

### Per-turn simulation structure
```
1. DEEP STRIKE ARRIVAL: units with start_turn == current turn materialize
2. MOVEMENT: per-type AI (infantry→objectives, cavalry→enemies, artillery→stay/advance, archer→kite, DS pre-disruption→trail hex, DS post-disruption→objectives)
3. TEMPORAL DISRUPTION CHECK: DS within COMBAT_RANGE of target trail hex → enemy yanked back, formation recomputed, cavalry lose charge. Wasted on dead unit trails. DS reverts to infantry AI after.
4. RANGED PHASE: artillery/archer shoot (one-way, skipped if in melee)
5. MELEE PHASE: all pairs within COMBAT_RANGE fight simultaneously (melee profiles for artillery/archer; disrupted cavalry lose charge bonus)
6. ARCHER RETREAT: archers that were in melee move 16 hex away from all units/objectives
7. OBJECTIVE CHECK: OC-based control (sum of models × oc per player within OC_RADIUS 4; most OC wins)
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
| 2 | CHANGED | 70% dark fog overlay dims the entire map. Changed units' old/new paths crossfade smoothly (1s per phase): pale purple = old timeline (WITHOUT), pale yellow = new timeline (WITH UNIT). Preview unit keeps team-colored trail. Unchanged units shown as dim silhouettes. Falls back to CLEAN when no preview active. |
| 3 | FULL | Full timelines for ALL units at 2x speed. Enhanced snail-trail visuals (thicker lines, higher opacity) — the spacetime worm view. |
| 4 | FINAL | Static end-state. All units at final/death positions, final objective control. No animation. |

Combat sparks are filtered per view mode — only shown when at least one participant has a visible timeline.

**H key** — Toggle deploy heatmap overlay (off by default). Shows VP delta per hex during deployment.

## Narrative Preview Panel
When hovering a deploy hex, a text panel appears below the fate chart summarizing the preview unit's projected fate:
- Objective contesting (which objectives, which turns)
- Combat partners (who it fights)
- Survival or elimination (and which turn)
- VP impact (score delta from this placement)

## Deep Strike Temporal Disruption
DS units arrive with one temporal disruption charge. Instead of normal objective AI, they pathfind to the **nearest enemy trail hex** (any past-turn position from `formations_timeline`, including eliminated units and other DS).

**Trigger:** DS reaches COMBAT_RANGE (2) of target trail hex.
**Effect:** Enemy teleported to trail position, formation recomputed. Disrupted cavalry lose charge bonus (yanked = lost momentum).
**Limits:** One disruption per DS. One enemy can be disrupted by multiple DS units.
**Risk:** Targeting a dead unit's trail wastes the disruption (intentional skill element).
**After use:** DS reverts to infantry AI (objective-focused).
**Persistence:** DS hunts trail hex across multiple turns if it can't reach on arrival turn.

**New unit state fields:**
- `has_disrupted` (bool) — DS has used its temporal disruption
- `disrupted` (bool) — unit was yanked by a DS
- `disrupted_turn` (int) — which turn disruption happened
- `disrupted_from` (Vector2i) — position before yank (for visual break)

**New function:** `_pick_trail_target(uid, units, formations_timeline, turn)` — scans `formations_timeline` for nearest enemy trail hex reachable by this DS unit.

**Combat log:** Shows "TEMPORAL DISRUPTION" messages when disruption occurs, or "disruption wasted" when targeting dead unit trail.

**Visual:** Worm fractures at disruption point — purple jagged line from old position to yanked position, X mark at severed old fate, ribbon gap in worm.

## Trail Hover Tooltip
Hovering over any unit's trail (any past-turn formation hex) during DEPLOY or DONE phases shows a tooltip near the cursor with that unit's stats:
- Unit name and type prefix
- Survival status (alive with model count, or eliminated on turn N)
- Total damage dealt
- Kill count
- Objectives held (count of "yes"/"won")
- Disruption status (disrupted on turn N, or used disruption)

The hovered unit's entire trail is highlighted with a bright team-colored glow and outline. Detection uses `_find_trail_uid_at_hex()` which scans `formations_timeline` for the hex under the cursor. State tracked via `hover_trail_uid` (updated in `_input()`).

## Timeline Shifted Popup — Placed Unit Performance
After unit placement, the "TIMELINE SHIFTED" popup now always includes the placed unit's performance summary immediately after the header (e.g., "Blue placed A Odo"). This line shows:
- Total damage dealt with per-target breakdown (e.g., "Deals 18 damage to I Ben (12), I Dan (6)")
- Kill count
- Objectives held
- Survival status

Previously, if no other unit's fate changed, the popup only said "Timeline shifted slightly." Now the player always gets feedback about what their newly placed unit accomplishes.

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

## Headless Simulation CLI Tool
Three files enable running the simulation without the Godot GUI:
- `HeadlessSim.gd` — Node script that reads `deploy.json`, creates `CombatSimulator.new()`, calls `simulate()`, writes results
- `HeadlessSim.tscn` — Minimal scene with HeadlessSim.gd attached
- `deploy.json` — Deployment config (army compositions + hex positions)

**Usage:**
```
& 'C:\Users\bigto\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe' --headless --path 'C:\Users\bigto\Documents\GitHub\hello-world-game\tactics-godot' res://HeadlessSim.tscn
```

**Modes:**
- Both sides specified: `deploy.json` has `"blue"` and `"red"` arrays of unit dicts
- vs Random AI: set either side to `"random"` string instead of an array

**Validation:** deploy zones, hex overlap, unit types, max 8 per side

**Output:**
- `user://results.json` — structured JSON with winner, scores, score_by_turn, obj_control_final, per-unit stats (damage, kills, objectives, damage_targets, survival)
- `user://combat_log.txt` — full text combat log
- stdout — summary line

## Simulation architecture
- `simulate(all_units: Array) -> Dictionary`
  - `all_units` = array of {player, col, row, unit_type, start_turn (optional)} dicts for every unit in the sim
  - returns `{ timelines, formations_timeline, units, combat, obj_control, vp_per_turn, unit_names, unit_obj, unit_kills, unit_dmg, combat_log, obj_ctrl_history, unit_snapshots }`
  - `timelines[uid]` = `Array[Vector2i]` of anchor positions, index 0 = initial
  - `formations_timeline[uid]` = `Array[Array[Vector2i]]` of formation hex snapshots per turn
  - `units[uid]` = final state dict `{ player, col, row, unit_type, models, eliminated, elim_turn, formation, has_disrupted, disrupted, disrupted_turn, disrupted_from }`
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

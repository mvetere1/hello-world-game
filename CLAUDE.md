# CLAUDE.md — hello-world-game

## Repository layout
```
ball-cannon/          HTML5 canvas ball cannon prototype
tactics/              HTML5 canvas tactics prototype  (prototype.html)
tactics-godot/        Godot 4.6 hex tactics DEVELOPER TESTING TOOL  (main active project)
  HexMoveDemo.gd       Main orchestrator (2,171 lines — state, input, rendering, HUD)
  scripts/
    battle_renderer.gd  Battle rendering — tiles, trails, tokens (862 lines)
    hex_math.gd         Static pure hex math (94 lines)
    combat_simulator.gd Simulation, AI, pathfinding, combat (948 lines)
    resources/          Resource class definitions (UnitStats, GridConfig, etc.)
  resources/            .tres config files (units, grid, battle, terrain)
  HeadlessSim.gd/tscn   Headless CLI sim tool (uses CombatSimulator directly)
  deploy.json           Deployment config for headless sim
  REFACTOR-NOTES.md     Migration plan and progress (Phases 0-5 done, 7-12 planned)
GAME-DESIGN-DOCUMENT.md
```

## Active focus
`tactics-godot/` — **Developer testing toolkit** for hex tactics game balance and game feel. Godot 4.6, multi-file architecture (migration to Godot-native patterns in progress).

**This is NOT a game — it's a prototyping tool.** The final game design is uncertain. This tool lets 4 teammates independently test variations of grid size, unit stats, combat rules, terrain, and visual presentation. All configuration must be editable from the Godot Inspector without touching code.

See `tactics-godot/CLAUDE.md` for Godot-specific rules, `tactics-godot/REFACTOR-NOTES.md` for migration plan.

## Core design principle
**RNG as Terrain, Not Chaos.** Randomness creates unique game states, but the player makes intelligent decisions to alter outcomes. All RNG must be previewable, local, and player-controllable. See `tactics-godot/GAME-DESIGN-DOCUMENT.md` for full philosophy.

## Architecture migration status
- **Phases 0-5: DONE** — Resources, terrain, hex math, combat simulator, battle renderer extracted
- **Phase 6 (Node2D HUDRenderer): SKIPPED** — going directly to Control nodes
- **Phases 7-12: TODO** — GameState extraction, VisualConfig resource, HUD → Control nodes, controller extraction, TileMapLayer rendering, @tool editor preview

Target: Godot-native architecture with CanvasLayer + Control nodes for HUD, TileMapLayer for hex grid, signals for decoupling, @export for all configuration. Dynamic rendering (trails, tokens, combat sparks) stays as draw_*.

## Game design summary
- Turn-based tactics, Warhammer-style combat
- Flat-top hex grid, odd-q offset coordinates, 56×40
- 3 objectives in center, 10 turns, deployment zones top/bottom
- 8 units per side, free pick from 5 unit types (no point budget yet)
- Unit types: Infantry (10 models, 5 hex), Cavalry (6 models, 3 hex), Artillery (1 model, 5 hex fixed), Deep Strike (8 models, 4 hex), Archer (8 models, 4 hex)
- Move values: Infantry 10, Cavalry 24, Artillery 8, Deep Strike 16, Archer 16
- Ranges: Artillery 40, Archer 24, Archer retreat 16; COMBAT_RANGE stays at 2
- Multi-hex formations: units occupy ceil(models/2) hexes in compact clusters; shrinks as models die
- Objective Control (OC): each model contributes 1 OC; most total OC within OC_RADIUS (4) controls objective
- Combat phases: Movement → Temporal Disruption → Ranged → Melee → Retreat
- Deep Strike temporal disruption: DS pathfinds to nearest enemy trail hex; at COMBAT_RANGE triggers yank
- VP scoring: 5 VP per objective held per turn (persistent control)
- Visual philosophy: spacetime worms — ghost trails ARE the unit (block universe / eternalism)
- View modes (keys 1–4): CLEAN, CHANGED, FULL, FINAL
- Local butterfly effect: per-combat RNG seeded from nearby units within 2 hexes
- Headless simulation CLI: `HeadlessSim.tscn` runs sim without GUI

## Workflow rules
- ALWAYS analyze before implementing — for any gameplay or design change, analyze implications, present questions, and wait for answers before writing code
- ALWAYS run `run_tests.ps1` after editing any .gd file before considering work done
- Never add code that isn't directly needed for the current task
- Never auto-commit
- When a bug recurs, add it to the "Known mistakes" section in the relevant CLAUDE.md
- After ANY gameplay or design change, update ALL relevant docs:
  - `tactics-godot/GAME-DESIGN-DOCUMENT.md` — authoritative design spec
  - `tactics-godot/CLAUDE.md` — dev rules, known bugs, architecture
  - `tactics-godot/CODE-GUIDE.md` — team onboarding guide
  - `CLAUDE.md` (this file) — top-level summary
  - Do NOT wait to be asked. If you changed behavior, update the docs in the same pass.

## Known bugs (fixed in recent session)
- **Shift summary placed unit name** — Fixed. Was showing wrong unit when Blue placed after Red due to index calculation.
- **elim_turn off-by-one** — Fixed across 9 locations. Display strings now correctly show `elim_turn + 1`.
- **Deep strike start_turn off-by-one** — Fixed. DS turn popup T3 now correctly sets 0-based turn 2.
- **Deploy formation zone bleed** — Fixed. Formations now compact within the deploy zone.
- **Deploy formation stacking** — Fixed. Deploy click and preview sim check full formation overlap via blocked cache.

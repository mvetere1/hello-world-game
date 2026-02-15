# CLAUDE.md — hello-world-game

## Repository layout
```
ball-cannon/          HTML5 canvas ball cannon prototype
tactics/              HTML5 canvas tactics prototype  (prototype.html)
tactics-godot/        Godot 4.6 hex tactics demo      (main active project)
  HeadlessSim.gd/tscn  Headless CLI sim tool (godot --headless res://HeadlessSim.tscn)
  deploy.json           Deployment config for headless sim
GAME-DESIGN-DOCUMENT.md
```

## Active focus
`tactics-godot/` — Godot 4.6 point-and-click hex tactics demo.
See `tactics-godot/CLAUDE.md` for all Godot-specific rules.

## Core design principle
**RNG as Terrain, Not Chaos.** Randomness creates unique game states, but the player makes intelligent decisions to alter outcomes. All RNG must be previewable, local, and player-controllable. See `tactics-godot/GAME-DESIGN-DOCUMENT.md` for full philosophy.

## Game design summary
- Turn-based tactics, Warhammer-style combat
- Flat-top hex grid, odd-q offset coordinates
- 3 objectives in center, 10 turns, deployment zones top/bottom
- 8 units per side, free pick from 5 unit types (no point budget yet)
- Unit types: Infantry, Cavalry, Artillery, Deep Strike, Archer
- Non-reversible unit selection popup before each placement (blind commitment)
- Combat phases: Movement → Ranged → Melee → Retreat (archer)
- Full combat: hit roll → wound roll → armor save (with rend) → damage
- VP scoring: 5 VP per objective held per turn (persistent control)
- Visual language: "all time at once" — ghost trails show full battle history simultaneously
- Local butterfly effect: per-combat RNG seeded from nearby units — only fights within 2 hexes of a new unit change
- Preview diff indicators: fate chart highlights, score delta, objective flip glow
- View modes (keys 1–4): CLEAN, CHANGED, FULL (spacetime worm view), FINAL (static end-state)
- Visual philosophy: units are spacetime worms (block universe / eternalism) — ghost trails ARE the unit, not history
- Narrative preview panel: text summary of preview unit's projected fate
- UI: scoreboard, unit fate chart, combat log, replay mode, battle summary
- Timeline shifted popup always shows placed unit's performance (damage, kills, objectives, survival)
- Headless simulation CLI: `HeadlessSim.tscn` runs sim without GUI, reads `deploy.json`, outputs `results.json`

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
- **Shift summary placed unit name** — Fixed. Was showing wrong unit when Blue placed after Red due to index calculation. Now correctly compute UID based on active player.
- **elim_turn off-by-one** — Fixed across 9 locations. Display strings now correctly show `elim_turn + 1` (user-facing turn numbers 1-10). Internal logic unchanged (0-based).
- **Deep strike start_turn off-by-one** — Fixed. DS turn popup T3 now correctly sets 0-based turn 2 (displays as Turn 3). HeadlessSim.gd converts deploy.json values (2-8) to 0-based.

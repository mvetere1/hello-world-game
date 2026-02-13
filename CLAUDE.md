# CLAUDE.md — hello-world-game

## Repository layout
```
ball-cannon/          HTML5 canvas ball cannon prototype
tactics/              HTML5 canvas tactics prototype  (prototype.html)
tactics-godot/        Godot 4.6 hex tactics demo      (main active project)
GAME-DESIGN-DOCUMENT.md
```

## Active focus
`tactics-godot/` — Godot 4.6 point-and-click hex tactics demo.
See `tactics-godot/CLAUDE.md` for all Godot-specific rules.

## Game design summary
- Turn-based tactics, Warhammer-style combat
- Pointy-top hex grid, odd-r offset coordinates
- 3 objectives in center, 5 turns, deployment zones top/bottom
- Unit types: Infantry (10 models, move 10) and Cavalry (5 models, move 18)
- Full combat: hit roll → wound roll → armor save (with rend) → damage
- Visual language: "all time at once" — ghost trails show full battle history simultaneously
- Full butterfly effect: entire simulation reruns on every unit placement

## Workflow rules
- ALWAYS run `run_tests.ps1` after editing any .gd file before considering work done
- Never add code that isn't directly needed for the current task
- Never auto-commit
- When a bug recurs, add it to the "Known mistakes" section in the relevant CLAUDE.md

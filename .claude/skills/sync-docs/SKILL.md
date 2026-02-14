---
name: sync-docs
description: Synchronize all documentation files with the current state of the code. Use after making changes, or when docs are out of date.
---

Read the current state of `tactics-godot/HexMoveDemo.gd` and update every doc to match the actual code. Check for discrepancies in:

## Files to sync

1. **`CLAUDE.md`** (root) — game design summary (hex type, grid size, turn count, unit stats, move values)
2. **`tactics-godot/CLAUDE.md`** — grid dimensions, unit count, combat range, phase descriptions, simulation architecture
3. **`tactics-godot/GAME-DESIGN-DOCUMENT.md`** — unit roster stats, grid size, turn count, deployment rules, victory conditions
4. **`tactics-godot/CODE-GUIDE.md`** — configuration constants, line number references, file structure description, data flow

## What to check

For each doc, compare against the actual code:
- Grid: COLS, ROWS
- Units: UNITS_PER_SIDE, stat blocks (INFANTRY, CAVALRY, any new types)
- Turns: TURNS constant
- Deploy zones: P1/P2 row ranges, column ranges
- Objectives: positions and count
- Combat: COMBAT_RANGE, hit/wound/armor/rend mechanics
- Phases: enum values and transitions
- Any line number references in CODE-GUIDE.md (these drift as code changes)

Update only what's actually wrong. Don't rewrite docs that are already correct.

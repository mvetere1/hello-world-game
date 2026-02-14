---
name: add-unit-type
description: Add a new unit type to the tactics prototype. Use when the user wants to add a new kind of unit (e.g., archers, mages, etc.)
argument-hint: "[unit-name]"
---

Add a new unit type called `$ARGUMENTS` to the tactics prototype. Follow these steps exactly:

## 1. Add the stat block

In `tactics-godot/HexMoveDemo.gd`, add a new const dictionary after the existing INFANTRY and CAVALRY blocks. Use the same format:

```gdscript
const UNIT_NAME = {
    "models"  : ???,
    "hp"      : ???,
    "move"    : ???,
    "attacks" : ???,
    "hit"     : ???,
    "wound"   : ???,
    "rend"    : ???,
    "armor"   : ???,
    "damage"  : ???,
}
```

Ask the user for the stat values if not provided.

## 2. Update simulation code

Search HexMoveDemo.gd for every place that checks `"infantry"` or `"cavalry"` and add the new unit type. Key locations:
- `_roll_combat()` — stats lookup
- `simulate()` — stats lookup for model count
- `_apply_wounds()` — hp lookup
- Movement phase — move stat lookup

## 3. Run syntax check

```powershell
& 'C:\Users\bigto\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe' --headless --path 'C:\Users\bigto\Documents\GitHub\hello-world-game\tactics-godot' --check-only
```

## 4. Update ALL docs (mandatory)

- `tactics-godot/GAME-DESIGN-DOCUMENT.md` — add unit to roster table
- `tactics-godot/CLAUDE.md` — update any unit references
- `tactics-godot/CODE-GUIDE.md` — update configuration constants section and unit stats
- `CLAUDE.md` — update game design summary

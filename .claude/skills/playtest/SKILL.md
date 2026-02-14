---
name: playtest
description: Run the Godot tactics prototype for visual testing. Use after making code changes to verify they work.
allowed-tools: Bash
---

Run the tactics prototype in Godot for visual playtesting.

## Scenes

- **2D main prototype**: `res://HexMoveDemo.tscn` (default main scene)
- **3D asset test**: `res://HexGrid3DTest.tscn` (KayKit tiles + flying camera)

To run the default (2D) scene:
```powershell
& 'C:\Users\bigto\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64.exe' --path 'C:\Users\bigto\Documents\GitHub\hello-world-game\tactics-godot'
```

To run the 3D test scene specifically:
```powershell
& 'C:\Users\bigto\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64.exe' --path 'C:\Users\bigto\Documents\GitHub\hello-world-game\tactics-godot' res://HexGrid3DTest.tscn
```

Before launching, ALWAYS run the syntax check first:

```powershell
& 'C:\Users\bigto\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe' --headless --path 'C:\Users\bigto\Documents\GitHub\hello-world-game\tactics-godot' --check-only
```

If syntax check fails, fix the errors before launching. Tell the user what you found.
If syntax check passes, launch the game and tell the user it's running.

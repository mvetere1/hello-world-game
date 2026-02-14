---
name: playtest
description: Run the Godot tactics prototype for visual testing. Use after making code changes to verify they work.
allowed-tools: Bash
---

Run the tactics prototype in Godot for visual playtesting:

```powershell
& 'C:\Users\bigto\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64.exe' --path 'C:\Users\bigto\Documents\GitHub\hello-world-game\tactics-godot'
```

Before launching, ALWAYS run the syntax check first:

```powershell
& 'C:\Users\bigto\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe' --headless --path 'C:\Users\bigto\Documents\GitHub\hello-world-game\tactics-godot' --check-only
```

If syntax check fails, fix the errors before launching. Tell the user what you found.
If syntax check passes, launch the game and tell the user it's running.

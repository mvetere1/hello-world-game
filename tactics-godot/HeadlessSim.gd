extends Node

# HeadlessSim.gd — Headless simulation runner for CLI playtesting.
# Usage: godot --headless --path <project_dir> res://HeadlessSim.tscn
#
# Reads:  res://deploy.json   (army compositions + positions)
# Writes: user://results.json (structured results)
#         user://combat_log.txt (text narrative)

const VALID_TYPES = ["infantry", "cavalry", "artillery", "deep_strike", "archer"]

const COLS = 28
const ROWS = 20
const P1_DEPLOY_ROWS_MIN = 16
const P1_DEPLOY_ROWS_MAX = 19
const P2_DEPLOY_ROWS_MIN = 0
const P2_DEPLOY_ROWS_MAX = 3
const DEPLOY_C_MIN = 2
const DEPLOY_C_MAX = 25
const UNITS_PER_SIDE = 8

func _ready():
	var hex_demo: Node2D = load("res://HexMoveDemo.gd").new()

	# Read deploy.json
	var deploy_path = "res://deploy.json"
	if not FileAccess.file_exists(deploy_path):
		printerr("ERROR: deploy.json not found at ", deploy_path)
		get_tree().quit(1)
		return

	var f = FileAccess.open(deploy_path, FileAccess.READ)
	var json_text = f.get_as_text()
	f.close()

	var json = JSON.new()
	var err = json.parse(json_text)
	if err != OK:
		printerr("ERROR: Failed to parse deploy.json: ", json.get_error_message())
		get_tree().quit(1)
		return

	var deploy = json.data
	if typeof(deploy) != TYPE_DICTIONARY:
		printerr("ERROR: deploy.json root must be a dictionary")
		get_tree().quit(1)
		return

	# Build input_units array
	var input_units: Array = []
	var occupied: Dictionary = {}  # hex_id -> true

	# Process blue (player 1)
	var blue_data = deploy.get("blue", [])
	var blue_units = _parse_side(blue_data, 1, occupied)
	if blue_units == null:
		get_tree().quit(1)
		return
	input_units.append_array(blue_units)

	# Process red (player 2)
	var red_data = deploy.get("red", [])
	var red_units = _parse_side(red_data, 2, occupied)
	if red_units == null:
		get_tree().quit(1)
		return
	input_units.append_array(red_units)

	if input_units.is_empty():
		printerr("ERROR: No units to simulate")
		get_tree().quit(1)
		return

	print("Simulating %d units (%d Blue, %d Red)..." % [input_units.size(), blue_units.size(), red_units.size()])

	# Run simulation
	var result = hex_demo.simulate(input_units)

	# Build output
	var output = _build_output(result, input_units)

	# Write results.json
	var results_json = JSON.stringify(output, "  ")
	var rf = FileAccess.open("user://results.json", FileAccess.WRITE)
	if rf:
		rf.store_string(results_json)
		rf.close()
		print("Results written to: ", ProjectSettings.globalize_path("user://results.json"))

	# Write combat_log.txt
	var combat_log: Array = result.get("combat_log", [])
	var lf = FileAccess.open("user://combat_log.txt", FileAccess.WRITE)
	if lf:
		for line in combat_log:
			lf.store_line(line)
		lf.close()
		print("Combat log written to: ", ProjectSettings.globalize_path("user://combat_log.txt"))

	# Print summary to stdout
	_print_summary(output)

	# Free the HexMoveDemo instance to avoid leak warnings
	hex_demo.free()

	get_tree().quit(0)


func _parse_side(data, player: int, occupied: Dictionary):
	# Returns Array of unit dicts, or null on error
	if typeof(data) == TYPE_STRING and data == "random":
		return _generate_random(player, occupied)
	if typeof(data) != TYPE_ARRAY:
		printerr("ERROR: Side data must be an array or \"random\"")
		return null

	var units: Array = []
	for i in data.size():
		var entry = data[i]
		if typeof(entry) != TYPE_DICTIONARY:
			printerr("ERROR: Unit %d must be a dictionary" % i)
			return null

		var unit_type: String = entry.get("unit_type", "infantry")
		if unit_type not in VALID_TYPES:
			printerr("ERROR: Invalid unit_type '%s'" % unit_type)
			return null

		var col: int = int(entry.get("col", -1))
		var row: int = int(entry.get("row", -1))
		if not _is_valid_deploy(col, row, player):
			printerr("ERROR: Invalid deploy hex (%d, %d) for player %d" % [col, row, player])
			return null

		var hid = col * 1000 + row
		if occupied.has(hid):
			printerr("ERROR: Hex (%d, %d) already occupied" % [col, row])
			return null
		occupied[hid] = true

		var unit := {"player": player, "col": col, "row": row, "unit_type": unit_type}
		if unit_type == "deep_strike":
			var st = int(entry.get("start_turn", 3))
			unit["start_turn"] = clampi(st, 2, 8)
		units.append(unit)

	if units.size() > UNITS_PER_SIDE:
		printerr("ERROR: Too many units for player %d (max %d)" % [player, UNITS_PER_SIDE])
		return null

	return units


func _generate_random(player: int, occupied: Dictionary) -> Array:
	var rng = RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_msec()

	var row_min = P1_DEPLOY_ROWS_MIN if player == 1 else P2_DEPLOY_ROWS_MIN
	var row_max = P1_DEPLOY_ROWS_MAX if player == 1 else P2_DEPLOY_ROWS_MAX

	var units: Array = []
	for _i in UNITS_PER_SIDE:
		var unit_type = VALID_TYPES[rng.randi_range(0, VALID_TYPES.size() - 1)]

		# Find a valid unoccupied hex
		var col := -1
		var row := -1
		for _attempt in 100:
			var c = rng.randi_range(DEPLOY_C_MIN, DEPLOY_C_MAX)
			var r = rng.randi_range(row_min, row_max)
			var hid = c * 1000 + r
			if not occupied.has(hid):
				col = c
				row = r
				occupied[hid] = true
				break

		if col < 0:
			printerr("ERROR: Could not find deploy hex for random unit")
			return units

		var unit := {"player": player, "col": col, "row": row, "unit_type": unit_type}
		if unit_type == "deep_strike":
			unit["start_turn"] = rng.randi_range(2, 8)
		units.append(unit)

	print("Generated random army for Player %d: %s" % [player, _army_summary(units)])
	return units


func _army_summary(units: Array) -> String:
	var counts := {}
	for u in units:
		var t = u.unit_type
		counts[t] = counts.get(t, 0) + 1
	var parts: Array = []
	for t in counts:
		parts.append("%dx %s" % [counts[t], t])
	return ", ".join(PackedStringArray(parts))


func _is_valid_deploy(col: int, row: int, player: int) -> bool:
	if col < DEPLOY_C_MIN or col > DEPLOY_C_MAX:
		return false
	if player == 1:
		return row >= P1_DEPLOY_ROWS_MIN and row <= P1_DEPLOY_ROWS_MAX
	else:
		return row >= P2_DEPLOY_ROWS_MIN and row <= P2_DEPLOY_ROWS_MAX


func _build_output(result: Dictionary, input_units: Array) -> Dictionary:
	var units: Array = result.get("units", [])
	var names: Array = result.get("unit_names", [])
	var kills: Array = result.get("unit_kills", [])
	var dmg: Array = result.get("unit_dmg", [])
	var dmg_to: Array = result.get("unit_dmg_to", [])
	var obj_arr: Array = result.get("unit_obj", [])
	var vpt: Array = result.get("vp_per_turn", [])
	var obj_ctrl: Array = result.get("obj_control", [])
	var combat_log: Array = result.get("combat_log", [])

	# Final score
	var final_vp = vpt[vpt.size() - 1] if vpt.size() > 0 else [0, 0]
	var winner = "Draw"
	if final_vp[0] > final_vp[1]: winner = "Blue"
	elif final_vp[1] > final_vp[0]: winner = "Red"

	# Per-unit data
	var unit_data: Array = []
	for uid in units.size():
		var u = units[uid]
		var entry := {
			"uid": uid,
			"name": names[uid] if uid < names.size() else "Unit %d" % uid,
			"player": u.player,
			"unit_type": u.unit_type,
			"deploy_col": u.get("deploy_col", -1),
			"deploy_row": u.get("deploy_row", -1),
			"survived": not u.eliminated,
			"eliminated_turn": u.elim_turn if u.eliminated else -1,
			"models_remaining": u.models,
			"damage_dealt": dmg[uid] if uid < dmg.size() else 0,
			"kills": kills[uid] if uid < kills.size() else 0,
			"objectives": obj_arr[uid] if uid < obj_arr.size() else [],
		}
		# Damage target breakdown
		if uid < dmg_to.size():
			var targets := {}
			var dt: Dictionary = dmg_to[uid]
			for tid in dt:
				if dt[tid] > 0:
					var tname = names[tid] if tid < names.size() else "Unit %d" % tid
					targets[tname] = dt[tid]
			entry["damage_targets"] = targets
		if u.get("start_turn", 0) > 0:
			entry["start_turn"] = u.start_turn
		unit_data.append(entry)

	# Score by turn
	var score_by_turn: Array = []
	for vp in vpt:
		score_by_turn.append({"blue": vp[0], "red": vp[1]})

	# Objective control final (as strings)
	var obj_final: Array = []
	for oc in obj_ctrl:
		match oc:
			1: obj_final.append("Blue")
			2: obj_final.append("Red")
			_: obj_final.append("Neutral")

	return {
		"winner": winner,
		"score": {"blue": final_vp[0], "red": final_vp[1]},
		"score_by_turn": score_by_turn,
		"obj_control_final": obj_final,
		"units": unit_data,
		"combat_log": combat_log,
	}


func _print_summary(output: Dictionary):
	print("")
	print("========================================")
	print("  BATTLE RESULTS")
	print("========================================")
	print("Winner: %s" % output.winner)
	print("Score:  Blue %d  -  Red %d" % [output.score.blue, output.score.red])
	print("")

	var obj_final: Array = output.obj_control_final
	for oi in obj_final.size():
		print("  Obj %d: %s" % [oi + 1, obj_final[oi]])
	print("")

	# Per-team unit summaries
	for p in [1, 2]:
		var team = "BLUE" if p == 1 else "RED"
		print("--- %s ---" % team)
		for u in output.units:
			if u.player != p: continue
			var prefix = u.unit_type.substr(0, 1).to_upper()
			if u.unit_type == "deep_strike": prefix = "D"
			var status = "ALIVE (%d models)" % u.models_remaining if u.survived else "DEAD (turn %d)" % u.eliminated_turn
			var dmg_str = "%d dmg, %d kills" % [u.damage_dealt, u.kills]
			print("  %s %s: %s | %s" % [prefix, u.name, status, dmg_str])
		print("")

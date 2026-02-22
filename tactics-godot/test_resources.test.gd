extends SceneTree

# test_resources.test.gd — Validates resource values match original hardcoded constants.
# Run via: run_tests.ps1 (auto-detected) or manually with --script

func _init():
	var pass_count := 0
	var fail_count := 0

	# Load resources
	var grid: GridConfig = load("res://resources/config/grid_config.tres")
	var battle: BattleConfig = load("res://resources/config/battle_config.tres")
	var infantry: UnitStats = load("res://resources/units/infantry.tres")
	var cavalry: UnitStats = load("res://resources/units/cavalry.tres")
	var artillery: UnitStats = load("res://resources/units/artillery.tres")
	var deep_strike: UnitStats = load("res://resources/units/deep_strike.tres")
	var archer: UnitStats = load("res://resources/units/archer.tres")

	# --- Grid Config ---
	var tests: Array = [
		["grid.cols", grid.cols, 56],
		["grid.rows", grid.rows, 40],
		["grid.hex_size", grid.hex_size, 20.0],
		["grid.p1_deploy_rows_min", grid.p1_deploy_rows_min, 32],
		["grid.p1_deploy_rows_max", grid.p1_deploy_rows_max, 39],
		["grid.p2_deploy_rows_min", grid.p2_deploy_rows_min, 0],
		["grid.p2_deploy_rows_max", grid.p2_deploy_rows_max, 7],
		["grid.deploy_col_min", grid.deploy_col_min, 4],
		["grid.deploy_col_max", grid.deploy_col_max, 51],
		["grid.objectives.size", grid.objectives.size(), 3],
		["grid.initial_zoom", grid.initial_zoom, 0.5],

		# --- Battle Config ---
		["battle.units_per_side", battle.units_per_side, 8],
		["battle.turns", battle.turns, 10],
		["battle.combat_range", battle.combat_range, 2],
		["battle.oc_radius", battle.oc_radius, 4],
		["battle.cavalry_aggro", battle.cavalry_aggro, 16],
		["battle.vp_per_objective", battle.vp_per_objective, 5],
		["battle.turn_duration", battle.turn_duration, 0.8],
		["battle.unit_names.size", battle.unit_names.size(), 20],

		# --- Infantry ---
		["infantry.models", infantry.models, 10],
		["infantry.hp", infantry.hp, 2],
		["infantry.move_speed", infantry.move_speed, 10],
		["infantry.attacks", infantry.attacks, 2],
		["infantry.hit", infantry.hit, 3],
		["infantry.wound", infantry.wound, 3],
		["infantry.rend", infantry.rend, 1],
		["infantry.armor", infantry.armor, 4],
		["infantry.damage", infantry.damage, 1],
		["infantry.prefix", infantry.prefix, "I"],
		["infantry.footprint(10)", infantry.get_footprint(10), 5],

		# --- Cavalry ---
		["cavalry.models", cavalry.models, 6],
		["cavalry.hp", cavalry.hp, 3],
		["cavalry.move_speed", cavalry.move_speed, 24],
		["cavalry.rend", cavalry.rend, 2],
		["cavalry.damage", cavalry.damage, 2],
		["cavalry.aggro_range", cavalry.aggro_range, 16],
		["cavalry.prefix", cavalry.prefix, "C"],
		["cavalry.footprint(6)", cavalry.get_footprint(6), 3],

		# --- Artillery ---
		["artillery.models", artillery.models, 1],
		["artillery.hp", artillery.hp, 12],
		["artillery.move_speed", artillery.move_speed, 8],
		["artillery.attack_range", artillery.attack_range, 40],
		["artillery.targets_furthest", artillery.targets_furthest, true],
		["artillery.fixed_footprint", artillery.fixed_footprint, 5],
		["artillery.has_melee_override", artillery.has_melee_override, true],
		["artillery.melee_attacks", artillery.melee_attacks, 1],
		["artillery.melee_hit", artillery.melee_hit, 5],
		["artillery.prefix", artillery.prefix, "A"],
		["artillery.footprint(1)", artillery.get_footprint(1), 5],

		# --- Deep Strike ---
		["deep_strike.models", deep_strike.models, 8],
		["deep_strike.hp", deep_strike.hp, 3],
		["deep_strike.move_speed", deep_strike.move_speed, 16],
		["deep_strike.can_deep_strike", deep_strike.can_deep_strike, true],
		["deep_strike.prefix", deep_strike.prefix, "D"],
		["deep_strike.footprint(8)", deep_strike.get_footprint(8), 4],

		# --- Archer ---
		["archer.models", archer.models, 8],
		["archer.hp", archer.hp, 2],
		["archer.move_speed", archer.move_speed, 16],
		["archer.attack_range", archer.attack_range, 24],
		["archer.can_retreat", archer.can_retreat, true],
		["archer.retreat_move", archer.retreat_move, 16],
		["archer.has_melee_override", archer.has_melee_override, true],
		["archer.melee_wound", archer.melee_wound, 5],
		["archer.prefix", archer.prefix, "W"],
		["archer.footprint(8)", archer.get_footprint(8), 4],
	]

	# --- Legacy dict bridge ---
	var inf_dict = infantry.to_legacy_dict()
	tests.append_array([
		["infantry.legacy.models", inf_dict.get("models"), 10],
		["infantry.legacy.hp", inf_dict.get("hp"), 2],
		["infantry.legacy.move", inf_dict.get("move"), 10],
		["infantry.legacy.attacks", inf_dict.get("attacks"), 2],
		["infantry.legacy.rend", inf_dict.get("rend"), 1],
		["infantry.legacy.no_footprint", inf_dict.has("footprint"), false],
	])

	var art_dict = artillery.to_legacy_dict()
	tests.append_array([
		["artillery.legacy.footprint", art_dict.get("footprint"), 5],
		["artillery.legacy.range", art_dict.get("range"), 40],
		["artillery.legacy.targets_furthest", art_dict.get("targets_furthest"), true],
		["artillery.legacy.melee_attacks", art_dict.get("melee_attacks"), 1],
	])

	var arch_dict = archer.to_legacy_dict()
	tests.append_array([
		["archer.legacy.retreat_move", arch_dict.get("retreat_move"), 16],
		["archer.legacy.range", arch_dict.get("range"), 24],
	])

	# --- Terrain resources ---
	var grass: TerrainType = load("res://resources/terrain/grass.tres")
	var forest: TerrainType = load("res://resources/terrain/forest.tres")
	var water: TerrainType = load("res://resources/terrain/water.tres")
	tests.append_array([
		["grass.passable", grass.passable, true],
		["grass.move_cost", grass.move_cost, 1.0],
		["grass.cover_bonus", grass.cover_bonus, 0],
		["forest.passable", forest.passable, true],
		["forest.move_cost", forest.move_cost, 2.0],
		["forest.cover_bonus", forest.cover_bonus, 1],
		["water.passable", water.passable, false],
	])

	# Run all tests
	for t in tests:
		var name: String = t[0]
		var actual = t[1]
		var expected = t[2]
		if actual == expected:
			pass_count += 1
		else:
			fail_count += 1
			printerr("FAILED: %s — expected %s, got %s" % [name, str(expected), str(actual)])

	if fail_count > 0:
		printerr("FAILED: %d of %d tests did not pass" % [fail_count, pass_count + fail_count])
	else:
		print("Resource validation: all %d tests passed" % pass_count)
	quit()

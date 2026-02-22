class_name CombatSimulator
extends RefCounted
## Standalone combat simulation engine. No scene-tree dependency.
## Owns AStar2D pathfinding, AI targeting, combat rolls, and the main simulate() loop.

# ---- Resources (preloaded, shared singletons) ----
var _grid: GridConfig = preload("res://resources/config/grid_config.tres")
var _battle: BattleConfig = preload("res://resources/config/battle_config.tres")
var _unit_resources: Array = [
	preload("res://resources/units/infantry.tres"),
	preload("res://resources/units/cavalry.tres"),
	preload("res://resources/units/artillery.tres"),
	preload("res://resources/units/deep_strike.tres"),
	preload("res://resources/units/archer.tres"),
]

# ---- Cached data ----
var _legacy_stats: Dictionary = {}
var _unit_type_keys: Array[String] = []

# ---- Terrain ----
var _terrain_resources: Dictionary = {}
var _terrain_data: Dictionary = {}
var _default_terrain_key: String = "grass"

# ---- AStar2D ----
var astar := AStar2D.new()
var _astar_built := false

# ---- Config property shortcuts ----
var COLS: int:
	get: return _grid.cols
var ROWS: int:
	get: return _grid.rows
var TURNS: int:
	get: return _battle.turns
var OBJECTIVES: Array:
	get: return _grid.objectives
var COMBAT_RANGE: int:
	get: return _battle.combat_range
var OC_RADIUS: int:
	get: return _battle.oc_radius
var CAVALRY_AGGRO: int:
	get: return _battle.cavalry_aggro
var UNIT_NAMES: Array:
	get: return _battle.unit_names
var P1_DEPLOY_ROWS_MIN: int:
	get: return _grid.p1_deploy_rows_min
var P1_DEPLOY_ROWS_MAX: int:
	get: return _grid.p1_deploy_rows_max
var P2_DEPLOY_ROWS_MIN: int:
	get: return _grid.p2_deploy_rows_min
var P2_DEPLOY_ROWS_MAX: int:
	get: return _grid.p2_deploy_rows_max
var DEPLOY_C_MIN: int:
	get: return _grid.deploy_col_min
var DEPLOY_C_MAX: int:
	get: return _grid.deploy_col_max

func _init(terrain_resources: Dictionary = {}, terrain_data: Dictionary = {}):
	for res in _unit_resources:
		_legacy_stats[res.unit_type_key] = res.to_legacy_dict()
		_unit_type_keys.append(res.unit_type_key)
	_terrain_resources = terrain_resources
	_terrain_data = terrain_data
	if _terrain_resources.is_empty():
		# Fallback: load terrain resources ourselves
		var terrain_list: Array = [
			preload("res://resources/terrain/grass.tres"),
			preload("res://resources/terrain/forest.tres"),
			preload("res://resources/terrain/water.tres"),
		]
		for tres in terrain_list:
			_terrain_resources[tres.terrain_key] = tres

# ============================================================================
# PUBLIC API
# ============================================================================

func get_stats(unit_type: String) -> Dictionary:
	return _legacy_stats.get(unit_type, _legacy_stats.get("infantry", {}))

func get_unit_prefix(unit_type: String) -> String:
	return _get_unit_res(unit_type).prefix

func compute_footprint(unit_type: String, models: int) -> int:
	return _get_unit_res(unit_type).get_footprint(models)

func build_blocked_from_units(units: Array, exclude_uid: int, turn: int, exclude_goal: Vector2i = Vector2i(-999, -999)) -> Dictionary:
	var blocked := {}
	for i in units.size():
		if i == exclude_uid or units[i].eliminated: continue
		if units[i].start_turn > 0 and turn < units[i].start_turn: continue
		var form: Array = units[i].get("formation", [])
		if form.is_empty():
			blocked[HexMath.hex_id(units[i].col, units[i].row)] = true
		else:
			for fh in form:
				if fh == exclude_goal: continue
				blocked[HexMath.hex_id(fh.x, fh.y)] = true
	return blocked

func find_path(sc: int, sr: int, gc: int, gr: int, blocked: Dictionary = {}) -> Array[Vector2i]:
	if not _astar_built:
		_build_astar_base()
	var disabled: Array[int] = []
	for bid in blocked:
		if astar.has_point(bid):
			astar.set_point_disabled(bid, true)
			disabled.append(bid)
	var sid = HexMath.hex_id(sc, sr)
	var gid = HexMath.hex_id(gc, gr)
	var result: Array[Vector2i] = []
	if astar.has_point(sid) and not astar.is_point_disabled(sid) and astar.has_point(gid) and not astar.is_point_disabled(gid):
		var id_path = astar.get_id_path(sid, gid)
		for id in id_path.slice(1):
			result.append(HexMath.id_to_hex(id))
	for bid in disabled:
		astar.set_point_disabled(bid, false)
	return result

static func build_trail_hex_cache(sim: Dictionary, turns: int) -> Dictionary:
	var cache := {}
	var formations_tl: Array = sim.get("formations_timeline", [])
	var final_units: Array = sim.get("units", [])
	for uid in formations_tl.size():
		var ftl: Array = formations_tl[uid]
		var u = final_units[uid]
		var alive_until = u.elim_turn if u.eliminated else turns
		var max_ti = mini(alive_until + 1, ftl.size() - 1)
		for ti in (max_ti + 1):
			var form: Array = ftl[ti]
			for fh in form:
				if fh == Vector2i(-1, -1): continue
				var hid = HexMath.hex_id(fh.x, fh.y)
				if not cache.has(hid):
					cache[hid] = uid
	return cache

# ============================================================================
# SIMULATION
# ============================================================================

func simulate(input_units: Array) -> Dictionary:
	var units: Array = []
	for i in input_units.size():
		var src = input_units[i]
		var stats = get_stats(src.get("unit_type", "infantry"))
		var st = src.get("start_turn", 0)
		units.append({
			"player"    : src.player,
			"col"       : src.col,
			"row"       : src.row,
			"unit_type" : src.get("unit_type", "infantry"),
			"models"    : stats.models,
			"wounds"    : 0,
			"eliminated": false,
			"elim_turn" : -1,
			"start_turn": st,
			"arrived"   : st <= 0,
			"has_retreated": false,
			"has_disrupted": false,
			"disrupted": false,
			"disrupted_turn": -1,
			"disrupted_from": Vector2i(-1, -1),
			"deploy_col": src.col,
			"deploy_row": src.row,
			"formation" : [],
		})

	# Compute initial formations
	var _zone_blocked_p1 := {}
	var _zone_blocked_p2 := {}
	for c in COLS:
		for r in ROWS:
			if HexMath.is_valid_hex(c, r):
				var hid = HexMath.hex_id(c, r)
				if r < P1_DEPLOY_ROWS_MIN or r > P1_DEPLOY_ROWS_MAX or c < DEPLOY_C_MIN or c > DEPLOY_C_MAX:
					_zone_blocked_p1[hid] = true
				if r < P2_DEPLOY_ROWS_MIN or r > P2_DEPLOY_ROWS_MAX or c < DEPLOY_C_MIN or c > DEPLOY_C_MAX:
					_zone_blocked_p2[hid] = true
	for uid in units.size():
		var u = units[uid]
		if u.start_turn > 0: continue
		var src_form: Array = input_units[uid].get("formation", [])
		if not src_form.is_empty():
			u.formation = src_form.duplicate()
			units[uid] = u
			continue
		var fp = compute_footprint(u.unit_type, u.models)
		var b: Dictionary = (_zone_blocked_p1 if u.player == 1 else _zone_blocked_p2).duplicate()
		for uid2 in uid:
			if units[uid2].start_turn > 0: continue
			for fh in units[uid2].formation:
				b[HexMath.hex_id(fh.x, fh.y)] = true
		u.formation = HexMath.compute_compact_cluster(Vector2i(u.col, u.row), fp, b)
		units[uid] = u

	var timelines: Array = []
	var formations_timeline: Array = []
	for u in units:
		var start_pos = Vector2i(-1, -1) if u.start_turn > 0 else Vector2i(u.col, u.row)
		timelines.append([start_pos])
		formations_timeline.append([u.formation.duplicate()])

	# Random unit names
	var name_rng = RandomNumberGenerator.new()
	name_rng.seed = 7777
	var name_pool = UNIT_NAMES.duplicate()
	for i in range(name_pool.size() - 1, 0, -1):
		var j = name_rng.randi() % (i + 1)
		var tmp = name_pool[i]
		name_pool[i] = name_pool[j]
		name_pool[j] = tmp
	var unit_names: Array = []
	for i in units.size():
		unit_names.append(name_pool[i % name_pool.size()])

	# Per-unit fate tracking
	var unit_obj: Array = []
	var unit_kills: Array = []
	var unit_dmg: Array = []
	var unit_dmg_to: Array = []
	for _i in units.size():
		unit_obj.append(["no", "no", "no"])
		unit_kills.append(0)
		unit_dmg.append(0)
		unit_dmg_to.append({})

	var combat_events: Array = []
	for _t in TURNS:
		combat_events.append([])

	var obj_control: Array = []
	for _i in OBJECTIVES.size():
		obj_control.append(0)

	var vp_per_turn: Array = []
	var p1_vp_total := 0
	var p2_vp_total := 0

	var obj_ctrl_history: Array = []
	var unit_snapshots: Array = []

	var combat_log: Array = []
	var p1_count = 0; var p2_count = 0
	for u in units:
		if u.player == 1: p1_count += 1
		else: p2_count += 1
	combat_log.append("=== Deployment: %d units (%d Blue, %d Red) ===" % [units.size(), p1_count, p2_count])
	for uid3 in units.size():
		var u3 = units[uid3]
		var tc3 = get_unit_prefix(u3.unit_type)
		var tm3 = "Blue" if u3.player == 1 else "Red"
		combat_log.append("  %s %s (%s) at (%d,%d)" % [tc3, unit_names[uid3], tm3, u3.col, u3.row])
	combat_log.append("")

	for turn in TURNS:
		combat_log.append("--- Turn %d ---" % [turn + 1])

		# ---- Deep strike arrival ----
		for uid in units.size():
			var u = units[uid]
			if u.start_turn > 0 and turn == u.start_turn:
				u.col = u.deploy_col
				u.row = u.deploy_row
				u.arrived = true
				var ds_blocked = build_blocked_from_units(units, uid, turn)
				var ds_fp = compute_footprint(u.unit_type, u.models)
				u.formation = HexMath.compute_compact_cluster(Vector2i(u.col, u.row), ds_fp, ds_blocked)
				units[uid] = u
				combat_log.append("  %s %s arrives via deep strike at (%d,%d)!" % [get_unit_prefix(u.unit_type), unit_names[uid], u.col, u.row])

		# ---- Track cavalry that started in melee range ----
		var cav_no_charge := {}
		for uid in units.size():
			var u = units[uid]
			if u.unit_type != "cavalry" or u.eliminated: continue
			if u.start_turn > 0 and turn < u.start_turn: continue
			for eid in units.size():
				var e = units[eid]
				if e.eliminated or e.player == u.player: continue
				if e.start_turn > 0 and turn < e.start_turn: continue
				if HexMath.formation_dist(u.get("formation", [Vector2i(u.col, u.row)]), e.get("formation", [Vector2i(e.col, e.row)])) <= COMBAT_RANGE:
					cav_no_charge[uid] = true
					break

		# ---- Movement ----
		for uid in units.size():
			var u = units[uid]
			if u.start_turn > 0 and turn < u.start_turn:
				timelines[uid].append(Vector2i(-1, -1))
				formations_timeline[uid].append([])
				continue
			if u.eliminated:
				timelines[uid].append(Vector2i(u.col, u.row))
				formations_timeline[uid].append(u.formation.duplicate())
				continue

			var ut = u.unit_type
			var stats = get_stats(ut)

			# Artillery: stay if has ranged target, else walk forward
			if ut == "artillery":
				if _find_ranged_target(uid, units, stats) >= 0:
					timelines[uid].append(Vector2i(u.col, u.row))
					formations_timeline[uid].append(u.formation.duplicate())
					continue
				var fwd_row = u.row + (-1 if u.player == 1 else 1)
				fwd_row = clampi(fwd_row, 0, ROWS - 1)
				var fwd_goal = Vector2i(u.col, fwd_row)
				var blocked_art = build_blocked_from_units(units, uid, turn, fwd_goal)
				var art_path = find_path(u.col, u.row, fwd_goal.x, fwd_goal.y, blocked_art)
				var art_steps = mini(stats.move, art_path.size())
				for step_i in art_steps:
					var nxt = art_path[step_i]
					u.col = nxt.x; u.row = nxt.y
					units[uid] = u
				var art_post_blocked = build_blocked_from_units(units, uid, turn)
				var art_fp = compute_footprint(ut, u.models)
				u.formation = HexMath.compute_compact_cluster(Vector2i(u.col, u.row), art_fp, art_post_blocked)
				units[uid] = u
				timelines[uid].append(Vector2i(u.col, u.row))
				formations_timeline[uid].append(u.formation.duplicate())
				continue

			# Archer: avoid melee range, kite at max range
			elif ut == "archer":
				if _nearest_enemy_in_range(uid, units, COMBAT_RANGE) < 0:
					var archer_goal = _pick_archer_target(uid, units)
					if archer_goal == Vector2i(u.col, u.row):
						timelines[uid].append(archer_goal)
						formations_timeline[uid].append(u.formation.duplicate())
						continue
					var blocked = build_blocked_from_units(units, uid, turn, archer_goal)
					var path = find_path(u.col, u.row, archer_goal.x, archer_goal.y, blocked)
					var move_steps = mini(stats.move, path.size())
					for step_i in move_steps:
						var nxt = path[step_i]
						var would_engage = false
						for oid in units.size():
							if oid == uid or units[oid].eliminated or units[oid].player == u.player: continue
							if units[oid].start_turn > 0 and turn < units[oid].start_turn: continue
							if HexMath.formation_dist_to_hex(units[oid].get("formation", [Vector2i(units[oid].col, units[oid].row)]), nxt) <= COMBAT_RANGE:
								would_engage = true
								break
						if would_engage:
							break
						u.col = nxt.x; u.row = nxt.y
						units[uid] = u
					var arch_post_blocked = build_blocked_from_units(units, uid, turn)
					var arch_fp = compute_footprint(ut, u.models)
					u.formation = HexMath.compute_compact_cluster(Vector2i(u.col, u.row), arch_fp, arch_post_blocked)
					units[uid] = u
					timelines[uid].append(Vector2i(u.col, u.row))
					formations_timeline[uid].append(u.formation.duplicate())
					continue
				else:
					timelines[uid].append(Vector2i(u.col, u.row))
					formations_timeline[uid].append(u.formation.duplicate())
					continue

			# Deep strike temporal disruption
			if ut == "deep_strike" and not u.has_disrupted:
				if _nearest_enemy_in_range(uid, units, COMBAT_RANGE) >= 0:
					timelines[uid].append(Vector2i(u.col, u.row))
					formations_timeline[uid].append(u.formation.duplicate())
					continue
				var trail_target = _pick_trail_target(uid, units, timelines, formations_timeline, turn)
				if trail_target.is_empty():
					pass
				else:
					var t_hex: Vector2i = trail_target.hex
					var t_eid: int = trail_target.enemy_uid
					var blocked_ds = build_blocked_from_units(units, uid, turn, t_hex)
					var ds_path = find_path(u.col, u.row, t_hex.x, t_hex.y, blocked_ds)
					var ds_move_steps = mini(stats.move, ds_path.size())
					for step_i in ds_move_steps:
						var nxt = ds_path[step_i]
						u.col = nxt.x; u.row = nxt.y
						u.formation = [Vector2i(u.col, u.row)]
						units[uid] = u
					var u_form_post = u.get("formation", [Vector2i(u.col, u.row)])
					if HexMath.formation_dist_to_hex(u_form_post, t_hex) <= COMBAT_RANGE:
						var enemy = units[t_eid]
						if not enemy.eliminated:
							var old_pos = Vector2i(enemy.col, enemy.row)
							enemy.col = t_hex.x
							enemy.row = t_hex.y
							enemy.disrupted = true
							enemy.disrupted_turn = turn
							enemy.disrupted_from = old_pos
							var e_blocked = build_blocked_from_units(units, t_eid, turn)
							var e_fp = compute_footprint(enemy.unit_type, enemy.models)
							enemy.formation = HexMath.compute_compact_cluster(Vector2i(enemy.col, enemy.row), e_fp, e_blocked)
							units[t_eid] = enemy
							if timelines[t_eid].size() > turn + 1:
								timelines[t_eid][timelines[t_eid].size() - 1] = Vector2i(enemy.col, enemy.row)
								formations_timeline[t_eid][formations_timeline[t_eid].size() - 1] = enemy.formation.duplicate()
							combat_log.append("  >> TEMPORAL DISRUPTION: %s %s yanks %s %s from (%d,%d) back to (%d,%d)!" % [
								get_unit_prefix(u.unit_type), unit_names[uid],
								get_unit_prefix(enemy.unit_type), unit_names[t_eid],
								old_pos.x, old_pos.y, enemy.col, enemy.row])
						else:
							combat_log.append("  >> %s %s reaches trail of eliminated %s %s — disruption wasted!" % [
								get_unit_prefix(u.unit_type), unit_names[uid],
								get_unit_prefix(units[t_eid].unit_type), unit_names[t_eid]])
						u.has_disrupted = true
						units[uid] = u
					var ds_post_blocked = build_blocked_from_units(units, uid, turn)
					var ds_fp = compute_footprint(ut, u.models)
					u.formation = HexMath.compute_compact_cluster(Vector2i(u.col, u.row), ds_fp, ds_post_blocked)
					units[uid] = u
					timelines[uid].append(Vector2i(u.col, u.row))
					formations_timeline[uid].append(u.formation.duplicate())
					continue

			# Default: infantry, cavalry, deep_strike, artillery fallback
			if _nearest_enemy_in_range(uid, units, COMBAT_RANGE) >= 0:
				timelines[uid].append(Vector2i(u.col, u.row))
				formations_timeline[uid].append(u.formation.duplicate())
				continue

			var goal = _pick_target(uid, units)
			if goal == Vector2i(u.col, u.row):
				timelines[uid].append(goal)
				formations_timeline[uid].append(u.formation.duplicate())
				continue

			var blocked = build_blocked_from_units(units, uid, turn, goal)
			var path = find_path(u.col, u.row, goal.x, goal.y, blocked)
			var move_steps = mini(stats.move, path.size())
			for step_i in move_steps:
				var nxt = path[step_i]
				u.col = nxt.x; u.row = nxt.y
				u.formation = [Vector2i(u.col, u.row)]
				units[uid] = u
				if _nearest_enemy_in_range(uid, units, COMBAT_RANGE) >= 0:
					break
			var post_blocked = build_blocked_from_units(units, uid, turn)
			var fp = compute_footprint(ut, u.models)
			u.formation = HexMath.compute_compact_cluster(Vector2i(u.col, u.row), fp, post_blocked)
			units[uid] = u
			timelines[uid].append(Vector2i(u.col, u.row))
			formations_timeline[uid].append(u.formation.duplicate())

		# Log movement
		for uid2 in units.size():
			var u2 = units[uid2]
			if u2.eliminated: continue
			if u2.start_turn > 0 and turn < u2.start_turn: continue
			var tl = timelines[uid2]
			if tl.size() < 2: continue
			var prev = tl[tl.size() - 2]
			var cur  = tl[tl.size() - 1]
			if prev != cur and prev != Vector2i(-1, -1):
				var tc2 = get_unit_prefix(u2.unit_type)
				var tm2 = "Blue" if u2.player == 1 else "Red"
				combat_log.append("  %s %s (%s) moves (%d,%d)->(%d,%d)" % [tc2, unit_names[uid2], tm2, prev.x, prev.y, cur.x, cur.y])

		# ---- Ranged Phase ----
		var ranged_shot := {}
		for uid in units.size():
			var u = units[uid]
			if u.eliminated: continue
			if u.start_turn > 0 and turn < u.start_turn: continue
			var stats = get_stats(u.unit_type)
			if not stats.has("range"): continue
			if _nearest_enemy_in_range(uid, units, COMBAT_RANGE) >= 0: continue
			var tid = _find_ranged_target(uid, units, stats)
			if tid < 0: continue
			ranged_shot[uid] = true
			var t = units[tid]
			var rng := RandomNumberGenerator.new()
			var rseed: int = turn * 13 + uid * 100003 + tid * 999983
			for ni in units.size():
				var nu = units[ni]
				if nu.eliminated: continue
				if nu.start_turn > 0 and turn < nu.start_turn: continue
				var nu_form = nu.get("formation", [Vector2i(nu.col, nu.row)])
				if HexMath.formation_dist(nu_form, u.get("formation", [Vector2i(u.col, u.row)])) <= COMBAT_RANGE or \
				   HexMath.formation_dist(nu_form, t.get("formation", [Vector2i(t.col, t.row)])) <= COMBAT_RANGE:
					rseed = rseed ^ (nu.col * 31 + nu.row * 97 + nu.player * 7919 + ni * 1009)
			rng.seed = rseed
			var dmg = _roll_combat(u, t, rng)
			unit_dmg[uid] += dmg
			if not unit_dmg_to[uid].has(tid): unit_dmg_to[uid][tid] = 0
			unit_dmg_to[uid][tid] += dmg
			var t_mdl_before = units[tid].models
			_apply_wounds(tid, units, dmg, turn)
			combat_events[turn].append({ "a": uid, "b": tid,
				"ac": u.col, "ar": u.row, "bc": t.col, "br": t.row })
			var u_tc = get_unit_prefix(u.unit_type)
			var t_tc = get_unit_prefix(t.unit_type)
			combat_log.append("  %s %s shoots %s %s (range):" % [u_tc, unit_names[uid], t_tc, unit_names[tid]])
			if dmg > 0:
				var lost = t_mdl_before - units[tid].models
				var lost_s = " (%d models killed)" % lost if lost > 0 else ""
				combat_log.append("    %s takes %d wounds%s" % [unit_names[tid], dmg, lost_s])
			else:
				combat_log.append("    No wounds dealt")
			if units[tid].eliminated and units[tid].elim_turn == turn:
				unit_kills[uid] += 1
				combat_log.append("    >>> %s %s ELIMINATED <<<" % [t_tc, unit_names[tid]])

		# ---- Melee Phase ----
		var fought := {}
		var melee_participants := {}
		for uid in units.size():
			var u = units[uid]
			if u.eliminated: continue
			if u.start_turn > 0 and turn < u.start_turn: continue
			var eid = _nearest_enemy_in_range(uid, units, COMBAT_RANGE)
			if eid < 0: continue
			var pair_key = mini(uid, eid) * 10000 + maxi(uid, eid)
			if fought.has(pair_key): continue
			fought[pair_key] = true
			melee_participants[uid] = true
			melee_participants[eid] = true
			var e = units[eid]
			combat_events[turn].append({ "a": uid, "b": eid,
				"ac": u.col, "ar": u.row, "bc": e.col, "br": e.row })

			var fight_rng := RandomNumberGenerator.new()
			var fight_seed: int = turn * 7 + mini(uid, eid) * 100003 + maxi(uid, eid) * 999983
			for ni in units.size():
				var nu = units[ni]
				if nu.eliminated: continue
				if nu.start_turn > 0 and turn < nu.start_turn: continue
				var nu_form = nu.get("formation", [Vector2i(nu.col, nu.row)])
				if HexMath.formation_dist(nu_form, u.get("formation", [Vector2i(u.col, u.row)])) <= COMBAT_RANGE or \
				   HexMath.formation_dist(nu_form, e.get("formation", [Vector2i(e.col, e.row)])) <= COMBAT_RANGE:
					fight_seed = fight_seed ^ (nu.col * 31 + nu.row * 97 + nu.player * 7919 + ni * 1009)
			fight_rng.seed = fight_seed
			var dmg_to_e = _roll_melee(u, e, fight_rng)
			var dmg_to_u = _roll_melee(e, u, fight_rng)
			if u.unit_type == "archer" and not u.has_retreated:
				dmg_to_e = dmg_to_e / 2
				dmg_to_u = dmg_to_u / 2
			if e.unit_type == "archer" and not e.has_retreated:
				dmg_to_e = dmg_to_e / 2
				dmg_to_u = dmg_to_u / 2
			if cav_no_charge.has(uid) or (u.unit_type == "cavalry" and u.disrupted and u.disrupted_turn == turn):
				dmg_to_e = dmg_to_e / 2
			if cav_no_charge.has(eid) or (e.unit_type == "cavalry" and e.disrupted and e.disrupted_turn == turn):
				dmg_to_u = dmg_to_u / 2
			unit_dmg[uid] += dmg_to_e
			unit_dmg[eid] += dmg_to_u
			if not unit_dmg_to[uid].has(eid): unit_dmg_to[uid][eid] = 0
			unit_dmg_to[uid][eid] += dmg_to_e
			if not unit_dmg_to[eid].has(uid): unit_dmg_to[eid][uid] = 0
			unit_dmg_to[eid][uid] += dmg_to_u
			var u_mdl_before = units[uid].models
			var e_mdl_before = units[eid].models
			_apply_wounds(uid, units, dmg_to_u, turn)
			_apply_wounds(eid, units, dmg_to_e, turn)

			var u_tc = get_unit_prefix(u.unit_type)
			var e_tc = get_unit_prefix(e.unit_type)
			combat_log.append("  %s %s vs %s %s (melee):" % [u_tc, unit_names[uid], e_tc, unit_names[eid]])
			if dmg_to_u > 0:
				var lost = u_mdl_before - units[uid].models
				var lost_s = " (%d models killed)" % lost if lost > 0 else ""
				combat_log.append("    %s takes %d wounds%s" % [unit_names[uid], dmg_to_u, lost_s])
			if dmg_to_e > 0:
				var lost = e_mdl_before - units[eid].models
				var lost_s = " (%d models killed)" % lost if lost > 0 else ""
				combat_log.append("    %s takes %d wounds%s" % [unit_names[eid], dmg_to_e, lost_s])
			if dmg_to_u == 0 and dmg_to_e == 0:
				combat_log.append("    No wounds dealt")

			if units[eid].eliminated and units[eid].elim_turn == turn:
				unit_kills[uid] += 1
				combat_log.append("    >>> %s %s ELIMINATED <<<" % [e_tc, unit_names[eid]])
			if units[uid].eliminated and units[uid].elim_turn == turn:
				unit_kills[eid] += 1
				combat_log.append("    >>> %s %s ELIMINATED <<<" % [u_tc, unit_names[uid]])

		# ---- Archer Retreat Phase ----
		for uid in units.size():
			var u = units[uid]
			if u.unit_type != "archer": continue
			if u.eliminated: continue
			if not melee_participants.has(uid): continue
			var best_hex := Vector2i(u.col, u.row)
			var best_score := -1.0
			var retreat_blocked = build_blocked_from_units(units, uid, turn)
			var visited := { HexMath.hex_id(u.col, u.row): 0 }
			var frontier := [Vector2i(u.col, u.row)]
			var retreat_stats = get_stats("archer")
			var max_steps = retreat_stats.get("retreat_move", 5)
			for _step in max_steps:
				var next_frontier: Array = []
				for fh in frontier:
					var fdist = visited[HexMath.hex_id(fh.x, fh.y)]
					if fdist >= max_steps: continue
					for nb in HexMath.hex_neighbors(fh.x, fh.y):
						var nid = HexMath.hex_id(nb.x, nb.y)
						if not HexMath.is_valid_hex(nb.x, nb.y): continue
						if visited.has(nid): continue
						if retreat_blocked.has(nid): continue
						visited[nid] = fdist + 1
						next_frontier.append(nb)
				frontier = next_frontier
			for hid in visited:
				var hx = HexMath.id_to_hex(hid)
				var min_dist := 999
				for i in units.size():
					if i == uid or units[i].eliminated: continue
					if units[i].start_turn > 0 and turn < units[i].start_turn: continue
					var d = HexMath.formation_dist_to_hex(units[i].get("formation", [Vector2i(units[i].col, units[i].row)]), hx)
					if d < min_dist: min_dist = d
				for obj in OBJECTIVES:
					var d = HexMath.hex_dist(hx.x, hx.y, obj.x, obj.y)
					if d < min_dist: min_dist = d
				if min_dist > best_score:
					best_score = min_dist
					best_hex = hx
			if best_hex != Vector2i(u.col, u.row):
				u.col = best_hex.x; u.row = best_hex.y
				var ret_blocked = build_blocked_from_units(units, uid, turn)
				var ret_fp = compute_footprint(u.unit_type, u.models)
				u.formation = HexMath.compute_compact_cluster(Vector2i(u.col, u.row), ret_fp, ret_blocked)
				units[uid] = u
				timelines[uid][timelines[uid].size() - 1] = best_hex
				formations_timeline[uid][formations_timeline[uid].size() - 1] = u.formation.duplicate()
				combat_log.append("  W %s retreats to (%d,%d)" % [unit_names[uid], best_hex.x, best_hex.y])
			if not u.has_retreated:
				u.has_retreated = true
				units[uid] = u

		# ---- Update persistent objective control ----
		for oi in OBJECTIVES.size():
			var obj = OBJECTIVES[oi]
			var old_ctrl = obj_control[oi]
			var p1_oc := 0; var p2_oc := 0
			for u in units:
				if u.eliminated: continue
				if u.start_turn > 0 and turn < u.start_turn: continue
				var ust = get_stats(u.unit_type)
				var u_form = u.get("formation", [Vector2i(u.col, u.row)])
				if HexMath.formation_dist_to_hex(u_form, obj) <= OC_RADIUS:
					var oc_total = ust.get("oc", 1) * u.models
					if u.player == 1: p1_oc += oc_total
					else:              p2_oc += oc_total
			if p1_oc > p2_oc and p1_oc > 0:
				obj_control[oi] = 1
			elif p2_oc > p1_oc and p2_oc > 0:
				obj_control[oi] = 2
			for uid2 in units.size():
				var u2 = units[uid2]
				if u2.eliminated: continue
				if u2.start_turn > 0 and turn < u2.start_turn: continue
				var u2_form = u2.get("formation", [Vector2i(u2.col, u2.row)])
				if HexMath.formation_dist_to_hex(u2_form, obj) > OC_RADIUS: continue
				if obj_control[oi] == u2.player and old_ctrl != u2.player:
					unit_obj[uid2][oi] = "won"
				elif p1_oc > 0 and p2_oc > 0 and unit_obj[uid2][oi] != "won":
					unit_obj[uid2][oi] = "yes"

		# Tally VP
		var vp_per_obj: int = _battle.vp_per_objective
		for oi2 in OBJECTIVES.size():
			if obj_control[oi2] == 1: p1_vp_total += vp_per_obj
			elif obj_control[oi2] == 2: p2_vp_total += vp_per_obj
		vp_per_turn.append([p1_vp_total, p2_vp_total])

		combat_log.append("  Objectives:")
		for oi3 in OBJECTIVES.size():
			var ctrl_s = "Neutral"
			if obj_control[oi3] == 1: ctrl_s = "Blue"
			elif obj_control[oi3] == 2: ctrl_s = "Red"
			combat_log.append("    O%d (%d,%d): %s" % [oi3 + 1, OBJECTIVES[oi3].x, OBJECTIVES[oi3].y, ctrl_s])
		combat_log.append("  Score: Blue %d - Red %d" % [p1_vp_total, p2_vp_total])
		combat_log.append("")

		obj_ctrl_history.append(obj_control.duplicate())
		var snap: Array = []
		for uid2 in units.size():
			var u2 = units[uid2]
			snap.append({ "models": u2.models, "eliminated": u2.eliminated, "col": u2.col, "row": u2.row, "formation": u2.formation.duplicate() })
		unit_snapshots.append(snap)

	return { "timelines": timelines, "formations_timeline": formations_timeline, "units": units, "combat": combat_events, "obj_control": obj_control, "vp_per_turn": vp_per_turn, "unit_names": unit_names, "unit_obj": unit_obj, "unit_kills": unit_kills, "unit_dmg": unit_dmg, "unit_dmg_to": unit_dmg_to, "combat_log": combat_log, "obj_ctrl_history": obj_ctrl_history, "unit_snapshots": unit_snapshots }

# ============================================================================
# PRIVATE HELPERS
# ============================================================================

func _get_unit_res(unit_type: String) -> UnitStats:
	for res in _unit_resources:
		if res.unit_type_key == unit_type:
			return res
	return _unit_resources[0]

func _get_terrain_at(col: int, row: int) -> TerrainType:
	var key = _terrain_data.get(HexMath.hex_id(col, row), _default_terrain_key)
	return _terrain_resources.get(key, _terrain_resources.get("grass"))

func _build_astar_base():
	astar.clear()
	astar.reserve_space(COLS * ROWS)
	for r in ROWS:
		for c in COLS:
			astar.add_point(HexMath.hex_id(c, r), Vector2(c, r))
	for r in ROWS:
		for c in COLS:
			var id = HexMath.hex_id(c, r)
			var terrain = _get_terrain_at(c, r)
			if not terrain.passable:
				astar.set_point_disabled(id, true)
			elif terrain.move_cost != 1.0:
				astar.set_point_weight_scale(id, terrain.move_cost)
			for nb in HexMath.hex_neighbors(c, r):
				var nb_id = HexMath.hex_id(nb.x, nb.y)
				if not astar.are_points_connected(id, nb_id):
					astar.connect_points(id, nb_id)
	_astar_built = true

func _pick_target(uid: int, units: Array) -> Vector2i:
	var u   = units[uid]
	var u_form = u.get("formation", [Vector2i(u.col, u.row)])
	var plr = u.player
	var is_cav = u.unit_type == "cavalry"

	if is_cav:
		var nearest_enemy := Vector2i(-1, -1)
		var nearest_d     := 999999
		for other in units:
			if other.eliminated or other.player == plr: continue
			if not other.get("arrived", true): continue
			var o_form = other.get("formation", [Vector2i(other.col, other.row)])
			var d = HexMath.formation_dist(u_form, o_form)
			if d < nearest_d:
				nearest_d     = d
				nearest_enemy = Vector2i(other.col, other.row)
		if nearest_enemy.x >= 0 and nearest_d <= CAVALRY_AGGRO:
			return nearest_enemy

	var obj_ctrl_local: Array = []
	for obj in OBJECTIVES:
		var cnt1 = 0; var cnt2 = 0
		for other in units:
			if other.eliminated: continue
			if not other.get("arrived", true): continue
			var o_form = other.get("formation", [Vector2i(other.col, other.row)])
			if HexMath.formation_dist_to_hex(o_form, obj) <= OC_RADIUS:
				if other.player == 1: cnt1 += 1
				else:                  cnt2 += 1
		if   cnt1 > cnt2: obj_ctrl_local.append(1)
		elif cnt2 > cnt1: obj_ctrl_local.append(2)
		else:             obj_ctrl_local.append(0)

	var best_pos  := Vector2i(-1, -1)
	var best_dist := 999999

	for i in OBJECTIVES.size():
		var ctrl = obj_ctrl_local[i]
		var my_dist = HexMath.formation_dist_to_hex(u_form, OBJECTIVES[i])
		if ctrl == plr and my_dist <= OC_RADIUS:
			return OBJECTIVES[i]
		if ctrl == plr:
			continue
		if my_dist < best_dist:
			best_dist = my_dist
			best_pos  = OBJECTIVES[i]

	if best_pos.x >= 0:
		return best_pos

	var nearest_enemy := Vector2i(-1, -1)
	var nearest_d     := 999999
	for other in units:
		if other.eliminated or other.player == plr: continue
		if not other.get("arrived", true): continue
		var o_form = other.get("formation", [Vector2i(other.col, other.row)])
		var d = HexMath.formation_dist(u_form, o_form)
		if d < nearest_d:
			nearest_d     = d
			nearest_enemy = Vector2i(other.col, other.row)
	if nearest_enemy.x >= 0:
		return nearest_enemy
	return Vector2i(u.col, u.row)

func _nearest_enemy_in_range(uid: int, units: Array, range_val: int) -> int:
	var u = units[uid]
	var u_form = u.get("formation", [Vector2i(u.col, u.row)])
	var best_eid = -1
	var best_d   = range_val + 1
	for eid in units.size():
		if eid == uid: continue
		var e = units[eid]
		if e.eliminated or e.player == u.player: continue
		if not e.get("arrived", true): continue
		var e_form = e.get("formation", [Vector2i(e.col, e.row)])
		var d = HexMath.formation_dist(u_form, e_form)
		if d <= range_val and d < best_d:
			best_d   = d
			best_eid = eid
	return best_eid

func _pick_trail_target(uid: int, units: Array, timelines: Array, formations_timeline: Array, turn: int) -> Dictionary:
	var u = units[uid]
	var u_form = u.get("formation", [Vector2i(u.col, u.row)])
	var best := {}
	var best_d := 999999
	for eid in units.size():
		var e = units[eid]
		if e.player == u.player: continue
		if eid >= formations_timeline.size(): continue
		var e_ftl: Array = formations_timeline[eid]
		var max_idx = mini(turn, e_ftl.size() - 1)
		for ti in (max_idx + 1):
			var form: Array = e_ftl[ti]
			for fh in form:
				if fh == Vector2i(-1, -1): continue
				var d = HexMath.formation_dist_to_hex(u_form, fh)
				if d < best_d:
					best_d = d
					best = {"hex": fh, "enemy_uid": eid, "trail_turn": ti}
	return best

func _roll_combat(attacker: Dictionary, defender: Dictionary, rng: RandomNumberGenerator) -> int:
	var stats = get_stats(attacker.get("unit_type", "infantry"))
	var def_stats = get_stats(defender.get("unit_type", "infantry"))
	var cover = _get_terrain_at(defender.col, defender.row).cover_bonus
	var wounds = 0
	for _i in attacker.models * stats.attacks:
		if rng.randi_range(1, 6) >= stats.hit:
			if rng.randi_range(1, 6) >= stats.wound:
				var save_target = def_stats.get("armor", 7) + stats.rend - cover
				if rng.randi_range(1, 6) < save_target:
					wounds += stats.damage
	return wounds

func _roll_melee(attacker: Dictionary, defender: Dictionary, rng: RandomNumberGenerator) -> int:
	var stats = get_stats(attacker.get("unit_type", "infantry"))
	var def_stats = get_stats(defender.get("unit_type", "infantry"))
	var cover = _get_terrain_at(defender.col, defender.row).cover_bonus
	var atk = stats.get("melee_attacks", stats.attacks)
	var hit = stats.get("melee_hit", stats.hit)
	var wnd = stats.get("melee_wound", stats.wound)
	var rnd = stats.get("melee_rend", stats.rend)
	var dmg = stats.get("melee_damage", stats.damage)
	var wounds = 0
	for _i in attacker.models * atk:
		if rng.randi_range(1, 6) >= hit:
			if rng.randi_range(1, 6) >= wnd:
				var save_target = def_stats.get("armor", 7) + rnd - cover
				if rng.randi_range(1, 6) < save_target:
					wounds += dmg
	return wounds

func _find_ranged_target(uid: int, units: Array, stats: Dictionary) -> int:
	var u = units[uid]
	var u_form = u.get("formation", [Vector2i(u.col, u.row)])
	var range_val = stats.get("range", 0)
	if range_val <= 0: return -1
	var targets_furthest = stats.get("targets_furthest", false)
	var best_eid = -1
	var best_d = -1 if targets_furthest else range_val + 1
	for eid in units.size():
		if eid == uid: continue
		var e = units[eid]
		if e.eliminated or e.player == u.player: continue
		if not e.get("arrived", true): continue
		var e_form = e.get("formation", [Vector2i(e.col, e.row)])
		var d = HexMath.formation_dist(u_form, e_form)
		if d > range_val: continue
		if targets_furthest:
			if d > best_d:
				best_d = d
				best_eid = eid
		else:
			if d < best_d:
				best_d = d
				best_eid = eid
	return best_eid

func _pick_archer_target(uid: int, units: Array) -> Vector2i:
	var u = units[uid]
	var u_form = u.get("formation", [Vector2i(u.col, u.row)])
	var archer_range = get_stats("archer").get("range", 24)
	var nearest_eid := -1
	var nearest_d := 999
	for eid in units.size():
		if eid == uid: continue
		var e = units[eid]
		if e.eliminated or e.player == u.player: continue
		if not e.get("arrived", true): continue
		var e_form = e.get("formation", [Vector2i(e.col, e.row)])
		var d = HexMath.formation_dist(u_form, e_form)
		if d <= archer_range and d < nearest_d:
			nearest_d = d
			nearest_eid = eid
	if nearest_eid >= 0:
		var e = units[nearest_eid]
		if nearest_d >= archer_range:
			return Vector2i(u.col, u.row)
		return Vector2i(e.col, e.row)
	var best_obj := Vector2i(u.col, u.row)
	var best_d2 := 999
	for obj in OBJECTIVES:
		var d = HexMath.formation_dist_to_hex(u_form, obj)
		if d < best_d2:
			best_d2 = d
			best_obj = obj
	return best_obj

func _apply_wounds(uid: int, units: Array, wounds: int, turn: int):
	var u     = units[uid]
	var stats = get_stats(u.unit_type)
	var old_models = u.models
	u.wounds += wounds
	while u.wounds >= stats.hp and u.models > 0:
		u.wounds -= stats.hp
		u.models -= 1
	if u.models <= 0:
		u.eliminated = true
		u.elim_turn  = turn
		u.formation = []
	elif u.models < old_models:
		var new_fp = compute_footprint(u.unit_type, u.models)
		if new_fp < u.get("formation", []).size():
			u.formation = _shrink_formation(u.formation, new_fp, uid, units)
	units[uid] = u

func _shrink_formation(formation: Array, new_size: int, uid: int, units: Array) -> Array:
	if formation.size() <= new_size:
		return formation
	var u = units[uid]
	var enemy_center := Vector2i(u.col, u.row)
	var best_d := 999999
	for eid in units.size():
		if eid == uid: continue
		var e = units[eid]
		if e.eliminated or e.player == u.player: continue
		if not e.get("arrived", true): continue
		var e_form = e.get("formation", [Vector2i(e.col, e.row)])
		var d = HexMath.formation_dist(formation, e_form)
		if d < best_d:
			best_d = d
			enemy_center = Vector2i(e.col, e.row)
	var sorted_form = formation.duplicate()
	sorted_form.sort_custom(func(a, b):
		return HexMath.hex_dist(a.x, a.y, enemy_center.x, enemy_center.y) > HexMath.hex_dist(b.x, b.y, enemy_center.x, enemy_center.y)
	)
	return sorted_form.slice(0, new_size)

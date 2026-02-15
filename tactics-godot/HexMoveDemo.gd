extends Node2D

# ============================================================================
# CONFIGURATION
# ============================================================================

const COLS          = 28
const ROWS          = 20
const HEX_SIZE      = 20.0   # circumradius of hex (center to corner)

const UNITS_PER_SIDE = 8
const TURNS          = 10
const COMBAT_RANGE   = 2
const TURN_DURATION  = 0.8   # seconds per animation frame

# Deployment zones
const P1_DEPLOY_ROWS_MIN = 16
const P1_DEPLOY_ROWS_MAX = 19
const P2_DEPLOY_ROWS_MIN = 0
const P2_DEPLOY_ROWS_MAX = 3
const DEPLOY_C_MIN       = 2
const DEPLOY_C_MAX       = 25

const OBJECTIVES = [
	Vector2i(7,  10),
	Vector2i(14, 9),
	Vector2i(21, 10),
]

const INFANTRY = {
	"models": 10, "hp": 2, "move": 6,
	"attacks": 2, "hit": 3, "wound": 3, "rend": 1, "armor": 4, "damage": 1,
	"can_capture": true, "obj_weight": 1.0,
}
const CAVALRY = {
	"models": 5, "hp": 5, "move": 10,
	"attacks": 2, "hit": 4, "wound": 3, "rend": 2, "armor": 3, "damage": 2,
	"can_capture": true, "obj_weight": 1.0,
}
const ARTILLERY = {
	"models": 1, "hp": 12, "move": 4,
	"attacks": 4, "hit": 4, "wound": 2, "rend": 1, "damage": 3,
	"range": 20, "targets_furthest": true,
	"melee_attacks": 1, "melee_hit": 5, "melee_wound": 4, "melee_rend": 0, "melee_damage": 1,
	"can_capture": false, "obj_weight": 0.0,
}
const DEEP_STRIKE = {
	"models": 6, "hp": 2, "move": 8,
	"attacks": 2, "hit": 4, "wound": 4, "rend": 0, "damage": 1,
	"armor": 4,
	"can_capture": true, "obj_weight": 0.5,
}
const ARCHER = {
	"models": 5, "hp": 2, "move": 5,
	"attacks": 2, "hit": 3, "wound": 2, "rend": 0, "damage": 1,
	"range": 8,
	"melee_attacks": 1, "melee_hit": 5, "melee_wound": 5, "melee_rend": 0, "melee_damage": 1,
	"armor": 5, "can_capture": true, "obj_weight": 0.5,
	"retreat_move": 5,
}
const UNIT_TYPES = ["infantry", "cavalry", "artillery", "deep_strike", "archer"]

const UNIT_NAMES = [
	"Ada", "Ben", "Cal", "Dan", "Eve", "Finn", "Gil", "Hal",
	"Ida", "Jay", "Kit", "Leo", "Max", "Ned", "Odo", "Pat",
	"Rex", "Sam", "Tom", "Val",
]

# ---- colors ------------------------------------------------------------------
const C_BG       = Color(0.07, 0.10, 0.18)   # dark navy
const C_FIELD    = Color(0.11, 0.16, 0.26)   # hex fill
const C_STROKE   = Color(0.20, 0.28, 0.42)   # hex outline
const C_P1       = Color(0.28, 0.58, 1.00)   # blue
const C_P2       = Color(1.00, 0.35, 0.28)   # red
const C_COMBAT   = Color(1.00, 0.75, 0.10)   # gold / trail color
const C_BANNER   = Color(0.85, 0.78, 0.32)
const C_SWORD    = Color(0.80, 0.80, 0.85)

func _get_stats(unit_type: String) -> Dictionary:
	match unit_type:
		"cavalry": return CAVALRY
		"artillery": return ARTILLERY
		"deep_strike": return DEEP_STRIKE
		"archer": return ARCHER
		_: return INFANTRY

func _unit_prefix(unit_type: String) -> String:
	match unit_type:
		"cavalry": return "C"
		"artillery": return "A"
		"deep_strike": return "D"
		"archer": return "W"
		_: return "I"

# ============================================================================
# FLAT-TOP TOP-DOWN HEX MATH  (odd-q offset coords)
# ============================================================================
# Offset layout: odd columns are staggered DOWN by half a hex height.
# x = col * size * 1.5
# y = row * size * sqrt(3)  +  (col & 1) * size * sqrt(3) * 0.5

var cam_offset := Vector2.ZERO
var cam_zoom   := 1.0

var tile_tex: Texture2D = null   # single flat-top hex tile

# Sprite sheets: unit_sprites[player][unit_type] = {"idle": Texture2D, "run": Texture2D}
var unit_sprites := {}
# Frame counts per sprite sheet (width / frame_height)
const SPRITE_FRAMES := {
	"infantry": {"idle": 8, "run": 6, "size": 192},
	"cavalry":  {"idle": 12, "run": 6, "size": 320},
	"artillery": {"idle": 6, "run": 4, "size": 192},
	"deep_strike": {"idle": 8, "run": 6, "size": 192},
	"archer":   {"idle": 6, "run": 4, "size": 192},
}

func hex_to_pixel(col: int, row: int) -> Vector2:
	var x = HEX_SIZE * 1.5 * col
	var y = HEX_SIZE * sqrt(3.0) * row + (col & 1) * HEX_SIZE * sqrt(3.0) * 0.5
	return Vector2(x, y) * cam_zoom + cam_offset

func pixel_to_hex(pos: Vector2) -> Vector2i:
	# Brute-force nearest hex from fractional estimates — reliable for offset layout
	var p = (pos - cam_offset) / cam_zoom
	var col_f = p.x / (HEX_SIZE * 1.5)
	var best  = Vector2i(0, 0)
	var best_d = 1e18
	for dc in range(-2, 3):
		var c = int(round(col_f)) + dc
		var stagger = (c & 1) * HEX_SIZE * sqrt(3.0) * 0.5
		var row_f = (p.y - stagger) / (HEX_SIZE * sqrt(3.0))
		for dr in range(-1, 2):
			var r = int(round(row_f)) + dr
			var cx = HEX_SIZE * 1.5 * c
			var cy = HEX_SIZE * sqrt(3.0) * r + stagger
			var dx = p.x - cx; var dy = p.y - cy
			var d2 = dx * dx + dy * dy
			if d2 < best_d:
				best_d = d2
				best   = Vector2i(c, r)
	return best

func hex_corners(center: Vector2) -> PackedVector2Array:
	var pts = PackedVector2Array()
	for i in 6:
		var angle = deg_to_rad(60.0 * i)
		pts.append(center + Vector2(cos(angle), sin(angle)) * HEX_SIZE * cam_zoom)
	return pts

func is_valid_hex(col: int, row: int) -> bool:
	return col >= 0 and col < COLS and row >= 0 and row < ROWS

func hex_id(col: int, row: int) -> int:
	return col * 1000 + row

func id_to_hex(id: int) -> Vector2i:
	return Vector2i(id / 1000, id % 1000)

# Flat-top odd-q offset neighbors (depend on whether col is even or odd)
const FLAT_DIRS_EVEN = [
	Vector2i( 1,  0), Vector2i(-1,  0),
	Vector2i( 0,  1), Vector2i( 0, -1),
	Vector2i( 1, -1), Vector2i(-1, -1),
]
const FLAT_DIRS_ODD = [
	Vector2i( 1,  0), Vector2i(-1,  0),
	Vector2i( 0,  1), Vector2i( 0, -1),
	Vector2i( 1,  1), Vector2i(-1,  1),
]

func hex_neighbors(col: int, row: int) -> Array[Vector2i]:
	var dirs = FLAT_DIRS_ODD if (col & 1) else FLAT_DIRS_EVEN
	var result: Array[Vector2i] = []
	for d in dirs:
		var nc = col + d.x
		var nr = row + d.y
		if is_valid_hex(nc, nr):
			result.append(Vector2i(nc, nr))
	return result

func _offset_to_cube(col: int, row: int) -> Vector3i:
	# odd-q offset → cube
	var q = col
	var r = row - (col - (col & 1)) / 2
	return Vector3i(q, r, -q - r)

func hex_dist(c1: int, r1: int, c2: int, r2: int) -> int:
	var a = _offset_to_cube(c1, r1)
	var b = _offset_to_cube(c2, r2)
	return (abs(a.x - b.x) + abs(a.y - b.y) + abs(a.z - b.z)) / 2

# ============================================================================
# A* PATHFINDING
# ============================================================================

var astar := AStar2D.new()

func build_astar(blocked: Dictionary = {}):
	astar.clear()
	for r in ROWS:
		for c in COLS:
			var id = hex_id(c, r)
			if blocked.has(id):
				continue
			astar.add_point(id, Vector2(c, r))
	for r in ROWS:
		for c in COLS:
			var id = hex_id(c, r)
			if not astar.has_point(id):
				continue
			for nb in hex_neighbors(c, r):
				var nb_id = hex_id(nb.x, nb.y)
				if astar.has_point(nb_id) and not astar.are_points_connected(id, nb_id):
					astar.connect_points(id, nb_id)

func find_path(sc: int, sr: int, gc: int, gr: int, blocked: Dictionary = {}) -> Array[Vector2i]:
	build_astar(blocked)
	var sid = hex_id(sc, sr)
	var gid = hex_id(gc, gr)
	if not astar.has_point(sid) or not astar.has_point(gid):
		return []
	var id_path = astar.get_id_path(sid, gid)
	var result: Array[Vector2i] = []
	for id in id_path.slice(1):
		result.append(id_to_hex(id))
	return result

# ============================================================================
# SIMULATION
# ============================================================================

func _pick_target(uid: int, units: Array) -> Vector2i:
	var u   = units[uid]
	var plr = u.player
	var is_cav = u.unit_type == "cavalry"

	# Cavalry: always hunt nearest enemy unless none within 8 hexes
	if is_cav:
		var nearest_enemy := Vector2i(-1, -1)
		var nearest_d     := 999999
		for other in units:
			if other.eliminated or other.player == plr: continue
			if not other.get("arrived", true): continue
			var d = hex_dist(u.col, u.row, other.col, other.row)
			if d < nearest_d:
				nearest_d     = d
				nearest_enemy = Vector2i(other.col, other.row)
		if nearest_enemy.x >= 0 and nearest_d <= 8:
			return nearest_enemy
		# No enemies within 8 — fall through to objective logic

	# Compute objective control from current unit positions
	var obj_control: Array = []  # 0=neutral, 1=P1, 2=P2
	for obj in OBJECTIVES:
		var cnt1 = 0; var cnt2 = 0
		for other in units:
			if other.eliminated: continue
			if not other.get("arrived", true): continue
			if hex_dist(other.col, other.row, obj.x, obj.y) <= 2:
				if other.player == 1: cnt1 += 1
				else:                  cnt2 += 1
		if   cnt1 > cnt2: obj_control.append(1)
		elif cnt2 > cnt1: obj_control.append(2)
		else:             obj_control.append(0)

	var best_pos  := Vector2i(-1, -1)
	var best_dist := 999999

	for i in OBJECTIVES.size():
		var ctrl = obj_control[i]
		var my_dist = hex_dist(u.col, u.row, OBJECTIVES[i].x, OBJECTIVES[i].y)
		# If I'm personally holding this objective, stay here
		if ctrl == plr and my_dist <= 2:
			return OBJECTIVES[i]
		if ctrl == plr:
			continue  # friendly-held by someone else — skip
		if my_dist < best_dist:
			best_dist = my_dist
			best_pos  = OBJECTIVES[i]

	if best_pos.x >= 0:
		return best_pos

	# All friendly-held — advance to nearest enemy
	var nearest_enemy := Vector2i(-1, -1)
	var nearest_d     := 999999
	for other in units:
		if other.eliminated or other.player == plr: continue
		if not other.get("arrived", true): continue
		var d = hex_dist(u.col, u.row, other.col, other.row)
		if d < nearest_d:
			nearest_d     = d
			nearest_enemy = Vector2i(other.col, other.row)
	if nearest_enemy.x >= 0:
		return nearest_enemy
	return Vector2i(u.col, u.row)  # nowhere to go

func _nearest_enemy_in_range(uid: int, units: Array, range_val: int) -> int:
	var u = units[uid]
	var best_eid = -1
	var best_d   = range_val + 1
	for eid in units.size():
		if eid == uid: continue
		var e = units[eid]
		if e.eliminated or e.player == u.player: continue
		if not e.get("arrived", true): continue  # deep strike not yet arrived
		var d = hex_dist(u.col, u.row, e.col, e.row)
		if d <= range_val and d < best_d:
			best_d   = d
			best_eid = eid
	return best_eid

func _roll_combat(attacker: Dictionary, defender: Dictionary, rng: RandomNumberGenerator) -> int:
	# Returns total wounds dealt to defender (uses ranged profile)
	var stats = _get_stats(attacker.get("unit_type", "infantry"))
	var def_stats = _get_stats(defender.get("unit_type", "infantry"))
	var wounds = 0
	for _i in attacker.models * stats.attacks:
		if rng.randi_range(1, 6) >= stats.hit:
			if rng.randi_range(1, 6) >= stats.wound:
				var save_target = def_stats.get("armor", 7) + stats.rend
				if rng.randi_range(1, 6) < save_target:
					wounds += stats.damage
	return wounds

func _roll_melee(attacker: Dictionary, defender: Dictionary, rng: RandomNumberGenerator) -> int:
	# Returns total wounds dealt in melee (uses melee profile for artillery/archer)
	var stats = _get_stats(attacker.get("unit_type", "infantry"))
	var def_stats = _get_stats(defender.get("unit_type", "infantry"))
	var atk = stats.get("melee_attacks", stats.attacks)
	var hit = stats.get("melee_hit", stats.hit)
	var wnd = stats.get("melee_wound", stats.wound)
	var rnd = stats.get("melee_rend", stats.rend)
	var dmg = stats.get("melee_damage", stats.damage)
	var wounds = 0
	for _i in attacker.models * atk:
		if rng.randi_range(1, 6) >= hit:
			if rng.randi_range(1, 6) >= wnd:
				var save_target = def_stats.get("armor", 7) + rnd
				if rng.randi_range(1, 6) < save_target:
					wounds += dmg
	return wounds

func _find_ranged_target(uid: int, units: Array, stats: Dictionary) -> int:
	var u = units[uid]
	var range_val = stats.get("range", 0)
	if range_val <= 0: return -1
	var targets_furthest = stats.get("targets_furthest", false)
	var best_eid = -1
	var best_d = -1 if targets_furthest else range_val + 1
	for eid in units.size():
		if eid == uid: continue
		var e = units[eid]
		if e.eliminated or e.player == u.player: continue
		if not e.get("arrived", true): continue  # deep strike not yet arrived
		var d = hex_dist(u.col, u.row, e.col, e.row)
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
	# Find nearest enemy within 8 hex
	var nearest_eid := -1
	var nearest_d := 999
	for eid in units.size():
		if eid == uid: continue
		var e = units[eid]
		if e.eliminated or e.player == u.player: continue
		if not e.get("arrived", true): continue  # deep strike not yet arrived
		var d = hex_dist(u.col, u.row, e.col, e.row)
		if d <= 8 and d < nearest_d:
			nearest_d = d
			nearest_eid = eid
	if nearest_eid >= 0:
		# Move toward enemy but maintain 8 hex distance
		var e = units[nearest_eid]
		if nearest_d >= 8:
			return Vector2i(u.col, u.row)  # already at good range, stay
		# Need to back up — find hex at distance ~8 from enemy
		# For simplicity, move toward the enemy's position (they're within 8, archer wants to stay at 8)
		# Actually archer wants to approach TO 8 if further, or retreat to 8 if closer
		return Vector2i(e.col, e.row)  # move toward, step loop will stop per archer avoidance logic
	# No enemy nearby — go to nearest objective
	var best_obj := Vector2i(u.col, u.row)
	var best_d2 := 999
	for obj in OBJECTIVES:
		var d = hex_dist(u.col, u.row, obj.x, obj.y)
		if d < best_d2:
			best_d2 = d
			best_obj = obj
	return best_obj

func simulate(input_units: Array) -> Dictionary:
	# input_units: Array of {player, col, row, unit_type}
	var units: Array = []
	for i in input_units.size():
		var src = input_units[i]
		var stats = _get_stats(src.get("unit_type", "infantry"))
		var st = src.get("start_turn", 0)  # 0 = available from turn 0
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
			"arrived"   : st <= 0,  # deep strike units start as not-arrived
			"deploy_col": src.col,
			"deploy_row": src.row,
		})

	var timelines: Array = []
	for u in units:
		var start_pos = Vector2i(-1, -1) if u.start_turn > 0 else Vector2i(u.col, u.row)
		timelines.append([start_pos])

	# Random unit names (separate RNG to avoid changing combat outcomes)
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
	var unit_dmg_to: Array = []   # per uid: {target_uid -> total_damage}
	for _i in units.size():
		unit_obj.append(["no", "no", "no"])
		unit_kills.append(0)
		unit_dmg.append(0)
		unit_dmg_to.append({})

	var combat_events: Array = []
	for _t in TURNS:
		combat_events.append([])

	# Persistent objective control: 0=neutral, 1=P1, 2=P2
	var obj_control: Array = []
	for _i in OBJECTIVES.size():
		obj_control.append(0)

	# Per-turn cumulative VP: vp_per_turn[t] = [p1_cumulative, p2_cumulative]
	var vp_per_turn: Array = []
	var p1_vp_total := 0
	var p2_vp_total := 0

	# Per-turn snapshots for replay
	var obj_ctrl_history: Array = []   # per turn: duplicate of obj_control
	var unit_snapshots: Array = []     # per turn: array of {models, eliminated, col, row}

	# Play-by-play combat log
	var combat_log: Array = []
	var p1_count = 0; var p2_count = 0
	for u in units:
		if u.player == 1: p1_count += 1
		else: p2_count += 1
	combat_log.append("=== Deployment: %d units (%d Blue, %d Red) ===" % [units.size(), p1_count, p2_count])
	for uid3 in units.size():
		var u3 = units[uid3]
		var tc3 = _unit_prefix(u3.unit_type)
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
				units[uid] = u
				combat_log.append("  %s %s arrives via deep strike at (%d,%d)!" % [_unit_prefix(u.unit_type), unit_names[uid], u.col, u.row])

		# ---- Movement ----
		for uid in units.size():
			var u = units[uid]
			# Not yet arrived (deep strike)
			if u.start_turn > 0 and turn < u.start_turn:
				timelines[uid].append(Vector2i(-1, -1))
				continue
			if u.eliminated:
				timelines[uid].append(Vector2i(u.col, u.row))
				continue

			var ut = u.unit_type
			var stats = _get_stats(ut)

			# Artillery: stay if has ranged target, else walk forward
			if ut == "artillery":
				if _find_ranged_target(uid, units, stats) >= 0:
					timelines[uid].append(Vector2i(u.col, u.row))
					continue
				# Walk straight forward (toward enemy deployment zone)
				var fwd_row = u.row + (-1 if u.player == 1 else 1)
				fwd_row = clampi(fwd_row, 0, ROWS - 1)
				var fwd_goal = Vector2i(u.col, fwd_row)
				var blocked_art := {}
				for i in units.size():
					if i == uid or units[i].eliminated: continue
					if units[i].start_turn > 0 and turn < units[i].start_turn: continue
					var oth = units[i]
					if oth.col == fwd_goal.x and oth.row == fwd_goal.y: continue
					blocked_art[hex_id(oth.col, oth.row)] = true
				var art_path = find_path(u.col, u.row, fwd_goal.x, fwd_goal.y, blocked_art)
				var art_steps = mini(stats.move, art_path.size())
				for step_i in art_steps:
					var nxt = art_path[step_i]
					u.col = nxt.x; u.row = nxt.y
					units[uid] = u
				timelines[uid].append(Vector2i(u.col, u.row))
				continue

			# Archer: avoid melee range, kite at range 8
			elif ut == "archer":
				# If not in melee, try to maintain range 8 from nearest enemy
				if _nearest_enemy_in_range(uid, units, COMBAT_RANGE) < 0:
					var archer_goal = _pick_archer_target(uid, units)
					if archer_goal == Vector2i(u.col, u.row):
						timelines[uid].append(archer_goal)
						continue
					var blocked := {}
					for i in units.size():
						if i == uid or units[i].eliminated: continue
						if units[i].start_turn > 0 and turn < units[i].start_turn: continue
						var oth = units[i]
						if oth.col == archer_goal.x and oth.row == archer_goal.y: continue
						blocked[hex_id(oth.col, oth.row)] = true
					var path = find_path(u.col, u.row, archer_goal.x, archer_goal.y, blocked)
					var move_steps = mini(stats.move, path.size())
					for step_i in move_steps:
						var nxt = path[step_i]
						# Archer avoids entering combat range
						var would_engage = false
						for oid in units.size():
							if oid == uid or units[oid].eliminated or units[oid].player == u.player: continue
							if units[oid].start_turn > 0 and turn < units[oid].start_turn: continue
							if hex_dist(nxt.x, nxt.y, units[oid].col, units[oid].row) <= COMBAT_RANGE:
								would_engage = true
								break
						if would_engage:
							break
						u.col = nxt.x; u.row = nxt.y
						units[uid] = u
					timelines[uid].append(Vector2i(u.col, u.row))
					continue
				else:
					# In melee — stay (will fight, then retreat after combat)
					timelines[uid].append(Vector2i(u.col, u.row))
					continue

			# Default: infantry, cavalry, deep_strike, artillery fallback
			if _nearest_enemy_in_range(uid, units, COMBAT_RANGE) >= 0:
				timelines[uid].append(Vector2i(u.col, u.row))
				continue

			var goal = _pick_target(uid, units)
			if goal == Vector2i(u.col, u.row):
				timelines[uid].append(goal)
				continue

			var blocked := {}
			for i in units.size():
				if i == uid or units[i].eliminated: continue
				if units[i].start_turn > 0 and turn < units[i].start_turn: continue
				var other = units[i]
				if other.col == goal.x and other.row == goal.y: continue
				blocked[hex_id(other.col, other.row)] = true

			var path = find_path(u.col, u.row, goal.x, goal.y, blocked)
			var move_steps = mini(stats.move, path.size())
			for step_i in move_steps:
				var nxt = path[step_i]
				u.col = nxt.x; u.row = nxt.y
				units[uid] = u
				if _nearest_enemy_in_range(uid, units, COMBAT_RANGE) >= 0:
					break
			timelines[uid].append(Vector2i(u.col, u.row))

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
				var tc2 = _unit_prefix(u2.unit_type)
				var tm2 = "Blue" if u2.player == 1 else "Red"
				combat_log.append("  %s %s (%s) moves (%d,%d)->(%d,%d)" % [tc2, unit_names[uid2], tm2, prev.x, prev.y, cur.x, cur.y])

		# ---- Ranged Phase ----
		var ranged_shot := {}  # uid -> true, track who shot at range
		for uid in units.size():
			var u = units[uid]
			if u.eliminated: continue
			if u.start_turn > 0 and turn < u.start_turn: continue
			var stats = _get_stats(u.unit_type)
			if not stats.has("range"): continue
			# Silenced in melee
			if _nearest_enemy_in_range(uid, units, COMBAT_RANGE) >= 0: continue
			var tid = _find_ranged_target(uid, units, stats)
			if tid < 0: continue
			ranged_shot[uid] = true
			var t = units[tid]
			# Per-combat RNG for ranged
			var rng := RandomNumberGenerator.new()
			var rseed: int = turn * 13 + uid * 100003 + tid * 999983
			for ni in units.size():
				var nu = units[ni]
				if nu.eliminated: continue
				if nu.start_turn > 0 and turn < nu.start_turn: continue
				if hex_dist(nu.col, nu.row, u.col, u.row) <= COMBAT_RANGE or \
				   hex_dist(nu.col, nu.row, t.col, t.row) <= COMBAT_RANGE:
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
			var u_tc = _unit_prefix(u.unit_type)
			var t_tc = _unit_prefix(t.unit_type)
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
		var melee_participants := {}  # uid -> true, for archer retreat tracking
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

			# Per-combat RNG
			var fight_rng := RandomNumberGenerator.new()
			var fight_seed: int = turn * 7 + mini(uid, eid) * 100003 + maxi(uid, eid) * 999983
			for ni in units.size():
				var nu = units[ni]
				if nu.eliminated: continue
				if nu.start_turn > 0 and turn < nu.start_turn: continue
				if hex_dist(nu.col, nu.row, u.col, u.row) <= COMBAT_RANGE or \
				   hex_dist(nu.col, nu.row, e.col, e.row) <= COMBAT_RANGE:
					fight_seed = fight_seed ^ (nu.col * 31 + nu.row * 97 + nu.player * 7919 + ni * 1009)
			fight_rng.seed = fight_seed
			# Use melee profile for artillery/archer
			var dmg_to_e = _roll_melee(u, e, fight_rng)
			var dmg_to_u = _roll_melee(e, u, fight_rng)
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

			var u_tc = _unit_prefix(u.unit_type)
			var e_tc = _unit_prefix(e.unit_type)
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
			# Retreat: move 5 hex away from all units and objectives
			var best_hex := Vector2i(u.col, u.row)
			var best_score := -1.0
			var retreat_blocked := {}
			for i in units.size():
				if i == uid or units[i].eliminated: continue
				if units[i].start_turn > 0 and turn < units[i].start_turn: continue
				retreat_blocked[hex_id(units[i].col, units[i].row)] = true
			# BFS to find reachable hexes within 5 steps
			var visited := { hex_id(u.col, u.row): 0 }
			var frontier := [Vector2i(u.col, u.row)]
			var retreat_stats = _get_stats("archer")
			var max_steps = retreat_stats.get("retreat_move", 5)
			for _step in max_steps:
				var next_frontier: Array = []
				for fh in frontier:
					var fdist = visited[hex_id(fh.x, fh.y)]
					if fdist >= max_steps: continue
					for nb in hex_neighbors(fh.x, fh.y):
						var nid = hex_id(nb.x, nb.y)
						if not is_valid_hex(nb.x, nb.y): continue
						if visited.has(nid): continue
						if retreat_blocked.has(nid): continue
						visited[nid] = fdist + 1
						next_frontier.append(nb)
				frontier = next_frontier
			# Score each reachable hex by min distance from all units/objectives
			for hid in visited:
				var hx = id_to_hex(hid)
				var min_dist := 999
				for i in units.size():
					if i == uid or units[i].eliminated: continue
					if units[i].start_turn > 0 and turn < units[i].start_turn: continue
					var d = hex_dist(hx.x, hx.y, units[i].col, units[i].row)
					if d < min_dist: min_dist = d
				for obj in OBJECTIVES:
					var d = hex_dist(hx.x, hx.y, obj.x, obj.y)
					if d < min_dist: min_dist = d
				if min_dist > best_score:
					best_score = min_dist
					best_hex = hx
			if best_hex != Vector2i(u.col, u.row):
				u.col = best_hex.x; u.row = best_hex.y
				units[uid] = u
				# Update the last timeline entry to reflect retreat position
				timelines[uid][timelines[uid].size() - 1] = best_hex
				combat_log.append("  W %s retreats to (%d,%d)" % [unit_names[uid], best_hex.x, best_hex.y])

		# ---- Update persistent objective control (with weighted capture) ----
		for oi in OBJECTIVES.size():
			var obj = OBJECTIVES[oi]
			var old_ctrl = obj_control[oi]
			var p1_weight := 0.0; var p2_weight := 0.0
			for u in units:
				if u.eliminated: continue
				if u.start_turn > 0 and turn < u.start_turn: continue
				var ust = _get_stats(u.unit_type)
				if not ust.get("can_capture", true): continue
				if hex_dist(u.col, u.row, obj.x, obj.y) <= 2:
					var w = ust.get("obj_weight", 1.0) * u.models
					if u.player == 1: p1_weight += w
					else:              p2_weight += w
			if p1_weight > p2_weight and p1_weight > 0:
				obj_control[oi] = 1
			elif p2_weight > p1_weight and p2_weight > 0:
				obj_control[oi] = 2
			# Track unit objective contributions
			for uid2 in units.size():
				var u2 = units[uid2]
				if u2.eliminated: continue
				if u2.start_turn > 0 and turn < u2.start_turn: continue
				if hex_dist(u2.col, u2.row, obj.x, obj.y) > 2: continue
				if obj_control[oi] == u2.player and old_ctrl != u2.player:
					unit_obj[uid2][oi] = "won"
				elif p1_weight > 0 and p2_weight > 0 and unit_obj[uid2][oi] != "won":
					unit_obj[uid2][oi] = "yes"

		# Tally VP: 5 per objective held this turn
		for oi2 in OBJECTIVES.size():
			if obj_control[oi2] == 1: p1_vp_total += 5
			elif obj_control[oi2] == 2: p2_vp_total += 5
		vp_per_turn.append([p1_vp_total, p2_vp_total])

		# Log objectives and score
		combat_log.append("  Objectives:")
		for oi3 in OBJECTIVES.size():
			var ctrl_s = "Neutral"
			if obj_control[oi3] == 1: ctrl_s = "Blue"
			elif obj_control[oi3] == 2: ctrl_s = "Red"
			combat_log.append("    O%d (%d,%d): %s" % [oi3 + 1, OBJECTIVES[oi3].x, OBJECTIVES[oi3].y, ctrl_s])
		combat_log.append("  Score: Blue %d - Red %d" % [p1_vp_total, p2_vp_total])
		combat_log.append("")

		# Snapshot for replay
		obj_ctrl_history.append(obj_control.duplicate())
		var snap: Array = []
		for uid2 in units.size():
			var u2 = units[uid2]
			snap.append({ "models": u2.models, "eliminated": u2.eliminated, "col": u2.col, "row": u2.row })
		unit_snapshots.append(snap)

	return { "timelines": timelines, "units": units, "combat": combat_events, "obj_control": obj_control, "vp_per_turn": vp_per_turn, "unit_names": unit_names, "unit_obj": unit_obj, "unit_kills": unit_kills, "unit_dmg": unit_dmg, "unit_dmg_to": unit_dmg_to, "combat_log": combat_log, "obj_ctrl_history": obj_ctrl_history, "unit_snapshots": unit_snapshots }

func _apply_wounds(uid: int, units: Array, wounds: int, turn: int):
	var u     = units[uid]
	var stats = _get_stats(u.unit_type)
	u.wounds += wounds
	while u.wounds >= stats.hp and u.models > 0:
		u.wounds -= stats.hp
		u.models -= 1
	if u.models <= 0:
		u.eliminated = true
		u.elim_turn  = turn
	units[uid] = u

# ============================================================================
# GAME STATE
# ============================================================================

enum Phase { DEPLOY, DONE }
enum ViewMode { CLEAN, CHANGED, FULL, FINAL }

var phase        = Phase.DEPLOY
var view_mode    = ViewMode.CLEAN
var active_player = 1           # whose turn to deploy (1 or 2)
var deploy_unit_type := "infantry"
var selecting_unit := true      # true = show unit selection popup
var placed_p1    : Array        = []  # Array of {player,col,row,unit_type,start_turn?}
var placed_p2    : Array        = []

# Deep strike deployment state
var ds_selecting_turn := false
var ds_arrival_turn   := -1
var ds_legal_hexes    := {}     # hex_id -> true for valid deep strike hexes
var ds_pending_hex    := Vector2i(-1, -1)  # hex clicked before turn selection

var confirmed_sim := {}
var preview_sim   := {}
var preview_diff  := {}   # diff between confirmed and preview sims
var showing_shift_summary := false
var shift_summary_lines: Array = []   # Array of lines; each line = Array of {t: String, c: Color}
var shift_summary_scroll := 0
var shift_summary_timer := 0.0
var shift_summary_diff := {}  # snapshot of preview_diff at placement time
var shift_old_sim := {}       # snapshot of confirmed_sim before placement
var hover_hex     := Vector2i(-1, -1)
var deploy_heatmap := {}  # hex_id -> vp delta for active player
var _heatmap_queue: Array = []  # hex coords still to compute
var _heatmap_base_vp := 0      # cached baseline VP for incremental compute
var _heatmap_base_units: Array = []  # cached unit list for incremental compute
var _heatmap_min := 0  # worst delta seen so far (for relative scaling)
var _heatmap_max := 0  # best delta seen so far

var anim_turn  := 0
var anim_frac  := 0.0   # 0.0–1.0 progress within the current turn (for smooth interpolation)
var _obj_control: Array = []  # per-objective: 0=neutral, 1=P1, 2=P2

# Combat log
var log_lines: Array = []
var log_scroll: int  = 0

# Replay mode
var replay_mode  := false
var replay_turn  := 0

# Battle summary
var show_summary := false
var summary_lines: Array = []  # Array of {text, color, bold}
var summary_scroll: int = 0

# Camera drag
var drag_active   := false
var drag_start    := Vector2.ZERO
var cam_start     := Vector2.ZERO

# ============================================================================
# READY
# ============================================================================

func _load_png_as_texture(path: String) -> Texture2D:
	var img = Image.load_from_file(path)
	if img == null:
		return null
	var tex = ImageTexture.create_from_image(img)
	return tex

func _load_unit_sprites():
	var base_dir = ProjectSettings.globalize_path("res://sprites/")
	var colors = {1: "blue", 2: "red"}
	for p in colors:
		unit_sprites[p] = {}
		for ut in UNIT_TYPES:
			var folder = base_dir + colors[p] + "/"
			var idle_tex = _load_png_as_texture(folder + ut + "_idle.png")
			var run_tex = _load_png_as_texture(folder + ut + "_run.png")
			if idle_tex:
				unit_sprites[p][ut] = {"idle": idle_tex, "run": run_tex}

var _terrain_map: TileMapLayer = null
var _cursor_hand: Texture2D = null
var _cursor_nogo: Texture2D = null
var _icon_sword: Texture2D = null
var _icon_survive: Texture2D = null
var _icon_death: Texture2D = null

func _ready():
	#tile_tex = load("res://assets/hex tactics assets/single tile.png")
	_terrain_map = get_node_or_null("TerrainMap")
	_load_unit_sprites()
	_cursor_hand = _load_png_as_texture(ProjectSettings.globalize_path("res://assets/2d tinytowers assets/UI Elements/UI Elements/Cursors/Cursor_02.png"))
	_cursor_nogo = _load_png_as_texture(ProjectSettings.globalize_path("res://assets/2d tinytowers assets/UI Elements/UI Elements/Cursors/Cursor_03.png"))
	if _cursor_hand:
		Input.set_custom_mouse_cursor(_cursor_hand, Input.CURSOR_ARROW, Vector2(16, 0))
	var icon_dir = ProjectSettings.globalize_path("res://assets/2d tinytowers assets/UI Elements/UI Elements/Icons/")
	_icon_sword = _load_png_as_texture(icon_dir + "Icon_05.png")
	_icon_survive = _load_png_as_texture(icon_dir + "Icon_07.png")
	_icon_death = _load_png_as_texture(icon_dir + "Icon_09.png")
	var vp = get_viewport_rect().size
	cam_zoom = 1.0
	# Center the map in the viewport (offset layout)
	var mid_col = COLS / 2
	var mid_row = ROWS / 2
	var map_center = Vector2(
		HEX_SIZE * 1.5 * mid_col,
		HEX_SIZE * sqrt(3.0) * mid_row + (mid_col & 1) * HEX_SIZE * sqrt(3.0) * 0.5
	)
	cam_offset = vp * 0.5 - map_center * cam_zoom
	_recalc_confirmed_sim()
	queue_redraw()

# ============================================================================
# INPUT
# ============================================================================

func _input(event: InputEvent):
	# Battle summary controls
	if show_summary:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			show_summary = false
			queue_redraw()
			return
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				summary_scroll = maxi(0, summary_scroll - 3)
				queue_redraw()
				return
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				summary_scroll += 3
				queue_redraw()
				return
			if event.button_index == MOUSE_BUTTON_LEFT:
				var vp_s = get_viewport_rect().size
				var panel_w: float = 620.0
				var panel_x: float = (vp_s.x - panel_w) / 2.0
				var close_rect = Rect2(panel_x + panel_w - 44, 45, 34, 26)
				if close_rect.has_point(event.position):
					show_summary = false
					queue_redraw()
					return
		if event is InputEventMouseButton or event is InputEventMouseMotion:
			return  # consume mouse events while summary is open

	# Replay mode controls
	if replay_mode and event is InputEventKey and event.pressed:
		if event.keycode == KEY_RIGHT:
			replay_turn = mini(replay_turn + 1, TURNS - 1)
			queue_redraw()
			return
		if event.keycode == KEY_LEFT:
			replay_turn = maxi(replay_turn - 1, 0)
			queue_redraw()
			return
		if event.keycode == KEY_ESCAPE:
			replay_mode = false
			queue_redraw()
			return
	if replay_mode:
		return  # block all other input during replay

	# View mode switching during deployment (keys 1-4)
	if phase == Phase.DEPLOY and event is InputEventKey and event.pressed:
		if event.keycode == KEY_1:
			view_mode = ViewMode.CLEAN
			queue_redraw()
			return
		if event.keycode == KEY_2:
			view_mode = ViewMode.CHANGED
			queue_redraw()
			return
		if event.keycode == KEY_3:
			view_mode = ViewMode.FULL
			queue_redraw()
			return
		if event.keycode == KEY_4:
			view_mode = ViewMode.FINAL
			queue_redraw()
			return

	# Log panel scroll (left side, 340px wide)
	if event is InputEventMouseButton and event.pressed and event.position.x < 420:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			log_scroll = maxi(0, log_scroll - 3)
			queue_redraw()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			log_scroll = mini(maxi(0, log_lines.size() - 10), log_scroll + 3)
			queue_redraw()
			return

	# Camera zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom(1.1, event.position)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom(0.9, event.position)
			return

	# Camera drag (right mouse or middle)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				drag_active = true
				drag_start  = event.position
				cam_start   = cam_offset
			else:
				drag_active = false
	if event is InputEventMouseMotion:
		if drag_active:
			cam_offset = cam_start + (event.position - drag_start)
			queue_redraw()
			return
		if selecting_unit or ds_selecting_turn:
			if _cursor_hand:
				Input.set_custom_mouse_cursor(_cursor_hand, Input.CURSOR_ARROW, Vector2(16, 0))
			queue_redraw()
			return
		# Update hover
		var h = pixel_to_hex(event.position)
		var new_hover = h if is_valid_hex(h.x, h.y) else Vector2i(-1, -1)
		if new_hover != hover_hex:
			hover_hex = new_hover
			if not selecting_unit and not ds_selecting_turn and not showing_shift_summary and _is_deploy_hex(new_hover):
				_recalc_preview_sim()
				anim_turn  = 0
				anim_frac  = 0.0
				if _cursor_hand:
					Input.set_custom_mouse_cursor(_cursor_hand, Input.CURSOR_ARROW, Vector2(16, 0))
			else:
				if not preview_sim.is_empty():
					preview_sim = {}
					preview_diff = {}
				if _cursor_nogo and phase == Phase.DEPLOY and is_valid_hex(new_hover.x, new_hover.y) and not selecting_unit and not ds_selecting_turn:
					Input.set_custom_mouse_cursor(_cursor_nogo, Input.CURSOR_ARROW, Vector2(32, 32))
				elif _cursor_hand:
					Input.set_custom_mouse_cursor(_cursor_hand, Input.CURSOR_ARROW, Vector2(16, 0))
			queue_redraw()

	# Shift summary scroll
	if showing_shift_summary and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			shift_summary_scroll = maxi(0, shift_summary_scroll - 1)
			queue_redraw()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			shift_summary_scroll += 1
			queue_redraw()
			return

	# Left click handling
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Dismiss shift summary on click
		if showing_shift_summary:
			showing_shift_summary = false
			shift_summary_diff = {}
			selecting_unit = true
			if _cursor_hand:
				Input.set_custom_mouse_cursor(_cursor_hand, Input.CURSOR_ARROW, Vector2(16, 0))
			queue_redraw()
			return
		if not drag_active:
			# Check REPLAY / SUMMARY button click
			if phase == Phase.DONE and not replay_mode:
				var vp2 = get_viewport_rect().size
				var btn_replay = Rect2(vp2.x / 2.0 - 135, 55, 120, 36)
				if btn_replay.has_point(event.position):
					replay_mode = true
					replay_turn = 0
					queue_redraw()
					return
				var btn_summary = Rect2(vp2.x / 2.0 + 15, 55, 120, 36)
				if btn_summary.has_point(event.position):
					summary_lines = _generate_battle_summary()
					summary_scroll = 0
					show_summary = true
					queue_redraw()
					return

			# Unit selection popup click
			if phase == Phase.DEPLOY and selecting_unit:
				_handle_unit_select_click(event.position)
				return

			# Deep strike turn selector click
			if phase == Phase.DEPLOY and ds_selecting_turn:
				_handle_ds_turn_click(event.position)
				return

			# Normal hex placement click
			var h = pixel_to_hex(event.position)
			_handle_deploy_click(h)

func _zoom(factor: float, pivot: Vector2):
	var old_zoom = cam_zoom
	cam_zoom = clamp(cam_zoom * factor, 0.3, 4.0)
	var scale = cam_zoom / old_zoom
	cam_offset = pivot + (cam_offset - pivot) * scale
	queue_redraw()

func _is_deploy_hex(h: Vector2i) -> bool:
	if phase != Phase.DEPLOY or not is_valid_hex(h.x, h.y):
		return false
	# Deep strike: can deploy anywhere on map within legal hexes
	if deploy_unit_type == "deep_strike" and ds_arrival_turn > 0:
		return ds_legal_hexes.has(hex_id(h.x, h.y))
	if active_player == 1:
		return h.y >= P1_DEPLOY_ROWS_MIN and h.y <= P1_DEPLOY_ROWS_MAX and h.x >= DEPLOY_C_MIN and h.x <= DEPLOY_C_MAX
	else:
		return h.y >= P2_DEPLOY_ROWS_MIN and h.y <= P2_DEPLOY_ROWS_MAX and h.x >= DEPLOY_C_MIN and h.x <= DEPLOY_C_MAX

func _handle_deploy_click(h: Vector2i):
	if phase != Phase.DEPLOY or selecting_unit or ds_selecting_turn: return
	if not _is_deploy_hex(h): return

	# Check no stacking on existing units
	var all_placed = placed_p1 + placed_p2
	for p in all_placed:
		if p.col == h.x and p.row == h.y: return

	var unit_data = { "player": active_player, "col": h.x, "row": h.y, "unit_type": deploy_unit_type }
	if deploy_unit_type == "deep_strike":
		unit_data["start_turn"] = ds_arrival_turn

	if active_player == 1:
		placed_p1.append(unit_data)
	else:
		placed_p2.append(unit_data)

	# Snapshot the diff and old sim before recalculating
	shift_summary_diff = preview_diff.duplicate(true) if not preview_diff.is_empty() else {}
	shift_old_sim = confirmed_sim.duplicate(true) if not confirmed_sim.is_empty() else {}
	var placed_unit_name = ""
	var placed_player = active_player
	var placed_type = deploy_unit_type

	# Reset deployment state for next turn
	active_player = 2 if active_player == 1 else 1
	ds_selecting_turn = false
	ds_arrival_turn = -1
	ds_legal_hexes = {}
	ds_pending_hex = Vector2i(-1, -1)
	hover_hex = Vector2i(-1, -1)
	deploy_heatmap = {}
	_heatmap_queue = []
	_recalc_confirmed_sim()
	preview_sim = {}
	preview_diff = {}
	anim_turn  = 0
	anim_frac  = 0.0

	# Get the placed unit's name from the new sim (it's the last unit added)
	var new_names: Array = confirmed_sim.get("unit_names", [])
	if not new_names.is_empty():
		placed_unit_name = new_names[new_names.size() - 1]

	var total_placed = placed_p1.size() + placed_p2.size()
	if total_placed >= UNITS_PER_SIDE * 2:
		phase = Phase.DONE
		selecting_unit = false
	else:
		# Show shift summary before next unit selection
		selecting_unit = false
		shift_summary_lines = _build_shift_summary_lines(shift_summary_diff, shift_old_sim, confirmed_sim, placed_unit_name, placed_type, placed_player)
		shift_summary_scroll = 0
		showing_shift_summary = true
		shift_summary_timer = 0.0
	queue_redraw()

func _handle_unit_select_click(pos: Vector2):
	var vp = get_viewport_rect().size
	var btn_w = 145.0
	var btn_h = 48.0
	var gap = 10.0
	var total_w = UNIT_TYPES.size() * btn_w + (UNIT_TYPES.size() - 1) * gap
	var start_x = (vp.x - total_w) / 2.0
	var start_y = vp.y / 2.0 - btn_h / 2.0
	for i in UNIT_TYPES.size():
		var bx = start_x + i * (btn_w + gap)
		var rect = Rect2(bx, start_y, btn_w, btn_h)
		if rect.has_point(pos):
			deploy_unit_type = UNIT_TYPES[i]
			selecting_unit = false
			if deploy_unit_type == "deep_strike":
				ds_selecting_turn = true
			else:
				_compute_deploy_heatmap()
			queue_redraw()
			return

func _handle_ds_turn_click(pos: Vector2):
	var vp = get_viewport_rect().size
	var btn_w = 60.0
	var btn_h = 42.0
	var gap = 10.0
	var turns_available = 7  # T2 through T8
	var total_w = turns_available * btn_w + (turns_available - 1) * gap
	var start_x = (vp.x - total_w) / 2.0
	var start_y = vp.y / 2.0 - btn_h / 2.0
	for i in turns_available:
		var bx = start_x + i * (btn_w + gap)
		var rect = Rect2(bx, start_y, btn_w, btn_h)
		if rect.has_point(pos):
			ds_arrival_turn = i + 2  # T2 = index 0 + 2
			ds_selecting_turn = false
			ds_legal_hexes = _compute_ds_legal_hexes(ds_arrival_turn)
			_compute_deploy_heatmap()
			queue_redraw()
			return

func _compute_ds_legal_hexes(arrival_turn: int) -> Dictionary:
	var legal := {}
	var snapshots: Array = confirmed_sim.get("unit_snapshots", [])
	var conf_units: Array = confirmed_sim.get("units", [])
	# If no sim yet (first unit), all hexes are legal
	if snapshots.is_empty():
		for c in COLS:
			for r in ROWS:
				if is_valid_hex(c, r):
					legal[hex_id(c, r)] = true
		return legal
	# Use snapshot at arrival_turn - 1 (0-indexed)
	var snap_idx = mini(arrival_turn - 1, snapshots.size() - 1)
	var snap: Array = snapshots[snap_idx]
	for c in COLS:
		for r in ROWS:
			if not is_valid_hex(c, r): continue
			var ok = true
			for uid in snap.size():
				var su = snap[uid]
				if su.eliminated: continue
				# Only check enemy units
				var u_player = conf_units[uid].player if uid < conf_units.size() else 0
				if u_player == active_player: continue
				if hex_dist(c, r, su.col, su.row) < 9:
					ok = false
					break
			if ok:
				legal[hex_id(c, r)] = true
	return legal

func _compute_obj_control(sim: Dictionary) -> Array:
	if sim.is_empty():
		var result: Array = []
		for _i in OBJECTIVES.size():
			result.append(0)
		return result
	return sim.get("obj_control", [0, 0, 0])

func _recalc_confirmed_sim():
	var all_units: Array = placed_p1.duplicate() + placed_p2.duplicate()
	if all_units.is_empty():
		confirmed_sim = {}
		log_lines = []
		return
	confirmed_sim = simulate(all_units)
	log_lines = confirmed_sim.get("combat_log", [])
	log_scroll = 0
	# Write to file
	var f = FileAccess.open("user://combat_log.txt", FileAccess.WRITE)
	if f:
		for line in log_lines:
			f.store_line(line)
		f.close()

func _recalc_preview_sim():
	if phase != Phase.DEPLOY or selecting_unit or ds_selecting_turn or showing_shift_summary: return
	if not _is_deploy_hex(hover_hex):
		preview_sim = {}
		preview_diff = {}
		return
	# Check not stacking on existing unit
	var all_placed = placed_p1 + placed_p2
	for p in all_placed:
		if p.col == hover_hex.x and p.row == hover_hex.y:
			preview_sim = {}
			preview_diff = {}
			return
	var preview_unit = { "player": active_player, "col": hover_hex.x, "row": hover_hex.y, "unit_type": deploy_unit_type }
	if deploy_unit_type == "deep_strike" and ds_arrival_turn > 0:
		preview_unit["start_turn"] = ds_arrival_turn
	var all_units: Array = placed_p1.duplicate() + placed_p2.duplicate()
	all_units.append(preview_unit)
	preview_sim = simulate(all_units)
	preview_diff = _compute_sim_diff()

func _compute_deploy_heatmap():
	deploy_heatmap = {}
	_heatmap_queue = []
	_heatmap_min = 0
	_heatmap_max = 0
	if phase != Phase.DEPLOY or selecting_unit or ds_selecting_turn:
		return
	# Cache baseline VP
	_heatmap_base_vp = 0
	var conf_vpt: Array = confirmed_sim.get("vp_per_turn", [])
	if not conf_vpt.is_empty():
		var final_vp = conf_vpt[conf_vpt.size() - 1]
		_heatmap_base_vp = final_vp[0] if active_player == 1 else final_vp[1]
	_heatmap_base_units = placed_p1.duplicate() + placed_p2.duplicate()
	# Build queue of hex coordinates to process
	var occupied := {}
	for p in _heatmap_base_units:
		occupied[hex_id(p.col, p.row)] = true
	if deploy_unit_type == "deep_strike" and ds_arrival_turn > 0:
		for hid in ds_legal_hexes:
			if not occupied.has(hid):
				_heatmap_queue.append(Vector2i(hid / 1000, hid % 1000))
	else:
		var r_min = P1_DEPLOY_ROWS_MIN if active_player == 1 else P2_DEPLOY_ROWS_MIN
		var r_max = P1_DEPLOY_ROWS_MAX if active_player == 1 else P2_DEPLOY_ROWS_MAX
		for r in range(r_min, r_max + 1):
			for c in range(DEPLOY_C_MIN, DEPLOY_C_MAX + 1):
				if not occupied.has(hex_id(c, r)):
					_heatmap_queue.append(Vector2i(c, r))

func _process_heatmap_batch(count: int):
	for _i in count:
		if _heatmap_queue.is_empty():
			return
		var coord: Vector2i = _heatmap_queue.pop_back()
		var c = coord.x
		var r = coord.y
		var test_unit = { "player": active_player, "col": c, "row": r, "unit_type": deploy_unit_type }
		if deploy_unit_type == "deep_strike" and ds_arrival_turn > 0:
			test_unit["start_turn"] = ds_arrival_turn
		var test_units = _heatmap_base_units.duplicate()
		test_units.append(test_unit)
		var result = simulate(test_units)
		var result_vpt: Array = result.get("vp_per_turn", [])
		var test_vp := 0
		if not result_vpt.is_empty():
			var fvp = result_vpt[result_vpt.size() - 1]
			test_vp = fvp[0] if active_player == 1 else fvp[1]
		var delta = test_vp - _heatmap_base_vp
		deploy_heatmap[hex_id(c, r)] = delta
		if delta < _heatmap_min: _heatmap_min = delta
		if delta > _heatmap_max: _heatmap_max = delta

func _compute_sim_diff() -> Dictionary:
	if confirmed_sim.is_empty() or preview_sim.is_empty():
		return {}
	var conf_units: Array = confirmed_sim.get("units", [])
	var prev_units: Array = preview_sim.get("units", [])
	var conf_vp: Array = confirmed_sim.get("vp_per_turn", [])
	var prev_vp: Array = preview_sim.get("vp_per_turn", [])
	var conf_obj: Array = confirmed_sim.get("obj_control", [])
	var prev_obj: Array = preview_sim.get("obj_control", [])

	# Unit fate changes (only compare units that exist in both sims)
	var shared_count = mini(conf_units.size(), prev_units.size())
	var fate_changes: Array = []
	for i in shared_count:
		var cu = conf_units[i]
		var pu = prev_units[i]
		var changed = false
		var fate = "same"
		if cu.eliminated != pu.eliminated:
			changed = true
			fate = "now_survives" if cu.eliminated and not pu.eliminated else "now_dies"
		elif cu.eliminated and pu.eliminated and cu.elim_turn != pu.elim_turn:
			changed = true
			fate = "shifted"
		fate_changes.append({"uid": i, "changed": changed, "fate": fate,
			"old_elim": cu.eliminated, "new_elim": pu.eliminated,
			"old_elim_turn": cu.elim_turn, "new_elim_turn": pu.elim_turn})

	# Score delta
	var p1_delta := 0
	var p2_delta := 0
	if not conf_vp.is_empty() and not prev_vp.is_empty():
		var conf_final = conf_vp[conf_vp.size() - 1]
		var prev_final = prev_vp[prev_vp.size() - 1]
		p1_delta = prev_final[0] - conf_final[0]
		p2_delta = prev_final[1] - conf_final[1]

	# Objective flips
	var obj_flips: Array = []
	for oi in OBJECTIVES.size():
		var co = conf_obj[oi] if oi < conf_obj.size() else 0
		var po = prev_obj[oi] if oi < prev_obj.size() else 0
		obj_flips.append(co != po)

	# Timeline changes — which units moved differently?
	var conf_tl: Array = confirmed_sim.get("timelines", [])
	var prev_tl: Array = preview_sim.get("timelines", [])
	var changed_uids: Dictionary = {}
	for i in mini(conf_tl.size(), prev_tl.size()):
		var ct: Array = conf_tl[i]
		var pt: Array = prev_tl[i]
		if ct.size() != pt.size():
			changed_uids[i] = true
			continue
		for j in ct.size():
			if ct[j] != pt[j]:
				changed_uids[i] = true
				break
	# The preview-only unit (last uid in preview) is always "changed"
	if prev_tl.size() > conf_tl.size():
		changed_uids[prev_tl.size() - 1] = true

	return {"fate_changes": fate_changes, "score_delta": [p1_delta, p2_delta], "obj_flips": obj_flips, "changed_uids": changed_uids}

func _unit_obj_hold_turns(sim: Dictionary, uid: int) -> Array:
	# Returns [turns_obj1, turns_obj2, turns_obj3] — turns this unit was within
	# capture range (2 hexes) of each objective while their team controlled it.
	var tls: Array = sim.get("timelines", [])
	var obj_hist: Array = sim.get("obj_ctrl_history", [])
	var sim_units: Array = sim.get("units", [])
	if uid >= tls.size() or uid >= sim_units.size():
		return [0, 0, 0]
	var u = sim_units[uid]
	var trail: Array = tls[uid]
	var result = [0, 0, 0]
	for t in obj_hist.size():
		var pos_idx = t + 1   # trail[0] is deploy position, trail[t+1] is after turn t
		if pos_idx >= trail.size(): break
		var pos = trail[pos_idx]
		if pos == Vector2i(-1, -1): continue
		for oi in OBJECTIVES.size():
			if obj_hist[t][oi] == u.player:
				if hex_dist(pos.x, pos.y, OBJECTIVES[oi].x, OBJECTIVES[oi].y) <= 2:
					result[oi] += 1
	return result

func _unit_dmg_summary(sim: Dictionary, uid: int) -> Array:
	# Returns array of {target_name, target_prefix, target_player, dmg} sorted by dmg desc
	var dmg_to: Array = sim.get("unit_dmg_to", [])
	var names: Array = sim.get("unit_names", [])
	var sim_units: Array = sim.get("units", [])
	if uid >= dmg_to.size(): return []
	var pairs: Array = []
	var dt: Dictionary = dmg_to[uid]
	for tid in dt:
		if dt[tid] <= 0: continue
		var tname = names[tid] if tid < names.size() else "?"
		var tprefix = _unit_prefix(sim_units[tid].unit_type) if tid < sim_units.size() else "?"
		var tplayer = sim_units[tid].player if tid < sim_units.size() else 0
		pairs.append({"name": tname, "prefix": tprefix, "player": tplayer, "dmg": dt[tid]})
	pairs.sort_custom(func(a, b): return a.dmg > b.dmg)
	return pairs

func _team_color(player: int) -> Color:
	return C_P1 if player == 1 else C_P2

func _build_shift_summary_lines(diff: Dictionary, old_sim: Dictionary, new_sim: Dictionary, placed_name: String, placed_type: String, placed_player: int) -> Array:
	# Returns Array of lines. Each line = Array of {t: String, c: Color} segments.
	var C_WHITE = Color(0.9, 0.9, 0.9)
	var C_YELLOW = Color(1.0, 0.9, 0.4)
	var C_GRAY = Color(0.65, 0.65, 0.65)
	var C_GREEN = Color(0.4, 1.0, 0.4)
	var C_DEATH = Color(1.0, 0.35, 0.35)
	var lines: Array = []

	if diff.is_empty():
		lines.append([{"t": "Timeline unchanged.", "c": C_GRAY}])
		return lines

	# Header: who was placed
	var team_str = "Blue" if placed_player == 1 else "Red"
	var p_prefix = _unit_prefix(placed_type)
	lines.append([
		{"t": team_str + " placed ", "c": C_WHITE},
		{"t": p_prefix + " " + placed_name, "c": _team_color(placed_player)},
	])

	# Placed unit's own performance in the new sim
	var new_all_units: Array = new_sim.get("units", [])
	var placed_uid = new_all_units.size() - 1
	if placed_uid >= 0:
		var placed_dmg_pairs = _unit_dmg_summary(new_sim, placed_uid)
		var placed_kills_arr: Array = new_sim.get("unit_kills", [])
		var placed_kills = placed_kills_arr[placed_uid] if placed_uid < placed_kills_arr.size() else 0
		var placed_dmg_total_arr: Array = new_sim.get("unit_dmg", [])
		var placed_dmg_total = placed_dmg_total_arr[placed_uid] if placed_uid < placed_dmg_total_arr.size() else 0
		var placed_u = new_all_units[placed_uid]

		var perf_line: Array = [{"t": "  ", "c": C_GRAY}]
		var has_content := false

		# Damage dealt
		if not placed_dmg_pairs.is_empty():
			perf_line.append({"t": "Deals %d damage to " % placed_dmg_total, "c": C_GRAY})
			for di in mini(3, placed_dmg_pairs.size()):
				if di > 0:
					perf_line.append({"t": ", ", "c": C_GRAY})
				var dp = placed_dmg_pairs[di]
				perf_line.append({"t": "%s %s (%d)" % [dp.prefix, dp.name, dp.dmg], "c": _team_color(dp.player)})
			has_content = true

		# Kills
		if placed_kills > 0:
			var kill_text = ", scoring %d kill%s" % [placed_kills, "s" if placed_kills > 1 else ""]
			perf_line.append({"t": kill_text, "c": C_GREEN})
			has_content = true

		# Objectives held (for non-artillery)
		var placed_obj_turns = _unit_obj_hold_turns(new_sim, placed_uid)
		var obj_parts: Array = []
		for oi in 3:
			if placed_obj_turns[oi] > 0:
				obj_parts.append("Obj %d for %d turns" % [oi + 1, placed_obj_turns[oi]])
		if not obj_parts.is_empty():
			var sep = ", " if has_content else ""
			perf_line.append({"t": sep + "holds " + ", ".join(PackedStringArray(obj_parts)), "c": C_YELLOW})
			has_content = true

		# Survival
		if has_content:
			if placed_u.eliminated:
				perf_line.append({"t": ", dies turn %d." % placed_u.elim_turn if placed_u.elim_turn > 0 else ", eliminated.", "c": C_DEATH})
			else:
				perf_line.append({"t": ", survives.", "c": C_GREEN})
			lines.append(perf_line)
		elif placed_u.eliminated:
			perf_line.append({"t": "Dies on turn %d without dealing damage." % placed_u.elim_turn if placed_u.elim_turn > 0 else "Eliminated without dealing damage.", "c": C_DEATH})
			lines.append(perf_line)
		else:
			perf_line.append({"t": "Survives but deals no damage.", "c": C_GRAY})
			lines.append(perf_line)

	# Per-unit fate narratives
	var fate_changes: Array = diff.get("fate_changes", [])
	var old_names: Array = old_sim.get("unit_names", [])
	var old_units: Array = old_sim.get("units", [])
	var new_units: Array = new_sim.get("units", [])
	var new_names: Array = new_sim.get("unit_names", [])

	for fc in fate_changes:
		if fc.fate == "same": continue
		var uid: int = fc.uid
		if uid >= old_units.size() or uid >= new_units.size(): continue
		var uname = old_names[uid] if uid < old_names.size() else "Unit %d" % uid
		var u_old = old_units[uid]
		var u_new = new_units[uid]
		var u_prefix = _unit_prefix(u_old.unit_type)
		var u_color = _team_color(u_old.player)

		# --- Sentence 1: old timeline story ---
		var line: Array = [{"t": u_prefix + " " + uname, "c": u_color}]
		line.append({"t": " in the prior timeline", "c": C_GRAY})
		var old_obj_turns = _unit_obj_hold_turns(old_sim, uid)
		var obj_strs: Array = []
		for oi in 3:
			if old_obj_turns[oi] > 0:
				obj_strs.append("Obj %d for %d turns" % [oi + 1, old_obj_turns[oi]])
		if not obj_strs.is_empty():
			line.append({"t": " held " + ", ".join(PackedStringArray(obj_strs)), "c": C_GRAY})

		# Damage dealt in old timeline (with colored target names)
		var old_dmg = _unit_dmg_summary(old_sim, uid)
		if not old_dmg.is_empty():
			var sep = ", " if not obj_strs.is_empty() else " "
			line.append({"t": sep + "dealt ", "c": C_GRAY})
			for di in mini(2, old_dmg.size()):
				if di > 0:
					line.append({"t": " and ", "c": C_GRAY})
				var dp = old_dmg[di]
				line.append({"t": "%d damage to " % dp.dmg, "c": C_GRAY})
				line.append({"t": "%s %s" % [dp.prefix, dp.name], "c": _team_color(dp.player)})

		# Old fate
		if obj_strs.is_empty() and old_dmg.is_empty():
			if u_old.eliminated:
				line.append({"t": " died on turn %d.", "c": C_GRAY} if u_old.elim_turn > 0 else {"t": " was eliminated.", "c": C_GRAY})
			else:
				line.append({"t": " survived the battle.", "c": C_GRAY})
		else:
			if u_old.eliminated:
				line.append({"t": " and died on turn %d." % u_old.elim_turn, "c": C_GRAY} if u_old.elim_turn > 0 else {"t": " and was eliminated.", "c": C_GRAY})
			else:
				line.append({"t": " and survived.", "c": C_GRAY})
		lines.append(line)

		# --- Line 2: new timeline change (verbose, narrative, indented) ---
		var fate_color = C_DEATH if fc.fate == "now_dies" else (C_GREEN if fc.fate == "now_survives" else C_YELLOW)
		var new_obj_turns = _unit_obj_hold_turns(new_sim, uid)

		# Build objective change descriptions
		var obj_changes: Array = []
		for oi in 3:
			var old_t = old_obj_turns[oi]
			var new_t = new_obj_turns[oi]
			if old_t == new_t: continue
			if new_t > 0 and old_t == 0:
				obj_changes.append("now holds Obj %d for %d turns" % [oi + 1, new_t])
			elif new_t == 0 and old_t > 0:
				obj_changes.append("losing Obj %d entirely" % (oi + 1))
			elif new_t < old_t:
				obj_changes.append("holding Obj %d for only %d turns instead of %d" % [oi + 1, new_t, old_t])
			elif new_t > old_t:
				obj_changes.append("holding Obj %d for %d turns instead of %d" % [oi + 1, new_t, old_t])

		# Compose the "Now" sentence
		var now_text := ""
		if fc.fate == "now_dies":
			now_text = "Now dies on turn %d" % u_new.elim_turn if u_new.elim_turn > 0 else "Now eliminated"
			if not obj_changes.is_empty():
				now_text += ", " + ", ".join(PackedStringArray(obj_changes))
			now_text += "."
		elif fc.fate == "now_survives":
			now_text = "Now survives the battle"
			if not obj_changes.is_empty():
				now_text += ", " + ", ".join(PackedStringArray(obj_changes))
			now_text += "."
		else:  # shifted
			now_text = "Now dies on turn %d instead of turn %d" % [u_new.elim_turn, u_old.elim_turn]
			if not obj_changes.is_empty():
				now_text += ", " + ", ".join(PackedStringArray(obj_changes))
			now_text += "."

		var now_line: Array = [{"t": "  ", "c": fate_color}, {"t": now_text, "c": fate_color}]
		lines.append(now_line)

	# Score summary line
	var score_delta: Array = diff.get("score_delta", [0, 0])
	var obj_flips: Array = diff.get("obj_flips", [])
	var score_parts: Array = []
	if score_delta[0] != 0 or score_delta[1] != 0:
		score_parts.append("Score shift: Blue %+d, Red %+d" % [score_delta[0], score_delta[1]])
	for oi in obj_flips.size():
		if obj_flips[oi]:
			score_parts.append("Obj %d flipped" % (oi + 1))
	if not score_parts.is_empty():
		lines.append([{"t": ", ".join(PackedStringArray(score_parts)), "c": C_YELLOW}])

	if lines.size() <= 1:
		lines.append([{"t": "Timeline shifted slightly.", "c": C_GRAY}])
	return lines

func _generate_battle_summary() -> Array:
	var sim = confirmed_sim
	if sim.is_empty(): return []
	var units: Array = sim.get("units", [])
	var names: Array = sim.get("unit_names", [])
	var kills: Array = sim.get("unit_kills", [])
	var dmg: Array = sim.get("unit_dmg", [])
	var obj_arr: Array = sim.get("unit_obj", [])
	var vpt: Array = sim.get("vp_per_turn", [])
	var obj_hist: Array = sim.get("obj_ctrl_history", [])
	var lines: Array = []
	var C_WHITE = Color(0.9, 0.9, 0.9)
	var C_YELLOW = Color(1.0, 0.85, 0.3)
	var C_BLUE = Color(0.4, 0.6, 1.0)
	var C_RED2 = Color(1.0, 0.4, 0.4)
	var C_GREEN = Color(0.4, 0.9, 0.4)
	var C_GRAY = Color(0.6, 0.6, 0.6)

	# Final score
	var final_vp = vpt[vpt.size() - 1] if vpt.size() > 0 else [0, 0]
	var winner = "DRAW"
	var wc = C_YELLOW
	if final_vp[0] > final_vp[1]: winner = "BLUE WINS"; wc = C_BLUE
	elif final_vp[1] > final_vp[0]: winner = "RED WINS"; wc = C_RED2
	lines.append({"text": "=== BATTLE REPORT ===", "color": C_YELLOW, "bold": true})
	lines.append({"text": "%s  —  Blue %d  vs  Red %d" % [winner, final_vp[0], final_vp[1]], "color": wc, "bold": true})
	lines.append({"text": "", "color": Color(0.85, 0.85, 0.85), "bold": false})

	# Army composition
	lines.append({"text": "ARMY COMPOSITION", "color": C_YELLOW, "bold": true})
	for p in [1, 2]:
		var team = "Blue" if p == 1 else "Red"
		var tc = C_BLUE if p == 1 else C_RED2
		var counts := {}
		for uid in units.size():
			if units[uid].player == p:
				var ut: String = units[uid].unit_type
				counts[ut] = counts.get(ut, 0) + 1
		var parts: Array = []
		for ut in UNIT_TYPES:
			if counts.has(ut):
				parts.append("%d %s" % [counts[ut], ut.replace("_", " ").capitalize()])
		lines.append({"text": "  %s: %s" % [team, ", ".join(parts)], "color": tc, "bold": false})
	lines.append({"text": "", "color": Color(0.85, 0.85, 0.85), "bold": false})

	# Unit performance table
	lines.append({"text": "UNIT PERFORMANCE", "color": C_YELLOW, "bold": true})
	lines.append({"text": "  %-4s %-10s %-10s %5s %5s %5s %6s" % ["", "Name", "Type", "Kills", "Dmg", "Died", "Alive"], "color": C_GRAY, "bold": false})
	for p in [1, 2]:
		var tc = C_BLUE if p == 1 else C_RED2
		var team = "BLUE" if p == 1 else "RED"
		lines.append({"text": "  --- %s ---" % team, "color": tc, "bold": true})
		for uid in units.size():
			var u = units[uid]
			if u.player != p: continue
			var prefix = _unit_prefix(u.unit_type)
			var name_str = names[uid] if uid < names.size() else "???"
			var type_str = u.unit_type.replace("_", " ").capitalize()
			var k = kills[uid] if uid < kills.size() else 0
			var d = dmg[uid] if uid < dmg.size() else 0
			var died_str = "T%d" % u.elim_turn if u.eliminated else "-"
			var alive_str = "%d mdl" % u.models if not u.eliminated else "DEAD"
			var row_color = tc.darkened(0.3) if u.eliminated else tc
			lines.append({"text": "  %-4s %-10s %-10s %5d %5d %5s %6s" % [prefix, name_str, type_str, k, d, died_str, alive_str], "color": row_color, "bold": false})
	lines.append({"text": "", "color": Color(0.85, 0.85, 0.85), "bold": false})

	# MVP
	var best_kills_uid := -1
	var best_kills_val := 0
	var best_dmg_uid := -1
	var best_dmg_val := 0
	for uid in units.size():
		var k = kills[uid] if uid < kills.size() else 0
		var d = dmg[uid] if uid < dmg.size() else 0
		if k > best_kills_val: best_kills_val = k; best_kills_uid = uid
		if d > best_dmg_val: best_dmg_val = d; best_dmg_uid = uid
	lines.append({"text": "STANDOUT PERFORMERS", "color": C_YELLOW, "bold": true})
	if best_kills_uid >= 0:
		var u = units[best_kills_uid]
		var tc = C_BLUE if u.player == 1 else C_RED2
		lines.append({"text": "  Most Kills: %s %s (%s) — %d kills" % [_unit_prefix(u.unit_type), names[best_kills_uid], "Blue" if u.player == 1 else "Red", best_kills_val], "color": tc, "bold": false})
	if best_dmg_uid >= 0:
		var u = units[best_dmg_uid]
		var tc = C_BLUE if u.player == 1 else C_RED2
		lines.append({"text": "  Most Damage: %s %s (%s) — %d wounds dealt" % [_unit_prefix(u.unit_type), names[best_dmg_uid], "Blue" if u.player == 1 else "Red", best_dmg_val], "color": tc, "bold": false})
	# Survivor count
	var alive_p1 := 0; var alive_p2 := 0
	for uid in units.size():
		if not units[uid].eliminated:
			if units[uid].player == 1: alive_p1 += 1
			else: alive_p2 += 1
	lines.append({"text": "  Survivors: Blue %d/%d, Red %d/%d" % [alive_p1, UNITS_PER_SIDE, alive_p2, UNITS_PER_SIDE], "color": Color(0.85, 0.85, 0.85), "bold": false})
	lines.append({"text": "", "color": Color(0.85, 0.85, 0.85), "bold": false})

	# Objective control timeline
	lines.append({"text": "OBJECTIVE CONTROL", "color": C_YELLOW, "bold": true})
	var obj_labels = ["O1 (Left)", "O2 (Center)", "O3 (Right)"]
	for oi in OBJECTIVES.size():
		var turns_p1 := 0; var turns_p2 := 0; var turns_neutral := 0
		for ti in obj_hist.size():
			var ctrl = obj_hist[ti]
			if oi < ctrl.size():
				if ctrl[oi] == 1: turns_p1 += 1
				elif ctrl[oi] == 2: turns_p2 += 1
				else: turns_neutral += 1
		var bar := ""
		for ti in obj_hist.size():
			var ctrl = obj_hist[ti]
			if oi < ctrl.size():
				if ctrl[oi] == 1: bar += "B"
				elif ctrl[oi] == 2: bar += "R"
				else: bar += "."
		lines.append({"text": "  %s: [%s]  Blue %d | Red %d | Neutral %d" % [obj_labels[oi], bar, turns_p1, turns_p2, turns_neutral], "color": Color(0.85, 0.85, 0.85), "bold": false})
	lines.append({"text": "", "color": Color(0.85, 0.85, 0.85), "bold": false})

	# Key moments (eliminations in chronological order)
	lines.append({"text": "KEY MOMENTS", "color": C_YELLOW, "bold": true})
	var elims: Array = []
	for uid in units.size():
		var u = units[uid]
		if u.eliminated:
			elims.append({"uid": uid, "turn": u.elim_turn, "player": u.player, "type": u.unit_type})
	elims.sort_custom(func(a, b): return a.turn < b.turn)
	for e in elims:
		var name_str = names[e.uid] if e.uid < names.size() else "???"
		var team = "Blue" if e.player == 1 else "Red"
		var tc = C_BLUE if e.player == 1 else C_RED2
		lines.append({"text": "  T%d: %s %s (%s) eliminated" % [e.turn, _unit_prefix(e.type), name_str, team], "color": tc, "bold": false})
	if elims.is_empty():
		lines.append({"text": "  No units eliminated!", "color": C_GREEN, "bold": false})
	lines.append({"text": "", "color": Color(0.85, 0.85, 0.85), "bold": false})

	# VP progression
	lines.append({"text": "VP PROGRESSION", "color": C_YELLOW, "bold": true})
	for ti in vpt.size():
		var v = vpt[ti]
		var lead = ""
		if v[0] > v[1]: lead = " (Blue +%d)" % (v[0] - v[1])
		elif v[1] > v[0]: lead = " (Red +%d)" % (v[1] - v[0])
		else: lead = " (Tied)"
		lines.append({"text": "  Turn %2d: Blue %3d - Red %3d%s" % [ti + 1, v[0], v[1], lead], "color": Color(0.85, 0.85, 0.85), "bold": false})

	return lines

# ============================================================================
# PROCESS
# ============================================================================

func _process(delta: float):
	if replay_mode:
		return  # freeze animation during replay
	# Process heatmap queue incrementally (2 sims per frame to stay responsive)
	if not _heatmap_queue.is_empty():
		_process_heatmap_batch(2)
	var speed = TURN_DURATION
	if phase == Phase.DEPLOY and view_mode == ViewMode.FULL:
		speed = 0.3  # 2x faster in FULL mode for snail-trail effect
	anim_frac += delta / speed
	if anim_frac >= 1.0:
		anim_frac -= 1.0
		anim_turn = (anim_turn + 1) % (TURNS + 1)
	if showing_shift_summary:
		shift_summary_timer += delta
	# Sync terrain tilemap with custom camera
	if _terrain_map:
		_terrain_map.position = cam_offset
		_terrain_map.scale = Vector2(cam_zoom, cam_zoom)
	queue_redraw()   # every frame for smooth interpolation

# ============================================================================
# DRAWING
# ============================================================================

func _draw():
	var vp = get_viewport_rect().size
	if not _terrain_map:
		draw_rect(Rect2(Vector2.ZERO, vp), C_BG)

	if replay_mode:
		_draw_replay()
		return

	# Choose which sim to display
	var use_preview = (not preview_sim.is_empty()) and (phase == Phase.DEPLOY)
	var draw_sim    = preview_sim if use_preview else confirmed_sim

	# Final state mode: show end-of-game positions, objectives, score
	if phase == Phase.DEPLOY and view_mode == ViewMode.FINAL:
		_draw_final_state(draw_sim)
		_draw_hud()
		_draw_scoreboard(draw_sim)
		_draw_unit_fate(draw_sim)
		_draw_combat_log()
		if use_preview:
			_draw_preview_narrative(draw_sim)
		# Overlay popups
		if selecting_unit:
			_draw_unit_select()
		elif ds_selecting_turn:
			_draw_ds_turn_select()
		return

	_obj_control = _compute_obj_control(draw_sim)

	# Top-down: no z-ordering needed, just draw row by row
	for r in ROWS:
		for c in COLS:
			_draw_tile(c, r)



	if not draw_sim.is_empty():
		_draw_sim(draw_sim, use_preview)

	_draw_hud()
	_draw_scoreboard(draw_sim)
	_draw_unit_fate(draw_sim)
	_draw_combat_log()
	if use_preview:
		_draw_preview_narrative(draw_sim)

	# Shift summary bar at bottom
	if showing_shift_summary and not shift_summary_lines.is_empty():
		_draw_shift_summary()

	# Overlay popups (drawn last, on top)
	if show_summary:
		_draw_battle_summary()
	elif phase == Phase.DEPLOY and selecting_unit:
		_draw_unit_select()
	elif phase == Phase.DEPLOY and ds_selecting_turn:
		_draw_ds_turn_select()

func _draw_tile(col: int, row: int):
	var center = hex_to_pixel(col, row)
	var corners = hex_corners(center)

	# Draw base tile texture.
	# The tile art has a flat hex face at the top and a 3D wall below.
	# tw = full width (flat-top hex: 2*size), th = taller to include the wall.
	# Offset rect upward so the face center sits at `center` and the wall hangs below.
	if tile_tex:
		var tw = HEX_SIZE * 2.0 * cam_zoom   # exact flat-top hex width
		var th = HEX_SIZE * 2.2 * cam_zoom   # face + small wall extension
		var dest = Rect2(center - Vector2(tw * 0.5, th * 0.35), Vector2(tw, th))
		draw_texture_rect(tile_tex, dest, false)
	elif not _terrain_map:
		draw_colored_polygon(corners, C_FIELD)

	# Outline
	var outline_pts = PackedVector2Array(corners)
	outline_pts.append(corners[0])
	draw_polyline(outline_pts, Color(C_STROKE.r, C_STROKE.g, C_STROKE.b, 0.5), 0.5)

	# Zone tint overlay
	var tint = Color(0, 0, 0, 0)
	if row >= P1_DEPLOY_ROWS_MIN and row <= P1_DEPLOY_ROWS_MAX and col >= DEPLOY_C_MIN and col <= DEPLOY_C_MAX:
		var a = 0.30 if (active_player == 1 and phase == Phase.DEPLOY) else 0.10
		tint = Color(C_P1.r, C_P1.g, C_P1.b, a)
	elif row >= P2_DEPLOY_ROWS_MIN and row <= P2_DEPLOY_ROWS_MAX and col >= DEPLOY_C_MIN and col <= DEPLOY_C_MAX:
		var a = 0.30 if (active_player == 2 and phase == Phase.DEPLOY) else 0.10
		tint = Color(C_P2.r, C_P2.g, C_P2.b, a)

	for i in OBJECTIVES.size():
		var obj = OBJECTIVES[i]
		var ctrl = _obj_control[i] if i < _obj_control.size() else 0
		var ctrl_color = C_BANNER
		if ctrl == 1: ctrl_color = C_P1
		elif ctrl == 2: ctrl_color = C_P2
		if hex_dist(col, row, obj.x, obj.y) <= 2:
			tint = tint.lerp(Color(ctrl_color.r, ctrl_color.g, ctrl_color.b, 0.25), 0.5)
		if col == obj.x and row == obj.y:
			tint = Color(ctrl_color.r, ctrl_color.g, ctrl_color.b, 0.45)

	if tint.a > 0.0:
		draw_colored_polygon(corners, tint)

	# VP heatmap overlay during deployment
	if not deploy_heatmap.is_empty() and phase == Phase.DEPLOY and not selecting_unit and not ds_selecting_turn:
		var hid = hex_id(col, row)
		if deploy_heatmap.has(hid):
			var vp_delta: int = deploy_heatmap[hid]
			if vp_delta > 0 and _heatmap_max > 0:
				var t = clampf(float(vp_delta) / _heatmap_max, 0.0, 1.0)
				var intensity = lerpf(0.08, 0.7, t * t)
				draw_colored_polygon(corners, Color(0.15, 1.0, 0.25, intensity))
			elif vp_delta < 0 and _heatmap_min < 0:
				var t = clampf(float(-vp_delta) / -_heatmap_min, 0.0, 1.0)
				var intensity = lerpf(0.08, 0.7, t * t)
				draw_colored_polygon(corners, Color(1.0, 0.15, 0.15, intensity))

	# Deep strike legal hex highlighting
	if deploy_unit_type == "deep_strike" and ds_arrival_turn > 0 and not selecting_unit and not ds_selecting_turn:
		if ds_legal_hexes.has(hex_id(col, row)):
			draw_colored_polygon(corners, Color(0.2, 0.8, 0.8, 0.12))
		else:
			draw_colored_polygon(corners, Color(0.8, 0.2, 0.2, 0.05))

	# Hover highlight
	if hover_hex.x == col and hover_hex.y == row:
		draw_colored_polygon(corners, Color(1, 1, 1, 0.20))

	# Objective flip glow (preview diff)
	var obj_flips: Array = preview_diff.get("obj_flips", [])
	for i in OBJECTIVES.size():
		if i < obj_flips.size() and obj_flips[i]:
			if hex_dist(col, row, OBJECTIVES[i].x, OBJECTIVES[i].y) <= 2:
				draw_colored_polygon(corners, Color(1.0, 0.9, 0.2, 0.15))
			if col == OBJECTIVES[i].x and row == OBJECTIVES[i].y:
				var glow_pts = PackedVector2Array(corners)
				glow_pts.append(corners[0])
				draw_polyline(glow_pts, Color(1.0, 0.9, 0.2, 0.7), 2.5)

	# Objective banner
	for i in OBJECTIVES.size():
		if OBJECTIVES[i] == Vector2i(col, row):
			_draw_banner(center, i)

func _draw_unit_final(uid: int, final_units: Array, timelines: Array, is_ghost: bool, alpha: float):
	var u = final_units[uid]
	var trail: Array = timelines[uid]
	var final_pos = Vector2i(-1, -1)
	if u.eliminated:
		var et = mini(u.elim_turn, trail.size() - 1)
		final_pos = trail[et]
	else:
		final_pos = trail[trail.size() - 1]
	if final_pos == Vector2i(-1, -1): return
	var center = hex_to_pixel(final_pos.x, final_pos.y)
	if u.eliminated:
		var r = 8.0 * cam_zoom
		draw_line(center + Vector2(-r, -r), center + Vector2(r, r),
			Color(0.9, 0.2, 0.2, 0.35 if is_ghost else 0.7), 2.5)
		draw_line(center + Vector2(r, -r), center + Vector2(-r, r),
			Color(0.9, 0.2, 0.2, 0.35 if is_ghost else 0.7), 2.5)
	else:
		_draw_unit_token(center, u.player, u.models, u.unit_type, is_ghost, alpha)

func _draw_single_timeline(uid: int, final_units: Array, timelines: Array, combat_ev: Array, display_turn: int, is_preview_unit: bool, _snail_trail: bool = false):
	var u = final_units[uid]
	var trail: Array = timelines[uid]
	var alive_until = u.elim_turn if u.eliminated else TURNS
	var max_ti = mini(alive_until + 1, trail.size() - 1)
	var base = C_P1 if u.player == 1 else C_P2
	var highlight_a = 0.25 if is_preview_unit else 0.30
	# Path hex highlights
	for ti in (max_ti + 1):
		var pos = trail[ti]
		if pos == Vector2i(-1, -1): continue
		var hc = hex_to_pixel(pos.x, pos.y)
		var corners = hex_corners(hc)
		draw_colored_polygon(corners, Color(base.r, base.g, base.b, highlight_a))
	# Snail trail ribbon
	var ribbon_w = HEX_SIZE * (0.6 if is_preview_unit else 0.7) * cam_zoom
	var ribbon_a = 0.50 if is_preview_unit else 0.6
	for ti in max_ti:
		var from_pos = trail[ti]
		var to_pos = trail[ti + 1]
		if from_pos == to_pos: continue
		if from_pos == Vector2i(-1, -1) or to_pos == Vector2i(-1, -1): continue
		var pa = hex_to_pixel(from_pos.x, from_pos.y)
		var pb = hex_to_pixel(to_pos.x, to_pos.y)
		var dir = (pb - pa).normalized()
		var perp = Vector2(-dir.y, dir.x) * ribbon_w
		var quad = PackedVector2Array([pa + perp, pa - perp, pb - perp, pb + perp])
		draw_colored_polygon(quad, Color(base.r, base.g, base.b, ribbon_a))
	# Snail trail ghost tokens with caterpillar taper
	var worm_alpha = 0.75 if is_preview_unit else 0.85
	for ti in (max_ti + 1):
		var pos = trail[ti]
		if pos == Vector2i(-1, -1): continue
		var center = hex_to_pixel(pos.x, pos.y)
		if ti != display_turn:
			_draw_unit_token(center, u.player, u.models, u.unit_type, true, worm_alpha, ti)
		if ti < max_ti:
			var next_pos = trail[ti + 1]
			if next_pos == Vector2i(-1, -1) or next_pos == pos: continue
			var next_center = hex_to_pixel(next_pos.x, next_pos.y)
			for interp in [0.17, 0.33, 0.50, 0.67, 0.83]:
				var mid = center.lerp(next_center, interp)
				var interp_frame = ti if interp < 0.5 else ti + 1
				_draw_unit_token_scaled(mid, u.player, u.models, u.unit_type, worm_alpha * 0.85, 0.7, interp_frame)
	# Current-turn token
	var cur_idx = mini(display_turn, trail.size() - 1)
	var next_idx = mini(display_turn + 1, trail.size() - 1)
	if trail[cur_idx] != Vector2i(-1, -1):
		var pos_a = hex_to_pixel(trail[cur_idx].x, trail[cur_idx].y)
		var pos_b = hex_to_pixel(trail[next_idx].x, trail[next_idx].y)
		var center = pos_a.lerp(pos_b, anim_frac)
		if u.eliminated and u.elim_turn <= display_turn - 1:
			var r = 8.0 * cam_zoom
			draw_line(center + Vector2(-r, -r), center + Vector2(r, r),
				Color(0.9, 0.2, 0.2, 0.7), 2.5)
			draw_line(center + Vector2(r, -r), center + Vector2(-r, r),
				Color(0.9, 0.2, 0.2, 0.7), 2.5)
		else:
			_draw_unit_token(center, u.player, u.models, u.unit_type, false, 1.0)

func _draw_sim(sim: Dictionary, is_preview: bool):
	var timelines   : Array = sim.get("timelines", [])
	var final_units : Array = sim.get("units", [])
	var combat_ev   : Array = sim.get("combat", [])

	var display_turn = mini(anim_turn, TURNS)
	var effective_mode = view_mode if phase == Phase.DEPLOY else ViewMode.FULL
	# Animation scan only in CLEAN mode; other modes show static snail trails
	var show_anim_scan = (effective_mode == ViewMode.CLEAN)

	# During preview, determine which units are affected by the placement
	var changed: Dictionary = preview_diff.get("changed_uids", {}) if is_preview else {}

	# Which units get snail trails depends on view mode
	var show_timeline_for_uid := func(uid: int) -> bool:
		if effective_mode == ViewMode.FULL:
			return true  # all units
		if effective_mode == ViewMode.CHANGED:
			# Show trails for changed units, preview unit, AND all units (so enemies visible)
			return true
		# CLEAN mode: only preview unit gets trail, others at final position
		if not is_preview: return false
		return uid == timelines.size() - 1

	# --- 0) Red ghost trails for units whose paths will change (preview only) ---
	if is_preview and not changed.is_empty() and not confirmed_sim.is_empty():
		var old_timelines: Array = confirmed_sim.get("timelines", [])
		var old_units: Array = confirmed_sim.get("units", [])
		var red = Color(0.9, 0.2, 0.15)
		for uid in changed:
			if uid >= old_timelines.size(): continue
			var ou = old_units[uid]
			var old_trail: Array = old_timelines[uid]
			var alive_until = ou.elim_turn if ou.eliminated else TURNS
			var max_ti = mini(alive_until + 1, old_trail.size() - 1)
			# Red ribbon
			for ti in max_ti:
				var from_pos = old_trail[ti]
				var to_pos = old_trail[ti + 1]
				if from_pos == to_pos: continue
				if from_pos == Vector2i(-1, -1) or to_pos == Vector2i(-1, -1): continue
				var pa = hex_to_pixel(from_pos.x, from_pos.y)
				var pb = hex_to_pixel(to_pos.x, to_pos.y)
				var dir = (pb - pa).normalized()
				var perp = Vector2(-dir.y, dir.x) * HEX_SIZE * 0.7 * cam_zoom
				var quad = PackedVector2Array([pa + perp, pa - perp, pb - perp, pb + perp])
				draw_colored_polygon(quad, Color(red.r, red.g, red.b, 0.35))
			# Red hex highlights
			for ti in (max_ti + 1):
				var pos = old_trail[ti]
				if pos == Vector2i(-1, -1): continue
				var hc = hex_to_pixel(pos.x, pos.y)
				var corners = hex_corners(hc)
				draw_colored_polygon(corners, Color(red.r, red.g, red.b, 0.20))

	# --- 0b) Draw units without timelines at their final position ---
	for uid in timelines.size():
		if show_timeline_for_uid.call(uid): continue
		_draw_unit_final(uid, final_units, timelines, false, 1.0)

	# --- 1) Highlight path hexes for each unit ---
	for uid in timelines.size():
		if not show_timeline_for_uid.call(uid): continue
		var u    = final_units[uid]
		var trail: Array = timelines[uid]
		var alive_until = u.elim_turn if u.eliminated else TURNS
		var max_ti = mini(alive_until + 1, trail.size() - 1)
		var is_preview_unit = (is_preview and uid == timelines.size() - 1)
		var base = C_P1 if u.player == 1 else C_P2
		var highlight_a = 0.25 if is_preview_unit else 0.30

		for ti in (max_ti + 1):
			var pos = trail[ti]
			if pos == Vector2i(-1, -1): continue
			var hc = hex_to_pixel(pos.x, pos.y)
			var corners = hex_corners(hc)
			draw_colored_polygon(corners, Color(base.r, base.g, base.b, highlight_a))

	# --- 2) Draw path connections ---
	for uid in timelines.size():
		if not show_timeline_for_uid.call(uid): continue
		var u    = final_units[uid]
		var trail: Array = timelines[uid]
		var alive_until = u.elim_turn if u.eliminated else TURNS
		var max_ti = mini(alive_until + 1, trail.size() - 1)
		var is_preview_unit = (is_preview and uid == timelines.size() - 1)
		var base = C_P1 if u.player == 1 else C_P2

		# Snail trail: filled ribbon between consecutive positions
		var ribbon_w = HEX_SIZE * (0.6 if is_preview_unit else 0.7) * cam_zoom
		var ribbon_a = 0.50 if is_preview_unit else 0.6
		for ti in max_ti:
			var from_pos = trail[ti]
			var to_pos   = trail[ti + 1]
			if from_pos == to_pos: continue
			if from_pos == Vector2i(-1, -1) or to_pos == Vector2i(-1, -1): continue
			var pa = hex_to_pixel(from_pos.x, from_pos.y)
			var pb = hex_to_pixel(to_pos.x, to_pos.y)
			var dir = (pb - pa).normalized()
			var perp = Vector2(-dir.y, dir.x) * ribbon_w
			var quad = PackedVector2Array([
				pa + perp, pa - perp, pb - perp, pb + perp
			])
			draw_colored_polygon(quad, Color(base.r, base.g, base.b, ribbon_a))

	# --- 3) Ghost tokens at each turn position ---
	for uid in timelines.size():
		if not show_timeline_for_uid.call(uid): continue
		var u    = final_units[uid]
		var trail: Array = timelines[uid]
		var alive_until = u.elim_turn if u.eliminated else TURNS
		var max_ti = mini(alive_until + 1, trail.size() - 1)
		var is_preview_unit = (is_preview and uid == timelines.size() - 1)

		# Snail trail: each turn gets a distinct sprite pose, dense interpolation between
		var worm_alpha = 0.75 if is_preview_unit else 0.85
		for ti in (max_ti + 1):
			var pos = trail[ti]
			if pos == Vector2i(-1, -1): continue
			var center = hex_to_pixel(pos.x, pos.y)
			if show_anim_scan and ti == display_turn: continue  # current-turn token drawn in section 5
			# Full-size sprite at each turn position
			_draw_unit_token(center, u.player, u.models, u.unit_type, true, worm_alpha, ti)
			# Caterpillar taper: smaller sprites between stops
			if ti < max_ti:
				var next_pos = trail[ti + 1]
				if next_pos == Vector2i(-1, -1) or next_pos == pos: continue
				var next_center = hex_to_pixel(next_pos.x, next_pos.y)
				for interp in [0.17, 0.33, 0.50, 0.67, 0.83]:
					var mid = center.lerp(next_center, interp)
					var interp_frame = ti if interp < 0.5 else ti + 1
					_draw_unit_token_scaled(mid, u.player, u.models, u.unit_type, worm_alpha * 0.85, 0.7, interp_frame)

	if show_anim_scan:
		# --- 4) Combat sparks (only in CLEAN mode with animation) ---
		for t in display_turn:
			if t >= combat_ev.size(): break
			for ev in combat_ev[t]:
				var aid = ev.get("a", -1)
				var eid = ev.get("b", -1)
				var show_spark = false
				if aid >= 0 and show_timeline_for_uid.call(aid): show_spark = true
				if eid >= 0 and show_timeline_for_uid.call(eid): show_spark = true
				if not show_spark: continue
				var ac = hex_to_pixel(ev.ac, ev.ar)
				var bc = hex_to_pixel(ev.bc, ev.br)
				var mid = (ac + bc) * 0.5
				draw_circle(mid, 14.0 * cam_zoom, Color(C_COMBAT.r, C_COMBAT.g, C_COMBAT.b, 0.20))
				_draw_swords(mid)

		# --- 5) Current-turn tokens on top (animated position) ---
		for uid in timelines.size():
			if not show_timeline_for_uid.call(uid): continue
			var trail: Array = timelines[uid]
			var u     = final_units[uid]
			var cur_idx  = mini(display_turn, trail.size() - 1)
			var next_idx = mini(display_turn + 1, trail.size() - 1)

			if trail[cur_idx] == Vector2i(-1, -1): continue

			var pos_a  = hex_to_pixel(trail[cur_idx].x,  trail[cur_idx].y)
			var pos_b  = hex_to_pixel(trail[next_idx].x, trail[next_idx].y)
			var center = pos_a.lerp(pos_b, anim_frac)

			if u.eliminated and u.elim_turn <= display_turn - 1:
				var r = 8.0 * cam_zoom
				draw_line(center + Vector2(-r, -r), center + Vector2(r, r),
					Color(0.9, 0.2, 0.2, 0.7), 2.5)
				draw_line(center + Vector2(r, -r), center + Vector2(-r, r),
					Color(0.9, 0.2, 0.2, 0.7), 2.5)
				continue
			_draw_unit_token(center, u.player, u.models, u.unit_type, false, 1.0)

	# --- 6) Fate icons during preview (sword/death/survival) ---
	if is_preview and not preview_diff.is_empty():
		var fate_changes: Array = preview_diff.get("fate_changes", [])
		var icon_size = HEX_SIZE * 2.5 * cam_zoom
		for fc in fate_changes:
			var uid_fc: int = fc.uid
			if uid_fc >= timelines.size(): continue
			var u_fc = final_units[uid_fc]
			var trail_fc: Array = timelines[uid_fc]
			# Get unit's final alive position
			var final_pos = Vector2i(-1, -1)
			if u_fc.eliminated:
				var et = mini(u_fc.elim_turn, trail_fc.size() - 1)
				final_pos = trail_fc[et]
			else:
				final_pos = trail_fc[trail_fc.size() - 1]
			if final_pos == Vector2i(-1, -1): continue
			var center = hex_to_pixel(final_pos.x, final_pos.y)
			var team_tint = C_P1 if u_fc.player == 1 else C_P2
			if fc.fate == "now_dies" and _icon_death:
				var death_offset = Vector2(icon_size * 0.5, -icon_size * 0.3)
				var death_rect = Rect2(center + death_offset - Vector2(icon_size * 0.5, icon_size * 0.5), Vector2(icon_size, icon_size))
				draw_texture_rect(_icon_death, death_rect, false, team_tint)
			elif fc.fate == "now_survives" and _icon_survive:
				var surv_offset = Vector2(0, -icon_size * 1.0)
				var surv_rect = Rect2(center + surv_offset - Vector2(icon_size * 0.5, icon_size * 0.5), Vector2(icon_size, icon_size))
				draw_texture_rect(_icon_survive, surv_rect, false, team_tint)
		# Sword icons for combat victories: unit alive with no enemies in combat range
		for uid_s in timelines.size():
			var u_s = final_units[uid_s]
			if u_s.eliminated: continue
			var trail_s: Array = timelines[uid_s]
			var final_pos_s = trail_s[trail_s.size() - 1]
			if final_pos_s == Vector2i(-1, -1): continue
			# Check if any enemy was eliminated nearby (within combat range)
			var has_kill = false
			for uid_e in timelines.size():
				var ue = final_units[uid_e]
				if ue.player == u_s.player: continue
				if not ue.eliminated: continue
				var elim_pos = timelines[uid_e][mini(ue.elim_turn, timelines[uid_e].size() - 1)]
				if elim_pos == Vector2i(-1, -1): continue
				var dist = hex_dist(final_pos_s.x, final_pos_s.y, elim_pos.x, elim_pos.y)
				if dist <= COMBAT_RANGE + 2:
					has_kill = true
					break
			if has_kill and _icon_sword:
				var center_s = hex_to_pixel(final_pos_s.x, final_pos_s.y)
				var sword_offset = Vector2(-icon_size * 0.6, -icon_size * 0.8)
				var sword_rect = Rect2(center_s + sword_offset, Vector2(icon_size, icon_size))
				var team_color = C_P1 if u_s.player == 1 else C_P2
				draw_texture_rect(_icon_sword, sword_rect, false, team_color)

# ============================================================================
# DRAW HELPERS
# ============================================================================

func _draw_unit_token(center: Vector2, player: int, models: int, unit_type: String, is_ghost: bool, alpha: float, fixed_frame: int = -1):
	var a = alpha * (0.60 if is_ghost else 1.0)
	# Try to draw sprite; fall back to colored circle if no texture
	var has_sprite = unit_sprites.has(player) and unit_sprites[player].has(unit_type)
	if has_sprite:
		var tex: Texture2D = unit_sprites[player][unit_type]["idle"]
		var info = SPRITE_FRAMES.get(unit_type, {"idle": 1, "size": 192})
		var frame_size = info["size"]
		var frame_count = info["idle"]
		var frame_idx: int
		if fixed_frame >= 0:
			# Spacetime worm: each time-slice shows a distinct pose
			frame_idx = fixed_frame % frame_count
		else:
			# Normal: cycle through idle frames using anim_frac + anim_turn
			var anim_speed = 8.0  # frames per second
			frame_idx = int(fmod(anim_turn * anim_speed * TURN_DURATION + anim_frac * anim_speed * TURN_DURATION, frame_count))
		frame_idx = clampi(frame_idx, 0, frame_count - 1)
		var src_rect = Rect2(frame_idx * frame_size, 0, frame_size, frame_size)
		# Draw size: scale up for larger frames so visible character matches
		var draw_size = HEX_SIZE * 4.3 * cam_zoom * (frame_size / 192.0)
		var dest_rect = Rect2(center - Vector2(draw_size * 0.5, draw_size * 0.6), Vector2(draw_size, draw_size))
		draw_texture_rect_region(tex, dest_rect, src_rect, Color(1, 1, 1, a))
	else:
		# Fallback: simple colored circle
		var base = C_P1 if player == 1 else C_P2
		var s = HEX_SIZE * 0.55 * cam_zoom
		var col = Color(base.r, base.g, base.b, a)
		var segments = 16
		var circle_pts = PackedVector2Array()
		for i in segments:
			var ang = i * TAU / segments
			circle_pts.append(center + Vector2(cos(ang), sin(ang)) * s)
		draw_colored_polygon(circle_pts, col)

	if not is_ghost and cam_zoom >= 0.5:
		var font = ThemeDB.fallback_font
		draw_string(font, center + Vector2(-5, 5), str(models),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, a))

func _draw_unit_token_scaled(center: Vector2, player: int, models: int, unit_type: String, alpha: float, scale_factor: float, fixed_frame: int = -1):
	# Smaller version of _draw_unit_token for caterpillar taper segments
	var a = alpha * 0.60  # always ghost-like
	var has_sprite = unit_sprites.has(player) and unit_sprites[player].has(unit_type)
	if has_sprite:
		var tex: Texture2D = unit_sprites[player][unit_type]["idle"]
		var info = SPRITE_FRAMES.get(unit_type, {"idle": 1, "size": 192})
		var frame_size = info["size"]
		var frame_count = info["idle"]
		var frame_idx = (fixed_frame % frame_count) if fixed_frame >= 0 else 0
		frame_idx = clampi(frame_idx, 0, frame_count - 1)
		var src_rect = Rect2(frame_idx * frame_size, 0, frame_size, frame_size)
		var draw_size = HEX_SIZE * 4.3 * cam_zoom * scale_factor * (frame_size / 192.0)
		var dest_rect = Rect2(center - Vector2(draw_size * 0.5, draw_size * 0.6), Vector2(draw_size, draw_size))
		draw_texture_rect_region(tex, dest_rect, src_rect, Color(1, 1, 1, a))
	else:
		var base = C_P1 if player == 1 else C_P2
		var s = HEX_SIZE * 0.55 * cam_zoom * scale_factor
		var col = Color(base.r, base.g, base.b, a)
		var segments = 16
		var circle_pts = PackedVector2Array()
		for i in segments:
			var ang = i * TAU / segments
			circle_pts.append(center + Vector2(cos(ang), sin(ang)) * s)
		draw_colored_polygon(circle_pts, col)

func _draw_shift_summary():
	var vp_size = get_viewport_rect().size
	var font = ThemeDB.fallback_font
	var line_h = 22.0
	var font_size = 15
	var title_size = 20
	var pad = 15.0
	var total_lines = shift_summary_lines.size()
	var max_visible_lines = 12
	var visible_lines = mini(total_lines, max_visible_lines)
	# Box height: title + visible lines + click prompt
	var box_h = 30.0 + visible_lines * line_h + 20.0 + pad
	var box_w = min(vp_size.x * 0.85, 1200.0)
	var box_x = (vp_size.x - box_w) * 0.5
	var box_y = vp_size.y * 0.7 - box_h * 0.5
	# Clamp scroll
	var max_scroll = maxi(0, total_lines - max_visible_lines)
	shift_summary_scroll = clampi(shift_summary_scroll, 0, max_scroll)
	# Dark background with border
	draw_rect(Rect2(box_x - 2, box_y - 2, box_w + 4, box_h + 4), Color(0.8, 0.7, 0.3, 0.9))
	draw_rect(Rect2(box_x, box_y, box_w, box_h), Color(0.12, 0.12, 0.15, 0.95))
	# Title
	draw_string(font, Vector2(box_x + pad, box_y + 26), "TIMELINE SHIFTED",
		HORIZONTAL_ALIGNMENT_LEFT, box_w - pad * 2, title_size, Color(1, 0.9, 0.4, 1.0))
	# Colored text lines (scrollable)
	var y_cursor = box_y + 30.0 + line_h
	for li in visible_lines:
		var line_idx = li + shift_summary_scroll
		if line_idx >= total_lines: break
		var line = shift_summary_lines[line_idx]
		var x_cursor = box_x + pad
		for seg in line:
			var text: String = seg.t
			var col: Color = seg.c
			draw_string(font, Vector2(x_cursor, y_cursor), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
			x_cursor += font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		y_cursor += line_h
	# Scroll indicator
	if max_scroll > 0:
		var bar_x = box_x + box_w - 10
		var bar_top = box_y + 34.0
		var bar_h = visible_lines * line_h
		draw_rect(Rect2(bar_x, bar_top, 5, bar_h), Color(0.3, 0.3, 0.3, 0.5))
		var thumb_h = bar_h * float(visible_lines) / float(total_lines)
		var thumb_y = bar_top + (bar_h - thumb_h) * float(shift_summary_scroll) / float(max_scroll)
		draw_rect(Rect2(bar_x, thumb_y, 5, thumb_h), Color(0.7, 0.7, 0.7, 0.7))
	# Click prompt
	draw_string(font, Vector2(box_x + pad, y_cursor + 4), "(click to continue)",
		HORIZONTAL_ALIGNMENT_LEFT, box_w - pad * 2, 13, Color(0.6, 0.6, 0.6, 0.8))
	# Draw fate icons on the map with swell animation
	if not shift_summary_diff.is_empty() and not confirmed_sim.is_empty():
		var fate_changes: Array = shift_summary_diff.get("fate_changes", [])
		var timelines_s: Array = confirmed_sim.get("timelines", [])
		var units_s: Array = confirmed_sim.get("units", [])
		# Swell: pulse from 1.0 to 1.5 and back over 0.6s
		var swell = 1.0 + 0.5 * sin(shift_summary_timer * TAU / 0.6)
		var icon_size = HEX_SIZE * 2.5 * cam_zoom * swell
		for fc in fate_changes:
			var uid_fc: int = fc.uid
			if uid_fc >= units_s.size() or uid_fc >= timelines_s.size(): continue
			var u_fc = units_s[uid_fc]
			var trail_fc: Array = timelines_s[uid_fc]
			var final_pos = Vector2i(-1, -1)
			if u_fc.eliminated:
				var et = mini(u_fc.elim_turn, trail_fc.size() - 1)
				final_pos = trail_fc[et]
			else:
				final_pos = trail_fc[trail_fc.size() - 1]
			if final_pos == Vector2i(-1, -1): continue
			var center = hex_to_pixel(final_pos.x, final_pos.y)
			var team_tint = C_P1 if u_fc.player == 1 else C_P2
			if fc.fate == "now_dies" and _icon_death:
				var r = Rect2(center - Vector2(icon_size * 0.5, icon_size * 0.5), Vector2(icon_size, icon_size))
				draw_texture_rect(_icon_death, r, false, team_tint)
			elif fc.fate == "now_survives" and _icon_survive:
				var r = Rect2(center - Vector2(icon_size * 0.5, icon_size * 0.5), Vector2(icon_size, icon_size))
				draw_texture_rect(_icon_survive, r, false, team_tint)

func _draw_banner(center: Vector2, idx: int):
	var sc = cam_zoom
	var pole_top = center + Vector2(0, -HEX_SIZE * sc * 1.1)
	var pole_bot = center + Vector2(0,  HEX_SIZE * sc * 0.3)
	draw_line(pole_bot, pole_top, Color(0.55, 0.45, 0.30), 1.5 * sc)
	var fw = HEX_SIZE * sc * 0.5
	var fh = HEX_SIZE * sc * 0.5
	var ft = pole_top + Vector2(0, fh * 0.05)
	var flag_cols = [Color(0.85, 0.72, 0.18), Color(0.72, 0.28, 0.14), Color(0.18, 0.55, 0.28)]
	draw_colored_polygon(PackedVector2Array([
		ft, ft + Vector2(fw, fh * 0.5), ft + Vector2(0, fh),
	]), flag_cols[idx % 3])

func _draw_swords(center: Vector2):
	var r = 9.0 * cam_zoom
	for sign in [-1.0, 1.0]:
		var angle = sign * PI / 4.0
		var dir   = Vector2(cos(angle), sin(angle))
		var perp  = Vector2(-dir.y, dir.x)
		draw_line(center - dir * r, center + dir * r, C_SWORD, 2.0)
		draw_line(center + dir * r * 0.3 - perp * r * 0.4,
			center + dir * r * 0.3 + perp * r * 0.4, C_SWORD.darkened(0.2), 1.5)

func _draw_hud():
	var font = ThemeDB.fallback_font
	var vp   = get_viewport_rect().size
	draw_rect(Rect2(0, 0, vp.x, 44), Color(0, 0, 0, 0.75))

	var p1_placed = placed_p1.size()
	var p2_placed = placed_p2.size()
	var txt := ""

	if phase == Phase.DEPLOY:
		var who = "BLUE (P1)" if active_player == 1 else "RED (P2)"
		var zone_desc = "bottom zone" if active_player == 1 else "top zone"
		var utype = deploy_unit_type.replace("_", " ").to_upper()
		var hint = "Select a unit type" if selecting_unit else ("Select arrival turn" if ds_selecting_turn else ("Click %s to place %s" % [zone_desc, utype]))
		txt = "%s's turn — %s   |   P1: %d/%d   P2: %d/%d" \
			% [who, hint, p1_placed, UNITS_PER_SIDE, p2_placed, UNITS_PER_SIDE]
	elif phase == Phase.DONE:
		var vpt: Array = confirmed_sim.get("vp_per_turn", [])
		var final_vp = vpt[vpt.size() - 1] if vpt.size() > 0 else [0, 0]
		var res = "DRAW"
		if   final_vp[0] > final_vp[1]: res = "BLUE WINS"
		elif final_vp[1] > final_vp[0]: res = "RED WINS"
		txt = "ALL DEPLOYED — %s   |   VP: BLUE %d - RED %d   |   Turn %d/%d" \
			% [res, final_vp[0], final_vp[1], anim_turn, TURNS]

	draw_string(font, Vector2(14, 28), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.88, 0.88, 0.88))

	# View mode indicator during deployment
	if phase == Phase.DEPLOY:
		var mode_names = ["1:CLEAN", "2:CHANGED", "3:FULL", "4:FINAL"]
		var mode_x = vp.x - 480.0
		for i in 4:
			var label = mode_names[i]
			var is_active = (i == view_mode)
			var col = Color(1.0, 0.9, 0.3) if is_active else Color(0.5, 0.5, 0.5)
			if is_active:
				label = "[%s]" % label
			draw_string(font, Vector2(mode_x, 28), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
			mode_x += 115.0

	# Turn indicator bar
	var bar_y: float = 44.0
	var bar_h: float = 4.0
	draw_rect(Rect2(0, bar_y, vp.x, bar_h), Color(0.15, 0.14, 0.12))
	var progress = float(anim_turn) / float(TURNS)
	draw_rect(Rect2(0, bar_y, vp.x * progress, bar_h), C_COMBAT)

	# REPLAY + SUMMARY buttons when game is done
	if phase == Phase.DONE:
		var btn_replay = Rect2(vp.x / 2.0 - 135, 55, 120, 36)
		draw_rect(btn_replay, Color(0.85, 0.75, 0.2, 0.9))
		draw_rect(btn_replay, Color(1, 1, 1, 0.4), false, 1.5)
		draw_string(font, Vector2(btn_replay.position.x + 18, btn_replay.position.y + 24), "REPLAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.1, 0.1, 0.1))

		var btn_summary = Rect2(vp.x / 2.0 + 15, 55, 120, 36)
		draw_rect(btn_summary, Color(0.2, 0.55, 0.85, 0.9))
		draw_rect(btn_summary, Color(1, 1, 1, 0.4), false, 1.5)
		draw_string(font, Vector2(btn_summary.position.x + 6, btn_summary.position.y + 24), "SUMMARY", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1))

func _generate_preview_narrative(sim: Dictionary) -> Array:
	if sim.is_empty() or preview_sim.is_empty():
		return []
	var timelines: Array = sim.get("timelines", [])
	var final_units: Array = sim.get("units", [])
	var combat_ev: Array = sim.get("combat", [])
	var names: Array = sim.get("unit_names", [])
	var obj_ctrl_hist: Array = sim.get("obj_ctrl_history", [])

	if timelines.is_empty():
		return []
	var puid = timelines.size() - 1
	var u = final_units[puid]
	var trail: Array = timelines[puid]
	var uname = names[puid] if puid < names.size() else "Unit"
	var utype = u.unit_type.replace("_", " ").capitalize()
	var team = "Blue" if u.player == 1 else "Red"

	var lines: Array = []
	lines.append({"text": "%s %s (%s)" % [utype, uname, team], "color": C_P1 if u.player == 1 else C_P2})

	# Track what objectives this unit is near each turn
	var at_obj := -1  # which objective (0,1,2) or -1
	var at_obj_since := -1
	var combat_partners: Array = []  # names of enemies fought
	var wounds_taken := 0
	var models_lost := 0
	var start_models = _get_stats(u.unit_type).models

	for t in TURNS:
		var ti = mini(t + 1, trail.size() - 1)
		var pos = trail[ti]
		if pos == Vector2i(-1, -1):
			if u.get("start_turn", 0) > 0 and t < u.start_turn:
				continue  # deep strike not yet arrived
			continue

		# Check objective proximity
		var near_obj := -1
		for oi in OBJECTIVES.size():
			if hex_dist(pos.x, pos.y, OBJECTIVES[oi].x, OBJECTIVES[oi].y) <= 2:
				near_obj = oi
				break
		if near_obj != at_obj:
			if at_obj >= 0 and at_obj_since >= 0:
				var dur = t - at_obj_since
				if dur > 0:
					lines.append({"text": "T%d-%d: Contests Obj %d" % [at_obj_since + 1, t, at_obj + 1], "color": Color(0.85, 0.85, 0.85)})
			at_obj = near_obj
			at_obj_since = t

		# Check combat events this turn
		if t < combat_ev.size():
			for ev in combat_ev[t]:
				var is_attacker = (ev.get("ac", -1) == pos.x and ev.get("ar", -1) == pos.y)
				var is_defender = (ev.get("bc", -1) == pos.x and ev.get("br", -1) == pos.y)
				if is_attacker or is_defender:
					var eid = ev.get("b", -1) if is_attacker else ev.get("a", -1)
					if eid >= 0 and eid < names.size():
						var ename = names[eid]
						if not combat_partners.has(ename):
							combat_partners.append(ename)

	# Final objective line
	if at_obj >= 0 and at_obj_since >= 0:
		var end_t = u.elim_turn if u.eliminated else TURNS
		var dur = end_t - at_obj_since
		if dur > 0:
			lines.append({"text": "T%d-%d: Contests Obj %d" % [at_obj_since + 1, end_t, at_obj + 1], "color": Color(0.85, 0.85, 0.85)})

	# Combat summary
	if combat_partners.size() > 0:
		var partner_str = ", ".join(combat_partners.slice(0, 3))
		if combat_partners.size() > 3:
			partner_str += " +%d more" % (combat_partners.size() - 3)
		lines.append({"text": "Fights: %s" % partner_str, "color": Color(0.9, 0.7, 0.3)})

	# Outcome
	if u.eliminated:
		lines.append({"text": "Killed turn %d" % u.elim_turn, "color": Color(0.9, 0.3, 0.3)})
		lines.append({"text": "%d/%d models lost" % [start_models, start_models], "color": Color(0.7, 0.4, 0.4)})
	else:
		var lost = start_models - u.models
		if lost > 0:
			lines.append({"text": "Survives (%d/%d models lost)" % [lost, start_models], "color": Color(0.8, 0.8, 0.3)})
		else:
			lines.append({"text": "Survives unscathed", "color": Color(0.3, 0.9, 0.3)})

	# Score impact
	var sd: Array = preview_diff.get("score_delta", [])
	if sd.size() >= 2:
		var delta = sd[0] if u.player == 1 else sd[1]
		var enemy_delta = sd[1] if u.player == 1 else sd[0]
		if delta != 0 or enemy_delta != 0:
			var net = delta - enemy_delta
			var net_col = Color(0.3, 0.9, 0.3) if net > 0 else (Color(0.9, 0.3, 0.3) if net < 0 else Color(0.7, 0.7, 0.7))
			lines.append({"text": "VP impact: %+d net" % net, "color": net_col})

	return lines

func _draw_preview_narrative(sim: Dictionary):
	if preview_sim.is_empty():
		return
	var lines = _generate_preview_narrative(sim)
	if lines.is_empty():
		return

	var font = ThemeDB.fallback_font
	var vp = get_viewport_rect().size
	var fs = 16
	var line_h = 22
	var pad = 10
	var panel_w = 280.0
	var panel_x = vp.x - panel_w - 16
	# Position below fate chart: scoreboard + fate chart
	var sb_h = 31 * (TURNS + 1) + 20
	var fate_h = 29 * (preview_sim.get("units", []).size() + 1) + 10
	var panel_y = 56.0 + sb_h + 10 + fate_h + 10

	var panel_h = lines.size() * line_h + pad * 2
	draw_rect(Rect2(panel_x, panel_y, panel_w, panel_h), Color(0.05, 0.05, 0.1, 0.85))
	draw_rect(Rect2(panel_x, panel_y, panel_w, panel_h), Color(0.4, 0.6, 0.3, 0.5), false, 1.5)

	var y = panel_y + pad + 14
	for entry in lines:
		draw_string(font, Vector2(panel_x + pad, y), entry.text,
			HORIZONTAL_ALIGNMENT_LEFT, panel_w - pad * 2, fs, entry.color)
		y += line_h

func _draw_scoreboard(sim: Dictionary):
	var vpt: Array = sim.get("vp_per_turn", [])
	if vpt.is_empty():
		return

	var font = ThemeDB.fallback_font
	var vp   = get_viewport_rect().size
	var fs   = 21  # font size
	var row_h = 31
	var col_w = 85
	var pad   = 10
	var board_w = col_w * 3  # turn label + blue + red
	var board_h = row_h * (TURNS + 1) + pad * 2  # header + turn rows + padding
	var bx = vp.x - board_w - 16  # right side
	var by: float = 56.0  # below HUD bar

	# Background
	draw_rect(Rect2(bx, by, board_w, board_h), Color(0, 0, 0, 0.7))

	# Header row
	var hdr_y = by + pad + row_h * 0.7
	draw_string(font, Vector2(bx + pad, hdr_y), "Turn", HORIZONTAL_ALIGNMENT_LEFT, col_w, fs, Color(0.7, 0.7, 0.7))
	draw_string(font, Vector2(bx + col_w, hdr_y), "BLUE", HORIZONTAL_ALIGNMENT_LEFT, col_w, fs, C_P1)
	draw_string(font, Vector2(bx + col_w * 2, hdr_y), "RED", HORIZONTAL_ALIGNMENT_LEFT, col_w, fs, C_P2)

	# Turn rows
	for t in TURNS:
		var ry = by + pad + row_h * (t + 1) + row_h * 0.7
		var label = str(t + 1)
		draw_string(font, Vector2(bx + pad, ry), label, HORIZONTAL_ALIGNMENT_LEFT, col_w, fs, Color(0.6, 0.6, 0.6))
		if t < vpt.size():
			var p1v = str(vpt[t][0])
			var p2v = str(vpt[t][1])
			draw_string(font, Vector2(bx + col_w, ry), p1v, HORIZONTAL_ALIGNMENT_LEFT, col_w, fs, C_P1)
			draw_string(font, Vector2(bx + col_w * 2, ry), p2v, HORIZONTAL_ALIGNMENT_LEFT, col_w, fs, C_P2)

	# Score delta when previewing
	var sd: Array = preview_diff.get("score_delta", [])
	if sd.size() >= 2 and (sd[0] != 0 or sd[1] != 0):
		var dy = by + pad + row_h * (TURNS + 1) + row_h * 0.7
		if sd[0] != 0:
			var s = ("+" if sd[0] > 0 else "") + str(sd[0])
			var c = Color(0.3, 0.9, 0.3) if sd[0] > 0 else Color(0.9, 0.3, 0.3)
			draw_string(font, Vector2(bx + col_w, dy), s, HORIZONTAL_ALIGNMENT_LEFT, col_w, fs, c)
		if sd[1] != 0:
			var s = ("+" if sd[1] > 0 else "") + str(sd[1])
			var c = Color(0.3, 0.9, 0.3) if sd[1] > 0 else Color(0.9, 0.3, 0.3)
			draw_string(font, Vector2(bx + col_w * 2, dy), s, HORIZONTAL_ALIGNMENT_LEFT, col_w, fs, c)

func _draw_unit_fate(sim: Dictionary):
	var names: Array = sim.get("unit_names", [])
	if names.is_empty():
		return
	var final_units: Array = sim.get("units", [])
	var obj_data: Array = sim.get("unit_obj", [])
	var kills_data: Array = sim.get("unit_kills", [])
	var dmg_data: Array = sim.get("unit_dmg", [])

	var font = ThemeDB.fallback_font
	var vp = get_viewport_rect().size
	var fs = 20
	var row_h = 29
	var cw = [115, 54, 46, 46, 46, 54, 54]  # unit, died, o1, o2, o3, kills, dmg
	var total_w = 0
	for w in cw:
		total_w += w

	# Position below scoreboard
	var sb_h = 31 * (TURNS + 1) + 20
	var bx = vp.x - total_w - 16
	var by = 56.0 + sb_h + 10

	var num = final_units.size()
	var chart_h = row_h * (num + 1) + 10

	# Background
	draw_rect(Rect2(bx, by, total_w, chart_h), Color(0, 0, 0, 0.7))

	# Header
	var hy = by + row_h * 0.85
	var headers = ["Unit", "Died", "O1", "O2", "O3", "Kills", "Dmg"]
	var hx = bx
	for i in headers.size():
		draw_string(font, Vector2(hx + 3, hy), headers[i], HORIZONTAL_ALIGNMENT_LEFT, cw[i], fs, Color(0.7, 0.7, 0.7))
		hx += cw[i]

	# Rows
	for uid in num:
		var u = final_units[uid]
		var ry = by + row_h * (uid + 1) + row_h * 0.85
		var rx = bx
		var tc = C_P1 if u.player == 1 else C_P2

		# Team divider
		if uid > 0 and u.player != final_units[uid - 1].player:
			var div_y = by + row_h * (uid + 1) - 1
			draw_line(Vector2(bx, div_y), Vector2(bx + total_w, div_y), Color(0.4, 0.4, 0.4, 0.5), 1.0)

		# Diff highlight (preview vs confirmed)
		var fate_list: Array = preview_diff.get("fate_changes", [])
		if uid < fate_list.size() and fate_list[uid].changed:
			var row_rect = Rect2(bx, by + row_h * (uid + 1), total_w, row_h)
			var tint_col: Color
			match fate_list[uid].fate:
				"now_survives": tint_col = Color(0.2, 0.8, 0.2, 0.25)
				"now_dies":     tint_col = Color(0.8, 0.2, 0.2, 0.25)
				_:              tint_col = Color(0.8, 0.8, 0.2, 0.15)
			draw_rect(row_rect, tint_col)

		# Name with type prefix
		var tp = _unit_prefix(u.unit_type) + " "
		draw_string(font, Vector2(rx + 3, ry), tp + names[uid], HORIZONTAL_ALIGNMENT_LEFT, cw[0], fs, tc)
		rx += cw[0]

		# Died on turn
		var d_str = str(u.elim_turn + 1) if u.eliminated else "-"
		var d_col = Color(0.8, 0.3, 0.3) if u.eliminated else Color(0.5, 0.5, 0.5)
		draw_string(font, Vector2(rx + 3, ry), d_str, HORIZONTAL_ALIGNMENT_LEFT, cw[1], fs, d_col)
		rx += cw[1]

		# Objective columns
		for oi in 3:
			var status = obj_data[uid][oi] if uid < obj_data.size() else "no"
			var s_str = "-"
			var s_col = Color(0.5, 0.5, 0.5)
			if status == "won":
				s_str = "WON"
				s_col = Color(0.3, 0.9, 0.3)
			elif status == "yes":
				s_str = "yes"
				s_col = Color(0.8, 0.8, 0.3)
			draw_string(font, Vector2(rx + 3, ry), s_str, HORIZONTAL_ALIGNMENT_LEFT, cw[2 + oi], fs, s_col)
			rx += cw[2 + oi]

		# Kills
		var k = kills_data[uid] if uid < kills_data.size() else 0
		var k_str = str(k) if k > 0 else "-"
		var k_col = Color(0.9, 0.6, 0.2) if k > 0 else Color(0.5, 0.5, 0.5)
		draw_string(font, Vector2(rx + 3, ry), k_str, HORIZONTAL_ALIGNMENT_LEFT, cw[5], fs, k_col)
		rx += cw[5]

		# Damage
		var dmg = dmg_data[uid] if uid < dmg_data.size() else 0
		var dmg_str = str(dmg) if dmg > 0 else "-"
		var dmg_col = Color(0.9, 0.4, 0.4) if dmg > 0 else Color(0.5, 0.5, 0.5)
		draw_string(font, Vector2(rx + 3, ry), dmg_str, HORIZONTAL_ALIGNMENT_LEFT, cw[6], fs, dmg_col)

func _draw_combat_log():
	if log_lines.is_empty():
		return
	var font = ThemeDB.fallback_font
	var vp = get_viewport_rect().size
	var fs = 13
	var line_h = 18
	var pad = 8
	var panel_w = 400
	var panel_x = 12
	var panel_y: float = 56.0
	var panel_h = vp.y - panel_y - 12
	var visible_lines = int(panel_h / line_h)

	# Background
	draw_rect(Rect2(panel_x, panel_y, panel_w, panel_h), Color(0, 0, 0, 0.75))

	# Title
	draw_string(font, Vector2(panel_x + pad, panel_y + 14), "Combat Log (scroll wheel)", HORIZONTAL_ALIGNMENT_LEFT, panel_w, 11, Color(0.7, 0.7, 0.7))

	# Lines
	var start_y = panel_y + 28
	var max_lines = mini(visible_lines - 2, log_lines.size() - log_scroll)
	for i in max_lines:
		var li = log_scroll + i
		if li >= log_lines.size(): break
		var line: String = log_lines[li]
		var y_pos = start_y + i * line_h
		if y_pos + line_h > panel_y + panel_h: break
		# Color based on content
		var col = Color(0.75, 0.75, 0.75)
		if line.begins_with("==="):
			col = Color(0.9, 0.85, 0.4)
		elif line.begins_with("---"):
			col = Color(0.5, 0.7, 0.9)
		elif "ELIMINATED" in line:
			col = Color(0.9, 0.3, 0.3)
		elif "Score:" in line:
			col = Color(0.4, 0.9, 0.5)
		elif line.find("moves") >= 0:
			col = Color(0.6, 0.6, 0.6)
		draw_string(font, Vector2(panel_x + pad, y_pos), line, HORIZONTAL_ALIGNMENT_LEFT, panel_w - pad * 2, fs, col)

	# Scroll indicator
	if log_lines.size() > visible_lines:
		var scroll_frac = float(log_scroll) / float(maxi(1, log_lines.size() - visible_lines))
		var bar_h = panel_h * float(visible_lines) / float(log_lines.size())
		var bar_y = panel_y + scroll_frac * (panel_h - bar_h)
		draw_rect(Rect2(panel_x + panel_w - 4, bar_y, 3, bar_h), Color(0.5, 0.5, 0.5, 0.5))

# ============================================================================
# REPLAY MODE
# ============================================================================

func _draw_final_state(sim: Dictionary):
	if sim.is_empty():
		return
	var timelines: Array = sim.get("timelines", [])
	var final_units: Array = sim.get("units", [])

	# Set objective control to final state
	_obj_control = sim.get("obj_control", [0, 0, 0])

	# Draw hex grid with final objective control
	for r in ROWS:
		for c in COLS:
			_draw_tile(c, r)


	# Draw all units at their final positions
	for uid in timelines.size():
		var u = final_units[uid]
		var trail: Array = timelines[uid]
		var final_pos = trail[trail.size() - 1] if trail.size() > 0 else Vector2i(-1, -1)
		# For eliminated units, use their last alive position
		if u.eliminated and u.elim_turn < trail.size():
			final_pos = trail[u.elim_turn]
		if final_pos == Vector2i(-1, -1): continue
		var center = hex_to_pixel(final_pos.x, final_pos.y)
		if u.eliminated:
			var r2 = 8.0 * cam_zoom
			draw_line(center + Vector2(-r2, -r2), center + Vector2(r2, r2),
				Color(0.9, 0.2, 0.2, 0.7), 2.5)
			draw_line(center + Vector2(r2, -r2), center + Vector2(-r2, r2),
				Color(0.9, 0.2, 0.2, 0.7), 2.5)
		else:
			_draw_unit_token(center, u.player, u.models, u.unit_type, false, 1.0)

	# Draw preview unit's full timeline on top so player sees their unit's path
	var is_preview = (not preview_sim.is_empty()) and sim == preview_sim
	if is_preview and timelines.size() > 0:
		var puid = timelines.size() - 1
		var combat_ev: Array = sim.get("combat", [])
		var display_turn = mini(anim_turn, TURNS)
		_draw_single_timeline(puid, final_units, timelines, combat_ev, display_turn, true)

func _draw_replay():
	var sim = confirmed_sim
	if sim.is_empty():
		return

	var timelines: Array = sim.get("timelines", [])
	var final_units: Array = sim.get("units", [])
	var snapshots: Array = sim.get("unit_snapshots", [])
	var obj_hist: Array = sim.get("obj_ctrl_history", [])
	var vpt: Array = sim.get("vp_per_turn", [])
	var unit_names: Array = sim.get("unit_names", [])

	if snapshots.is_empty():
		return

	# Set obj_control for tile drawing
	if replay_turn < obj_hist.size():
		_obj_control = obj_hist[replay_turn]
	else:
		_obj_control = sim.get("obj_control", [0, 0, 0])

	# Draw hex grid
	for r in ROWS:
		for c in COLS:
			_draw_tile(c, r)


	# Draw only the units at their replay_turn position — no ghosts, no trails
	var snap: Array = snapshots[replay_turn] if replay_turn < snapshots.size() else []
	for uid in timelines.size():
		var trail: Array = timelines[uid]
		# timeline index: turn 0 result is at index 1 (index 0 is deployment)
		var ti = mini(replay_turn + 1, trail.size() - 1)
		var pos = trail[ti]
		if pos == Vector2i(-1, -1): continue  # deep strike off-map
		var center = hex_to_pixel(pos.x, pos.y)

		var u_snap = snap[uid] if uid < snap.size() else {}
		var is_elim = u_snap.get("eliminated", false)
		var models = u_snap.get("models", 0)
		var u = final_units[uid]

		if is_elim:
			var r = 8.0 * cam_zoom
			draw_line(center + Vector2(-r, -r), center + Vector2(r, r),
				Color(0.9, 0.2, 0.2, 0.7), 2.5)
			draw_line(center + Vector2(r, -r), center + Vector2(-r, r),
				Color(0.9, 0.2, 0.2, 0.7), 2.5)
			continue

		_draw_unit_token(center, u.player, models, u.unit_type, false, 1.0)

	# Draw combat events for this turn
	var combat_ev: Array = sim.get("combat", [])
	if replay_turn < combat_ev.size():
		for ev in combat_ev[replay_turn]:
			var ac = hex_to_pixel(ev.ac, ev.ar)
			var bc = hex_to_pixel(ev.bc, ev.br)
			var mid = (ac + bc) * 0.5
			draw_circle(mid, 14.0 * cam_zoom, Color(C_COMBAT.r, C_COMBAT.g, C_COMBAT.b, 0.35))
			_draw_swords(mid)

	# --- Replay HUD ---
	var font = ThemeDB.fallback_font
	var vp = get_viewport_rect().size

	# Top bar
	draw_rect(Rect2(0, 0, vp.x, 44), Color(0, 0, 0, 0.85))
	var score_txt = ""
	if replay_turn < vpt.size():
		score_txt = "   |   VP: BLUE %d - RED %d" % [vpt[replay_turn][0], vpt[replay_turn][1]]
	var hud_txt = "REPLAY  —  Turn %d/%d   (Left/Right to navigate, Esc to exit)%s" % [replay_turn + 1, TURNS, score_txt]
	draw_string(font, Vector2(14, 28), hud_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.95, 0.85, 0.3))

	# Turn indicator bar
	draw_rect(Rect2(0, 44, vp.x, 4), Color(0.15, 0.14, 0.12))
	var progress = float(replay_turn + 1) / float(TURNS)
	draw_rect(Rect2(0, 38, vp.x * progress, 4), C_COMBAT)

	# Turn pips at bottom
	var pip_y = vp.y - 30
	var pip_w = 20.0
	var total_pip_w = pip_w * TURNS
	var pip_start = (vp.x - total_pip_w) / 2.0
	for t in TURNS:
		var px = pip_start + t * pip_w
		var is_active = (t == replay_turn)
		var pip_col = C_COMBAT if is_active else Color(0.3, 0.3, 0.3, 0.6)
		draw_rect(Rect2(px + 2, pip_y, pip_w - 4, 12), pip_col)
		draw_string(font, Vector2(px + 4, pip_y + 10), str(t + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.8) if is_active else Color(0.6, 0.6, 0.6))

# ============================================================================
# BATTLE SUMMARY
# ============================================================================

func _draw_battle_summary():
	var font = ThemeDB.fallback_font
	var vp = get_viewport_rect().size

	# Dark overlay
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.85))

	# Panel dimensions
	var panel_w: float = 620.0
	var panel_h: float = vp.y - 80.0
	var panel_x: float = (vp.x - panel_w) / 2.0
	var panel_y: float = 40.0

	# Panel background
	draw_rect(Rect2(panel_x, panel_y, panel_w, panel_h), Color(0.08, 0.08, 0.12))
	draw_rect(Rect2(panel_x, panel_y, panel_w, panel_h), Color(0.4, 0.35, 0.2, 0.6), false, 2.0)

	# Close button
	var close_rect = Rect2(panel_x + panel_w - 44, panel_y + 5, 34, 26)
	draw_rect(close_rect, Color(0.7, 0.2, 0.2, 0.8))
	draw_string(font, Vector2(close_rect.position.x + 8, close_rect.position.y + 19), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1))

	# Scroll hint
	draw_string(font, Vector2(panel_x + 10, panel_y + 26), "Scroll to navigate  |  Esc or X to close", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.5, 0.5))

	# Content area
	var content_x: float = panel_x + 16.0
	var content_y_start: float = panel_y + 38.0
	var content_h: float = panel_h - 48.0
	var line_h := 24.0

	# Clip to panel
	var visible_lines := int(content_h / line_h)
	var max_scroll = maxi(0, summary_lines.size() - visible_lines)
	summary_scroll = clampi(summary_scroll, 0, max_scroll)

	var y: float = content_y_start
	for i in visible_lines:
		var idx = i + summary_scroll
		if idx >= summary_lines.size(): break
		var entry = summary_lines[idx]
		var fsize = 18 if entry.bold else 16
		draw_string(font, Vector2(content_x, y + 18), entry.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, entry.color)
		y += line_h

	# Scroll bar
	if summary_lines.size() > visible_lines:
		var bar_x: float = panel_x + panel_w - 8
		var bar_total_h: float = content_h
		var thumb_h: float = maxf(20.0, bar_total_h * float(visible_lines) / float(summary_lines.size()))
		var thumb_y: float = content_y_start + (bar_total_h - thumb_h) * float(summary_scroll) / float(max_scroll) if max_scroll > 0 else content_y_start
		draw_rect(Rect2(bar_x, content_y_start, 4, bar_total_h), Color(0.2, 0.2, 0.2, 0.5))
		draw_rect(Rect2(bar_x, thumb_y, 4, thumb_h), Color(0.5, 0.5, 0.5, 0.7))

# ============================================================================
# UNIT SELECTION & DEEP STRIKE UI
# ============================================================================

func _draw_unit_select():
	var font = ThemeDB.fallback_font
	var vp = get_viewport_rect().size
	# Dim overlay
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.6))

	var accent = C_P1 if active_player == 1 else C_P2
	var who = "BLUE" if active_player == 1 else "RED"
	# Header
	draw_string(font, Vector2(vp.x / 2.0 - 130, vp.y / 2.0 - 55),
		"%s — Choose Unit Type" % who, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, accent)

	var btn_w = 145.0
	var btn_h = 48.0
	var gap = 10.0
	var total_w = UNIT_TYPES.size() * btn_w + (UNIT_TYPES.size() - 1) * gap
	var start_x = (vp.x - total_w) / 2.0
	var start_y = vp.y / 2.0 - btn_h / 2.0

	var mpos = get_viewport().get_mouse_position()
	for i in UNIT_TYPES.size():
		var bx = start_x + i * (btn_w + gap)
		var rect = Rect2(bx, start_y, btn_w, btn_h)
		var hovered = rect.has_point(mpos)
		var fill_alpha = 0.55 if hovered else 0.3
		var border_alpha = 1.0 if hovered else 0.5
		draw_rect(rect, Color(accent.r, accent.g, accent.b, fill_alpha))
		draw_rect(rect, Color(1, 1, 1, border_alpha), false, 2.0 if hovered else 1.5)
		var label = UNIT_TYPES[i].replace("_", " ").to_upper()
		draw_string(font, Vector2(bx + 8, start_y + 30), label,
			HORIZONTAL_ALIGNMENT_LEFT, btn_w - 16, 16, Color.WHITE if hovered else Color(0.95, 0.95, 0.95))

func _draw_ds_turn_select():
	var font = ThemeDB.fallback_font
	var vp = get_viewport_rect().size
	# Dim overlay
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.6))

	var accent = C_P1 if active_player == 1 else C_P2
	draw_string(font, Vector2(vp.x / 2.0 - 100, vp.y / 2.0 - 45),
		"Choose Arrival Turn", HORIZONTAL_ALIGNMENT_LEFT, -1, 21, accent)

	var btn_w = 60.0
	var btn_h = 42.0
	var gap = 10.0
	var count = 7  # T2 through T8
	var total_w = count * btn_w + (count - 1) * gap
	var start_x = (vp.x - total_w) / 2.0
	var start_y = vp.y / 2.0 - btn_h / 2.0

	var mpos = get_viewport().get_mouse_position()
	for i in count:
		var bx = start_x + i * (btn_w + gap)
		var rect = Rect2(bx, start_y, btn_w, btn_h)
		var hovered = rect.has_point(mpos)
		var fill_alpha = 0.55 if hovered else 0.3
		var border_alpha = 1.0 if hovered else 0.5
		draw_rect(rect, Color(accent.r, accent.g, accent.b, fill_alpha))
		draw_rect(rect, Color(1, 1, 1, border_alpha), false, 2.0 if hovered else 1.5)
		draw_string(font, Vector2(bx + 14, start_y + 28), "T%d" % (i + 2),
			HORIZONTAL_ALIGNMENT_LEFT, btn_w - 10, 17, Color.WHITE if hovered else Color(0.95, 0.95, 0.95))

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
	"models"  : 10,
	"hp"      : 2,
	"move"    : 6,
	"attacks" : 2,
	"hit"     : 3,
	"wound"   : 3,
	"rend"    : 1,
	"armor"   : 4,
	"damage"  : 1,
}

const CAVALRY = {
	"models"  : 5,
	"hp"      : 5,
	"move"    : 10,
	"attacks" : 2,
	"hit"     : 4,
	"wound"   : 3,
	"rend"    : 2,
	"armor"   : 3,
	"damage"  : 2,
}

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

# ============================================================================
# FLAT-TOP TOP-DOWN HEX MATH  (odd-q offset coords)
# ============================================================================
# Offset layout: odd columns are staggered DOWN by half a hex height.
# x = col * size * 1.5
# y = row * size * sqrt(3)  +  (col & 1) * size * sqrt(3) * 0.5

var cam_offset := Vector2.ZERO
var cam_zoom   := 1.0

var tile_tex: Texture2D = null   # single flat-top hex tile

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
			if other.eliminated or other.player == plr:
				continue
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
			if other.eliminated:
				continue
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
		if other.eliminated or other.player == plr:
			continue
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
		var d = hex_dist(u.col, u.row, e.col, e.row)
		if d <= range_val and d < best_d:
			best_d   = d
			best_eid = eid
	return best_eid

func _roll_combat(attacker: Dictionary, defender: Dictionary, rng: RandomNumberGenerator) -> int:
	# Returns total wounds dealt to defender
	var stats = INFANTRY if attacker.get("unit_type", "infantry") == "infantry" else CAVALRY
	var def_stats = INFANTRY if defender.get("unit_type", "infantry") == "infantry" else CAVALRY
	var wounds = 0
	for _i in attacker.models * stats.attacks:
		if rng.randi_range(1, 6) >= stats.hit:
			if rng.randi_range(1, 6) >= stats.wound:
				var save_target = def_stats.armor + stats.rend
				if rng.randi_range(1, 6) < save_target:
					wounds += stats.damage
	return wounds

func simulate(input_units: Array) -> Dictionary:
	# input_units: Array of {player, col, row, unit_type}
	var rng := RandomNumberGenerator.new()
	# Derive seed from positions for determinism per placement
	var seed_val = 42
	for u in input_units:
		seed_val = seed_val ^ (u.col * 31 + u.row * 97 + u.player * 7919)
	rng.seed = seed_val

	var units: Array = []
	for i in input_units.size():
		var src = input_units[i]
		var stats = INFANTRY if src.get("unit_type", "infantry") == "infantry" else CAVALRY
		units.append({
			"player"    : src.player,
			"col"       : src.col,
			"row"       : src.row,
			"unit_type" : src.get("unit_type", "infantry"),
			"models"    : stats.models,
			"wounds"    : 0,
			"eliminated": false,
			"elim_turn" : -1,
		})

	var timelines: Array = []
	for u in units:
		timelines.append([Vector2i(u.col, u.row)])

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
	for _i in units.size():
		unit_obj.append(["no", "no", "no"])
		unit_kills.append(0)
		unit_dmg.append(0)

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

	# Play-by-play combat log
	var combat_log: Array = []
	var p1_count = 0; var p2_count = 0
	for u in units:
		if u.player == 1: p1_count += 1
		else: p2_count += 1
	combat_log.append("=== Deployment: %d units (%d Blue, %d Red) ===" % [units.size(), p1_count, p2_count])
	for uid3 in units.size():
		var u3 = units[uid3]
		var tc3 = "C" if u3.unit_type == "cavalry" else "I"
		var tm3 = "Blue" if u3.player == 1 else "Red"
		combat_log.append("  %s %s (%s) at (%d,%d)" % [tc3, unit_names[uid3], tm3, u3.col, u3.row])
	combat_log.append("")

	for turn in TURNS:
		combat_log.append("--- Turn %d ---" % [turn + 1])

		# ---- Movement ----
		for uid in units.size():
			var u = units[uid]
			if u.eliminated:
				timelines[uid].append(Vector2i(u.col, u.row))
				continue
			# Stay if enemy in range
			if _nearest_enemy_in_range(uid, units, COMBAT_RANGE) >= 0:
				timelines[uid].append(Vector2i(u.col, u.row))
				continue

			var goal = _pick_target(uid, units)
			if goal == Vector2i(u.col, u.row):
				timelines[uid].append(goal)
				continue

			# Build blocked (all other units except goal hex)
			var blocked := {}
			for i in units.size():
				if i == uid or units[i].eliminated: continue
				var other = units[i]
				if other.col == goal.x and other.row == goal.y: continue
				blocked[hex_id(other.col, other.row)] = true

			var stats = INFANTRY if u.unit_type == "infantry" else CAVALRY
			var path = find_path(u.col, u.row, goal.x, goal.y, blocked)
			var steps = mini(stats.move, path.size())
			for step_i in steps:
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
			var tl = timelines[uid2]
			if tl.size() < 2: continue
			var prev = tl[tl.size() - 2]
			var cur  = tl[tl.size() - 1]
			if prev != cur:
				var tc2 = "C" if u2.unit_type == "cavalry" else "I"
				var tm2 = "Blue" if u2.player == 1 else "Red"
				combat_log.append("  %s %s (%s) moves (%d,%d)->(%d,%d)" % [tc2, unit_names[uid2], tm2, prev.x, prev.y, cur.x, cur.y])

		# ---- Combat ----
		var fought := {}
		for uid in units.size():
			var u = units[uid]
			if u.eliminated: continue
			var eid = _nearest_enemy_in_range(uid, units, COMBAT_RANGE)
			if eid < 0: continue
			var pair_key = mini(uid, eid) * 10000 + maxi(uid, eid)
			if fought.has(pair_key): continue
			fought[pair_key] = true
			var e = units[eid]
			combat_events[turn].append({ "a": uid, "b": eid,
				"ac": u.col, "ar": u.row, "bc": e.col, "br": e.row })

			# Roll both sides before applying (simultaneous resolution)
			var dmg_b = _roll_combat(u, e, rng)
			var dmg_a = _roll_combat(e, u, rng)
			unit_dmg[uid] += dmg_b
			unit_dmg[eid] += dmg_a
			var u_mdl_before = units[uid].models
			var e_mdl_before = units[eid].models
			_apply_wounds(uid, units, dmg_b, turn)
			_apply_wounds(eid, units, dmg_a, turn)

			# Log combat detail
			var u_tc = "C" if u.unit_type == "cavalry" else "I"
			var e_tc = "C" if e.unit_type == "cavalry" else "I"
			combat_log.append("  %s %s vs %s %s:" % [u_tc, unit_names[uid], e_tc, unit_names[eid]])
			if dmg_b > 0:
				var lost = u_mdl_before - units[uid].models
				var lost_s = " (%d models killed)" % lost if lost > 0 else ""
				combat_log.append("    %s takes %d wounds%s" % [unit_names[uid], dmg_b, lost_s])
			if dmg_a > 0:
				var lost = e_mdl_before - units[eid].models
				var lost_s = " (%d models killed)" % lost if lost > 0 else ""
				combat_log.append("    %s takes %d wounds%s" % [unit_names[eid], dmg_a, lost_s])
			if dmg_b == 0 and dmg_a == 0:
				combat_log.append("    No wounds dealt")

			if units[eid].eliminated and units[eid].elim_turn == turn:
				unit_kills[uid] += 1
				combat_log.append("    >>> %s %s ELIMINATED <<<" % [e_tc, unit_names[eid]])
			if units[uid].eliminated and units[uid].elim_turn == turn:
				unit_kills[eid] += 1
				combat_log.append("    >>> %s %s ELIMINATED <<<" % [u_tc, unit_names[uid]])

		# ---- Update persistent objective control ----
		for oi in OBJECTIVES.size():
			var obj = OBJECTIVES[oi]
			var old_ctrl = obj_control[oi]
			var p1_touch = false; var p2_touch = false
			for u in units:
				if u.eliminated: continue
				if hex_dist(u.col, u.row, obj.x, obj.y) <= 2:
					if u.player == 1: p1_touch = true
					else:              p2_touch = true
			if p1_touch and not p2_touch:
				obj_control[oi] = 1
			elif p2_touch and not p1_touch:
				obj_control[oi] = 2
			# Track unit objective contributions
			for uid2 in units.size():
				var u2 = units[uid2]
				if u2.eliminated: continue
				if hex_dist(u2.col, u2.row, obj.x, obj.y) > 2: continue
				if obj_control[oi] == u2.player and old_ctrl != u2.player:
					unit_obj[uid2][oi] = "won"
				elif p1_touch and p2_touch and unit_obj[uid2][oi] != "won":
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

	return { "timelines": timelines, "units": units, "combat": combat_events, "obj_control": obj_control, "vp_per_turn": vp_per_turn, "unit_names": unit_names, "unit_obj": unit_obj, "unit_kills": unit_kills, "unit_dmg": unit_dmg, "combat_log": combat_log }

func _apply_wounds(uid: int, units: Array, wounds: int, turn: int):
	var u     = units[uid]
	var stats = INFANTRY if u.unit_type == "infantry" else CAVALRY
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

var phase        = Phase.DEPLOY
var active_player = 1           # whose turn to deploy (1 or 2)
var deploy_unit_type := "infantry"  # toggle with Tab
var placed_p1    : Array        = []  # Array of {player,col,row,unit_type}
var placed_p2    : Array        = []

var confirmed_sim := {}
var preview_sim   := {}
var hover_hex     := Vector2i(-1, -1)

var anim_turn  := 0
var anim_frac  := 0.0   # 0.0–1.0 progress within the current turn (for smooth interpolation)
var _obj_control: Array = []  # per-objective: 0=neutral, 1=P1, 2=P2

# Combat log
var log_lines: Array = []
var log_scroll: int  = 0

# Camera drag
var drag_active   := false
var drag_start    := Vector2.ZERO
var cam_start     := Vector2.ZERO

# ============================================================================
# READY
# ============================================================================

func _ready():
	#tile_tex = load("res://assets/hex tactics assets/single tile.png")
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
	# Log panel scroll (left side, 340px wide)
	if event is InputEventMouseButton and event.pressed and event.position.x < 352:
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
		# Update hover
		var h = pixel_to_hex(event.position)
		var new_hover = h if is_valid_hex(h.x, h.y) else Vector2i(-1, -1)
		if new_hover != hover_hex:
			hover_hex = new_hover
			if _is_deploy_hex(new_hover):
				_recalc_preview_sim()
				anim_turn  = 0
				anim_frac  = 0.0
			elif not preview_sim.is_empty():
				preview_sim = {}
			queue_redraw()

	# Tab toggles unit type during deploy
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB and phase == Phase.DEPLOY:
		deploy_unit_type = "cavalry" if deploy_unit_type == "infantry" else "infantry"
		_recalc_preview_sim()
		queue_redraw()
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not drag_active:
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
	if active_player == 1:
		return h.y >= P1_DEPLOY_ROWS_MIN and h.y <= P1_DEPLOY_ROWS_MAX and h.x >= DEPLOY_C_MIN and h.x <= DEPLOY_C_MAX
	else:
		return h.y >= P2_DEPLOY_ROWS_MIN and h.y <= P2_DEPLOY_ROWS_MAX and h.x >= DEPLOY_C_MIN and h.x <= DEPLOY_C_MAX

func _handle_deploy_click(h: Vector2i):
	if phase != Phase.DEPLOY: return
	if not is_valid_hex(h.x, h.y): return

	if active_player == 1:
		if not (h.y >= P1_DEPLOY_ROWS_MIN and h.y <= P1_DEPLOY_ROWS_MAX and h.x >= DEPLOY_C_MIN and h.x <= DEPLOY_C_MAX):
			return
		for p in placed_p1:
			if p.col == h.x and p.row == h.y: return
		placed_p1.append({ "player": 1, "col": h.x, "row": h.y, "unit_type": deploy_unit_type })
		active_player = 2
	else:
		if not (h.y >= P2_DEPLOY_ROWS_MIN and h.y <= P2_DEPLOY_ROWS_MAX and h.x >= DEPLOY_C_MIN and h.x <= DEPLOY_C_MAX):
			return
		for p in placed_p2:
			if p.col == h.x and p.row == h.y: return
		placed_p2.append({ "player": 2, "col": h.x, "row": h.y, "unit_type": deploy_unit_type })
		active_player = 1

	hover_hex = Vector2i(-1, -1)
	_recalc_confirmed_sim()
	_recalc_preview_sim()
	anim_turn  = 0
	anim_frac  = 0.0

	var total_placed = placed_p1.size() + placed_p2.size()
	if total_placed >= UNITS_PER_SIDE * 2:
		phase = Phase.DONE
	queue_redraw()

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
	if phase != Phase.DEPLOY: return
	# Is the hover over the active player's deploy zone?
	if not is_valid_hex(hover_hex.x, hover_hex.y):
		preview_sim = {}
		return
	var in_zone = false
	if active_player == 1:
		in_zone = (hover_hex.y >= P1_DEPLOY_ROWS_MIN and hover_hex.y <= P1_DEPLOY_ROWS_MAX
			and hover_hex.x >= DEPLOY_C_MIN and hover_hex.x <= DEPLOY_C_MAX)
	else:
		in_zone = (hover_hex.y >= P2_DEPLOY_ROWS_MIN and hover_hex.y <= P2_DEPLOY_ROWS_MAX
			and hover_hex.x >= DEPLOY_C_MIN and hover_hex.x <= DEPLOY_C_MAX)
	if not in_zone:
		preview_sim = {}
		return
	# Check not stacking on existing unit
	var existing = placed_p1 if active_player == 1 else placed_p2
	for p in existing:
		if p.col == hover_hex.x and p.row == hover_hex.y:
			preview_sim = {}
			return
	var preview_unit = { "player": active_player, "col": hover_hex.x, "row": hover_hex.y, "unit_type": deploy_unit_type }
	var all_units: Array = placed_p1.duplicate() + placed_p2.duplicate()
	all_units.append(preview_unit)
	preview_sim = simulate(all_units)

# ============================================================================
# PROCESS
# ============================================================================

func _process(delta: float):
	anim_frac += delta / TURN_DURATION
	if anim_frac >= 1.0:
		anim_frac -= 1.0
		anim_turn = (anim_turn + 1) % (TURNS + 1)
	queue_redraw()   # every frame for smooth interpolation

# ============================================================================
# DRAWING
# ============================================================================

func _draw():
	var vp = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), C_BG)

	# Choose which sim to display
	var use_preview = (not preview_sim.is_empty()) and (phase == Phase.DEPLOY)
	var draw_sim    = preview_sim if use_preview else confirmed_sim
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
	else:
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

	# Hover highlight
	if hover_hex.x == col and hover_hex.y == row:
		draw_colored_polygon(corners, Color(1, 1, 1, 0.20))

	# Objective banner
	for i in OBJECTIVES.size():
		if OBJECTIVES[i] == Vector2i(col, row):
			_draw_banner(center, i)

func _draw_sim(sim: Dictionary, is_preview: bool):
	var timelines   : Array = sim.get("timelines", [])
	var final_units : Array = sim.get("units", [])
	var combat_ev   : Array = sim.get("combat", [])

	var display_turn = mini(anim_turn, TURNS)

	# --- 1) Highlight path hexes for each unit ---
	for uid in timelines.size():
		var u    = final_units[uid]
		var trail: Array = timelines[uid]
		var alive_until = u.elim_turn if u.eliminated else TURNS
		var max_ti = mini(alive_until + 1, trail.size() - 1)
		var is_preview_unit = (is_preview and uid == timelines.size() - 1)
		var base = C_P1 if u.player == 1 else C_P2
		var highlight_a = 0.08 if is_preview_unit else 0.15

		for ti in (max_ti + 1):
			var pos = trail[ti]
			var hc = hex_to_pixel(pos.x, pos.y)
			var corners = hex_corners(hc)
			draw_colored_polygon(corners, Color(base.r, base.g, base.b, highlight_a))

	# --- 2) Draw path lines connecting timeline positions ---
	for uid in timelines.size():
		var u    = final_units[uid]
		var trail: Array = timelines[uid]
		var alive_until = u.elim_turn if u.eliminated else TURNS
		var max_ti = mini(alive_until + 1, trail.size() - 1)
		var is_preview_unit = (is_preview and uid == timelines.size() - 1)
		var base = C_P1 if u.player == 1 else C_P2
		var line_alpha = 0.35 if is_preview_unit else 0.7
		var line_w = 1.5 * cam_zoom if is_preview_unit else 2.5 * cam_zoom

		for ti in max_ti:
			var from_pos = trail[ti]
			var to_pos   = trail[ti + 1]
			if from_pos == to_pos:
				continue  # stationary — no line needed
			var pa = hex_to_pixel(from_pos.x, from_pos.y)
			var pb = hex_to_pixel(to_pos.x, to_pos.y)
			draw_line(pa, pb, Color(base.r, base.g, base.b, line_alpha), line_w)

	# --- 3) Ghost tokens at each turn position ---
	for uid in timelines.size():
		var u    = final_units[uid]
		var trail: Array = timelines[uid]
		var alive_until = u.elim_turn if u.eliminated else TURNS
		var max_ti = mini(alive_until + 1, trail.size() - 1)
		var is_preview_unit = (is_preview and uid == timelines.size() - 1)

		for ti in (max_ti + 1):
			var pos = trail[ti]
			var center = hex_to_pixel(pos.x, pos.y)
			var progress = float(ti) / float(maxi(1, TURNS))
			var alpha = 0.15 + progress * 0.35
			if is_preview_unit:
				alpha *= 0.5
			var is_current = (ti == display_turn)
			if not is_current:
				_draw_unit_token(center, u.player, u.models, u.unit_type, true, alpha)

	# --- 4) Combat sparks ---
	for t in display_turn:
		if t >= combat_ev.size(): break
		for ev in combat_ev[t]:
			var ac = hex_to_pixel(ev.ac, ev.ar)
			var bc = hex_to_pixel(ev.bc, ev.br)
			var mid = (ac + bc) * 0.5
			draw_circle(mid, 14.0 * cam_zoom, Color(C_COMBAT.r, C_COMBAT.g, C_COMBAT.b, 0.20))
			_draw_swords(mid)

	# --- 5) Current-turn tokens on top (interpolated position) ---
	for uid in timelines.size():
		var trail: Array = timelines[uid]
		var u     = final_units[uid]
		var is_preview_unit = (is_preview and uid == timelines.size() - 1)
		var cur_idx  = mini(display_turn, trail.size() - 1)
		var next_idx = mini(display_turn + 1, trail.size() - 1)

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
		var alpha = 0.55 if is_preview_unit else 1.0
		_draw_unit_token(center, u.player, u.models, u.unit_type, is_preview_unit, alpha)

# ============================================================================
# DRAW HELPERS
# ============================================================================

func _draw_unit_token(center: Vector2, player: int, models: int, unit_type: String, is_ghost: bool, alpha: float):
	var base = C_P1 if player == 1 else C_P2
	var s    = HEX_SIZE * 0.55 * cam_zoom
	var a    = alpha * (0.60 if is_ghost else 1.0)
	var col  = Color(base.r, base.g, base.b, a)
	var line = Color(1, 1, 1, a * 0.5)

	if unit_type == "cavalry":
		# Diamond shape for cavalry
		var pts = PackedVector2Array([
			center + Vector2( 0,       -s * 1.1),
			center + Vector2( s * 1.1,  0),
			center + Vector2( 0,        s * 1.1),
			center + Vector2(-s * 1.1,  0),
		])
		draw_colored_polygon(pts, col)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), line, 1.0)
		# Chevron emblem (like a lance/arrow)
		var arm = s * 0.4
		draw_line(center + Vector2(-arm, arm * 0.3), center + Vector2(0, -arm * 0.5),
			Color(1, 1, 1, a * 0.7), 1.5)
		draw_line(center + Vector2(arm, arm * 0.3), center + Vector2(0, -arm * 0.5),
			Color(1, 1, 1, a * 0.7), 1.5)
	else:
		# Shield shape for infantry
		var pts = PackedVector2Array([
			center + Vector2(-s,       -s * 0.9),
			center + Vector2( s,       -s * 0.9),
			center + Vector2( s * 1.1,  s * 0.1),
			center + Vector2( 0,        s * 1.1),
			center + Vector2(-s * 1.1,  s * 0.1),
		])
		draw_colored_polygon(pts, col)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[4], pts[0]]), line, 1.0)
		# Cross emblem
		var arm = s * 0.45
		draw_line(center + Vector2(0, -arm), center + Vector2(0, arm),
			Color(1, 1, 1, a * 0.7), 1.5)
		draw_line(center + Vector2(-arm, -arm * 0.2), center + Vector2(arm, -arm * 0.2),
			Color(1, 1, 1, a * 0.7), 1.5)

	if not is_ghost and cam_zoom >= 0.5:
		var font = ThemeDB.fallback_font
		draw_string(font, center + Vector2(-4, 4), str(models),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, a))

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
	draw_rect(Rect2(0, 0, vp.x, 38), Color(0, 0, 0, 0.75))

	var p1_placed = placed_p1.size()
	var p2_placed = placed_p2.size()
	var txt := ""

	if phase == Phase.DEPLOY:
		var who = "BLUE (P1)" if active_player == 1 else "RED (P2)"
		var zone_desc = "bottom zone" if active_player == 1 else "top zone"
		var utype = deploy_unit_type.to_upper()
		txt = "%s's turn — click %s to place %s (Tab = switch)   |   P1: %d/%d   P2: %d/%d" \
			% [who, zone_desc, utype, p1_placed, UNITS_PER_SIDE, p2_placed, UNITS_PER_SIDE]
	elif phase == Phase.DONE:
		var vpt: Array = confirmed_sim.get("vp_per_turn", [])
		var final_vp = vpt[vpt.size() - 1] if vpt.size() > 0 else [0, 0]
		var res = "DRAW"
		if   final_vp[0] > final_vp[1]: res = "BLUE WINS"
		elif final_vp[1] > final_vp[0]: res = "RED WINS"
		txt = "ALL DEPLOYED — %s   |   VP: BLUE %d - RED %d   |   Turn %d/%d" \
			% [res, final_vp[0], final_vp[1], anim_turn, TURNS]

	draw_string(font, Vector2(14, 24), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.88, 0.88, 0.88))

	# Turn indicator bar
	var bar_y: float = 38.0
	var bar_h: float = 4.0
	draw_rect(Rect2(0, bar_y, vp.x, bar_h), Color(0.15, 0.14, 0.12))
	var progress = float(anim_turn) / float(TURNS)
	draw_rect(Rect2(0, bar_y, vp.x * progress, bar_h), C_COMBAT)

func _draw_scoreboard(sim: Dictionary):
	var vpt: Array = sim.get("vp_per_turn", [])
	if vpt.is_empty():
		return

	var font = ThemeDB.fallback_font
	var vp   = get_viewport_rect().size
	var fs   = 12  # font size
	var row_h = 18
	var col_w = 50
	var pad   = 8
	var board_w = col_w * 3  # turn label + blue + red
	var board_h = row_h * (TURNS + 1) + pad * 2  # header + turn rows + padding
	var bx = vp.x - board_w - 12  # right side
	var by: float = 50.0  # below HUD bar

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
	var fs = 11
	var row_h = 15
	var cw = [62, 30, 25, 25, 25, 30, 30]  # unit, died, o1, o2, o3, kills, dmg
	var total_w = 0
	for w in cw:
		total_w += w

	# Position below scoreboard
	var sb_h = 18 * (TURNS + 1) + 16
	var bx = vp.x - total_w - 12
	var by = 50.0 + sb_h + 8

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

		# Name with type prefix
		var tp = "C " if u.unit_type == "cavalry" else "I "
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
	var fs = 10
	var line_h = 14
	var pad = 6
	var panel_w = 340
	var panel_x = 12
	var panel_y: float = 50.0
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

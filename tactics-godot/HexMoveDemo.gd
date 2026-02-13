extends Node2D

# ============================================================================
# CONFIGURATION
# ============================================================================

const COLS          = 28
const ROWS          = 20
const HEX_SIZE      = 20.0   # circumradius of hex (center to corner)

const UNITS_PER_SIDE = 3
const TURNS          = 12
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

func _pick_target_objective(uid: int, units: Array) -> Vector2i:
	# Priority: nearest unclaimed or enemy-held; ignore friendly-held
	# If all friendly-held, return nearest enemy position
	var u     = units[uid]
	var plr   = u.player

	# Compute objective control from current unit positions
	var obj_control: Array = []  # -1=none, 1=P1, 2=P2
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
		if ctrl == plr:
			continue  # friendly-held — skip
		var d = hex_dist(u.col, u.row, OBJECTIVES[i].x, OBJECTIVES[i].y)
		if d < best_dist:
			best_dist = d
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

	var combat_events: Array = []
	for _t in TURNS:
		combat_events.append([])

	for turn in TURNS:
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

			var goal = _pick_target_objective(uid, units)
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
			_apply_wounds(uid, units, dmg_b, turn)
			_apply_wounds(eid, units, dmg_a, turn)

	return { "timelines": timelines, "units": units, "combat": combat_events }

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
var placed_p1    : Array        = []  # Array of {player,col,row,unit_type}
var placed_p2    : Array        = []

var confirmed_sim := {}
var preview_sim   := {}
var hover_hex     := Vector2i(-1, -1)

var anim_turn  := 0
var anim_frac  := 0.0   # 0.0–1.0 progress within the current turn (for smooth interpolation)

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
			_recalc_preview_sim()
			anim_turn  = 0
			anim_frac  = 0.0
			queue_redraw()

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

func _handle_deploy_click(h: Vector2i):
	if phase != Phase.DEPLOY: return
	if not is_valid_hex(h.x, h.y): return

	if active_player == 1:
		if not (h.y >= P1_DEPLOY_ROWS_MIN and h.y <= P1_DEPLOY_ROWS_MAX and h.x >= DEPLOY_C_MIN and h.x <= DEPLOY_C_MAX):
			return
		for p in placed_p1:
			if p.col == h.x and p.row == h.y: return
		placed_p1.append({ "player": 1, "col": h.x, "row": h.y, "unit_type": "infantry" })
		active_player = 2
	else:
		if not (h.y >= P2_DEPLOY_ROWS_MIN and h.y <= P2_DEPLOY_ROWS_MAX and h.x >= DEPLOY_C_MIN and h.x <= DEPLOY_C_MAX):
			return
		for p in placed_p2:
			if p.col == h.x and p.row == h.y: return
		placed_p2.append({ "player": 2, "col": h.x, "row": h.y, "unit_type": "infantry" })
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

func _recalc_confirmed_sim():
	var all_units: Array = placed_p1.duplicate() + placed_p2.duplicate()
	if all_units.is_empty():
		confirmed_sim = {}
		return
	confirmed_sim = simulate(all_units)

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
	var preview_unit = { "player": active_player, "col": hover_hex.x, "row": hover_hex.y, "unit_type": "infantry" }
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

	# Top-down: no z-ordering needed, just draw row by row
	for r in ROWS:
		for c in COLS:
			_draw_tile(c, r)

	# Choose which sim to display
	var use_preview = (not preview_sim.is_empty()) and (phase == Phase.DEPLOY)
	var draw_sim    = preview_sim if use_preview else confirmed_sim

	if not draw_sim.is_empty():
		_draw_sim(draw_sim, use_preview)

	_draw_hud()

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

	for obj in OBJECTIVES:
		if hex_dist(col, row, obj.x, obj.y) <= 2:
			tint = tint.lerp(Color(C_BANNER.r, C_BANNER.g, C_BANNER.b, 0.25), 0.5)
		if col == obj.x and row == obj.y:
			tint = Color(C_BANNER.r, C_BANNER.g, C_BANNER.b, 0.45)

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
				_draw_unit_token(center, u.player, u.models, true, alpha)

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
		_draw_unit_token(center, u.player, u.models, is_preview_unit, alpha)

# ============================================================================
# DRAW HELPERS
# ============================================================================

func _draw_unit_token(center: Vector2, player: int, models: int, is_ghost: bool, alpha: float):
	var base = C_P1 if player == 1 else C_P2
	var s    = HEX_SIZE * 0.55 * cam_zoom
	var a    = alpha * (0.60 if is_ghost else 1.0)
	# Shield shape
	var pts  = PackedVector2Array([
		center + Vector2(-s,       -s * 0.9),
		center + Vector2( s,       -s * 0.9),
		center + Vector2( s * 1.1,  s * 0.1),
		center + Vector2( 0,        s * 1.1),
		center + Vector2(-s * 1.1,  s * 0.1),
	])
	draw_colored_polygon(pts, Color(base.r, base.g, base.b, a))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[4], pts[0]]),
		Color(1, 1, 1, a * 0.5), 1.0)
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
		txt = "%s's turn — click %s to place   |   P1: %d/%d   P2: %d/%d   |   RMB/Scroll = pan/zoom" \
			% [who, zone_desc, p1_placed, UNITS_PER_SIDE, p2_placed, UNITS_PER_SIDE]
	elif phase == Phase.DONE:
		var fu: Array = confirmed_sim.get("units", [])
		var p1a = 0; var p2a = 0
		for u in fu:
			if not u.eliminated:
				if u.player == 1:
					p1a += 1
				else:
					p2a += 1
		var res = "DRAW"
		if   p1a > p2a: res = "BLUE WINS"
		elif p2a > p1a: res = "RED WINS"
		txt = "ALL UNITS DEPLOYED — %s   |   Turn %d/%d   |   RMB/Scroll = pan/zoom" % [res, anim_turn, TURNS]

	draw_string(font, Vector2(14, 24), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.88, 0.88, 0.88))

	# Turn indicator bar
	var bar_y: float = 38.0
	var bar_h: float = 4.0
	draw_rect(Rect2(0, bar_y, vp.x, bar_h), Color(0.15, 0.14, 0.12))
	var progress = float(anim_turn) / float(TURNS)
	draw_rect(Rect2(0, bar_y, vp.x * progress, bar_h), C_COMBAT)

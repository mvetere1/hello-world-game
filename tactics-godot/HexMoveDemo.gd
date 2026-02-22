extends Node2D

# ============================================================================
# RESOURCE REFERENCES  (edit .tres files in Godot Inspector to tweak gameplay)
# ============================================================================

var _grid: GridConfig = preload("res://resources/config/grid_config.tres")
var _battle: BattleConfig = preload("res://resources/config/battle_config.tres")
var _unit_resources: Array = [
	preload("res://resources/units/infantry.tres"),
	preload("res://resources/units/cavalry.tres"),
	preload("res://resources/units/artillery.tres"),
	preload("res://resources/units/deep_strike.tres"),
	preload("res://resources/units/archer.tres"),
]
var _terrain_res_list: Array = [
	preload("res://resources/terrain/grass.tres"),
	preload("res://resources/terrain/forest.tres"),
	preload("res://resources/terrain/water.tres"),
]

# Cached legacy dicts — populated in _init() from resources above
var _legacy_stats: Dictionary = {}
var _unit_type_keys: Array[String] = []

# Terrain system — terrain_key -> TerrainType resource, hex_id -> terrain_key
var _terrain_resources: Dictionary = {}
var _terrain_data: Dictionary = {}
var _default_terrain_key: String = "grass"

func _init():
	for res in _unit_resources:
		_legacy_stats[res.unit_type_key] = res.to_legacy_dict()
		_unit_type_keys.append(res.unit_type_key)
	for tres in _terrain_res_list:
		_terrain_resources[tres.terrain_key] = tres

# ============================================================================
# CONFIGURATION  (backed by GridConfig + BattleConfig resources)
# ============================================================================

# Grid config — edit resources/config/grid_config.tres
var COLS: int:
	get: return _grid.cols
var ROWS: int:
	get: return _grid.rows
var HEX_SIZE: float:
	get: return _grid.hex_size
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
var OBJECTIVES: Array:
	get: return _grid.objectives

# Battle config — edit resources/config/battle_config.tres
var UNITS_PER_SIDE: int:
	get: return _battle.units_per_side
var TURNS: int:
	get: return _battle.turns
var COMBAT_RANGE: int:
	get: return _battle.combat_range
var TURN_DURATION: float:
	get: return _battle.turn_duration
var OC_RADIUS: int:
	get: return _battle.oc_radius
var CAVALRY_AGGRO: int:
	get: return _battle.cavalry_aggro
var UNIT_NAMES: Array:
	get: return _battle.unit_names

# Unit stat dicts — backed by UnitStats resources in resources/units/
var INFANTRY: Dictionary:
	get: return _legacy_stats.get("infantry", {})
var CAVALRY: Dictionary:
	get: return _legacy_stats.get("cavalry", {})
var ARTILLERY: Dictionary:
	get: return _legacy_stats.get("artillery", {})
var DEEP_STRIKE: Dictionary:
	get: return _legacy_stats.get("deep_strike", {})
var ARCHER: Dictionary:
	get: return _legacy_stats.get("archer", {})
var UNIT_TYPES: Array:
	get: return _unit_type_keys

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
	return _legacy_stats.get(unit_type, _legacy_stats.get("infantry", {}))

func _get_unit_res(unit_type: String) -> UnitStats:
	for res in _unit_resources:
		if res.unit_type_key == unit_type:
			return res
	return _unit_resources[0]

func _unit_prefix(unit_type: String) -> String:
	return _get_unit_res(unit_type).prefix

# ---- terrain query -----------------------------------------------------------

func _get_terrain_at(col: int, row: int) -> TerrainType:
	var key = _terrain_data.get(hex_id(col, row), _default_terrain_key)
	return _terrain_resources.get(key, _terrain_resources.get("grass"))

func _is_hex_passable(col: int, row: int) -> bool:
	return _get_terrain_at(col, row).passable

func _load_terrain_data():
	var path = "res://terrain_data.json"
	if not FileAccess.file_exists(path):
		return  # all grass by default
	var f = FileAccess.open(path, FileAccess.READ)
	var json = JSON.new()
	if json.parse(f.get_as_text()) == OK and typeof(json.data) == TYPE_DICTIONARY:
		for hex_id_str in json.data:
			_terrain_data[int(hex_id_str)] = json.data[hex_id_str]
	f.close()

func _load_terrain_sprites():
	var base = ProjectSettings.globalize_path("res://terrain/elements/")
	var mapping = {"forest": "trees.png", "water": "pond.png"}
	for key in mapping:
		var tex = _load_png_as_texture(base + mapping[key])
		if tex:
			_terrain_sprites[key] = tex

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
# Frame counts per sprite sheet — derived from UnitStats resources
var SPRITE_FRAMES: Dictionary:
	get:
		var d := {}
		for res in _unit_resources:
			d[res.unit_type_key] = {"idle": res.idle_frames, "run": res.run_frames, "size": res.sprite_size}
		return d

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

# --- Delegated to HexMath static class (scripts/hex_math.gd) ---
func is_valid_hex(col: int, row: int) -> bool: return HexMath.is_valid_hex(col, row)
func hex_id(col: int, row: int) -> int: return HexMath.hex_id(col, row)
func id_to_hex(id: int) -> Vector2i: return HexMath.id_to_hex(id)
func hex_neighbors(col: int, row: int) -> Array[Vector2i]: return HexMath.hex_neighbors(col, row)
func hex_dist(c1: int, r1: int, c2: int, r2: int) -> int: return HexMath.hex_dist(c1, r1, c2, r2)

# ============================================================================
# COMBAT SIMULATOR  (delegated to scripts/combat_simulator.gd)
# ============================================================================

var _sim: CombatSimulator

# --- Wrappers for deployment logic that uses simulator functions ---
func find_path(sc: int, sr: int, gc: int, gr: int, blocked: Dictionary = {}) -> Array[Vector2i]: return _sim.find_path(sc, sr, gc, gr, blocked)
func _compute_footprint(unit_type: String, models: int) -> int: return _sim.compute_footprint(unit_type, models)
func compute_compact_cluster(anchor: Vector2i, size: int, blocked: Dictionary) -> Array[Vector2i]: return HexMath.compute_compact_cluster(anchor, size, blocked)
func formation_dist(form_a: Array, form_b: Array) -> int: return HexMath.formation_dist(form_a, form_b)
func formation_dist_to_hex(formation: Array, target: Vector2i) -> int: return HexMath.formation_dist_to_hex(formation, target)

func _build_blocked_from_units(units: Array, exclude_uid: int, turn: int, exclude_goal: Vector2i = Vector2i(-999, -999)) -> Dictionary:
	return _sim.build_blocked_from_units(units, exclude_uid, turn, exclude_goal)

func simulate(input_units: Array) -> Dictionary: return _sim.simulate(input_units)
func _get_sim_stats(unit_type: String) -> Dictionary: return _sim.get_stats(unit_type)

# --- Trail tooltip (stays in HexMoveDemo for hover access) ---

func _build_trail_hex_cache(sim: Dictionary) -> Dictionary:
	var cache := {}
	var formations_tl: Array = sim.get("formations_timeline", [])
	var final_units: Array = sim.get("units", [])
	for uid in formations_tl.size():
		var ftl: Array = formations_tl[uid]
		var u = final_units[uid]
		var alive_until = u.elim_turn if u.eliminated else TURNS
		var max_ti = mini(alive_until + 1, ftl.size() - 1)
		for ti in (max_ti + 1):
			var form: Array = ftl[ti]
			for fh in form:
				if fh == Vector2i(-1, -1): continue
				var hid = hex_id(fh.x, fh.y)
				if not cache.has(hid):
					cache[hid] = uid
	return cache

func _find_trail_uid_at_hex(hex: Vector2i, sim: Dictionary) -> int:
	if not is_same(sim, _trail_hex_cache_ref):
		_trail_hex_cache = _build_trail_hex_cache(sim)
		_trail_hex_cache_ref = sim
	return _trail_hex_cache.get(hex_id(hex.x, hex.y), -1)

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
var hover_trail_uid := -1  # UID of unit whose trail is under cursor (-1 = none)
var _trail_hex_cache := {}  # hex_id -> uid, rebuilt when sim changes
var _trail_hex_cache_ref: Dictionary  # reference to sim the cache was built for
var _mouse_pos := Vector2.ZERO  # last known mouse position for tooltip placement
var deploy_heatmap := {}  # hex_id -> vp delta for active player
var _heatmap_queue: Array = []  # hex coords still to compute
var _heatmap_base_vp := 0      # cached baseline VP for incremental compute
var _heatmap_base_units: Array = []  # cached unit list for incremental compute
var _heatmap_min := 0  # worst delta seen so far (for relative scaling)
var _heatmap_max := 0  # best delta seen so far
var _heatmap_enabled := false  # toggled by H key during deploy
var _deploy_blocked_cache: Dictionary = {}  # zone + formation blocked hexes
var _log_visible := false  # toggled by L key

var anim_turn  := 0
var anim_frac  := 0.0   # 0.0–1.0 progress within the current turn (for smooth interpolation)
var _diff_flash_time := 0.0  # timer for CHANGED mode old/new crossfade (2s cycle)
var _obj_control: Array = []  # per-objective: 0=neutral, 1=P1, 2=P2

# Combat log
var log_lines: Array = []
var log_scroll: int  = 0

# Replay mode
var replay_mode  := false
var replay_turn  := 0

# Analytics UI toggle (Tab key)
var show_analytics_ui := true

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
var _terrain_sprites: Dictionary = {}  # terrain_key -> Texture2D
var _cursor_hand: Texture2D = null
var _cursor_nogo: Texture2D = null
var _icon_sword: Texture2D = null
var _icon_survive: Texture2D = null
var _icon_death: Texture2D = null

func _ready():
	#tile_tex = load("res://assets/hex tactics assets/single tile.png")
	_terrain_map = get_node_or_null("TerrainMap")
	_load_terrain_data()
	_sim = CombatSimulator.new(_terrain_resources, _terrain_data)
	_load_terrain_sprites()
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
	cam_zoom = _grid.initial_zoom
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
		if event.keycode == KEY_H:
			_heatmap_enabled = not _heatmap_enabled
			if _heatmap_enabled:
				_compute_deploy_heatmap()
			else:
				deploy_heatmap = {}
				_heatmap_queue = []
			queue_redraw()
			return
		if event.keycode == KEY_L:
			_log_visible = not _log_visible
			queue_redraw()
			return
		if event.keycode == KEY_TAB:
			show_analytics_ui = not show_analytics_ui
			queue_redraw()
			return

	# Log panel scroll (left side, 340px wide)
	if _log_visible and event is InputEventMouseButton and event.pressed and event.position.x < 420:
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
		_mouse_pos = event.position
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
			# Trail hover detection: find unit whose trail is under cursor
			hover_trail_uid = -1
			if new_hover != Vector2i(-1, -1) and not selecting_unit and not ds_selecting_turn and not showing_shift_summary and not show_summary:
				var active_sim = preview_sim if not preview_sim.is_empty() else confirmed_sim
				if not active_sim.is_empty():
					hover_trail_uid = _find_trail_uid_at_hex(new_hover, active_sim)
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
	# Basic zone check first
	var in_zone := false
	if deploy_unit_type == "deep_strike" and ds_arrival_turn > 0:
		in_zone = ds_legal_hexes.has(hex_id(h.x, h.y))
	elif active_player == 1:
		in_zone = h.y >= P1_DEPLOY_ROWS_MIN and h.y <= P1_DEPLOY_ROWS_MAX and h.x >= DEPLOY_C_MIN and h.x <= DEPLOY_C_MAX
	else:
		in_zone = h.y >= P2_DEPLOY_ROWS_MIN and h.y <= P2_DEPLOY_ROWS_MAX and h.x >= DEPLOY_C_MIN and h.x <= DEPLOY_C_MAX
	if not in_zone:
		return false
	# Cannot deploy on impassable terrain
	if not _is_hex_passable(h.x, h.y):
		return false
	# Check anchor not blocked by existing formations
	if _deploy_blocked_cache.has(hex_id(h.x, h.y)):
		return false
	# Check that the full formation cluster fits
	var stats = _get_stats(deploy_unit_type)
	var fp = _compute_footprint(deploy_unit_type, stats.models)
	var cluster = compute_compact_cluster(h, fp, _deploy_blocked_cache)
	return cluster.size() == fp

func _handle_deploy_click(h: Vector2i):
	if phase != Phase.DEPLOY or selecting_unit or ds_selecting_turn: return
	if not _is_deploy_hex(h): return

	# Compute the deploy formation (zone + stacking validated by _is_deploy_hex)
	var stats = _get_stats(deploy_unit_type)
	var fp = _compute_footprint(deploy_unit_type, stats.models)
	var formation = compute_compact_cluster(h, fp, _deploy_blocked_cache)
	if formation.size() < fp: return  # safety: can't fit

	var unit_data = { "player": active_player, "col": h.x, "row": h.y, "unit_type": deploy_unit_type, "formation": formation }
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

	# Get the placed unit's UID and name from the new sim
	var placed_uid = placed_p1.size() - 1 if placed_player == 1 else placed_p1.size() + placed_p2.size() - 1
	var new_names: Array = confirmed_sim.get("unit_names", [])
	if placed_uid >= 0 and placed_uid < new_names.size():
		placed_unit_name = new_names[placed_uid]

	var total_placed = placed_p1.size() + placed_p2.size()
	if total_placed >= UNITS_PER_SIDE * 2:
		phase = Phase.DONE
		selecting_unit = false
	else:
		# Show shift summary before next unit selection
		selecting_unit = false
		shift_summary_lines = _build_shift_summary_lines(shift_summary_diff, shift_old_sim, confirmed_sim, placed_unit_name, placed_type, placed_player, placed_uid)
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
				_recompute_deploy_cache()
				if _heatmap_enabled:
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
			ds_arrival_turn = i + 1  # T2 button (i=0) → 0-based turn 1 = display Turn 2
			ds_selecting_turn = false
			ds_legal_hexes = _compute_ds_legal_hexes(ds_arrival_turn)
			_recompute_deploy_cache()
			if _heatmap_enabled:
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
				# Check distance from candidate hex to enemy formation
				var su_form: Array = su.get("formation", [Vector2i(su.col, su.row)])
				if formation_dist_to_hex(su_form, Vector2i(c, r)) < CAVALRY_AGGRO + 1:
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
	# Compute preview formation using blocked cache (zone + stacking)
	var stats = _get_stats(deploy_unit_type)
	var fp = _compute_footprint(deploy_unit_type, stats.models)
	var formation = compute_compact_cluster(hover_hex, fp, _deploy_blocked_cache)
	if formation.size() < fp:
		preview_sim = {}
		preview_diff = {}
		return
	var preview_unit = { "player": active_player, "col": hover_hex.x, "row": hover_hex.y, "unit_type": deploy_unit_type, "formation": formation }
	if deploy_unit_type == "deep_strike" and ds_arrival_turn > 0:
		preview_unit["start_turn"] = ds_arrival_turn
	var all_units: Array = placed_p1.duplicate() + placed_p2.duplicate()
	all_units.append(preview_unit)
	preview_sim = simulate(all_units)
	preview_diff = _compute_sim_diff()

func _recompute_deploy_cache():
	_deploy_blocked_cache = {}
	var all_placed = placed_p1 + placed_p2
	# Add all stored formation hexes from placed units
	for p in all_placed:
		var form: Array = p.get("formation", [])
		if form.is_empty() and p.get("start_turn", 0) == 0:
			# Fallback: compute formation if not stored (shouldn't happen normally)
			var stats = _get_stats(p.unit_type)
			var fp = _compute_footprint(p.unit_type, stats.models)
			var b := {}
			for p2 in all_placed:
				if p2 == p: break
				for fh in p2.get("formation", []):
					b[hex_id(fh.x, fh.y)] = true
			form = compute_compact_cluster(Vector2i(p.col, p.row), fp, b)
		for fh in form:
			_deploy_blocked_cache[hex_id(fh.x, fh.y)] = true
	# Block non-deploy-zone hexes for current player (regular units)
	if deploy_unit_type != "deep_strike" or ds_arrival_turn <= 0:
		var r_min = P1_DEPLOY_ROWS_MIN if active_player == 1 else P2_DEPLOY_ROWS_MIN
		var r_max = P1_DEPLOY_ROWS_MAX if active_player == 1 else P2_DEPLOY_ROWS_MAX
		for c in COLS:
			for r in ROWS:
				if is_valid_hex(c, r) and (r < r_min or r > r_max or c < DEPLOY_C_MIN or c > DEPLOY_C_MAX):
					_deploy_blocked_cache[hex_id(c, r)] = true
	else:
		# Deep strike: block hexes not in ds_legal_hexes
		for c in COLS:
			for r in ROWS:
				if is_valid_hex(c, r) and not ds_legal_hexes.has(hex_id(c, r)):
					_deploy_blocked_cache[hex_id(c, r)] = true

func _compute_deploy_heatmap():
	deploy_heatmap = {}
	_heatmap_queue = []
	_heatmap_min = 0
	_heatmap_max = 0
	if phase != Phase.DEPLOY or selecting_unit or ds_selecting_turn or not _heatmap_enabled:
		return
	# Cache baseline VP
	_heatmap_base_vp = 0
	var conf_vpt: Array = confirmed_sim.get("vp_per_turn", [])
	if not conf_vpt.is_empty():
		var final_vp = conf_vpt[conf_vpt.size() - 1]
		_heatmap_base_vp = final_vp[0] if active_player == 1 else final_vp[1]
	_heatmap_base_units = placed_p1.duplicate() + placed_p2.duplicate()
	# Build queue of hex coordinates to process (filtered by formation validity)
	var stats = _get_stats(deploy_unit_type)
	var fp = _compute_footprint(deploy_unit_type, stats.models)
	if deploy_unit_type == "deep_strike" and ds_arrival_turn > 0:
		for hid in ds_legal_hexes:
			if _deploy_blocked_cache.has(hid): continue
			var coord = Vector2i(hid / 1000, hid % 1000)
			var cluster = compute_compact_cluster(coord, fp, _deploy_blocked_cache)
			if cluster.size() == fp:
				_heatmap_queue.append(coord)
	else:
		var r_min = P1_DEPLOY_ROWS_MIN if active_player == 1 else P2_DEPLOY_ROWS_MIN
		var r_max = P1_DEPLOY_ROWS_MAX if active_player == 1 else P2_DEPLOY_ROWS_MAX
		for r in range(r_min, r_max + 1):
			for c in range(DEPLOY_C_MIN, DEPLOY_C_MAX + 1):
				var hid = hex_id(c, r)
				if _deploy_blocked_cache.has(hid): continue
				var cluster = compute_compact_cluster(Vector2i(c, r), fp, _deploy_blocked_cache)
				if cluster.size() == fp:
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
	var ftls: Array = sim.get("formations_timeline", [])
	var obj_hist: Array = sim.get("obj_ctrl_history", [])
	var sim_units: Array = sim.get("units", [])
	if uid >= ftls.size() or uid >= sim_units.size():
		return [0, 0, 0]
	var u = sim_units[uid]
	var ftrail: Array = ftls[uid]
	var result = [0, 0, 0]
	for t in obj_hist.size():
		var pos_idx = t + 1   # ftrail[0] is deploy formation, ftrail[t+1] is after turn t
		if pos_idx >= ftrail.size(): break
		var form: Array = ftrail[pos_idx]
		if form.is_empty(): continue
		for oi in OBJECTIVES.size():
			if obj_hist[t][oi] == u.player:
				if formation_dist_to_hex(form, OBJECTIVES[oi]) <= OC_RADIUS:
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

func _build_shift_summary_lines(diff: Dictionary, old_sim: Dictionary, new_sim: Dictionary, placed_name: String, placed_type: String, placed_player: int, placed_uid: int = -1) -> Array:
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
	if placed_uid < 0:
		placed_uid = new_all_units.size() - 1
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
				perf_line.append({"t": ", dies turn %d." % (placed_u.elim_turn + 1) if placed_u.elim_turn >= 0 else ", eliminated.", "c": C_DEATH})
			else:
				perf_line.append({"t": ", survives.", "c": C_GREEN})
			lines.append(perf_line)
		elif placed_u.eliminated:
			perf_line.append({"t": "Dies on turn %d without dealing damage." % (placed_u.elim_turn + 1) if placed_u.elim_turn >= 0 else "Eliminated without dealing damage.", "c": C_DEATH})
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
				line.append({"t": " died on turn %d." % (u_old.elim_turn + 1), "c": C_GRAY} if u_old.elim_turn >= 0 else {"t": " was eliminated.", "c": C_GRAY})
			else:
				line.append({"t": " survived the battle.", "c": C_GRAY})
		else:
			if u_old.eliminated:
				line.append({"t": " and died on turn %d." % (u_old.elim_turn + 1), "c": C_GRAY} if u_old.elim_turn >= 0 else {"t": " and was eliminated.", "c": C_GRAY})
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
			now_text = "Now dies on turn %d" % (u_new.elim_turn + 1) if u_new.elim_turn >= 0 else "Now eliminated"
			if not obj_changes.is_empty():
				now_text += ", " + ", ".join(PackedStringArray(obj_changes))
			now_text += "."
		elif fc.fate == "now_survives":
			now_text = "Now survives the battle"
			if not obj_changes.is_empty():
				now_text += ", " + ", ".join(PackedStringArray(obj_changes))
			now_text += "."
		else:  # shifted
			now_text = "Now dies on turn %d instead of turn %d" % [u_new.elim_turn + 1, u_old.elim_turn + 1]
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
			var died_str = "T%d" % (u.elim_turn + 1) if u.eliminated else "-"
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
		lines.append({"text": "  T%d: %s %s (%s) eliminated" % [e.turn + 1, _unit_prefix(e.type), name_str, team], "color": tc, "bold": false})
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
	_diff_flash_time += delta
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
		if show_analytics_ui:
			_draw_scoreboard(draw_sim)
			_draw_unit_fate(draw_sim)
			if _log_visible: _draw_combat_log()
			if use_preview:
				_draw_preview_narrative(draw_sim)
			if hover_trail_uid >= 0 and not selecting_unit and not ds_selecting_turn:
				_draw_trail_tooltip(draw_sim)
		# "Change view" cursor tooltip in FINAL mode
		if not preview_sim.is_empty() and not selecting_unit and not ds_selecting_turn:
			var vp_f = get_viewport_rect().size
			var vhf_font = ThemeDB.fallback_font
			var vhf_fs = 14
			var vhf_pad = 6
			var vhf_prefix = "Change view:  "
			var vhf_nums = "1  2  3  4"
			var vhf_tw = vhf_font.get_string_size(vhf_prefix + vhf_nums, HORIZONTAL_ALIGNMENT_LEFT, -1, vhf_fs).x + vhf_pad * 2
			var vhf_th = 18 + vhf_pad * 2
			var vhf_x = _mouse_pos.x + 20
			var vhf_y = _mouse_pos.y - vhf_th - 10
			if vhf_x + vhf_tw > vp_f.x - 10:
				vhf_x = _mouse_pos.x - vhf_tw - 10
			if vhf_y < 10:
				vhf_y = _mouse_pos.y + 30
			draw_rect(Rect2(vhf_x, vhf_y, vhf_tw, vhf_th), Color(0.05, 0.05, 0.1, 0.8))
			draw_rect(Rect2(vhf_x, vhf_y, vhf_tw, vhf_th), Color(0.5, 0.5, 0.5, 0.4), false, 1.5)
			var vhf_cx = vhf_x + vhf_pad
			var vhf_cy = vhf_y + vhf_pad + 12
			draw_string(vhf_font, Vector2(vhf_cx, vhf_cy), vhf_prefix,
				HORIZONTAL_ALIGNMENT_LEFT, -1, vhf_fs, Color(0.6, 0.6, 0.6))
			vhf_cx += vhf_font.get_string_size(vhf_prefix, HORIZONTAL_ALIGNMENT_LEFT, -1, vhf_fs).x
			for vi in 4:
				var vnum = str(vi + 1)
				var vnum_col = Color(1.0, 0.9, 0.3) if vi == view_mode else Color(0.5, 0.5, 0.5)
				draw_string(vhf_font, Vector2(vhf_cx, vhf_cy), vnum,
					HORIZONTAL_ALIGNMENT_LEFT, -1, vhf_fs, vnum_col)
				var vnum_spacing = vnum + ("  " if vi < 3 else "")
				vhf_cx += vhf_font.get_string_size(vnum_spacing, HORIZONTAL_ALIGNMENT_LEFT, -1, vhf_fs).x
		# Overlay popups
		if selecting_unit:
			_draw_unit_select()
		elif ds_selecting_turn:
			_draw_ds_turn_select()
		return

	_obj_control = _compute_obj_control(draw_sim)

	# Viewport culling: only draw hexes visible on screen
	var vp_rect = get_viewport_rect().size
	var world_min = -cam_offset / cam_zoom
	var world_max = (vp_rect - cam_offset) / cam_zoom
	var hex_w = HEX_SIZE * 1.5
	var hex_h = HEX_SIZE * sqrt(3.0)
	var c_min = clampi(int(world_min.x / hex_w) - 2, 0, COLS - 1)
	var c_max = clampi(int(world_max.x / hex_w) + 2, 0, COLS - 1)
	var r_min = clampi(int(world_min.y / hex_h) - 2, 0, ROWS - 1)
	var r_max = clampi(int(world_max.y / hex_h) + 2, 0, ROWS - 1)
	for r in range(r_min, r_max + 1):
		for c in range(c_min, c_max + 1):
			_draw_tile(c, r)

	# Dark fog overlay for CHANGED mode — dims tiles so only changes pop
	if phase == Phase.DEPLOY and view_mode == ViewMode.CHANGED and not preview_sim.is_empty():
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.70))

	if not draw_sim.is_empty():
		_draw_sim(draw_sim, use_preview)

	_draw_hud()
	if show_analytics_ui:
		_draw_scoreboard(draw_sim)
		_draw_unit_fate(draw_sim)
		_draw_combat_log()
		if use_preview:
			_draw_preview_narrative(draw_sim)

		# Trail hover tooltip (works in both DEPLOY and DONE phases)
		if hover_trail_uid >= 0 and not selecting_unit and not ds_selecting_turn and not showing_shift_summary and not show_summary:
			_draw_trail_tooltip(draw_sim)

	# "Change view" cursor tooltip during deploy with active preview
	if phase == Phase.DEPLOY and not preview_sim.is_empty() and not selecting_unit and not ds_selecting_turn and not showing_shift_summary and not show_summary:
		var vh_font = ThemeDB.fallback_font
		var vh_fs = 14
		var vh_pad = 6
		var vh_prefix = "Change view:  "
		var vh_nums = "1  2  3  4"
		var vh_tw = vh_font.get_string_size(vh_prefix + vh_nums, HORIZONTAL_ALIGNMENT_LEFT, -1, vh_fs).x + vh_pad * 2
		var vh_th = 18 + vh_pad * 2
		var vh_x = _mouse_pos.x + 20
		var vh_y = _mouse_pos.y - vh_th - 10
		if vh_x + vh_tw > vp.x - 10:
			vh_x = _mouse_pos.x - vh_tw - 10
		if vh_y < 10:
			vh_y = _mouse_pos.y + 30
		draw_rect(Rect2(vh_x, vh_y, vh_tw, vh_th), Color(0.05, 0.05, 0.1, 0.8))
		draw_rect(Rect2(vh_x, vh_y, vh_tw, vh_th), Color(0.5, 0.5, 0.5, 0.4), false, 1.5)
		var vh_cx = vh_x + vh_pad
		var vh_cy = vh_y + vh_pad + 12
		draw_string(vh_font, Vector2(vh_cx, vh_cy), vh_prefix,
			HORIZONTAL_ALIGNMENT_LEFT, -1, vh_fs, Color(0.6, 0.6, 0.6))
		vh_cx += vh_font.get_string_size(vh_prefix, HORIZONTAL_ALIGNMENT_LEFT, -1, vh_fs).x
		for vi in 4:
			var vnum = str(vi + 1)
			var vnum_col = Color(1.0, 0.9, 0.3) if vi == view_mode else Color(0.5, 0.5, 0.5)
			draw_string(vh_font, Vector2(vh_cx, vh_cy), vnum,
				HORIZONTAL_ALIGNMENT_LEFT, -1, vh_fs, vnum_col)
			var vnum_spacing = vnum + ("  " if vi < 3 else "")
			vh_cx += vh_font.get_string_size(vnum_spacing, HORIZONTAL_ALIGNMENT_LEFT, -1, vh_fs).x

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

	# Terrain sprite overlay (non-grass hexes)
	var terrain = _get_terrain_at(col, row)
	if terrain.terrain_key != "grass":
		var t_sprite = _terrain_sprites.get(terrain.terrain_key)
		if t_sprite:
			var tw = HEX_SIZE * 2.0 * cam_zoom
			var th = HEX_SIZE * 2.0 * cam_zoom
			var dest = Rect2(center - Vector2(tw * 0.5, th * 0.5), Vector2(tw, th))
			draw_texture_rect(t_sprite, dest, false)
		else:
			var t_tint = terrain.tile_color
			t_tint.a = 0.35
			draw_colored_polygon(corners, t_tint)
		var t_outline = PackedVector2Array(corners)
		t_outline.append(corners[0])
		var t_color = Color(0.2, 0.5, 0.2) if terrain.terrain_key == "forest" else Color(0.2, 0.4, 0.7)
		draw_polyline(t_outline, t_color, 2.5 * cam_zoom)

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
		if hex_dist(col, row, obj.x, obj.y) <= OC_RADIUS:
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
			if hex_dist(col, row, OBJECTIVES[i].x, OBJECTIVES[i].y) <= OC_RADIUS:
				draw_colored_polygon(corners, Color(1.0, 0.9, 0.2, 0.15))
			if col == OBJECTIVES[i].x and row == OBJECTIVES[i].y:
				var glow_pts = PackedVector2Array(corners)
				glow_pts.append(corners[0])
				draw_polyline(glow_pts, Color(1.0, 0.9, 0.2, 0.7), 2.5)

	# Objective banner
	for i in OBJECTIVES.size():
		if OBJECTIVES[i] == Vector2i(col, row):
			_draw_banner(center, i)

func _draw_unit_final(uid: int, final_units: Array, timelines: Array, formations_tl: Array, is_ghost: bool, alpha: float):
	var u = final_units[uid]
	var trail: Array = timelines[uid]
	var ftl: Array = formations_tl[uid] if uid < formations_tl.size() else []
	var final_pos = Vector2i(-1, -1)
	var final_idx := 0
	if u.eliminated:
		final_idx = mini(u.elim_turn, trail.size() - 1)
		final_pos = trail[final_idx]
	else:
		final_idx = trail.size() - 1
		final_pos = trail[final_idx]
	if final_pos == Vector2i(-1, -1): return
	var final_form: Array = ftl[final_idx] if final_idx < ftl.size() else [final_pos]
	if u.eliminated:
		for fh in final_form:
			var center = hex_to_pixel(fh.x, fh.y)
			var r = 8.0 * cam_zoom
			draw_line(center + Vector2(-r, -r), center + Vector2(r, r),
				Color(0.9, 0.2, 0.2, 0.35 if is_ghost else 0.7), 2.5)
			draw_line(center + Vector2(r, -r), center + Vector2(-r, r),
				Color(0.9, 0.2, 0.2, 0.35 if is_ghost else 0.7), 2.5)
	else:
		for fh in final_form:
			var center = hex_to_pixel(fh.x, fh.y)
			_draw_unit_token(center, u.player, u.models, u.unit_type, is_ghost, alpha)

func _draw_single_timeline(uid: int, final_units: Array, timelines: Array, formations_tl: Array, combat_ev: Array, display_turn: int, is_preview_unit: bool, _snail_trail: bool = false):
	var u = final_units[uid]
	var trail: Array = timelines[uid]
	var ftl: Array = formations_tl[uid] if uid < formations_tl.size() else []
	var alive_until = u.elim_turn if u.eliminated else TURNS
	var max_ti = mini(alive_until + 1, trail.size() - 1)
	var base = C_P1 if u.player == 1 else C_P2
	var highlight_a = 0.25 if is_preview_unit else 0.30
	# Path hex highlights — highlight all formation hexes per turn
	for ti in (max_ti + 1):
		var pos = trail[ti]
		if pos == Vector2i(-1, -1): continue
		var form: Array = ftl[ti] if ti < ftl.size() else [pos]
		for fh in form:
			var hc = hex_to_pixel(fh.x, fh.y)
			var corners = hex_corners(hc)
			draw_colored_polygon(corners, Color(base.r, base.g, base.b, highlight_a))
	# Snail trail ribbon (uses anchor positions)
	var ribbon_w = HEX_SIZE * (0.6 if is_preview_unit else 0.7) * cam_zoom
	var ribbon_a = 0.50 if is_preview_unit else 0.6
	var is_disrupted = u.disrupted and u.disrupted_turn >= 0
	var disrupt_ti = (u.disrupted_turn + 1) if is_disrupted else -1
	for ti in max_ti:
		var from_pos = trail[ti]
		var to_pos = trail[ti + 1]
		if from_pos == to_pos: continue
		if from_pos == Vector2i(-1, -1) or to_pos == Vector2i(-1, -1): continue
		if is_disrupted and ti == disrupt_ti: continue  # skip ribbon at disruption
		var pa = hex_to_pixel(from_pos.x, from_pos.y)
		var pb = hex_to_pixel(to_pos.x, to_pos.y)
		var dir = (pb - pa).normalized()
		var perp = Vector2(-dir.y, dir.x) * ribbon_w
		var quad = PackedVector2Array([pa + perp, pa - perp, pb - perp, pb + perp])
		draw_colored_polygon(quad, Color(base.r, base.g, base.b, ribbon_a))
	# Disruption break visual
	if is_disrupted and u.disrupted_from != Vector2i(-1, -1) and disrupt_ti < trail.size():
		var yank_pos = trail[disrupt_ti] if disrupt_ti < trail.size() else Vector2i(u.col, u.row)
		if yank_pos != Vector2i(-1, -1):
			var pa = hex_to_pixel(u.disrupted_from.x, u.disrupted_from.y)
			var pb = hex_to_pixel(yank_pos.x, yank_pos.y)
			var disrupt_color = Color(0.8, 0.2, 1.0, 0.9)
			var seg_len = 6.0 * cam_zoom
			var total = pa.distance_to(pb)
			if total > 0:
				var ddir = (pb - pa).normalized()
				var perp2 = Vector2(-ddir.y, ddir.x)
				var steps = int(total / seg_len)
				for si in maxi(steps, 1):
					var t0 = float(si) / float(maxi(steps, 1))
					var t1 = float(si + 1) / float(maxi(steps, 1))
					var p0 = pa.lerp(pb, t0) + perp2 * (seg_len * (0.5 if si % 2 == 0 else -0.5))
					var p1 = pa.lerp(pb, t1) + perp2 * (seg_len * (0.5 if (si + 1) % 2 == 0 else -0.5))
					draw_line(p0, p1, disrupt_color, 2.5 * cam_zoom)
			var r2 = 10.0 * cam_zoom
			draw_line(pa + Vector2(-r2, -r2), pa + Vector2(r2, r2), disrupt_color, 2.5 * cam_zoom)
			draw_line(pa + Vector2(r2, -r2), pa + Vector2(-r2, r2), disrupt_color, 2.5 * cam_zoom)
	# Snail trail ghost tokens with caterpillar taper — draw on all formation hexes
	var worm_alpha = 0.75 if is_preview_unit else 0.85
	for ti in (max_ti + 1):
		var pos = trail[ti]
		if pos == Vector2i(-1, -1): continue
		var form: Array = ftl[ti] if ti < ftl.size() else [pos]
		if ti != display_turn:
			for fh in form:
				var center = hex_to_pixel(fh.x, fh.y)
				_draw_unit_token(center, u.player, u.models, u.unit_type, true, worm_alpha, ti)
		if ti < max_ti:
			var next_pos = trail[ti + 1]
			if next_pos == Vector2i(-1, -1) or next_pos == pos: continue
			# Interpolation taper uses anchor-to-anchor
			var center = hex_to_pixel(pos.x, pos.y)
			var next_center = hex_to_pixel(next_pos.x, next_pos.y)
			for interp in [0.17, 0.33, 0.50, 0.67, 0.83]:
				var mid = center.lerp(next_center, interp)
				var interp_frame = ti if interp < 0.5 else ti + 1
				_draw_unit_token_scaled(mid, u.player, u.models, u.unit_type, worm_alpha * 0.85, 0.7, interp_frame)
	# Current-turn token — draw at all formation hexes
	var cur_idx = mini(display_turn, trail.size() - 1)
	if trail[cur_idx] != Vector2i(-1, -1):
		var cur_form: Array = ftl[cur_idx] if cur_idx < ftl.size() else [trail[cur_idx]]
		if u.eliminated and u.elim_turn <= display_turn - 1:
			for fh in cur_form:
				var center = hex_to_pixel(fh.x, fh.y)
				var r = 8.0 * cam_zoom
				draw_line(center + Vector2(-r, -r), center + Vector2(r, r),
					Color(0.9, 0.2, 0.2, 0.7), 2.5)
				draw_line(center + Vector2(r, -r), center + Vector2(-r, r),
					Color(0.9, 0.2, 0.2, 0.7), 2.5)
		else:
			for fh in cur_form:
				var center = hex_to_pixel(fh.x, fh.y)
				_draw_unit_token(center, u.player, u.models, u.unit_type, false, 1.0)

func _draw_sim(sim: Dictionary, is_preview: bool):
	var timelines   : Array = sim.get("timelines", [])
	var formations_tl : Array = sim.get("formations_timeline", [])
	var final_units : Array = sim.get("units", [])
	var combat_ev   : Array = sim.get("combat", [])

	var display_turn = mini(anim_turn, TURNS)
	var effective_mode = view_mode if phase == Phase.DEPLOY else ViewMode.FULL
	# Animation scan only in CLEAN mode; other modes show static snail trails
	var show_anim_scan = (effective_mode == ViewMode.CLEAN)

	# During preview, determine which units are affected by the placement
	var changed: Dictionary = preview_diff.get("changed_uids", {}) if is_preview else {}

	# Fall back to CLEAN when CHANGED has no active preview
	if effective_mode == ViewMode.CHANGED and not is_preview:
		effective_mode = ViewMode.CLEAN

	# Which units get snail trails depends on view mode
	var show_timeline_for_uid := func(uid: int) -> bool:
		if effective_mode == ViewMode.FULL:
			return true  # all units
		if effective_mode == ViewMode.CHANGED:
			# Only preview unit gets team-colored trail; changed units use red/green diff only
			return is_preview and uid == timelines.size() - 1
		# CLEAN mode: only preview unit gets trail, others at final position
		if not is_preview: return false
		return uid == timelines.size() - 1

	# --- Hover trail highlight: bright glow on hovered unit's entire trail ---
	if hover_trail_uid >= 0 and hover_trail_uid < formations_tl.size():
		var hu = final_units[hover_trail_uid]
		var h_ftl: Array = formations_tl[hover_trail_uid]
		var h_trail: Array = timelines[hover_trail_uid]
		var h_alive = hu.elim_turn if hu.eliminated else TURNS
		var h_max = mini(h_alive + 1, h_ftl.size() - 1)
		var h_color = C_P1 if hu.player == 1 else C_P2
		var glow = Color(h_color.r, h_color.g, h_color.b, 0.85)
		var outline_col = Color(1, 1, 1, 0.9)
		# Glow on all formation hexes — double pass for stronger effect
		for ti in (h_max + 1):
			var form: Array = h_ftl[ti] if ti < h_ftl.size() else []
			for fh in form:
				if fh == Vector2i(-1, -1): continue
				var hc = hex_to_pixel(fh.x, fh.y)
				var corners = hex_corners(hc)
				draw_colored_polygon(corners, glow)
				draw_polyline(corners + PackedVector2Array([corners[0]]), outline_col, 4.0)
		# Bright ribbon along trail
		var h_ribbon_w = HEX_SIZE * 1.1 * cam_zoom
		for ti in h_max:
			var from_pos = h_trail[ti]
			var to_pos = h_trail[ti + 1]
			if from_pos == to_pos: continue
			if from_pos == Vector2i(-1, -1) or to_pos == Vector2i(-1, -1): continue
			var pa = hex_to_pixel(from_pos.x, from_pos.y)
			var pb = hex_to_pixel(to_pos.x, to_pos.y)
			var dir = (pb - pa).normalized()
			var perp = Vector2(-dir.y, dir.x) * h_ribbon_w
			var quad = PackedVector2Array([pa + perp, pa - perp, pb - perp, pb + perp])
			draw_colored_polygon(quad, Color(h_color.r, h_color.g, h_color.b, 0.7))

	# --- 0) Changed trail crossfade (CHANGED mode preview only) ---
	# Hold each phase 1.5s, quick 0.5s smoothstep crossfade between them (4s total cycle)
	if is_preview and effective_mode == ViewMode.CHANGED and not changed.is_empty() and not confirmed_sim.is_empty():
		var cycle = fmod(_diff_flash_time, 4.0)
		var old_blend: float
		if cycle < 1.5:
			old_blend = 1.0
		elif cycle < 2.0:
			var t = (cycle - 1.5) / 0.5
			old_blend = 1.0 - t * t * (3.0 - 2.0 * t)
		elif cycle < 3.5:
			old_blend = 0.0
		else:
			var t = (cycle - 3.5) / 0.5
			old_blend = t * t * (3.0 - 2.0 * t)
		var new_blend = 1.0 - old_blend
		var old_timelines: Array = confirmed_sim.get("timelines", [])
		var old_units: Array = confirmed_sim.get("units", [])
		var old_col = Color(0.75, 0.55, 0.95)  # pale purple
		var new_col = Color(1.0, 0.95, 0.45)   # pale yellow
		for uid in changed:
			# Skip the preview unit itself (it has no "old" path)
			if uid >= old_timelines.size(): continue
			# OLD path (pale purple) — what would have happened without this unit
			if old_blend > 0.02:
				var ou = old_units[uid]
				var old_trail: Array = old_timelines[uid]
				var alive_until = ou.elim_turn if ou.eliminated else TURNS
				var max_ti = mini(alive_until + 1, old_trail.size() - 1)
				for ti in max_ti:
					var from_pos = old_trail[ti]
					var to_pos = old_trail[ti + 1]
					if from_pos == to_pos: continue
					if from_pos == Vector2i(-1, -1) or to_pos == Vector2i(-1, -1): continue
					var pa = hex_to_pixel(from_pos.x, from_pos.y)
					var pb = hex_to_pixel(to_pos.x, to_pos.y)
					var dir = (pb - pa).normalized()
					var perp = Vector2(-dir.y, dir.x) * HEX_SIZE * 0.9 * cam_zoom
					var quad = PackedVector2Array([pa + perp, pa - perp, pb - perp, pb + perp])
					draw_colored_polygon(quad, Color(old_col.r, old_col.g, old_col.b, 0.80 * old_blend))
				var old_ftl: Array = confirmed_sim.get("formations_timeline", [])
				if uid < old_ftl.size():
					for ti in (max_ti + 1):
						var form: Array = old_ftl[uid][ti] if ti < old_ftl[uid].size() else []
						for fh in form:
							if fh == Vector2i(-1, -1): continue
							var hc = hex_to_pixel(fh.x, fh.y)
							var corners = hex_corners(hc)
							draw_colored_polygon(corners, Color(old_col.r, old_col.g, old_col.b, 0.55 * old_blend))
							draw_polyline(corners + PackedVector2Array([corners[0]]), Color(old_col.r, old_col.g, old_col.b, 0.80 * old_blend), 2.0)
			# NEW path (pale yellow) — what will happen with this unit
			if new_blend > 0.02 and uid < timelines.size():
				var new_trail: Array = timelines[uid]
				var nu = final_units[uid]
				var new_alive = nu.elim_turn if nu.eliminated else TURNS
				var new_max = mini(new_alive + 1, new_trail.size() - 1)
				for ti in new_max:
					var from_pos = new_trail[ti]
					var to_pos = new_trail[ti + 1]
					if from_pos == to_pos: continue
					if from_pos == Vector2i(-1, -1) or to_pos == Vector2i(-1, -1): continue
					var pa = hex_to_pixel(from_pos.x, from_pos.y)
					var pb = hex_to_pixel(to_pos.x, to_pos.y)
					var dir = (pb - pa).normalized()
					var perp = Vector2(-dir.y, dir.x) * HEX_SIZE * 0.9 * cam_zoom
					var quad = PackedVector2Array([pa + perp, pa - perp, pb - perp, pb + perp])
					draw_colored_polygon(quad, Color(new_col.r, new_col.g, new_col.b, 0.80 * new_blend))
				if uid < formations_tl.size():
					for ti in (new_max + 1):
						var form: Array = formations_tl[uid][ti] if ti < formations_tl[uid].size() else []
						for fh in form:
							if fh == Vector2i(-1, -1): continue
							var hc = hex_to_pixel(fh.x, fh.y)
							var corners = hex_corners(hc)
							draw_colored_polygon(corners, Color(new_col.r, new_col.g, new_col.b, 0.55 * new_blend))
							draw_polyline(corners + PackedVector2Array([corners[0]]), Color(new_col.r, new_col.g, new_col.b, 0.80 * new_blend), 2.0)
		# Phase label tooltip — "WITHOUT" / "WITH UNIT" follows cursor
		var cw_font = ThemeDB.fallback_font
		var cw_fs = 15
		var cw_pad = 8
		var cw_text = ""
		var cw_col = Color.WHITE
		var cw_a = 0.0
		if old_blend >= new_blend:
			cw_a = clampf(old_blend * 1.5, 0.0, 1.0)
			cw_text = "WITHOUT"
			cw_col = old_col
		else:
			cw_a = clampf(new_blend * 1.5, 0.0, 1.0)
			cw_text = "WITH UNIT"
			cw_col = new_col
		if cw_a > 0.05:
			var cw_tw = cw_font.get_string_size(cw_text, HORIZONTAL_ALIGNMENT_LEFT, -1, cw_fs).x + cw_pad * 2
			var cw_th = 20 + cw_pad * 2
			var cw_vp = get_viewport_rect().size
			var cw_x = _mouse_pos.x + 20
			var cw_y = _mouse_pos.y - cw_th - 45
			if cw_x + cw_tw > cw_vp.x - 10:
				cw_x = _mouse_pos.x - cw_tw - 10
			if cw_y < 10:
				cw_y = _mouse_pos.y + 60
			draw_rect(Rect2(cw_x, cw_y, cw_tw, cw_th), Color(0.05, 0.05, 0.1, 0.85 * cw_a))
			draw_rect(Rect2(cw_x, cw_y, cw_tw, cw_th), Color(cw_col.r, cw_col.g, cw_col.b, 0.6 * cw_a), false, 2.0)
			draw_string(cw_font, Vector2(cw_x + cw_pad, cw_y + cw_pad + 13), cw_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, cw_fs, Color(cw_col.r, cw_col.g, cw_col.b, cw_a))

	# --- 0b) Draw units without timelines at their final position ---
	var fog_mode = (effective_mode == ViewMode.CHANGED and is_preview)
	for uid in timelines.size():
		if show_timeline_for_uid.call(uid): continue
		_draw_unit_final(uid, final_units, timelines, formations_tl, fog_mode, 0.20 if fog_mode else 1.0)

	# --- 1) Highlight path hexes for each unit (all formation hexes) ---
	for uid in timelines.size():
		if not show_timeline_for_uid.call(uid): continue
		var u    = final_units[uid]
		var trail: Array = timelines[uid]
		var ftl: Array = formations_tl[uid] if uid < formations_tl.size() else []
		var alive_until = u.elim_turn if u.eliminated else TURNS
		var max_ti = mini(alive_until + 1, trail.size() - 1)
		var is_preview_unit = (is_preview and uid == timelines.size() - 1)
		var base = C_P1 if u.player == 1 else C_P2
		var highlight_a = 0.25 if is_preview_unit else 0.30
		if effective_mode == ViewMode.CHANGED: highlight_a = 0.50

		for ti in (max_ti + 1):
			var pos = trail[ti]
			if pos == Vector2i(-1, -1): continue
			var form: Array = ftl[ti] if ti < ftl.size() else [pos]
			for fh in form:
				var hc = hex_to_pixel(fh.x, fh.y)
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
		if effective_mode == ViewMode.CHANGED:
			ribbon_a = 0.85
			ribbon_w = HEX_SIZE * 0.85 * cam_zoom
		# Check if this unit was disrupted (for visual break in ribbon)
		var is_disrupted = u.disrupted and u.disrupted_turn >= 0
		var disrupt_ti = (u.disrupted_turn + 1) if is_disrupted else -1  # timeline index of disruption
		for ti in max_ti:
			var from_pos = trail[ti]
			var to_pos   = trail[ti + 1]
			if from_pos == to_pos: continue
			if from_pos == Vector2i(-1, -1) or to_pos == Vector2i(-1, -1): continue
			# Skip ribbon at disruption point — draw break instead
			if is_disrupted and ti == disrupt_ti:
				continue
			var pa = hex_to_pixel(from_pos.x, from_pos.y)
			var pb = hex_to_pixel(to_pos.x, to_pos.y)
			var dir = (pb - pa).normalized()
			var perp = Vector2(-dir.y, dir.x) * ribbon_w
			var quad = PackedVector2Array([
				pa + perp, pa - perp, pb - perp, pb + perp
			])
			draw_colored_polygon(quad, Color(base.r, base.g, base.b, ribbon_a))

		# Draw disruption break: dashed line from old position to yanked position
		if is_disrupted and u.disrupted_from != Vector2i(-1, -1) and disrupt_ti < trail.size():
			var yank_pos = trail[disrupt_ti] if disrupt_ti < trail.size() else Vector2i(u.col, u.row)
			if yank_pos != Vector2i(-1, -1):
				var pa = hex_to_pixel(u.disrupted_from.x, u.disrupted_from.y)
				var pb = hex_to_pixel(yank_pos.x, yank_pos.y)
				# Draw jagged disruption line (purple/magenta for temporal effect)
				var disrupt_color = Color(0.8, 0.2, 1.0, 0.9)
				var seg_len = 6.0 * cam_zoom
				var total = pa.distance_to(pb)
				if total > 0:
					var dir = (pb - pa).normalized()
					var perp = Vector2(-dir.y, dir.x)
					var steps = int(total / seg_len)
					for si in maxi(steps, 1):
						var t0 = float(si) / float(maxi(steps, 1))
						var t1 = float(si + 1) / float(maxi(steps, 1))
						var p0 = pa.lerp(pb, t0) + perp * (seg_len * (0.5 if si % 2 == 0 else -0.5))
						var p1 = pa.lerp(pb, t1) + perp * (seg_len * (0.5 if (si + 1) % 2 == 0 else -0.5))
						draw_line(p0, p1, disrupt_color, 2.5 * cam_zoom)
				# Draw X marks at the disrupted-from position (old fate severed)
				var r = 10.0 * cam_zoom
				draw_line(pa + Vector2(-r, -r), pa + Vector2(r, r), disrupt_color, 2.5 * cam_zoom)
				draw_line(pa + Vector2(r, -r), pa + Vector2(-r, r), disrupt_color, 2.5 * cam_zoom)

	# --- 3) Ghost tokens at each turn position (all formation hexes) ---
	for uid in timelines.size():
		if not show_timeline_for_uid.call(uid): continue
		var u    = final_units[uid]
		var trail: Array = timelines[uid]
		var ftl: Array = formations_tl[uid] if uid < formations_tl.size() else []
		var alive_until = u.elim_turn if u.eliminated else TURNS
		var max_ti = mini(alive_until + 1, trail.size() - 1)
		var is_preview_unit = (is_preview and uid == timelines.size() - 1)

		# Snail trail: each turn gets a distinct sprite pose, dense interpolation between
		var worm_alpha = 0.75 if is_preview_unit else 0.85
		if effective_mode == ViewMode.CHANGED: worm_alpha = 0.95
		for ti in (max_ti + 1):
			var pos = trail[ti]
			if pos == Vector2i(-1, -1): continue
			if show_anim_scan and ti == display_turn: continue  # current-turn token drawn in section 5
			# Full-size sprite at each formation hex
			var form: Array = ftl[ti] if ti < ftl.size() else [pos]
			for fh in form:
				var center = hex_to_pixel(fh.x, fh.y)
				_draw_unit_token(center, u.player, u.models, u.unit_type, true, worm_alpha, ti)
			# Caterpillar taper: smaller sprites between anchor stops
			if ti < max_ti:
				var next_pos = trail[ti + 1]
				if next_pos == Vector2i(-1, -1) or next_pos == pos: continue
				var anchor_center = hex_to_pixel(pos.x, pos.y)
				var next_center = hex_to_pixel(next_pos.x, next_pos.y)
				for interp in [0.17, 0.33, 0.50, 0.67, 0.83]:
					var mid = anchor_center.lerp(next_center, interp)
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

		# --- 5) Current-turn tokens on top (at formation hexes) ---
		for uid in timelines.size():
			if not show_timeline_for_uid.call(uid): continue
			var trail: Array = timelines[uid]
			var ftl: Array = formations_tl[uid] if uid < formations_tl.size() else []
			var u     = final_units[uid]
			var cur_idx  = mini(display_turn, trail.size() - 1)

			if trail[cur_idx] == Vector2i(-1, -1): continue

			var cur_form: Array = ftl[cur_idx] if cur_idx < ftl.size() else [trail[cur_idx]]

			if u.eliminated and u.elim_turn <= display_turn - 1:
				for fh in cur_form:
					var center = hex_to_pixel(fh.x, fh.y)
					var r = 8.0 * cam_zoom
					draw_line(center + Vector2(-r, -r), center + Vector2(r, r),
						Color(0.9, 0.2, 0.2, 0.7), 2.5)
					draw_line(center + Vector2(r, -r), center + Vector2(-r, r),
						Color(0.9, 0.2, 0.2, 0.7), 2.5)
				continue
			for fh in cur_form:
				var center = hex_to_pixel(fh.x, fh.y)
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
			if hex_dist(pos.x, pos.y, OBJECTIVES[oi].x, OBJECTIVES[oi].y) <= OC_RADIUS:
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
		lines.append({"text": "Killed turn %d" % (u.elim_turn + 1), "color": Color(0.9, 0.3, 0.3)})
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
	var panel_y = 56.0 + sb_h + 10 + fate_h + 30

	var panel_h = lines.size() * line_h + pad * 2
	draw_rect(Rect2(panel_x, panel_y, panel_w, panel_h), Color(0.05, 0.05, 0.1, 0.85))
	draw_rect(Rect2(panel_x, panel_y, panel_w, panel_h), Color(0.4, 0.6, 0.3, 0.5), false, 1.5)

	var y = panel_y + pad + 14
	for entry in lines:
		draw_string(font, Vector2(panel_x + pad, y), entry.text,
			HORIZONTAL_ALIGNMENT_LEFT, panel_w - pad * 2, fs, entry.color)
		y += line_h

func _draw_trail_tooltip(sim: Dictionary):
	if hover_trail_uid < 0: return
	var final_units: Array = sim.get("units", [])
	var names: Array = sim.get("unit_names", [])
	var kills_data: Array = sim.get("unit_kills", [])
	var dmg_data: Array = sim.get("unit_dmg", [])
	var obj_data: Array = sim.get("unit_obj", [])
	var timelines_t: Array = sim.get("timelines", [])
	if hover_trail_uid >= final_units.size(): return

	var u = final_units[hover_trail_uid]
	var uname = names[hover_trail_uid] if hover_trail_uid < names.size() else "Unit"
	var utype = u.unit_type.replace("_", " ").capitalize()
	var team_col = C_P1 if u.player == 1 else C_P2
	var team_str = "Blue" if u.player == 1 else "Red"
	var stats = _get_stats(u.unit_type)

	# Build tooltip lines
	var lines: Array = []
	lines.append({"text": "%s %s (%s)" % [utype, uname, team_str], "color": team_col})

	# Survival status
	if u.eliminated:
		lines.append({"text": "Dies turn %d" % (u.elim_turn + 1), "color": Color(0.9, 0.3, 0.3)})
	else:
		var lost = stats.models - u.models
		if lost > 0:
			lines.append({"text": "Survives (%d/%d models)" % [u.models, stats.models], "color": Color(0.8, 0.8, 0.3)})
		else:
			lines.append({"text": "Survives unscathed", "color": Color(0.3, 0.9, 0.3)})

	# Damage and kills
	var dmg = dmg_data[hover_trail_uid] if hover_trail_uid < dmg_data.size() else 0
	var kills = kills_data[hover_trail_uid] if hover_trail_uid < kills_data.size() else 0
	if dmg > 0 or kills > 0:
		lines.append({"text": "%d damage, %d kills" % [dmg, kills], "color": Color(0.9, 0.6, 0.2)})

	# Objective contribution
	if hover_trail_uid < obj_data.size():
		var obj_strs: Array = []
		for oi in 3:
			var status = obj_data[hover_trail_uid][oi]
			if status == "won":
				obj_strs.append("O%d:WON" % (oi + 1))
			elif status == "yes":
				obj_strs.append("O%d:yes" % (oi + 1))
		if obj_strs.size() > 0:
			lines.append({"text": "Objectives: %s" % ", ".join(obj_strs), "color": Color(0.85, 0.85, 0.85)})

	# Disruption info
	if u.get("disrupted", false) and u.disrupted_turn >= 0:
		lines.append({"text": "Disrupted turn %d" % (u.disrupted_turn + 1), "color": Color(0.8, 0.2, 1.0)})
	if u.get("has_disrupted", false):
		lines.append({"text": "Used temporal disruption", "color": Color(0.8, 0.2, 1.0)})

	# Draw the panel near cursor
	var font = ThemeDB.fallback_font
	var vp = get_viewport_rect().size
	var fs = 15
	var line_h = 20
	var pad = 8
	var panel_w = 240.0
	var panel_h = lines.size() * line_h + pad * 2

	# Position near mouse, offset right+down, clamp to viewport
	var px = _mouse_pos.x + 20
	var py = _mouse_pos.y + 20
	if px + panel_w > vp.x - 10:
		px = _mouse_pos.x - panel_w - 10
	if py + panel_h > vp.y - 10:
		py = _mouse_pos.y - panel_h - 10

	draw_rect(Rect2(px, py, panel_w, panel_h), Color(0.05, 0.05, 0.1, 0.9))
	draw_rect(Rect2(px, py, panel_w, panel_h), Color(team_col.r, team_col.g, team_col.b, 0.6), false, 2.0)

	var ty = py + pad + 13
	for entry in lines:
		draw_string(font, Vector2(px + pad, ty), entry.text,
			HORIZONTAL_ALIGNMENT_LEFT, panel_w - pad * 2, fs, entry.color)
		ty += line_h

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
	var board_h = row_h * (TURNS + 2) + pad * 2  # header + turn rows + delta row + padding
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
	var sb_h = 31 * (TURNS + 2) + 20
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
	var formations_tl: Array = sim.get("formations_timeline", [])
	var final_units: Array = sim.get("units", [])

	# Set objective control to final state
	_obj_control = sim.get("obj_control", [0, 0, 0])

	# Draw hex grid with final objective control
	for r in ROWS:
		for c in COLS:
			_draw_tile(c, r)

	# Draw all units at their final positions (using formation data)
	for uid in timelines.size():
		_draw_unit_final(uid, final_units, timelines, formations_tl, false, 1.0)

	# Draw preview unit's full timeline on top so player sees their unit's path
	var is_preview = (not preview_sim.is_empty()) and sim == preview_sim
	if is_preview and timelines.size() > 0:
		var puid = timelines.size() - 1
		var combat_ev: Array = sim.get("combat", [])
		var display_turn = mini(anim_turn, TURNS)
		_draw_single_timeline(puid, final_units, timelines, formations_tl, combat_ev, display_turn, true)

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
		var u_snap = snap[uid] if uid < snap.size() else {}
		var is_elim = u_snap.get("eliminated", false)
		var models = u_snap.get("models", 0)
		var u = final_units[uid]
		# Use snapshot formation if available, else fall back to timeline position
		var snap_form: Array = u_snap.get("formation", [])
		if snap_form.is_empty():
			var trail: Array = timelines[uid]
			var ti = mini(replay_turn + 1, trail.size() - 1)
			var pos = trail[ti]
			if pos == Vector2i(-1, -1): continue
			snap_form = [pos]

		if is_elim:
			for fh in snap_form:
				var center = hex_to_pixel(fh.x, fh.y)
				var r = 8.0 * cam_zoom
				draw_line(center + Vector2(-r, -r), center + Vector2(r, r),
					Color(0.9, 0.2, 0.2, 0.7), 2.5)
				draw_line(center + Vector2(r, -r), center + Vector2(-r, r),
					Color(0.9, 0.2, 0.2, 0.7), 2.5)
			continue

		for fh in snap_form:
			var center = hex_to_pixel(fh.x, fh.y)
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

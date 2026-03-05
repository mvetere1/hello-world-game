extends Node2D

# ============================================================================
# RESOURCE REFERENCES  (edit .tres files in Godot Inspector to tweak gameplay)
# ============================================================================

var _grid: GridConfig = preload("res://resources/config/grid_config.tres")
var _battle: BattleConfig = preload("res://resources/config/battle_config.tres")
var _visual: VisualConfig = preload("res://resources/config/visual_config.tres")
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

# ---- colors (backed by VisualConfig resource) --------------------------------
var C_BG: Color:
	get: return _visual.color_background
var C_FIELD: Color:
	get: return _visual.color_hex_fill
var C_STROKE: Color:
	get: return _visual.color_hex_stroke
var C_P1: Color:
	get: return _visual.color_p1
var C_P2: Color:
	get: return _visual.color_p2
var C_COMBAT: Color:
	get: return _visual.color_combat
var C_BANNER: Color:
	get: return _visual.color_banner
var C_SWORD: Color:
	get: return _visual.color_sword

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
	if not is_same(sim, _state._trail_hex_cache_ref):
		_state._trail_hex_cache = _build_trail_hex_cache(sim)
		_state._trail_hex_cache_ref = sim
	return _state._trail_hex_cache.get(hex_id(hex.x, hex.y), -1)

# ============================================================================
# GAME STATE  (centralized in scripts/game_state.gd)
# ============================================================================

var _state: GameState

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
var _battle_renderer: BattleRenderer = null
var _hud_layer: CanvasLayer = null
var _top_bar: TopBar = null
var _unit_select_popup: UnitSelectPopup = null
var _ds_turn_popup: DSTurnPopup = null
var _scoreboard: Scoreboard = null
var _fate_chart: FateChart = null
var _analytics_vbox: VBoxContainer = null
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
	# GameState — centralized mutable state
	_state = GameState.new()
	add_child(_state)
	# Battle renderer — child Node2D for tile/trail/token drawing
	_battle_renderer = BattleRenderer.new()
	_battle_renderer.init(self, _state)
	_battle_renderer.z_index = -1  # draw battle layer under HUD
	add_child(_battle_renderer)
	_recalc_confirmed_sim()
	# HUD layer — separate coordinate space from world
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 10
	_hud_layer.name = "HUD"
	add_child(_hud_layer)
	# TopBar panel
	var top_bar_scene = preload("res://scenes/hud/top_bar.tscn")
	_top_bar = top_bar_scene.instantiate()
	_hud_layer.add_child(_top_bar)
	_top_bar.init(_state)
	_top_bar.replay_requested.connect(_on_replay_requested)
	_top_bar.summary_requested.connect(_on_summary_requested)
	# UnitSelectPopup
	var unit_popup_scene = preload("res://scenes/hud/unit_select_popup.tscn")
	_unit_select_popup = unit_popup_scene.instantiate()
	_hud_layer.add_child(_unit_select_popup)
	_unit_select_popup.init(_state)
	_unit_select_popup.unit_selected.connect(_on_unit_selected)
	# DSTurnPopup
	var ds_popup_scene = preload("res://scenes/hud/ds_turn_popup.tscn")
	_ds_turn_popup = ds_popup_scene.instantiate()
	_hud_layer.add_child(_ds_turn_popup)
	_ds_turn_popup.init(_state)
	_ds_turn_popup.turn_selected.connect(_on_ds_turn_selected)
	# Right-side analytics panel (VBox: scoreboard + fate chart)
	_analytics_vbox = VBoxContainer.new()
	_analytics_vbox.name = "AnalyticsPanel"
	_analytics_vbox.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_analytics_vbox.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_analytics_vbox.offset_left = -435.0
	_analytics_vbox.offset_top = 56.0
	_analytics_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_analytics_vbox.add_theme_constant_override("separation", 6)
	_hud_layer.add_child(_analytics_vbox)
	# Scoreboard
	_scoreboard = preload("res://scenes/hud/scoreboard.tscn").instantiate()
	_analytics_vbox.add_child(_scoreboard)
	_scoreboard.init(_state)
	# Fate chart
	_fate_chart = preload("res://scenes/hud/fate_chart.tscn").instantiate()
	_analytics_vbox.add_child(_fate_chart)
	_fate_chart.init(_state)
	# Redraw battle when view mode changes (from TopBar button clicks)
	_state.view_mode_changed.connect(func(_m): queue_redraw())
	queue_redraw()

# ============================================================================
# INPUT
# ============================================================================

func _input(event: InputEvent):
	# Battle summary controls
	if _state.show_summary:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_state.show_summary = false
			queue_redraw()
			return
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_state.summary_scroll = maxi(0, _state.summary_scroll - 3)
				queue_redraw()
				return
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_state.summary_scroll += 3
				queue_redraw()
				return
			if event.button_index == MOUSE_BUTTON_LEFT:
				var vp_s = get_viewport_rect().size
				var panel_w: float = 620.0
				var panel_x: float = (vp_s.x - panel_w) / 2.0
				var close_rect = Rect2(panel_x + panel_w - 44, 45, 34, 26)
				if close_rect.has_point(event.position):
					_state.show_summary = false
					queue_redraw()
					return
		if event is InputEventMouseButton or event is InputEventMouseMotion:
			return  # consume mouse events while summary is open

	# Replay mode controls
	if _state.replay_mode and event is InputEventKey and event.pressed:
		if event.keycode == KEY_RIGHT:
			_state.replay_turn = mini(_state.replay_turn + 1, TURNS - 1)
			_state.replay_changed.emit(_state.replay_turn)
			queue_redraw()
			return
		if event.keycode == KEY_LEFT:
			_state.replay_turn = maxi(_state.replay_turn - 1, 0)
			_state.replay_changed.emit(_state.replay_turn)
			queue_redraw()
			return
		if event.keycode == KEY_ESCAPE:
			_state.replay_mode = false
			queue_redraw()
			return
	if _state.replay_mode:
		return  # block all other input during replay

	# View mode switching during deployment (keys 1-4)
	if _state.phase == GameState.Phase.DEPLOY and event is InputEventKey and event.pressed:
		if event.keycode == KEY_1:
			_state.view_mode = GameState.ViewMode.CLEAN
			_state.view_mode_changed.emit(_state.view_mode)
			queue_redraw()
			return
		if event.keycode == KEY_2:
			_state.view_mode = GameState.ViewMode.CHANGED
			_state.view_mode_changed.emit(_state.view_mode)
			queue_redraw()
			return
		if event.keycode == KEY_3:
			_state.view_mode = GameState.ViewMode.FULL
			_state.view_mode_changed.emit(_state.view_mode)
			queue_redraw()
			return
		if event.keycode == KEY_4:
			_state.view_mode = GameState.ViewMode.FINAL
			_state.view_mode_changed.emit(_state.view_mode)
			queue_redraw()
			return
		if event.keycode == KEY_H:
			_state._heatmap_enabled = not _state._heatmap_enabled
			if _state._heatmap_enabled:
				_compute_deploy_heatmap()
			else:
				_state.deploy_heatmap = {}
				_state._heatmap_queue = []
			queue_redraw()
			return
		if event.keycode == KEY_L:
			_state._log_visible = not _state._log_visible
			queue_redraw()
			return
		if event.keycode == KEY_TAB:
			_state.show_analytics_ui = not _state.show_analytics_ui
			queue_redraw()
			return

	# Log panel scroll (left side, 340px wide)
	if _state._log_visible and event is InputEventMouseButton and event.pressed and event.position.x < 420:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_state.log_scroll = maxi(0, _state.log_scroll - 3)
			queue_redraw()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_state.log_scroll = mini(maxi(0, _state.log_lines.size() - 10), _state.log_scroll + 3)
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
		_state._mouse_pos = event.position
		if drag_active:
			cam_offset = cam_start + (event.position - drag_start)
			queue_redraw()
			return
		# Update hover
		var h = pixel_to_hex(event.position)
		var new_hover = h if is_valid_hex(h.x, h.y) else Vector2i(-1, -1)
		if new_hover != _state.hover_hex:
			_state.hover_hex = new_hover
			_state.hover_changed.emit(_state.hover_hex)
			# Trail hover detection: find unit whose trail is under cursor
			_state.hover_trail_uid = -1
			if new_hover != Vector2i(-1, -1) and not _state.selecting_unit and not _state.ds_selecting_turn and not _state.showing_shift_summary and not _state.show_summary:
				var active_sim = _state.preview_sim if not _state.preview_sim.is_empty() else _state.confirmed_sim
				if not active_sim.is_empty():
					_state.hover_trail_uid = _find_trail_uid_at_hex(new_hover, active_sim)
			if not _state.selecting_unit and not _state.ds_selecting_turn and not _state.showing_shift_summary and _is_deploy_hex(new_hover):
				_recalc_preview_sim()
				_state.anim_turn  = 0
				_state.anim_frac  = 0.0
				if _cursor_hand:
					Input.set_custom_mouse_cursor(_cursor_hand, Input.CURSOR_ARROW, Vector2(16, 0))
			else:
				if not _state.preview_sim.is_empty():
					_state.preview_sim = {}
					_state.preview_diff = {}
				if _cursor_nogo and _state.phase == GameState.Phase.DEPLOY and is_valid_hex(new_hover.x, new_hover.y) and not _state.selecting_unit and not _state.ds_selecting_turn:
					Input.set_custom_mouse_cursor(_cursor_nogo, Input.CURSOR_ARROW, Vector2(32, 32))
				elif _cursor_hand:
					Input.set_custom_mouse_cursor(_cursor_hand, Input.CURSOR_ARROW, Vector2(16, 0))
			queue_redraw()

	# Shift summary scroll
	if _state.showing_shift_summary and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_state.shift_summary_scroll = maxi(0, _state.shift_summary_scroll - 1)
			queue_redraw()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_state.shift_summary_scroll += 1
			queue_redraw()
			return

	# Left click handling
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Dismiss shift summary on click
		if _state.showing_shift_summary:
			_state.showing_shift_summary = false
			_state.shift_summary_diff = {}
			_state.selecting_unit = true
			if _cursor_hand:
				Input.set_custom_mouse_cursor(_cursor_hand, Input.CURSOR_ARROW, Vector2(16, 0))
			queue_redraw()
			return
		if not drag_active:
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
	if _state.phase != GameState.Phase.DEPLOY or not is_valid_hex(h.x, h.y):
		return false
	# Basic zone check first
	var in_zone := false
	if _state.deploy_unit_type == "deep_strike" and _state.ds_arrival_turn > 0:
		in_zone = _state.ds_legal_hexes.has(hex_id(h.x, h.y))
	elif _state.active_player == 1:
		in_zone = h.y >= P1_DEPLOY_ROWS_MIN and h.y <= P1_DEPLOY_ROWS_MAX and h.x >= DEPLOY_C_MIN and h.x <= DEPLOY_C_MAX
	else:
		in_zone = h.y >= P2_DEPLOY_ROWS_MIN and h.y <= P2_DEPLOY_ROWS_MAX and h.x >= DEPLOY_C_MIN and h.x <= DEPLOY_C_MAX
	if not in_zone:
		return false
	# Cannot deploy on impassable terrain
	if not _is_hex_passable(h.x, h.y):
		return false
	# Check anchor not blocked by existing formations
	if _state._deploy_blocked_cache.has(hex_id(h.x, h.y)):
		return false
	# Check that the full formation cluster fits
	var stats = _get_stats(_state.deploy_unit_type)
	var fp = _compute_footprint(_state.deploy_unit_type, stats.models)
	var cluster = compute_compact_cluster(h, fp, _state._deploy_blocked_cache)
	return cluster.size() == fp

func _handle_deploy_click(h: Vector2i):
	if _state.phase != GameState.Phase.DEPLOY or _state.selecting_unit or _state.ds_selecting_turn: return
	if not _is_deploy_hex(h): return

	# Compute the deploy formation (zone + stacking validated by _is_deploy_hex)
	var stats = _get_stats(_state.deploy_unit_type)
	var fp = _compute_footprint(_state.deploy_unit_type, stats.models)
	var formation = compute_compact_cluster(h, fp, _state._deploy_blocked_cache)
	if formation.size() < fp: return  # safety: can't fit

	var unit_data = { "player": _state.active_player, "col": h.x, "row": h.y, "unit_type": _state.deploy_unit_type, "formation": formation }
	if _state.deploy_unit_type == "deep_strike":
		unit_data["start_turn"] = _state.ds_arrival_turn

	if _state.active_player == 1:
		_state.placed_p1.append(unit_data)
	else:
		_state.placed_p2.append(unit_data)

	# Snapshot the diff and old sim before recalculating
	_state.shift_summary_diff = _state.preview_diff.duplicate(true) if not _state.preview_diff.is_empty() else {}
	_state.shift_old_sim = _state.confirmed_sim.duplicate(true) if not _state.confirmed_sim.is_empty() else {}
	var placed_unit_name = ""
	var placed_player = _state.active_player
	var placed_type = _state.deploy_unit_type

	# Reset deployment state for next turn
	_state.active_player = 2 if _state.active_player == 1 else 1
	_state.ds_selecting_turn = false
	_state.ds_arrival_turn = -1
	_state.ds_legal_hexes = {}
	_state.ds_pending_hex = Vector2i(-1, -1)
	_state.hover_hex = Vector2i(-1, -1)
	_state.deploy_heatmap = {}
	_state._heatmap_queue = []
	_recalc_confirmed_sim()
	_state.preview_sim = {}
	_state.preview_diff = {}
	_state.anim_turn  = 0
	_state.anim_frac  = 0.0

	# Get the placed unit's UID and name from the new sim
	var placed_uid = _state.placed_p1.size() - 1 if placed_player == 1 else _state.placed_p1.size() + _state.placed_p2.size() - 1
	var new_names: Array = _state.confirmed_sim.get("unit_names", [])
	if placed_uid >= 0 and placed_uid < new_names.size():
		placed_unit_name = new_names[placed_uid]
	_state.unit_placed.emit(placed_uid)

	var total_placed = _state.placed_p1.size() + _state.placed_p2.size()
	if total_placed >= UNITS_PER_SIDE * 2:
		_state.phase = GameState.Phase.DONE
		_state.phase_changed.emit(_state.phase)
		_state.selecting_unit = false
	else:
		# Show shift summary before next unit selection
		_state.selecting_unit = false
		_state.shift_summary_lines = _build_shift_summary_lines(_state.shift_summary_diff, _state.shift_old_sim, _state.confirmed_sim, placed_unit_name, placed_type, placed_player, placed_uid)
		_state.shift_summary_scroll = 0
		_state.showing_shift_summary = true
		_state.shift_summary_timer = 0.0
	queue_redraw()


func _compute_ds_legal_hexes(arrival_turn: int) -> Dictionary:
	var legal := {}
	var snapshots: Array = _state.confirmed_sim.get("unit_snapshots", [])
	var conf_units: Array = _state.confirmed_sim.get("units", [])
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
				if u_player == _state.active_player: continue
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
	var all_units: Array = _state.placed_p1.duplicate() + _state.placed_p2.duplicate()
	if all_units.is_empty():
		_state.confirmed_sim = {}
		_state.log_lines = []
		_state.sim_changed.emit()
		return
	_state.confirmed_sim = simulate(all_units)
	_state.log_lines = _state.confirmed_sim.get("combat_log", [])
	_state.log_scroll = 0
	# Write to file
	var f = FileAccess.open("user://combat_log.txt", FileAccess.WRITE)
	if f:
		for line in _state.log_lines:
			f.store_line(line)
		f.close()
	_state.sim_changed.emit()

func _recalc_preview_sim():
	if _state.phase != GameState.Phase.DEPLOY or _state.selecting_unit or _state.ds_selecting_turn or _state.showing_shift_summary: return
	if not _is_deploy_hex(_state.hover_hex):
		_state.preview_sim = {}
		_state.preview_diff = {}
		return
	# Compute preview formation using blocked cache (zone + stacking)
	var stats = _get_stats(_state.deploy_unit_type)
	var fp = _compute_footprint(_state.deploy_unit_type, stats.models)
	var formation = compute_compact_cluster(_state.hover_hex, fp, _state._deploy_blocked_cache)
	if formation.size() < fp:
		_state.preview_sim = {}
		_state.preview_diff = {}
		return
	var preview_unit = { "player": _state.active_player, "col": _state.hover_hex.x, "row": _state.hover_hex.y, "unit_type": _state.deploy_unit_type, "formation": formation }
	if _state.deploy_unit_type == "deep_strike" and _state.ds_arrival_turn > 0:
		preview_unit["start_turn"] = _state.ds_arrival_turn
	var all_units: Array = _state.placed_p1.duplicate() + _state.placed_p2.duplicate()
	all_units.append(preview_unit)
	_state.preview_sim = simulate(all_units)
	_state.preview_diff = _compute_sim_diff()
	_state.sim_changed.emit()

func _recompute_deploy_cache():
	_state._deploy_blocked_cache = {}
	var all_placed = _state.placed_p1 + _state.placed_p2
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
			_state._deploy_blocked_cache[hex_id(fh.x, fh.y)] = true
	# Block non-deploy-zone hexes for current player (regular units)
	if _state.deploy_unit_type != "deep_strike" or _state.ds_arrival_turn <= 0:
		var r_min = P1_DEPLOY_ROWS_MIN if _state.active_player == 1 else P2_DEPLOY_ROWS_MIN
		var r_max = P1_DEPLOY_ROWS_MAX if _state.active_player == 1 else P2_DEPLOY_ROWS_MAX
		for c in COLS:
			for r in ROWS:
				if is_valid_hex(c, r) and (r < r_min or r > r_max or c < DEPLOY_C_MIN or c > DEPLOY_C_MAX):
					_state._deploy_blocked_cache[hex_id(c, r)] = true
	else:
		# Deep strike: block hexes not in _state.ds_legal_hexes
		for c in COLS:
			for r in ROWS:
				if is_valid_hex(c, r) and not _state.ds_legal_hexes.has(hex_id(c, r)):
					_state._deploy_blocked_cache[hex_id(c, r)] = true

func _compute_deploy_heatmap():
	_state.deploy_heatmap = {}
	_state._heatmap_queue = []
	_state._heatmap_min = 0
	_state._heatmap_max = 0
	if _state.phase != GameState.Phase.DEPLOY or _state.selecting_unit or _state.ds_selecting_turn or not _state._heatmap_enabled:
		return
	# Cache baseline VP
	_state._heatmap_base_vp = 0
	var conf_vpt: Array = _state.confirmed_sim.get("vp_per_turn", [])
	if not conf_vpt.is_empty():
		var final_vp = conf_vpt[conf_vpt.size() - 1]
		_state._heatmap_base_vp = final_vp[0] if _state.active_player == 1 else final_vp[1]
	_state._heatmap_base_units = _state.placed_p1.duplicate() + _state.placed_p2.duplicate()
	# Build queue of hex coordinates to process (filtered by formation validity)
	var stats = _get_stats(_state.deploy_unit_type)
	var fp = _compute_footprint(_state.deploy_unit_type, stats.models)
	if _state.deploy_unit_type == "deep_strike" and _state.ds_arrival_turn > 0:
		for hid in _state.ds_legal_hexes:
			if _state._deploy_blocked_cache.has(hid): continue
			var coord = Vector2i(hid / 1000, hid % 1000)
			var cluster = compute_compact_cluster(coord, fp, _state._deploy_blocked_cache)
			if cluster.size() == fp:
				_state._heatmap_queue.append(coord)
	else:
		var r_min = P1_DEPLOY_ROWS_MIN if _state.active_player == 1 else P2_DEPLOY_ROWS_MIN
		var r_max = P1_DEPLOY_ROWS_MAX if _state.active_player == 1 else P2_DEPLOY_ROWS_MAX
		for r in range(r_min, r_max + 1):
			for c in range(DEPLOY_C_MIN, DEPLOY_C_MAX + 1):
				var hid = hex_id(c, r)
				if _state._deploy_blocked_cache.has(hid): continue
				var cluster = compute_compact_cluster(Vector2i(c, r), fp, _state._deploy_blocked_cache)
				if cluster.size() == fp:
					_state._heatmap_queue.append(Vector2i(c, r))

func _process_heatmap_batch(count: int):
	for _i in count:
		if _state._heatmap_queue.is_empty():
			return
		var coord: Vector2i = _state._heatmap_queue.pop_back()
		var c = coord.x
		var r = coord.y
		var test_unit = { "player": _state.active_player, "col": c, "row": r, "unit_type": _state.deploy_unit_type }
		if _state.deploy_unit_type == "deep_strike" and _state.ds_arrival_turn > 0:
			test_unit["start_turn"] = _state.ds_arrival_turn
		var test_units = _state._heatmap_base_units.duplicate()
		test_units.append(test_unit)
		var result = simulate(test_units)
		var result_vpt: Array = result.get("vp_per_turn", [])
		var test_vp := 0
		if not result_vpt.is_empty():
			var fvp = result_vpt[result_vpt.size() - 1]
			test_vp = fvp[0] if _state.active_player == 1 else fvp[1]
		var delta = test_vp - _state._heatmap_base_vp
		_state.deploy_heatmap[hex_id(c, r)] = delta
		if delta < _state._heatmap_min: _state._heatmap_min = delta
		if delta > _state._heatmap_max: _state._heatmap_max = delta

func _compute_sim_diff() -> Dictionary:
	if _state.confirmed_sim.is_empty() or _state.preview_sim.is_empty():
		return {}
	var conf_units: Array = _state.confirmed_sim.get("units", [])
	var prev_units: Array = _state.preview_sim.get("units", [])
	var conf_vp: Array = _state.confirmed_sim.get("vp_per_turn", [])
	var prev_vp: Array = _state.preview_sim.get("vp_per_turn", [])
	var conf_obj: Array = _state.confirmed_sim.get("obj_control", [])
	var prev_obj: Array = _state.preview_sim.get("obj_control", [])

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
	var conf_tl: Array = _state.confirmed_sim.get("timelines", [])
	var prev_tl: Array = _state.preview_sim.get("timelines", [])
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

func _on_replay_requested() -> void:
	_state.replay_mode = true
	_state.replay_turn = 0
	_state.replay_changed.emit(_state.replay_turn)
	queue_redraw()

func _on_summary_requested() -> void:
	_state.summary_lines = _generate_battle_summary()
	_state.summary_scroll = 0
	_state.show_summary = true
	queue_redraw()

func _on_unit_selected(unit_type: String) -> void:
	_state.deploy_unit_type = unit_type
	_state.selecting_unit = false
	if unit_type == "deep_strike":
		_state.ds_selecting_turn = true
	else:
		_recompute_deploy_cache()
		if _state._heatmap_enabled:
			_compute_deploy_heatmap()
	queue_redraw()

func _on_ds_turn_selected(turn: int) -> void:
	_state.ds_arrival_turn = turn
	_state.ds_selecting_turn = false
	_state.ds_legal_hexes = _compute_ds_legal_hexes(turn)
	_recompute_deploy_cache()
	if _state._heatmap_enabled:
		_compute_deploy_heatmap()
	queue_redraw()

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
	var sim = _state.confirmed_sim
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
	if _state.replay_mode:
		return  # freeze animation during replay
	# Process heatmap queue incrementally (2 sims per frame to stay responsive)
	if not _state._heatmap_queue.is_empty():
		_process_heatmap_batch(2)
	var speed = TURN_DURATION
	if _state.phase == GameState.Phase.DEPLOY and _state.view_mode == GameState.ViewMode.FULL:
		speed = _visual.full_mode_speed
	_state.anim_frac += delta / speed
	if _state.anim_frac >= 1.0:
		_state.anim_frac -= 1.0
		_state.anim_turn = (_state.anim_turn + 1) % (TURNS + 1)
	_state._diff_flash_time += delta
	if _state.showing_shift_summary:
		_state.shift_summary_timer += delta
	# Sync terrain tilemap with custom camera
	if _terrain_map:
		_terrain_map.position = cam_offset
		_terrain_map.scale = Vector2(cam_zoom, cam_zoom)

	# Update objective control state (moved from _draw for purity)
	if _state.replay_mode:
		var sim = _state.confirmed_sim
		if not sim.is_empty():
			var obj_hist: Array = sim.get("obj_ctrl_history", [])
			if _state.replay_turn < obj_hist.size():
				_state._obj_control = obj_hist[_state.replay_turn]
			else:
				_state._obj_control = sim.get("obj_control", [0, 0, 0])
	elif _state.phase == GameState.Phase.DEPLOY and _state.view_mode == GameState.ViewMode.FINAL:
		var use_preview = (not _state.preview_sim.is_empty())
		var draw_sim = _state.preview_sim if use_preview else _state.confirmed_sim
		if not draw_sim.is_empty():
			_state._obj_control = draw_sim.get("obj_control", [0, 0, 0])
	else:
		var use_preview = (not _state.preview_sim.is_empty()) and (_state.phase == GameState.Phase.DEPLOY)
		var draw_sim = _state.preview_sim if use_preview else _state.confirmed_sim
		_state._obj_control = _compute_obj_control(draw_sim)

	queue_redraw()   # every frame for smooth interpolation
	if _battle_renderer:
		_battle_renderer.queue_redraw()

# ============================================================================
# DRAWING
# ============================================================================

func _draw():
	# Battle drawing is handled by BattleRenderer (child Node2D at z_index=-1).
	# This function draws HUD overlays on top.

	if _state.replay_mode:
		return  # BattleRenderer handles replay drawing including replay HUD

	var use_preview = (not _state.preview_sim.is_empty()) and (_state.phase == GameState.Phase.DEPLOY)
	var draw_sim    = _state.preview_sim if use_preview else _state.confirmed_sim
	var vp = get_viewport_rect().size

	# FINAL mode: BattleRenderer draws battle, we draw HUD on top
	if _state.phase == GameState.Phase.DEPLOY and _state.view_mode == GameState.ViewMode.FINAL:
		_draw_hud()
		if _state.show_analytics_ui:
			if _state._log_visible: _draw_combat_log()
			if use_preview:
				_draw_preview_narrative(draw_sim)
			if _state.hover_trail_uid >= 0 and not _state.selecting_unit and not _state.ds_selecting_turn:
				_draw_trail_tooltip(draw_sim)
		# "Change view" cursor tooltip in FINAL mode
		if not _state.preview_sim.is_empty() and not _state.selecting_unit and not _state.ds_selecting_turn:
			var vp_f = get_viewport_rect().size
			var vhf_font = ThemeDB.fallback_font
			var vhf_fs = 14
			var vhf_pad = 6
			var vhf_prefix = "Change view:  "
			var vhf_nums = "1  2  3  4"
			var vhf_tw = vhf_font.get_string_size(vhf_prefix + vhf_nums, HORIZONTAL_ALIGNMENT_LEFT, -1, vhf_fs).x + vhf_pad * 2
			var vhf_th = 18 + vhf_pad * 2
			var vhf_x = _state._mouse_pos.x + 20
			var vhf_y = _state._mouse_pos.y - vhf_th - 10
			if vhf_x + vhf_tw > vp_f.x - 10:
				vhf_x = _state._mouse_pos.x - vhf_tw - 10
			if vhf_y < 10:
				vhf_y = _state._mouse_pos.y + 30
			draw_rect(Rect2(vhf_x, vhf_y, vhf_tw, vhf_th), Color(0.05, 0.05, 0.1, 0.8))
			draw_rect(Rect2(vhf_x, vhf_y, vhf_tw, vhf_th), Color(0.5, 0.5, 0.5, 0.4), false, 1.5)
			var vhf_cx = vhf_x + vhf_pad
			var vhf_cy = vhf_y + vhf_pad + 12
			draw_string(vhf_font, Vector2(vhf_cx, vhf_cy), vhf_prefix,
				HORIZONTAL_ALIGNMENT_LEFT, -1, vhf_fs, Color(0.6, 0.6, 0.6))
			vhf_cx += vhf_font.get_string_size(vhf_prefix, HORIZONTAL_ALIGNMENT_LEFT, -1, vhf_fs).x
			for vi in 4:
				var vnum = str(vi + 1)
				var vnum_col = Color(1.0, 0.9, 0.3) if vi == _state.view_mode else Color(0.5, 0.5, 0.5)
				draw_string(vhf_font, Vector2(vhf_cx, vhf_cy), vnum,
					HORIZONTAL_ALIGNMENT_LEFT, -1, vhf_fs, vnum_col)
				var vnum_spacing = vnum + ("  " if vi < 3 else "")
				vhf_cx += vhf_font.get_string_size(vnum_spacing, HORIZONTAL_ALIGNMENT_LEFT, -1, vhf_fs).x
		return

	# Normal mode: BattleRenderer draws tiles + sim, we draw HUD on top
	_draw_hud()
	if _state.show_analytics_ui:
		_draw_combat_log()
		if use_preview:
			_draw_preview_narrative(draw_sim)

		# Trail hover tooltip (works in both DEPLOY and DONE phases)
		if _state.hover_trail_uid >= 0 and not _state.selecting_unit and not _state.ds_selecting_turn and not _state.showing_shift_summary and not _state.show_summary:
			_draw_trail_tooltip(draw_sim)

	# "Change view" cursor tooltip during deploy with active preview
	if _state.phase == GameState.Phase.DEPLOY and not _state.preview_sim.is_empty() and not _state.selecting_unit and not _state.ds_selecting_turn and not _state.showing_shift_summary and not _state.show_summary:
		var vh_font = ThemeDB.fallback_font
		var vh_fs = 14
		var vh_pad = 6
		var vh_prefix = "Change view:  "
		var vh_nums = "1  2  3  4"
		var vh_tw = vh_font.get_string_size(vh_prefix + vh_nums, HORIZONTAL_ALIGNMENT_LEFT, -1, vh_fs).x + vh_pad * 2
		var vh_th = 18 + vh_pad * 2
		var vh_x = _state._mouse_pos.x + 20
		var vh_y = _state._mouse_pos.y - vh_th - 10
		if vh_x + vh_tw > vp.x - 10:
			vh_x = _state._mouse_pos.x - vh_tw - 10
		if vh_y < 10:
			vh_y = _state._mouse_pos.y + 30
		draw_rect(Rect2(vh_x, vh_y, vh_tw, vh_th), Color(0.05, 0.05, 0.1, 0.8))
		draw_rect(Rect2(vh_x, vh_y, vh_tw, vh_th), Color(0.5, 0.5, 0.5, 0.4), false, 1.5)
		var vh_cx = vh_x + vh_pad
		var vh_cy = vh_y + vh_pad + 12
		draw_string(vh_font, Vector2(vh_cx, vh_cy), vh_prefix,
			HORIZONTAL_ALIGNMENT_LEFT, -1, vh_fs, Color(0.6, 0.6, 0.6))
		vh_cx += vh_font.get_string_size(vh_prefix, HORIZONTAL_ALIGNMENT_LEFT, -1, vh_fs).x
		for vi in 4:
			var vnum = str(vi + 1)
			var vnum_col = Color(1.0, 0.9, 0.3) if vi == _state.view_mode else Color(0.5, 0.5, 0.5)
			draw_string(vh_font, Vector2(vh_cx, vh_cy), vnum,
				HORIZONTAL_ALIGNMENT_LEFT, -1, vh_fs, vnum_col)
			var vnum_spacing = vnum + ("  " if vi < 3 else "")
			vh_cx += vh_font.get_string_size(vnum_spacing, HORIZONTAL_ALIGNMENT_LEFT, -1, vh_fs).x

	# Shift summary bar at bottom
	if _state.showing_shift_summary and not _state.shift_summary_lines.is_empty():
		_draw_shift_summary()

	# Overlay popups (drawn last, on top)
	if _state.show_summary:
		_draw_battle_summary()

func _draw_shift_summary():
	var vp_size = get_viewport_rect().size
	var font = ThemeDB.fallback_font
	var line_h = 22.0
	var font_size = 15
	var title_size = 20
	var pad = 15.0
	var total_lines = _state.shift_summary_lines.size()
	var max_visible_lines = 12
	var visible_lines = mini(total_lines, max_visible_lines)
	# Box height: title + visible lines + click prompt
	var box_h = 30.0 + visible_lines * line_h + 20.0 + pad
	var box_w = min(vp_size.x * 0.85, 1200.0)
	var box_x = (vp_size.x - box_w) * 0.5
	var box_y = vp_size.y * 0.7 - box_h * 0.5
	# Clamp scroll
	var max_scroll = maxi(0, total_lines - max_visible_lines)
	_state.shift_summary_scroll = clampi(_state.shift_summary_scroll, 0, max_scroll)
	# Dark background with border
	draw_rect(Rect2(box_x - 2, box_y - 2, box_w + 4, box_h + 4), Color(0.8, 0.7, 0.3, 0.9))
	draw_rect(Rect2(box_x, box_y, box_w, box_h), Color(0.12, 0.12, 0.15, 0.95))
	# Title
	draw_string(font, Vector2(box_x + pad, box_y + 26), "TIMELINE SHIFTED",
		HORIZONTAL_ALIGNMENT_LEFT, box_w - pad * 2, title_size, Color(1, 0.9, 0.4, 1.0))
	# Colored text lines (scrollable)
	var y_cursor = box_y + 30.0 + line_h
	for li in visible_lines:
		var line_idx = li + _state.shift_summary_scroll
		if line_idx >= total_lines: break
		var line = _state.shift_summary_lines[line_idx]
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
		var thumb_y = bar_top + (bar_h - thumb_h) * float(_state.shift_summary_scroll) / float(max_scroll)
		draw_rect(Rect2(bar_x, thumb_y, 5, thumb_h), Color(0.7, 0.7, 0.7, 0.7))
	# Click prompt
	draw_string(font, Vector2(box_x + pad, y_cursor + 4), "(click to continue)",
		HORIZONTAL_ALIGNMENT_LEFT, box_w - pad * 2, 13, Color(0.6, 0.6, 0.6, 0.8))
	# Draw fate icons on the map with swell animation
	if not _state.shift_summary_diff.is_empty() and not _state.confirmed_sim.is_empty():
		var fate_changes: Array = _state.shift_summary_diff.get("fate_changes", [])
		var timelines_s: Array = _state.confirmed_sim.get("timelines", [])
		var units_s: Array = _state.confirmed_sim.get("units", [])
		# Swell: pulse from 1.0 to 1.0+amplitude and back
		var swell = 1.0 + _visual.shift_pulse_amplitude * sin(_state.shift_summary_timer * TAU / _visual.shift_pulse_period)
		var icon_size = HEX_SIZE * _visual.fate_icon_scale * cam_zoom * swell
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

func _draw_hud():
	pass  # Now handled by TopBar Control node (CanvasLayer)

func _generate_preview_narrative(sim: Dictionary) -> Array:
	if sim.is_empty() or _state.preview_sim.is_empty():
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
	var sd: Array = _state.preview_diff.get("score_delta", [])
	if sd.size() >= 2:
		var delta = sd[0] if u.player == 1 else sd[1]
		var enemy_delta = sd[1] if u.player == 1 else sd[0]
		if delta != 0 or enemy_delta != 0:
			var net = delta - enemy_delta
			var net_col = Color(0.3, 0.9, 0.3) if net > 0 else (Color(0.9, 0.3, 0.3) if net < 0 else Color(0.7, 0.7, 0.7))
			lines.append({"text": "VP impact: %+d net" % net, "color": net_col})

	return lines

func _draw_preview_narrative(sim: Dictionary):
	if _state.preview_sim.is_empty():
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
	var fate_h = 29 * (_state.preview_sim.get("units", []).size() + 1) + 10
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
	if _state.hover_trail_uid < 0: return
	var final_units: Array = sim.get("units", [])
	var names: Array = sim.get("unit_names", [])
	var kills_data: Array = sim.get("unit_kills", [])
	var dmg_data: Array = sim.get("unit_dmg", [])
	var obj_data: Array = sim.get("unit_obj", [])
	var timelines_t: Array = sim.get("timelines", [])
	if _state.hover_trail_uid >= final_units.size(): return

	var u = final_units[_state.hover_trail_uid]
	var uname = names[_state.hover_trail_uid] if _state.hover_trail_uid < names.size() else "Unit"
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
	var dmg = dmg_data[_state.hover_trail_uid] if _state.hover_trail_uid < dmg_data.size() else 0
	var kills = kills_data[_state.hover_trail_uid] if _state.hover_trail_uid < kills_data.size() else 0
	if dmg > 0 or kills > 0:
		lines.append({"text": "%d damage, %d kills" % [dmg, kills], "color": Color(0.9, 0.6, 0.2)})

	# Objective contribution
	if _state.hover_trail_uid < obj_data.size():
		var obj_strs: Array = []
		for oi in 3:
			var status = obj_data[_state.hover_trail_uid][oi]
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
	var px = _state._mouse_pos.x + 20
	var py = _state._mouse_pos.y + 20
	if px + panel_w > vp.x - 10:
		px = _state._mouse_pos.x - panel_w - 10
	if py + panel_h > vp.y - 10:
		py = _state._mouse_pos.y - panel_h - 10

	draw_rect(Rect2(px, py, panel_w, panel_h), Color(0.05, 0.05, 0.1, 0.9))
	draw_rect(Rect2(px, py, panel_w, panel_h), Color(team_col.r, team_col.g, team_col.b, 0.6), false, 2.0)

	var ty = py + pad + 13
	for entry in lines:
		draw_string(font, Vector2(px + pad, ty), entry.text,
			HORIZONTAL_ALIGNMENT_LEFT, panel_w - pad * 2, fs, entry.color)
		ty += line_h

func _draw_combat_log():
	if _state.log_lines.is_empty():
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
	var max_lines = mini(visible_lines - 2, _state.log_lines.size() - _state.log_scroll)
	for i in max_lines:
		var li = _state.log_scroll + i
		if li >= _state.log_lines.size(): break
		var line: String = _state.log_lines[li]
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
	if _state.log_lines.size() > visible_lines:
		var scroll_frac = float(_state.log_scroll) / float(maxi(1, _state.log_lines.size() - visible_lines))
		var bar_h = panel_h * float(visible_lines) / float(_state.log_lines.size())
		var bar_y = panel_y + scroll_frac * (panel_h - bar_h)
		draw_rect(Rect2(panel_x + panel_w - 4, bar_y, 3, bar_h), Color(0.5, 0.5, 0.5, 0.5))

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
	var max_scroll = maxi(0, _state.summary_lines.size() - visible_lines)
	_state.summary_scroll = clampi(_state.summary_scroll, 0, max_scroll)

	var y: float = content_y_start
	for i in visible_lines:
		var idx = i + _state.summary_scroll
		if idx >= _state.summary_lines.size(): break
		var entry = _state.summary_lines[idx]
		var fsize = 18 if entry.bold else 16
		draw_string(font, Vector2(content_x, y + 18), entry.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, entry.color)
		y += line_h

	# Scroll bar
	if _state.summary_lines.size() > visible_lines:
		var bar_x: float = panel_x + panel_w - 8
		var bar_total_h: float = content_h
		var thumb_h: float = maxf(20.0, bar_total_h * float(visible_lines) / float(_state.summary_lines.size()))
		var thumb_y: float = content_y_start + (bar_total_h - thumb_h) * float(_state.summary_scroll) / float(max_scroll) if max_scroll > 0 else content_y_start
		draw_rect(Rect2(bar_x, content_y_start, 4, bar_total_h), Color(0.2, 0.2, 0.2, 0.5))
		draw_rect(Rect2(bar_x, thumb_y, 4, thumb_h), Color(0.5, 0.5, 0.5, 0.7))

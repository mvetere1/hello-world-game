extends Node3D

# Grid config (matches 2D prototype)
const COLS     = 28
const ROWS     = 20
const HEX_SIZE = 1.0

const OBJECTIVES = [Vector2i(7, 10), Vector2i(14, 9), Vector2i(21, 10)]

# Colors
const C_BG = Color(0.07, 0.10, 0.18)

# Asset paths
const ASSET_BASE = "res://assets/medieval free hex/KayKit_Medieval_Hexagon_Pack_1.0_FREE/Assets/gltf/"
const TILE_PATH  = ASSET_BASE + "tiles/base/hex_grass.gltf"
const OBJ_PATH   = ASSET_BASE + "buildings/yellow/building_tower_A_yellow.gltf"

# Camera
var cam_yaw      := 0.0
var cam_pitch    := -0.55
var cam_speed    := 15.0
var mouse_captured := false
var camera: Camera3D

func _ready():
	RenderingServer.set_default_clear_color(C_BG)

	# Camera
	camera = Camera3D.new()
	add_child(camera)
	var cx = HEX_SIZE * 1.5 * (COLS / 2)
	var cz = HEX_SIZE * sqrt(3.0) * (ROWS / 2)
	camera.position = Vector3(cx, 22.0, cz + 18.0)
	camera.rotation = Vector3(cam_pitch, cam_yaw, 0)
	camera.current = true
	camera.far = 200.0

	# Light
	var light = DirectionalLight3D.new()
	add_child(light)
	light.rotation = Vector3(deg_to_rad(-55), deg_to_rad(30), 0)
	light.light_energy = 0.8

	# Environment (ambient + bg color)
	var env = Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color  = Color(0.3, 0.35, 0.45)
	env.ambient_light_energy = 0.6
	env.background_mode  = Environment.BG_COLOR
	env.background_color = C_BG
	var world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	_build_grid()

# ============================================================================
# HEX GRID — INSTANCED KAYKIT TILES
# ============================================================================

func _build_grid():
	var grass_scene = load(TILE_PATH) as PackedScene
	var water_scene = load(ASSET_BASE + "tiles/base/hex_water.gltf") as PackedScene
	var road_scene  = load(ASSET_BASE + "tiles/roads/hex_road_A.gltf") as PackedScene
	var obj_scene   = load(OBJ_PATH) as PackedScene

	var decos: Array[PackedScene] = [
		load(ASSET_BASE + "decoration/nature/tree_single_A.gltf"),
		load(ASSET_BASE + "decoration/nature/tree_single_B.gltf"),
		load(ASSET_BASE + "decoration/nature/trees_A_small.gltf"),
		load(ASSET_BASE + "decoration/nature/rock_single_A.gltf"),
		load(ASSET_BASE + "decoration/nature/rock_single_B.gltf"),
	]

	var rng = RandomNumberGenerator.new()
	rng.seed = 42

	# Road cells: horizontal strip connecting the 3 objectives
	var road_cells := {}
	for c in range(7, 22):
		road_cells[Vector2i(c, 10)] = true
	road_cells[Vector2i(14, 9)] = true
	road_cells[Vector2i(13, 9)] = true
	road_cells[Vector2i(15, 9)] = true

	var obj_set := {}
	for obj in OBJECTIVES:
		obj_set[obj] = true

	for r in ROWS:
		for c in COLS:
			var center = _hex_center(c, r)
			var pos = Vector2i(c, r)
			var is_edge = r == 0 or r == ROWS - 1 or c == 0 or c == COLS - 1

			# Pick tile type
			var tile: Node3D
			if is_edge:
				tile = water_scene.instantiate()
			elif road_cells.has(pos) and not obj_set.has(pos):
				tile = road_scene.instantiate()
			else:
				tile = grass_scene.instantiate()

			tile.position = center
			tile.rotation.y = deg_to_rad(30)
			add_child(tile)

			# Scatter decorations on plain grass tiles (~15%)
			if not is_edge and not road_cells.has(pos) and not obj_set.has(pos):
				if rng.randf() < 0.15:
					var deco = decos[rng.randi() % decos.size()].instantiate()
					deco.position = center
					add_child(deco)

	# Objectives
	for obj in OBJECTIVES:
		var center = _hex_center(obj.x, obj.y)
		var marker = obj_scene.instantiate()
		marker.position = center
		add_child(marker)

func _hex_center(col: int, row: int) -> Vector3:
	var x = HEX_SIZE * 1.5 * col
	var z = HEX_SIZE * sqrt(3.0) * row + (col & 1) * HEX_SIZE * sqrt(3.0) * 0.5
	return Vector3(x, 0, z)

# ============================================================================
# FLYING CAMERA
# ============================================================================

func _input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			mouse_captured = true
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_speed = min(cam_speed * 1.2, 60.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_speed = max(cam_speed / 1.2, 3.0)

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		mouse_captured = false

	if event is InputEventMouseMotion and mouse_captured:
		cam_yaw   -= event.relative.x * 0.003
		cam_pitch -= event.relative.y * 0.003
		cam_pitch  = clamp(cam_pitch, -PI * 0.49, PI * 0.49)
		camera.rotation = Vector3(cam_pitch, cam_yaw, 0)

func _process(delta: float):
	if not mouse_captured:
		return
	var dir = Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir -= camera.basis.z
	if Input.is_key_pressed(KEY_S): dir += camera.basis.z
	if Input.is_key_pressed(KEY_A): dir -= camera.basis.x
	if Input.is_key_pressed(KEY_D): dir += camera.basis.x
	if Input.is_key_pressed(KEY_E): dir.y += 1
	if Input.is_key_pressed(KEY_Q): dir.y -= 1
	if Input.is_key_pressed(KEY_SHIFT): dir *= 2.5
	if dir.length() > 0:
		camera.position += dir.normalized() * cam_speed * delta

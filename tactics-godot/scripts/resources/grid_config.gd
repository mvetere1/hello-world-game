class_name GridConfig
extends Resource

@export_group("Grid Dimensions")
@export_range(8, 100) var cols: int = 56
@export_range(8, 100) var rows: int = 40
@export_range(8.0, 64.0, 0.5) var hex_size: float = 20.0

@export_group("Deployment — Player 1 (Bottom)")
@export_range(0, 99) var p1_deploy_rows_min: int = 32
@export_range(0, 99) var p1_deploy_rows_max: int = 39
@export_range(0, 99) var deploy_col_min: int = 4
@export_range(0, 99) var deploy_col_max: int = 51

@export_group("Deployment — Player 2 (Top)")
@export_range(0, 99) var p2_deploy_rows_min: int = 0
@export_range(0, 99) var p2_deploy_rows_max: int = 7

@export_group("Objectives")
@export var objectives: Array[Vector2i] = [
	Vector2i(14, 20),
	Vector2i(28, 18),
	Vector2i(42, 20),
]

@export_group("Camera")
@export_range(0.1, 2.0, 0.05) var initial_zoom: float = 0.5

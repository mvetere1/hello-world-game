class_name TerrainType
extends Resource

@export_group("Identity")
@export var terrain_name: String = "Grass"
@export var terrain_key: String = "grass"

@export_group("Movement")
@export var passable: bool = true
@export_range(0.5, 5.0, 0.5) var move_cost: float = 1.0

@export_group("Combat")
@export_range(0, 3) var cover_bonus: int = 0
@export var blocks_los: bool = false

@export_group("Visuals")
@export var tile_color: Color = Color(0.11, 0.16, 0.26)
@export var tile_texture: Texture2D

class_name BattleConfig
extends Resource

@export_group("Army")
@export_range(1, 20) var units_per_side: int = 8
@export_range(1, 30) var turns: int = 10

@export_group("Combat")
@export_range(1, 10, 1, "suffix:hex") var combat_range: int = 2
@export_range(1, 20, 1, "suffix:hex") var oc_radius: int = 4
@export_range(1, 50, 1, "suffix:hex") var cavalry_aggro: int = 16

@export_group("Scoring")
@export_range(1, 20) var vp_per_objective: int = 5

@export_group("Animation")
@export_range(0.1, 3.0, 0.1, "suffix:s") var turn_duration: float = 0.8

@export_group("Names Pool")
@export var unit_names: Array[String] = [
	"Ada", "Ben", "Cal", "Dan", "Eve", "Finn", "Gil", "Hal",
	"Ida", "Jay", "Kit", "Leo", "Max", "Ned", "Odo", "Pat",
	"Rex", "Sam", "Tom", "Val",
]

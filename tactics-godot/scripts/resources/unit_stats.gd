class_name UnitStats
extends Resource

@export_group("Identity")
@export var display_name: String = ""
@export var unit_type_key: String = ""  # "infantry", "cavalry", etc.
@export var prefix: String = "I"       # single-letter prefix for combat log

@export_group("Formation")
@export_range(1, 20) var models: int = 10
@export_range(0, 10) var fixed_footprint: int = 0  # 0 = auto (ceil(models/2))

@export_group("Movement")
@export_range(0, 50, 1, "suffix:hex") var move_speed: int = 10

@export_group("Combat — Ranged")
@export_range(0, 50, 1, "suffix:hex") var attack_range: int = 0  # 0 = melee only
@export var targets_furthest: bool = false

@export_group("Combat — Primary")
@export_range(1, 10) var attacks: int = 2
@export_range(1, 6) var hit: int = 3
@export_range(1, 6) var wound: int = 3
@export_range(0, 3) var rend: int = 0
@export_range(1, 6) var damage: int = 1

@export_group("Combat — Melee Override")
@export var has_melee_override: bool = false
@export_range(1, 10) var melee_attacks: int = 1
@export_range(1, 6) var melee_hit: int = 5
@export_range(1, 6) var melee_wound: int = 4
@export_range(0, 3) var melee_rend: int = 0
@export_range(1, 6) var melee_damage: int = 1

@export_group("Defense")
@export_range(1, 20) var hp: int = 2
@export_range(1, 6) var armor: int = 4
@export_range(1, 5) var oc: int = 1

@export_group("Special Rules")
@export var can_deep_strike: bool = false
@export var can_retreat: bool = false
@export_range(0, 50, 1, "suffix:hex") var retreat_move: int = 0
@export_range(0, 50, 1, "suffix:hex") var aggro_range: int = 0

@export_group("Sprites")
@export var sprite_idle: Texture2D
@export var sprite_run: Texture2D
@export_range(1, 20) var idle_frames: int = 8
@export_range(1, 20) var run_frames: int = 6
@export_range(64, 512) var sprite_size: int = 192


func get_footprint(current_models: int = -1) -> int:
	var m = current_models if current_models > 0 else models
	if fixed_footprint > 0:
		return fixed_footprint
	return ceili(float(m) / 2.0)


func to_legacy_dict() -> Dictionary:
	var d := {
		"models": models, "hp": hp, "move": move_speed,
		"attacks": attacks, "hit": hit, "wound": wound,
		"rend": rend, "armor": armor, "damage": damage,
		"oc": oc,
	}
	if fixed_footprint > 0:
		d["footprint"] = fixed_footprint
	if attack_range > 0:
		d["range"] = attack_range
	if targets_furthest:
		d["targets_furthest"] = true
	if has_melee_override:
		d["melee_attacks"] = melee_attacks
		d["melee_hit"] = melee_hit
		d["melee_wound"] = melee_wound
		d["melee_rend"] = melee_rend
		d["melee_damage"] = melee_damage
	if can_retreat and retreat_move > 0:
		d["retreat_move"] = retreat_move
	return d

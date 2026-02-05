extends Area2D

@export var damage := 5

func _on_body_entered(body):
	print("Hit:", body.name)
	if body.has_method("take_damage"):
		var direction = sign(body.global_position.x - global_position.x)
		print(body.global_position.x)
		body.take_damage(damage, direction)

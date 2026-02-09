extends CharacterBody2D

@export var speed = 400

@onready var sprite = $MainChar

func _physics_process(delta):
	var input_vector = Vector2(
		Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left"),
		Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
	).normalized()
	
	# Move the player
	velocity = input_vector * speed
	move_and_slide()

	# Play correct animation
	if input_vector.x != 0:
		sprite.play("walk")
		sprite.flip_h = input_vector.x < 0  # mirror left
	elif input_vector.y != 0:
		sprite.play("walk")
		sprite.flip_h = velocity.x < 0  # optional: maintain last horizontal direction
	else:
		sprite.play("idle")

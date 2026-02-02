extends CharacterBody2D

@export var speed : float = 400.0

func _physics_process(_delta: float) -> void:
	# 1. Get input direction (Vector2)
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	if direction:
		#velocity.x = direction * SPEED
		$AnimatedSprite2D.play("Loop")
	else:
		#velocity.x = move_toward(velocity.x, 0, SPEED)
		$AnimatedSprite2D.stop()
		
	# 2. Set velocity directly based on input
	velocity = direction * speed
	
	# 3. Move the body
	move_and_slide()

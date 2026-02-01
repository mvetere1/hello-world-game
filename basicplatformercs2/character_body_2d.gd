extends CharacterBody2D

const BASE_SPEED = 400.0
var speed = BASE_SPEED
var jump_velocity = -600.0


func _physics_process(delta: float) -> void:
	# Add the gravity.

	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity
		$AnimatedSprite2D.play("Loop")


	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var direction := Input.get_axis("ui_left", "ui_right")
	if direction:
		velocity.x = direction * speed
		$AnimatedSprite2D.play("Loop")
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		$AnimatedSprite2D.stop()

	move_and_slide()

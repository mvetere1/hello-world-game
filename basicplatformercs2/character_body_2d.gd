extends CharacterBody2D

const BASE_SPEED = 400.0
var speed = BASE_SPEED
var jump_velocity = -600.0
@export var health := 10
@export var knockback_strength := 300.0
@export var knockback_y := -200.0  # negative = up in Godot
var in_knockback := false

func die():
	print("Character died — restarting level")
	$AnimatedSprite2D.play("now poop")
	#get_tree().reload_current_scene()
	print("printing from Matts branch")
	

func apply_knockback(source_position: float):
	velocity.x = source_position * knockback_strength
	# Vertical push (upward pop)
	velocity.y = knockback_y
	
	in_knockback = true
	await get_tree().create_timer(0.15).timeout
	in_knockback = false
	
func take_damage(amount: int, source_position: float):
	health -= amount
	apply_knockback(source_position)
	if (health <=0):
		call_deferred("die")
func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not in_knockback:
		if not is_on_floor():
			velocity += get_gravity() * delta

		# Handle jump.
		if Input.is_action_just_pressed("ui_accept") and is_on_floor():
			velocity.y = jump_velocity
			$AnimatedSprite2D.play("Loop")

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity
		$AnimatedSprite2D.play("Loop")

	var direction := Input.get_axis("ui_left", "ui_right")
	if direction:
		velocity.x = direction * speed
		$AnimatedSprite2D.play("turn into butthole monster")
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		#$AnimatedSprite2D.stop()


	move_and_slide()

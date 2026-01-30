extends Node2D

# Movement speed in pixels per second
var speed = 200

func _process(delta):
	var velocity = Vector2.ZERO
	
	if Input.is_action_pressed("ui_right"):
		velocity.x += 1
	if Input.is_action_pressed("ui_left"):
		velocity.x -= 1
	if Input.is_action_pressed("ui_down"):
		velocity.y += 1
	if Input.is_action_pressed("ui_up"):
		velocity.y -= 1

	# Normalize so diagonal movement isn't faster
	velocity = velocity.normalized() * speed * delta
	position += velocity

	queue_redraw()  # redraw circle

func _draw():
	draw_circle(Vector2.ZERO, 20, Color(1, 0, 0))  # red circle

extends Area2D


@export var speed_bonus := 800.0
@export var jump_bonus := 200.0
@export var duration := 10.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	body_entered.connect(_on_body_entered)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func _on_body_entered(body: Node) -> void:
	if body is CharacterBody2D:
		body.speed += speed_bonus
		body.jump_velocity -= jump_bonus
		queue_free()

	var timer := get_tree().create_timer(duration)
	timer.timeout.connect(func ():
		if is_instance_valid(body):
			body.speed = body.BASE_SPEED)
		
	queue_free()

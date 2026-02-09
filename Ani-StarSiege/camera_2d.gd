extends Camera2D

@export var speed := 400.0

func _process(delta):
	var input := Input.get_vector(
		"ui_left",
		"ui_right",
		"ui_up",
        "ui_down"
	)

	position += input * speed * delta

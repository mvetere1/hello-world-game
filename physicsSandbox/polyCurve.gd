extends StaticBody2D

@export var color: Color = Color.BLUE

func _draw():
	var shape = $Curve.shape as RectangleShape2D
	var size = shape.size
	draw_rect(
		Rect2(-size / 2, size),
		color
	)

func _ready():
	queue_redraw()

extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_pressed() -> void:
	$Label.text = "Hello, Godot!"
	pass # Replace with function body.


func _on_button_2_pressed() -> void:
	$Label2.text = "Hello, button2"
	pass # Replace with function body.


func _on_button_2_toggled(toggled_on: bool) -> void:
	if (toggled_on):
		$Label2.text = "toggle worked"
	else:
		$Label2.text = "toggle workedELSE"
	pass # Replace with function body.

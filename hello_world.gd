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
	$Label3.text = "Hello, button3"
	pass # Replace with function body.

func _on_button_tommy_toggled(toggled_on: bool) -> void:
	if toggled_on == true:
		$label_Tommy.text = "the toggle is true"
	else:
		$label_Tommy.text = "the toggle is false"
	pass # Replace with function body.


func _on_button_3_toggled(toggled_on: bool) -> void:
	if toggled_on:
		$Label4.text = "the toggle is true"
	else:
		$Label4.text = "the toggle is false"

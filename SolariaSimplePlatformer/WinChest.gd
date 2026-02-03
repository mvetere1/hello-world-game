extends Area2D

func win_game():
	get_tree().change_scene_to_file("res://youWin.tscn")

func _on_body_entered(body):
	print("Entered by:", body.name)
	if body is CharacterBody2D:
		call_deferred("win_game")

class_name DSTurnPopup
extends ColorRect

signal turn_selected(turn: int)

# Resources — loaded independently
var _visual: VisualConfig = preload("res://resources/config/visual_config.tres")

# State reference — set via init()
var _state: GameState

# Child node references
@onready var _header: Label = %Header
@onready var _button_row: HBoxContainer = %ButtonRow

var _buttons: Array[Button] = []


func init(state: GameState) -> void:
	_state = state
	# Collect buttons from the row
	for child in _button_row.get_children():
		if child is Button:
			_buttons.append(child)
	# Connect button signals — T2 (i=0) → turn 1, T8 (i=6) → turn 7
	for i in _buttons.size():
		_buttons[i].pressed.connect(_on_turn_btn.bind(i))
	# Initial state
	_update_accent()
	visible = _state.ds_selecting_turn


func _process(_delta: float) -> void:
	if _state == null:
		return
	var should_show = _state.phase == GameState.Phase.DEPLOY and _state.ds_selecting_turn
	if visible != should_show:
		visible = should_show
		if should_show:
			_update_accent()


func _on_turn_btn(index: int) -> void:
	# T2 button (index=0) → 0-based turn 1, T8 button (index=6) → turn 7
	turn_selected.emit(index + 1)


func _update_accent() -> void:
	if _state == null:
		return
	var accent = _visual.color_p1 if _state.active_player == 1 else _visual.color_p2
	_header.text = "Choose Arrival Turn"
	_header.add_theme_color_override("font_color", accent)
	for btn in _buttons:
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
		btn.add_theme_color_override("font_pressed_color", accent)

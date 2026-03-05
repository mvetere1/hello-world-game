class_name UnitSelectPopup
extends ColorRect

signal unit_selected(unit_type: String)

# Resources — loaded independently
var _visual: VisualConfig = preload("res://resources/config/visual_config.tres")

# State reference — set via init()
var _state: GameState

# Unit types matching HexMoveDemo.UNIT_TYPES order
const UNIT_TYPES = ["infantry", "cavalry", "artillery", "deep_strike", "archer"]

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
	# Connect button signals
	for i in _buttons.size():
		_buttons[i].pressed.connect(_on_unit_btn.bind(i))
	# Initial state
	_update_accent()
	visible = _state.selecting_unit


func _process(_delta: float) -> void:
	if _state == null:
		return
	var should_show = _state.phase == GameState.Phase.DEPLOY and _state.selecting_unit
	if visible != should_show:
		visible = should_show
		if should_show:
			_update_accent()


func _on_unit_btn(index: int) -> void:
	unit_selected.emit(UNIT_TYPES[index])


func _update_accent() -> void:
	if _state == null:
		return
	var accent = _visual.color_p1 if _state.active_player == 1 else _visual.color_p2
	var who = "BLUE" if _state.active_player == 1 else "RED"
	_header.text = "%s — Choose Unit Type" % who
	_header.add_theme_color_override("font_color", accent)
	# Style buttons with team accent
	for btn in _buttons:
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
		btn.add_theme_color_override("font_pressed_color", accent)

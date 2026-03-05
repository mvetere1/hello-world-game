class_name Scoreboard
extends PanelContainer

# Resources — loaded independently
var _visual: VisualConfig = preload("res://resources/config/visual_config.tres")
var _battle: BattleConfig = preload("res://resources/config/battle_config.tres")

# State reference — set via init()
var _state: GameState

# Child refs
@onready var _grid: GridContainer = %Grid

# Dynamic labels — created in _build_grid(), updated on sim_changed
var _turn_labels: Array[Label] = []
var _blue_labels: Array[Label] = []
var _red_labels: Array[Label] = []
var _delta_blue: Label
var _delta_red: Label


func init(state: GameState) -> void:
	_state = state
	_state.sim_changed.connect(_on_sim_changed)
	_build_grid()
	_on_sim_changed()


func _build_grid() -> void:
	var col_w = 85
	var fs = 21

	# Header row
	_add_label("Turn", Color(0.7, 0.7, 0.7), fs, col_w)
	_add_label("BLUE", _visual.color_p1, fs, col_w)
	_add_label("RED", _visual.color_p2, fs, col_w)

	# Turn rows
	for t in _battle.turns:
		var turn_lbl = _add_label(str(t + 1), Color(0.6, 0.6, 0.6), fs, col_w)
		_turn_labels.append(turn_lbl)
		var blue_lbl = _add_label("", _visual.color_p1, fs, col_w)
		_blue_labels.append(blue_lbl)
		var red_lbl = _add_label("", _visual.color_p2, fs, col_w)
		_red_labels.append(red_lbl)

	# Delta row
	_add_label("", Color(0.6, 0.6, 0.6), fs, col_w)
	_delta_blue = _add_label("", Color(0.3, 0.9, 0.3), fs, col_w)
	_delta_red = _add_label("", Color(0.3, 0.9, 0.3), fs, col_w)


func _add_label(text: String, color: Color, font_size: int, min_width: int) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.custom_minimum_size.x = min_width
	_grid.add_child(lbl)
	return lbl


func _on_sim_changed() -> void:
	var sim = _get_active_sim()
	var vpt: Array = sim.get("vp_per_turn", [])

	# Update turn VP labels
	for t in _blue_labels.size():
		if t < vpt.size():
			_blue_labels[t].text = str(vpt[t][0])
			_red_labels[t].text = str(vpt[t][1])
		else:
			_blue_labels[t].text = ""
			_red_labels[t].text = ""

	# Update delta row from preview_diff
	var sd: Array = _state.preview_diff.get("score_delta", [])
	if sd.size() >= 2 and (sd[0] != 0 or sd[1] != 0):
		if sd[0] != 0:
			_delta_blue.text = ("+" if sd[0] > 0 else "") + str(sd[0])
			_delta_blue.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3) if sd[0] > 0 else Color(0.9, 0.3, 0.3))
		else:
			_delta_blue.text = ""
		if sd[1] != 0:
			_delta_red.text = ("+" if sd[1] > 0 else "") + str(sd[1])
			_delta_red.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3) if sd[1] > 0 else Color(0.9, 0.3, 0.3))
		else:
			_delta_red.text = ""
	else:
		_delta_blue.text = ""
		_delta_red.text = ""


func _get_active_sim() -> Dictionary:
	if not _state.preview_sim.is_empty():
		return _state.preview_sim
	return _state.confirmed_sim


func _process(_delta: float) -> void:
	if _state == null:
		return
	visible = _state.show_analytics_ui and not _state.replay_mode

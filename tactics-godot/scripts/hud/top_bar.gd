class_name TopBar
extends PanelContainer

signal replay_requested()
signal summary_requested()

# Resources — loaded independently, no HexMoveDemo reference needed
var _battle: BattleConfig = preload("res://resources/config/battle_config.tres")
var _visual: VisualConfig = preload("res://resources/config/visual_config.tres")

# State reference — set via init()
var _state: GameState

# Child node references (unique names in scene)
@onready var _phase_label: Label = %PhaseLabel
@onready var _view_modes: HBoxContainer = %ViewModes
@onready var _progress_bg: ColorRect = %ProgressBg
@onready var _progress_fill: ColorRect = %ProgressFill
@onready var _button_row: HBoxContainer = %ButtonRow
@onready var _replay_btn: Button = %ReplayBtn
@onready var _summary_btn: Button = %SummaryBtn

var _view_mode_buttons: Array[Button] = []


func init(state: GameState) -> void:
	_state = state
	# Collect view mode buttons from the ViewModes container
	for child in _view_modes.get_children():
		if child is Button:
			_view_mode_buttons.append(child)
	# Connect GameState signals
	_state.phase_changed.connect(_on_phase_changed)
	_state.sim_changed.connect(_on_sim_changed)
	_state.view_mode_changed.connect(_on_view_mode_changed)
	_state.unit_placed.connect(_on_unit_placed)
	# Connect button signals
	for i in _view_mode_buttons.size():
		_view_mode_buttons[i].pressed.connect(_on_view_mode_btn.bind(i))
	_replay_btn.pressed.connect(func(): replay_requested.emit())
	_summary_btn.pressed.connect(func(): summary_requested.emit())
	# Initial state
	_update_phase_text()
	_update_view_mode_highlight()
	_update_button_row()


func _process(_delta: float) -> void:
	if _state == null:
		return
	# Hide during replay — BattleRenderer has its own replay HUD
	visible = not _state.replay_mode
	if not visible:
		return
	# Update progress bar width
	var turns = _battle.turns
	var progress = float(_state.anim_turn) / float(turns) if turns > 0 else 0.0
	_progress_fill.size.x = _progress_bg.size.x * progress
	# Update phase text every frame for anim_turn display in DONE phase
	if _state.phase == GameState.Phase.DONE:
		_update_phase_text()


# -- Signal handlers ----------------------------------------------------------

func _on_phase_changed(_phase: int) -> void:
	_update_phase_text()
	_update_button_row()
	_update_view_mode_visibility()

func _on_sim_changed() -> void:
	_update_phase_text()

func _on_view_mode_changed(_mode: int) -> void:
	_update_view_mode_highlight()

func _on_unit_placed(_uid: int) -> void:
	_update_phase_text()

func _on_view_mode_btn(index: int) -> void:
	_state.view_mode = index
	_state.view_mode_changed.emit(index)


# -- Update helpers -----------------------------------------------------------

func _update_phase_text() -> void:
	var p1_placed = _state.placed_p1.size()
	var p2_placed = _state.placed_p2.size()
	var ups = _battle.units_per_side
	var txt := ""
	if _state.phase == GameState.Phase.DEPLOY:
		var who = "BLUE (P1)" if _state.active_player == 1 else "RED (P2)"
		var zone_desc = "bottom zone" if _state.active_player == 1 else "top zone"
		var utype = _state.deploy_unit_type.replace("_", " ").to_upper()
		var hint = "Select a unit type" if _state.selecting_unit else ("Select arrival turn" if _state.ds_selecting_turn else ("Click %s to place %s" % [zone_desc, utype]))
		txt = "%s's turn — %s   |   P1: %d/%d   P2: %d/%d" \
			% [who, hint, p1_placed, ups, p2_placed, ups]
	elif _state.phase == GameState.Phase.DONE:
		var vpt: Array = _state.confirmed_sim.get("vp_per_turn", [])
		var final_vp = vpt[vpt.size() - 1] if vpt.size() > 0 else [0, 0]
		var res = "DRAW"
		if final_vp[0] > final_vp[1]: res = "BLUE WINS"
		elif final_vp[1] > final_vp[0]: res = "RED WINS"
		txt = "ALL DEPLOYED — %s   |   VP: BLUE %d - RED %d   |   Turn %d/%d" \
			% [res, final_vp[0], final_vp[1], _state.anim_turn, _battle.turns]
	_phase_label.text = txt

func _update_view_mode_highlight() -> void:
	var mode_names = ["1:CLEAN", "2:CHANGED", "3:FULL", "4:FINAL"]
	for i in _view_mode_buttons.size():
		var btn = _view_mode_buttons[i]
		var is_active = (i == _state.view_mode)
		btn.text = "[%s]" % mode_names[i] if is_active else mode_names[i]
		var col = _visual.view_mode_active_color if is_active else _visual.view_mode_inactive_color
		btn.add_theme_color_override("font_color", col)
		btn.add_theme_color_override("font_hover_color", col)
		btn.add_theme_color_override("font_pressed_color", col)

func _update_view_mode_visibility() -> void:
	_view_modes.visible = (_state.phase == GameState.Phase.DEPLOY)

func _update_button_row() -> void:
	_button_row.visible = (_state.phase == GameState.Phase.DONE)

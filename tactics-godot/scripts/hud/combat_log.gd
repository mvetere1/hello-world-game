class_name CombatLog
extends PanelContainer

# Resources — loaded independently
var _visual: VisualConfig = preload("res://resources/config/visual_config.tres")

# State reference — set via init()
var _state: GameState

# Child refs
var _rtl: RichTextLabel

func init(state: GameState) -> void:
	_state = state
	_state.sim_changed.connect(_on_sim_changed)
	# Build the RichTextLabel child
	var scroll := ScrollContainer.new()
	scroll.layout_mode = 2
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_rtl = RichTextLabel.new()
	_rtl.bbcode_enabled = true
	_rtl.fit_content = false
	_rtl.scroll_active = true
	_rtl.selection_enabled = false
	_rtl.layout_mode = 2
	_rtl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rtl.mouse_filter = Control.MOUSE_FILTER_PASS
	_rtl.add_theme_font_size_override("normal_font_size", 13)
	scroll.add_child(_rtl)
	_on_sim_changed()

func _on_sim_changed() -> void:
	if _rtl == null:
		return
	_rtl.clear()
	if _state.log_lines.is_empty():
		return
	# Title
	_rtl.push_color(Color(0.7, 0.7, 0.7))
	_rtl.push_font_size(11)
	_rtl.add_text("Combat Log (scroll wheel)")
	_rtl.pop()  # font_size
	_rtl.pop()  # color
	_rtl.newline()
	# Log lines with color coding
	for line in _state.log_lines:
		var col := _line_color(line)
		_rtl.push_color(col)
		_rtl.add_text(line)
		_rtl.pop()
		_rtl.newline()

func _line_color(line: String) -> Color:
	if line.begins_with("==="):
		return Color(0.9, 0.85, 0.4)
	if line.begins_with("---"):
		return Color(0.5, 0.7, 0.9)
	if "ELIMINATED" in line:
		return Color(0.9, 0.3, 0.3)
	if "Score:" in line:
		return Color(0.4, 0.9, 0.5)
	if line.find("moves") >= 0:
		return Color(0.6, 0.6, 0.6)
	return Color(0.75, 0.75, 0.75)

func _process(_delta: float) -> void:
	if _state == null:
		return
	visible = _state.show_analytics_ui and _state._log_visible and not _state.replay_mode

class_name FateChart
extends PanelContainer

# Resources — loaded independently
var _visual: VisualConfig = preload("res://resources/config/visual_config.tres")

# State reference — set via init()
var _state: GameState

# Child refs
@onready var _rows_vbox: VBoxContainer = %Rows

# Per-row tracking — rebuilt when unit count changes
var _row_panels: Array[PanelContainer] = []
var _name_labels: Array[Label] = []
var _died_labels: Array[Label] = []
var _obj_labels: Array = []  # Array of Array[Label] — [uid][0..2]
var _kills_labels: Array[Label] = []
var _dmg_labels: Array[Label] = []
var _divider: HSeparator = null
var _current_unit_count: int = 0

const COL_WIDTHS = [115, 54, 46, 46, 46, 54, 54]
const FONT_SIZE = 20


func init(state: GameState) -> void:
	_state = state
	_state.sim_changed.connect(_on_sim_changed)
	_build_header()
	_on_sim_changed()


func _unit_prefix(unit_type: String) -> String:
	match unit_type:
		"infantry": return "I"
		"cavalry": return "C"
		"artillery": return "A"
		"deep_strike": return "D"
		"archer": return "W"
		_: return "?"


func _build_header() -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	var headers = ["Unit", "Died", "O1", "O2", "O3", "Kills", "Dmg"]
	for i in headers.size():
		var lbl = Label.new()
		lbl.text = headers[i]
		lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		lbl.add_theme_font_size_override("font_size", FONT_SIZE)
		lbl.custom_minimum_size.x = COL_WIDTHS[i]
		hbox.add_child(lbl)
	_rows_vbox.add_child(hbox)


func _build_rows(unit_count: int) -> void:
	# Clear existing rows (keep header at index 0)
	_row_panels.clear()
	_name_labels.clear()
	_died_labels.clear()
	_obj_labels.clear()
	_kills_labels.clear()
	_dmg_labels.clear()
	_divider = null
	while _rows_vbox.get_child_count() > 1:
		var child = _rows_vbox.get_child(1)
		_rows_vbox.remove_child(child)
		child.queue_free()

	_current_unit_count = unit_count
	for uid in unit_count:
		var panel = PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Transparent default style
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.content_margin_left = 0
		style.content_margin_right = 0
		style.content_margin_top = 0
		style.content_margin_bottom = 0
		panel.add_theme_stylebox_override("panel", style)

		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 0)

		# Name label
		var name_lbl = _make_label("", Color.WHITE, COL_WIDTHS[0])
		hbox.add_child(name_lbl)
		_name_labels.append(name_lbl)

		# Died label
		var died_lbl = _make_label("", Color(0.5, 0.5, 0.5), COL_WIDTHS[1])
		hbox.add_child(died_lbl)
		_died_labels.append(died_lbl)

		# Objective labels (3)
		var obj_row: Array[Label] = []
		for oi in 3:
			var obj_lbl = _make_label("", Color(0.5, 0.5, 0.5), COL_WIDTHS[2 + oi])
			hbox.add_child(obj_lbl)
			obj_row.append(obj_lbl)
		_obj_labels.append(obj_row)

		# Kills label
		var kills_lbl = _make_label("", Color(0.5, 0.5, 0.5), COL_WIDTHS[5])
		hbox.add_child(kills_lbl)
		_kills_labels.append(kills_lbl)

		# Damage label
		var dmg_lbl = _make_label("", Color(0.5, 0.5, 0.5), COL_WIDTHS[6])
		hbox.add_child(dmg_lbl)
		_dmg_labels.append(dmg_lbl)

		panel.add_child(hbox)
		_row_panels.append(panel)
		_rows_vbox.add_child(panel)


func _make_label(text: String, color: Color, min_width: int) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", FONT_SIZE)
	lbl.custom_minimum_size.x = min_width
	return lbl


func _on_sim_changed() -> void:
	var sim = _get_active_sim()
	var names: Array = sim.get("unit_names", [])
	if names.is_empty():
		visible = false
		return
	var final_units: Array = sim.get("units", [])
	var obj_data: Array = sim.get("unit_obj", [])
	var kills_data: Array = sim.get("unit_kills", [])
	var dmg_data: Array = sim.get("unit_dmg", [])

	# Rebuild rows if unit count changed
	if final_units.size() != _current_unit_count:
		_build_rows(final_units.size())

	var fate_list: Array = _state.preview_diff.get("fate_changes", [])

	# Insert team divider if needed
	_update_divider(final_units)

	for uid in final_units.size():
		var u = final_units[uid]
		var tc = _visual.color_p1 if u.player == 1 else _visual.color_p2

		# Name with type prefix
		var prefix = _unit_prefix(u.unit_type)
		_name_labels[uid].text = prefix + " " + (names[uid] if uid < names.size() else "?")
		_name_labels[uid].add_theme_color_override("font_color", tc)

		# Died on turn
		if u.eliminated:
			_died_labels[uid].text = str(u.elim_turn + 1)
			_died_labels[uid].add_theme_color_override("font_color", Color(0.8, 0.3, 0.3))
		else:
			_died_labels[uid].text = "-"
			_died_labels[uid].add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

		# Objective columns
		for oi in 3:
			var status = obj_data[uid][oi] if uid < obj_data.size() else "no"
			if status == "won":
				_obj_labels[uid][oi].text = "WON"
				_obj_labels[uid][oi].add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
			elif status == "yes":
				_obj_labels[uid][oi].text = "yes"
				_obj_labels[uid][oi].add_theme_color_override("font_color", Color(0.8, 0.8, 0.3))
			else:
				_obj_labels[uid][oi].text = "-"
				_obj_labels[uid][oi].add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

		# Kills
		var k = kills_data[uid] if uid < kills_data.size() else 0
		_kills_labels[uid].text = str(k) if k > 0 else "-"
		_kills_labels[uid].add_theme_color_override("font_color", Color(0.9, 0.6, 0.2) if k > 0 else Color(0.5, 0.5, 0.5))

		# Damage
		var dmg = dmg_data[uid] if uid < dmg_data.size() else 0
		_dmg_labels[uid].text = str(dmg) if dmg > 0 else "-"
		_dmg_labels[uid].add_theme_color_override("font_color", Color(0.9, 0.4, 0.4) if dmg > 0 else Color(0.5, 0.5, 0.5))

		# Fate highlight
		var style: StyleBoxFlat = _row_panels[uid].get_theme_stylebox("panel")
		if uid < fate_list.size() and fate_list[uid].changed:
			match fate_list[uid].fate:
				"now_survives": style.bg_color = Color(0.2, 0.8, 0.2, 0.25)
				"now_dies":     style.bg_color = Color(0.8, 0.2, 0.2, 0.25)
				_:              style.bg_color = Color(0.8, 0.8, 0.2, 0.15)
		else:
			style.bg_color = Color(0, 0, 0, 0)


func _update_divider(final_units: Array) -> void:
	# Remove old divider
	if _divider != null and _divider.get_parent() != null:
		_divider.get_parent().remove_child(_divider)
		_divider.queue_free()
		_divider = null

	# Find team boundary
	for uid in range(1, final_units.size()):
		if final_units[uid].player != final_units[uid - 1].player:
			_divider = HSeparator.new()
			_divider.add_theme_color_override("separator", Color(0.4, 0.4, 0.4, 0.5))
			_divider.add_theme_constant_override("separation", 2)
			# Insert after the P1 last row panel (index = header + uid panels)
			var insert_idx = 1 + uid  # +1 for header
			_rows_vbox.move_child(_row_panels[uid], insert_idx)
			_rows_vbox.add_child(_divider)
			_rows_vbox.move_child(_divider, insert_idx)
			break


func _get_active_sim() -> Dictionary:
	if not _state.preview_sim.is_empty():
		return _state.preview_sim
	return _state.confirmed_sim


func _process(_delta: float) -> void:
	if _state == null:
		return
	visible = _state.show_analytics_ui and not _state.replay_mode

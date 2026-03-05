class_name BattleRenderer
extends Node2D

# Reference to parent HexMoveDemo for config/methods, and GameState for mutable state
var _parent: Node2D
var _state: GameState
var _v: VisualConfig = preload("res://resources/config/visual_config.tres")

func init(parent: Node2D, state: GameState):
	_parent = parent
	_state = state

# ============================================================================
# DRAW ORCHESTRATION  (battle portion of the old HexMoveDemo._draw())
# ============================================================================

func _draw():
	if _parent == null:
		return
	var vp = get_viewport_rect().size
	if not _parent._terrain_map:
		draw_rect(Rect2(Vector2.ZERO, vp), _v.color_background)

	if _state.replay_mode:
		_draw_replay()
		return

	# Choose which sim to display
	var use_preview = (not _state.preview_sim.is_empty()) and (_state.phase == GameState.Phase.DEPLOY)
	var draw_sim    = _state.preview_sim if use_preview else _state.confirmed_sim

	# Final state mode: show end-of-game positions, objectives, score
	if _state.phase == GameState.Phase.DEPLOY and _state.view_mode == GameState.ViewMode.FINAL:
		_draw_final_state(draw_sim)
		return

	# Viewport culling: only draw hexes visible on screen
	var vp_rect = get_viewport_rect().size
	var world_min = -_parent.cam_offset / _parent.cam_zoom
	var world_max = (vp_rect - _parent.cam_offset) / _parent.cam_zoom
	var hex_w = _parent.HEX_SIZE * 1.5
	var hex_h = _parent.HEX_SIZE * sqrt(3.0)
	var c_min = clampi(int(world_min.x / hex_w) - 2, 0, _parent.COLS - 1)
	var c_max = clampi(int(world_max.x / hex_w) + 2, 0, _parent.COLS - 1)
	var r_min = clampi(int(world_min.y / hex_h) - 2, 0, _parent.ROWS - 1)
	var r_max = clampi(int(world_max.y / hex_h) + 2, 0, _parent.ROWS - 1)
	for r in range(r_min, r_max + 1):
		for c in range(c_min, c_max + 1):
			_draw_tile(c, r)

	# Dark fog overlay for CHANGED mode — dims tiles so only changes pop
	if _state.phase == GameState.Phase.DEPLOY and _state.view_mode == GameState.ViewMode.CHANGED and not _state.preview_sim.is_empty():
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, _v.changed_fog_alpha))

	if not draw_sim.is_empty():
		_draw_sim(draw_sim, use_preview)

# ============================================================================
# TILE DRAWING
# ============================================================================

func _draw_tile(col: int, row: int):
	var center = _parent.hex_to_pixel(col, row)
	var corners = _parent.hex_corners(center)

	# Draw base tile texture.
	if _parent.tile_tex:
		var tw = _parent.HEX_SIZE * 2.0 * _parent.cam_zoom
		var th = _parent.HEX_SIZE * 2.2 * _parent.cam_zoom
		var dest = Rect2(center - Vector2(tw * 0.5, th * 0.35), Vector2(tw, th))
		draw_texture_rect(_parent.tile_tex, dest, false)
	elif not _parent._terrain_map:
		draw_colored_polygon(corners, _v.color_hex_fill)

	# Outline
	var outline_pts = PackedVector2Array(corners)
	outline_pts.append(corners[0])
	draw_polyline(outline_pts, Color(_v.color_hex_stroke.r, _v.color_hex_stroke.g, _v.color_hex_stroke.b, _v.hex_stroke_alpha), 0.5)

	# Terrain sprite overlay (non-grass hexes)
	var terrain = _parent._get_terrain_at(col, row)
	if terrain.terrain_key != "grass":
		var t_sprite = _parent._terrain_sprites.get(terrain.terrain_key)
		if t_sprite:
			var tw = _parent.HEX_SIZE * 2.0 * _parent.cam_zoom
			var th = _parent.HEX_SIZE * 2.0 * _parent.cam_zoom
			var dest = Rect2(center - Vector2(tw * 0.5, th * 0.5), Vector2(tw, th))
			draw_texture_rect(t_sprite, dest, false)
		else:
			var t_tint = terrain.tile_color
			t_tint.a = _v.terrain_tint_alpha
			draw_colored_polygon(corners, t_tint)
		var t_outline = PackedVector2Array(corners)
		t_outline.append(corners[0])
		var t_color = _v.forest_outline_color if terrain.terrain_key == "forest" else _v.water_outline_color
		draw_polyline(t_outline, t_color, _v.terrain_outline_width * _parent.cam_zoom)

	# Zone tint overlay
	var tint = Color(0, 0, 0, 0)
	if row >= _parent.P1_DEPLOY_ROWS_MIN and row <= _parent.P1_DEPLOY_ROWS_MAX and col >= _parent.DEPLOY_C_MIN and col <= _parent.DEPLOY_C_MAX:
		var a = _v.deploy_zone_alpha_active if (_state.active_player == 1 and _state.phase == GameState.Phase.DEPLOY) else _v.deploy_zone_alpha_inactive
		tint = Color(_v.color_p1.r, _v.color_p1.g, _v.color_p1.b, a)
	elif row >= _parent.P2_DEPLOY_ROWS_MIN and row <= _parent.P2_DEPLOY_ROWS_MAX and col >= _parent.DEPLOY_C_MIN and col <= _parent.DEPLOY_C_MAX:
		var a = _v.deploy_zone_alpha_active if (_state.active_player == 2 and _state.phase == GameState.Phase.DEPLOY) else _v.deploy_zone_alpha_inactive
		tint = Color(_v.color_p2.r, _v.color_p2.g, _v.color_p2.b, a)

	for i in _parent.OBJECTIVES.size():
		var obj = _parent.OBJECTIVES[i]
		var ctrl = _state._obj_control[i] if i < _state._obj_control.size() else 0
		var ctrl_color = _v.color_banner
		if ctrl == 1: ctrl_color = _v.color_p1
		elif ctrl == 2: ctrl_color = _v.color_p2
		if _parent.hex_dist(col, row, obj.x, obj.y) <= _parent.OC_RADIUS:
			tint = tint.lerp(Color(ctrl_color.r, ctrl_color.g, ctrl_color.b, _v.objective_zone_alpha), 0.5)
		if col == obj.x and row == obj.y:
			tint = Color(ctrl_color.r, ctrl_color.g, ctrl_color.b, _v.objective_hex_alpha)

	if tint.a > 0.0:
		draw_colored_polygon(corners, tint)

	# VP heatmap overlay during deployment
	if not _state.deploy_heatmap.is_empty() and _state.phase == GameState.Phase.DEPLOY and not _state.selecting_unit and not _state.ds_selecting_turn:
		var hid = _parent.hex_id(col, row)
		if _state.deploy_heatmap.has(hid):
			var vp_delta: int = _state.deploy_heatmap[hid]
			if vp_delta > 0 and _state._heatmap_max > 0:
				var t = clampf(float(vp_delta) / _state._heatmap_max, 0.0, 1.0)
				var intensity = lerpf(_v.heatmap_min_intensity, _v.heatmap_max_intensity, t * t)
				draw_colored_polygon(corners, Color(_v.heatmap_positive_color.r, _v.heatmap_positive_color.g, _v.heatmap_positive_color.b, intensity))
			elif vp_delta < 0 and _state._heatmap_min < 0:
				var t = clampf(float(-vp_delta) / -_state._heatmap_min, 0.0, 1.0)
				var intensity = lerpf(_v.heatmap_min_intensity, _v.heatmap_max_intensity, t * t)
				draw_colored_polygon(corners, Color(_v.heatmap_negative_color.r, _v.heatmap_negative_color.g, _v.heatmap_negative_color.b, intensity))

	# Deep strike legal hex highlighting
	if _state.deploy_unit_type == "deep_strike" and _state.ds_arrival_turn > 0 and not _state.selecting_unit and not _state.ds_selecting_turn:
		if _state.ds_legal_hexes.has(_parent.hex_id(col, row)):
			draw_colored_polygon(corners, _v.ds_legal_color)
		else:
			draw_colored_polygon(corners, _v.ds_illegal_color)

	# Hover highlight
	if _state.hover_hex.x == col and _state.hover_hex.y == row:
		draw_colored_polygon(corners, _v.hover_hex_color)

	# Objective flip glow (preview diff)
	var obj_flips: Array = _state.preview_diff.get("obj_flips", [])
	for i in _parent.OBJECTIVES.size():
		if i < obj_flips.size() and obj_flips[i]:
			if _parent.hex_dist(col, row, _parent.OBJECTIVES[i].x, _parent.OBJECTIVES[i].y) <= _parent.OC_RADIUS:
				draw_colored_polygon(corners, _v.objective_flip_glow)
			if col == _parent.OBJECTIVES[i].x and row == _parent.OBJECTIVES[i].y:
				var glow_pts = PackedVector2Array(corners)
				glow_pts.append(corners[0])
				draw_polyline(glow_pts, Color(_v.objective_flip_glow.r, _v.objective_flip_glow.g, _v.objective_flip_glow.b, 0.7), 2.5)

	# Objective banner
	for i in _parent.OBJECTIVES.size():
		if _parent.OBJECTIVES[i] == Vector2i(col, row):
			_draw_banner(center, i)

# ============================================================================
# UNIT DRAWING
# ============================================================================

func _draw_unit_final(uid: int, final_units: Array, timelines: Array, formations_tl: Array, is_ghost: bool, alpha: float):
	var u = final_units[uid]
	var trail: Array = timelines[uid]
	var ftl: Array = formations_tl[uid] if uid < formations_tl.size() else []
	var final_pos = Vector2i(-1, -1)
	var final_idx := 0
	if u.eliminated:
		final_idx = mini(u.elim_turn, trail.size() - 1)
		final_pos = trail[final_idx]
	else:
		final_idx = trail.size() - 1
		final_pos = trail[final_idx]
	if final_pos == Vector2i(-1, -1): return
	var final_form: Array = ftl[final_idx] if final_idx < ftl.size() else [final_pos]
	if u.eliminated:
		for fh in final_form:
			var center = _parent.hex_to_pixel(fh.x, fh.y)
			var r = _v.elim_cross_radius * _parent.cam_zoom
			var ea = _v.elim_cross_alpha_ghost if is_ghost else _v.elim_cross_alpha
			draw_line(center + Vector2(-r, -r), center + Vector2(r, r),
				Color(_v.elim_cross_color.r, _v.elim_cross_color.g, _v.elim_cross_color.b, ea), _v.elim_cross_width)
			draw_line(center + Vector2(r, -r), center + Vector2(-r, r),
				Color(_v.elim_cross_color.r, _v.elim_cross_color.g, _v.elim_cross_color.b, ea), _v.elim_cross_width)
	else:
		for fh in final_form:
			var center = _parent.hex_to_pixel(fh.x, fh.y)
			_draw_unit_token(center, u.player, u.models, u.unit_type, is_ghost, alpha)

func _draw_single_timeline(uid: int, final_units: Array, timelines: Array, formations_tl: Array, combat_ev: Array, display_turn: int, is_preview_unit: bool, _snail_trail: bool = false):
	var u = final_units[uid]
	var trail: Array = timelines[uid]
	var ftl: Array = formations_tl[uid] if uid < formations_tl.size() else []
	var alive_until = u.elim_turn if u.eliminated else _parent.TURNS
	var max_ti = mini(alive_until + 1, trail.size() - 1)
	var base = _v.color_p1 if u.player == 1 else _v.color_p2
	var highlight_a = _v.highlight_alpha_preview if is_preview_unit else _v.highlight_alpha
	# Path hex highlights — highlight all formation hexes per turn
	for ti in (max_ti + 1):
		var pos = trail[ti]
		if pos == Vector2i(-1, -1): continue
		var form: Array = ftl[ti] if ti < ftl.size() else [pos]
		for fh in form:
			var hc = _parent.hex_to_pixel(fh.x, fh.y)
			var hcorners = _parent.hex_corners(hc)
			draw_colored_polygon(hcorners, Color(base.r, base.g, base.b, highlight_a))
	# Snail trail ribbon (uses anchor positions)
	var ribbon_w = _parent.HEX_SIZE * (_v.ribbon_width_preview if is_preview_unit else _v.ribbon_width) * _parent.cam_zoom
	var ribbon_a = _v.ribbon_alpha_preview if is_preview_unit else _v.ribbon_alpha
	var is_disrupted = u.disrupted and u.disrupted_turn >= 0
	var disrupt_ti = (u.disrupted_turn + 1) if is_disrupted else -1
	for ti in max_ti:
		var from_pos = trail[ti]
		var to_pos = trail[ti + 1]
		if from_pos == to_pos: continue
		if from_pos == Vector2i(-1, -1) or to_pos == Vector2i(-1, -1): continue
		if is_disrupted and ti == disrupt_ti: continue  # skip ribbon at disruption
		var pa = _parent.hex_to_pixel(from_pos.x, from_pos.y)
		var pb = _parent.hex_to_pixel(to_pos.x, to_pos.y)
		var dir = (pb - pa).normalized()
		var perp = Vector2(-dir.y, dir.x) * ribbon_w
		var quad = PackedVector2Array([pa + perp, pa - perp, pb - perp, pb + perp])
		draw_colored_polygon(quad, Color(base.r, base.g, base.b, ribbon_a))
	# Disruption break visual
	if is_disrupted and u.disrupted_from != Vector2i(-1, -1) and disrupt_ti < trail.size():
		var yank_pos = trail[disrupt_ti] if disrupt_ti < trail.size() else Vector2i(u.col, u.row)
		if yank_pos != Vector2i(-1, -1):
			var pa = _parent.hex_to_pixel(u.disrupted_from.x, u.disrupted_from.y)
			var pb = _parent.hex_to_pixel(yank_pos.x, yank_pos.y)
			var disrupt_color = _v.disruption_color
			var seg_len = _v.disruption_seg_length * _parent.cam_zoom
			var total = pa.distance_to(pb)
			if total > 0:
				var ddir = (pb - pa).normalized()
				var perp2 = Vector2(-ddir.y, ddir.x)
				var steps = int(total / seg_len)
				for si in maxi(steps, 1):
					var t0 = float(si) / float(maxi(steps, 1))
					var t1 = float(si + 1) / float(maxi(steps, 1))
					var p0 = pa.lerp(pb, t0) + perp2 * (seg_len * (0.5 if si % 2 == 0 else -0.5))
					var p1 = pa.lerp(pb, t1) + perp2 * (seg_len * (0.5 if (si + 1) % 2 == 0 else -0.5))
					draw_line(p0, p1, disrupt_color, _v.disruption_x_width * _parent.cam_zoom)
			var r2 = _v.disruption_x_radius * _parent.cam_zoom
			draw_line(pa + Vector2(-r2, -r2), pa + Vector2(r2, r2), disrupt_color, _v.disruption_x_width * _parent.cam_zoom)
			draw_line(pa + Vector2(r2, -r2), pa + Vector2(-r2, r2), disrupt_color, _v.disruption_x_width * _parent.cam_zoom)
	# Snail trail ghost tokens with caterpillar taper — draw on all formation hexes
	var worm_alpha = _v.worm_alpha_preview if is_preview_unit else _v.worm_alpha
	for ti in (max_ti + 1):
		var pos = trail[ti]
		if pos == Vector2i(-1, -1): continue
		var form: Array = ftl[ti] if ti < ftl.size() else [pos]
		if ti != display_turn:
			for fh in form:
				var center = _parent.hex_to_pixel(fh.x, fh.y)
				_draw_unit_token(center, u.player, u.models, u.unit_type, true, worm_alpha, ti)
		if ti < max_ti:
			var next_pos = trail[ti + 1]
			if next_pos == Vector2i(-1, -1) or next_pos == pos: continue
			# Interpolation taper uses anchor-to-anchor
			var center = _parent.hex_to_pixel(pos.x, pos.y)
			var next_center = _parent.hex_to_pixel(next_pos.x, next_pos.y)
			for interp in [0.17, 0.33, 0.50, 0.67, 0.83]:
				var mid = center.lerp(next_center, interp)
				var interp_frame = ti if interp < 0.5 else ti + 1
				_draw_unit_token_scaled(mid, u.player, u.models, u.unit_type, worm_alpha * _v.interp_alpha_multiplier, _v.interp_token_scale, interp_frame)
	# Current-turn token — draw at all formation hexes
	var cur_idx = mini(display_turn, trail.size() - 1)
	if trail[cur_idx] != Vector2i(-1, -1):
		var cur_form: Array = ftl[cur_idx] if cur_idx < ftl.size() else [trail[cur_idx]]
		if u.eliminated and u.elim_turn <= display_turn - 1:
			for fh in cur_form:
				var center = _parent.hex_to_pixel(fh.x, fh.y)
				var r = _v.elim_cross_radius * _parent.cam_zoom
				draw_line(center + Vector2(-r, -r), center + Vector2(r, r),
					Color(_v.elim_cross_color.r, _v.elim_cross_color.g, _v.elim_cross_color.b, _v.elim_cross_alpha), _v.elim_cross_width)
				draw_line(center + Vector2(r, -r), center + Vector2(-r, r),
					Color(_v.elim_cross_color.r, _v.elim_cross_color.g, _v.elim_cross_color.b, _v.elim_cross_alpha), _v.elim_cross_width)
		else:
			for fh in cur_form:
				var center = _parent.hex_to_pixel(fh.x, fh.y)
				_draw_unit_token(center, u.player, u.models, u.unit_type, false, 1.0)

# ============================================================================
# SIM DRAWING  (main sim renderer — trails, tokens, combat)
# ============================================================================

func _draw_sim(sim: Dictionary, is_preview: bool):
	var timelines   : Array = sim.get("timelines", [])
	var formations_tl : Array = sim.get("formations_timeline", [])
	var final_units : Array = sim.get("units", [])
	var combat_ev   : Array = sim.get("combat", [])

	var display_turn = mini(_state.anim_turn, _parent.TURNS)
	var effective_mode = _state.view_mode if _state.phase == GameState.Phase.DEPLOY else GameState.ViewMode.FULL
	# Animation scan only in CLEAN mode; other modes show static snail trails
	var show_anim_scan = (effective_mode == GameState.ViewMode.CLEAN)

	# During preview, determine which units are affected by the placement
	var changed: Dictionary = _state.preview_diff.get("changed_uids", {}) if is_preview else {}

	# Fall back to CLEAN when CHANGED has no active preview
	if effective_mode == GameState.ViewMode.CHANGED and not is_preview:
		effective_mode = GameState.ViewMode.CLEAN

	# Which units get snail trails depends on view mode
	var show_timeline_for_uid := func(uid: int) -> bool:
		if effective_mode == GameState.ViewMode.FULL:
			return true  # all units
		if effective_mode == GameState.ViewMode.CHANGED:
			# Only preview unit gets team-colored trail; changed units use red/green diff only
			return is_preview and uid == timelines.size() - 1
		# CLEAN mode: only preview unit gets trail, others at final position
		if not is_preview: return false
		return uid == timelines.size() - 1

	# --- Hover trail highlight: bright glow on hovered unit's entire trail ---
	if _state.hover_trail_uid >= 0 and _state.hover_trail_uid < formations_tl.size():
		var hu = final_units[_state.hover_trail_uid]
		var h_ftl: Array = formations_tl[_state.hover_trail_uid]
		var h_trail: Array = timelines[_state.hover_trail_uid]
		var h_alive = hu.elim_turn if hu.eliminated else _parent.TURNS
		var h_max = mini(h_alive + 1, h_ftl.size() - 1)
		var h_color = _v.color_p1 if hu.player == 1 else _v.color_p2
		var glow = Color(h_color.r, h_color.g, h_color.b, _v.hover_glow_alpha)
		var outline_col = Color(1, 1, 1, _v.hover_outline_alpha)
		# Glow on all formation hexes — double pass for stronger effect
		for ti in (h_max + 1):
			var form: Array = h_ftl[ti] if ti < h_ftl.size() else []
			for fh in form:
				if fh == Vector2i(-1, -1): continue
				var hc = _parent.hex_to_pixel(fh.x, fh.y)
				var hcorners = _parent.hex_corners(hc)
				draw_colored_polygon(hcorners, glow)
				draw_polyline(hcorners + PackedVector2Array([hcorners[0]]), outline_col, _v.hover_outline_width)
		# Bright ribbon along trail
		var h_ribbon_w = _parent.HEX_SIZE * _v.ribbon_width_hover * _parent.cam_zoom
		for ti in h_max:
			var from_pos = h_trail[ti]
			var to_pos = h_trail[ti + 1]
			if from_pos == to_pos: continue
			if from_pos == Vector2i(-1, -1) or to_pos == Vector2i(-1, -1): continue
			var pa = _parent.hex_to_pixel(from_pos.x, from_pos.y)
			var pb = _parent.hex_to_pixel(to_pos.x, to_pos.y)
			var dir = (pb - pa).normalized()
			var perp = Vector2(-dir.y, dir.x) * h_ribbon_w
			var quad = PackedVector2Array([pa + perp, pa - perp, pb - perp, pb + perp])
			draw_colored_polygon(quad, Color(h_color.r, h_color.g, h_color.b, _v.hover_ribbon_alpha))

	# --- 0) Changed trail crossfade (CHANGED mode preview only) ---
	if is_preview and effective_mode == GameState.ViewMode.CHANGED and not changed.is_empty() and not _state.confirmed_sim.is_empty():
		var cycle = fmod(_state._diff_flash_time, _v.changed_cycle_duration)
		var old_blend: float
		if cycle < _v.changed_show_duration:
			old_blend = 1.0
		elif cycle < _v.changed_show_duration + _v.changed_fade_duration:
			var t = (cycle - _v.changed_show_duration) / _v.changed_fade_duration
			old_blend = 1.0 - t * t * (3.0 - 2.0 * t)
		elif cycle < _v.changed_cycle_duration - _v.changed_fade_duration:
			old_blend = 0.0
		else:
			var t = (cycle - (_v.changed_cycle_duration - _v.changed_fade_duration)) / _v.changed_fade_duration
			old_blend = t * t * (3.0 - 2.0 * t)
		var new_blend = 1.0 - old_blend
		var old_timelines: Array = _state.confirmed_sim.get("timelines", [])
		var old_units: Array = _state.confirmed_sim.get("units", [])
		var old_col = _v.changed_old_color
		var new_col = _v.changed_new_color
		for uid in changed:
			# Skip the preview unit itself (it has no "old" path)
			if uid >= old_timelines.size(): continue
			# OLD path (pale purple)
			if old_blend > 0.02:
				var ou = old_units[uid]
				var old_trail: Array = old_timelines[uid]
				var alive_until = ou.elim_turn if ou.eliminated else _parent.TURNS
				var max_ti = mini(alive_until + 1, old_trail.size() - 1)
				for ti in max_ti:
					var from_pos = old_trail[ti]
					var to_pos = old_trail[ti + 1]
					if from_pos == to_pos: continue
					if from_pos == Vector2i(-1, -1) or to_pos == Vector2i(-1, -1): continue
					var pa = _parent.hex_to_pixel(from_pos.x, from_pos.y)
					var pb = _parent.hex_to_pixel(to_pos.x, to_pos.y)
					var dir = (pb - pa).normalized()
					var perp = Vector2(-dir.y, dir.x) * _parent.HEX_SIZE * _v.changed_ribbon_width * _parent.cam_zoom
					var quad = PackedVector2Array([pa + perp, pa - perp, pb - perp, pb + perp])
					draw_colored_polygon(quad, Color(old_col.r, old_col.g, old_col.b, _v.changed_ribbon_alpha * old_blend))
				var old_ftl: Array = _state.confirmed_sim.get("formations_timeline", [])
				if uid < old_ftl.size():
					for ti in (max_ti + 1):
						var form: Array = old_ftl[uid][ti] if ti < old_ftl[uid].size() else []
						for fh in form:
							if fh == Vector2i(-1, -1): continue
							var hc = _parent.hex_to_pixel(fh.x, fh.y)
							var hcorners = _parent.hex_corners(hc)
							draw_colored_polygon(hcorners, Color(old_col.r, old_col.g, old_col.b, _v.changed_hex_alpha * old_blend))
							draw_polyline(hcorners + PackedVector2Array([hcorners[0]]), Color(old_col.r, old_col.g, old_col.b, _v.changed_ribbon_alpha * old_blend), 2.0)
			# NEW path (pale yellow)
			if new_blend > 0.02 and uid < timelines.size():
				var new_trail: Array = timelines[uid]
				var nu = final_units[uid]
				var new_alive = nu.elim_turn if nu.eliminated else _parent.TURNS
				var new_max = mini(new_alive + 1, new_trail.size() - 1)
				for ti in new_max:
					var from_pos = new_trail[ti]
					var to_pos = new_trail[ti + 1]
					if from_pos == to_pos: continue
					if from_pos == Vector2i(-1, -1) or to_pos == Vector2i(-1, -1): continue
					var pa = _parent.hex_to_pixel(from_pos.x, from_pos.y)
					var pb = _parent.hex_to_pixel(to_pos.x, to_pos.y)
					var dir = (pb - pa).normalized()
					var perp = Vector2(-dir.y, dir.x) * _parent.HEX_SIZE * _v.changed_ribbon_width * _parent.cam_zoom
					var quad = PackedVector2Array([pa + perp, pa - perp, pb - perp, pb + perp])
					draw_colored_polygon(quad, Color(new_col.r, new_col.g, new_col.b, _v.changed_ribbon_alpha * new_blend))
				if uid < formations_tl.size():
					for ti in (new_max + 1):
						var form: Array = formations_tl[uid][ti] if ti < formations_tl[uid].size() else []
						for fh in form:
							if fh == Vector2i(-1, -1): continue
							var hc = _parent.hex_to_pixel(fh.x, fh.y)
							var hcorners = _parent.hex_corners(hc)
							draw_colored_polygon(hcorners, Color(new_col.r, new_col.g, new_col.b, _v.changed_hex_alpha * new_blend))
							draw_polyline(hcorners + PackedVector2Array([hcorners[0]]), Color(new_col.r, new_col.g, new_col.b, _v.changed_ribbon_alpha * new_blend), 2.0)
		# Phase label tooltip — "WITHOUT" / "WITH UNIT" follows cursor
		var cw_font = ThemeDB.fallback_font
		var cw_fs = 15
		var cw_pad = 8
		var cw_text = ""
		var cw_col = Color.WHITE
		var cw_a = 0.0
		if old_blend >= new_blend:
			cw_a = clampf(old_blend * 1.5, 0.0, 1.0)
			cw_text = "WITHOUT"
			cw_col = old_col
		else:
			cw_a = clampf(new_blend * 1.5, 0.0, 1.0)
			cw_text = "WITH UNIT"
			cw_col = new_col
		if cw_a > 0.05:
			var cw_tw = cw_font.get_string_size(cw_text, HORIZONTAL_ALIGNMENT_LEFT, -1, cw_fs).x + cw_pad * 2
			var cw_th = 20 + cw_pad * 2
			var cw_vp = get_viewport_rect().size
			var cw_x = _state._mouse_pos.x + 20
			var cw_y = _state._mouse_pos.y - cw_th - 45
			if cw_x + cw_tw > cw_vp.x - 10:
				cw_x = _state._mouse_pos.x - cw_tw - 10
			if cw_y < 10:
				cw_y = _state._mouse_pos.y + 60
			draw_rect(Rect2(cw_x, cw_y, cw_tw, cw_th), Color(0.05, 0.05, 0.1, 0.85 * cw_a))
			draw_rect(Rect2(cw_x, cw_y, cw_tw, cw_th), Color(cw_col.r, cw_col.g, cw_col.b, 0.6 * cw_a), false, 2.0)
			draw_string(cw_font, Vector2(cw_x + cw_pad, cw_y + cw_pad + 13), cw_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, cw_fs, Color(cw_col.r, cw_col.g, cw_col.b, cw_a))

	# --- 0b) Draw units without timelines at their final position ---
	var fog_mode = (effective_mode == GameState.ViewMode.CHANGED and is_preview)
	for uid in timelines.size():
		if show_timeline_for_uid.call(uid): continue
		_draw_unit_final(uid, final_units, timelines, formations_tl, fog_mode, 0.20 if fog_mode else 1.0)

	# --- 1) Highlight path hexes for each unit (all formation hexes) ---
	for uid in timelines.size():
		if not show_timeline_for_uid.call(uid): continue
		var u    = final_units[uid]
		var trail: Array = timelines[uid]
		var ftl: Array = formations_tl[uid] if uid < formations_tl.size() else []
		var alive_until = u.elim_turn if u.eliminated else _parent.TURNS
		var max_ti = mini(alive_until + 1, trail.size() - 1)
		var is_preview_unit = (is_preview and uid == timelines.size() - 1)
		var base = _v.color_p1 if u.player == 1 else _v.color_p2
		var highlight_a = _v.highlight_alpha_preview if is_preview_unit else _v.highlight_alpha
		if effective_mode == GameState.ViewMode.CHANGED: highlight_a = _v.highlight_alpha_changed

		for ti in (max_ti + 1):
			var pos = trail[ti]
			if pos == Vector2i(-1, -1): continue
			var form: Array = ftl[ti] if ti < ftl.size() else [pos]
			for fh in form:
				var hc = _parent.hex_to_pixel(fh.x, fh.y)
				var hcorners = _parent.hex_corners(hc)
				draw_colored_polygon(hcorners, Color(base.r, base.g, base.b, highlight_a))

	# --- 2) Draw path connections ---
	for uid in timelines.size():
		if not show_timeline_for_uid.call(uid): continue
		var u    = final_units[uid]
		var trail: Array = timelines[uid]
		var alive_until = u.elim_turn if u.eliminated else _parent.TURNS
		var max_ti = mini(alive_until + 1, trail.size() - 1)
		var is_preview_unit = (is_preview and uid == timelines.size() - 1)
		var base = _v.color_p1 if u.player == 1 else _v.color_p2

		# Snail trail: filled ribbon between consecutive positions
		var ribbon_w = _parent.HEX_SIZE * (_v.ribbon_width_preview if is_preview_unit else _v.ribbon_width) * _parent.cam_zoom
		var ribbon_a = _v.ribbon_alpha_preview if is_preview_unit else _v.ribbon_alpha
		if effective_mode == GameState.ViewMode.CHANGED:
			ribbon_a = _v.ribbon_alpha_changed
			ribbon_w = _parent.HEX_SIZE * _v.ribbon_width_changed * _parent.cam_zoom
		# Check if this unit was disrupted (for visual break in ribbon)
		var is_disrupted = u.disrupted and u.disrupted_turn >= 0
		var disrupt_ti = (u.disrupted_turn + 1) if is_disrupted else -1
		for ti in max_ti:
			var from_pos = trail[ti]
			var to_pos   = trail[ti + 1]
			if from_pos == to_pos: continue
			if from_pos == Vector2i(-1, -1) or to_pos == Vector2i(-1, -1): continue
			if is_disrupted and ti == disrupt_ti:
				continue
			var pa = _parent.hex_to_pixel(from_pos.x, from_pos.y)
			var pb = _parent.hex_to_pixel(to_pos.x, to_pos.y)
			var dir = (pb - pa).normalized()
			var perp = Vector2(-dir.y, dir.x) * ribbon_w
			var quad = PackedVector2Array([
				pa + perp, pa - perp, pb - perp, pb + perp
			])
			draw_colored_polygon(quad, Color(base.r, base.g, base.b, ribbon_a))

		# Draw disruption break: dashed line from old position to yanked position
		if is_disrupted and u.disrupted_from != Vector2i(-1, -1) and disrupt_ti < trail.size():
			var yank_pos = trail[disrupt_ti] if disrupt_ti < trail.size() else Vector2i(u.col, u.row)
			if yank_pos != Vector2i(-1, -1):
				var pa = _parent.hex_to_pixel(u.disrupted_from.x, u.disrupted_from.y)
				var pb = _parent.hex_to_pixel(yank_pos.x, yank_pos.y)
				var disrupt_color = _v.disruption_color
				var seg_len = _v.disruption_seg_length * _parent.cam_zoom
				var total = pa.distance_to(pb)
				if total > 0:
					var dir = (pb - pa).normalized()
					var perp = Vector2(-dir.y, dir.x)
					var steps = int(total / seg_len)
					for si in maxi(steps, 1):
						var t0 = float(si) / float(maxi(steps, 1))
						var t1 = float(si + 1) / float(maxi(steps, 1))
						var p0 = pa.lerp(pb, t0) + perp * (seg_len * (0.5 if si % 2 == 0 else -0.5))
						var p1 = pa.lerp(pb, t1) + perp * (seg_len * (0.5 if (si + 1) % 2 == 0 else -0.5))
						draw_line(p0, p1, disrupt_color, _v.disruption_x_width * _parent.cam_zoom)
				var r = _v.disruption_x_radius * _parent.cam_zoom
				draw_line(pa + Vector2(-r, -r), pa + Vector2(r, r), disrupt_color, _v.disruption_x_width * _parent.cam_zoom)
				draw_line(pa + Vector2(r, -r), pa + Vector2(-r, r), disrupt_color, _v.disruption_x_width * _parent.cam_zoom)

	# --- 3) Ghost tokens at each turn position (all formation hexes) ---
	for uid in timelines.size():
		if not show_timeline_for_uid.call(uid): continue
		var u    = final_units[uid]
		var trail: Array = timelines[uid]
		var ftl: Array = formations_tl[uid] if uid < formations_tl.size() else []
		var alive_until = u.elim_turn if u.eliminated else _parent.TURNS
		var max_ti = mini(alive_until + 1, trail.size() - 1)
		var is_preview_unit = (is_preview and uid == timelines.size() - 1)

		var worm_alpha = _v.worm_alpha_preview if is_preview_unit else _v.worm_alpha
		if effective_mode == GameState.ViewMode.CHANGED: worm_alpha = _v.worm_alpha_changed
		for ti in (max_ti + 1):
			var pos = trail[ti]
			if pos == Vector2i(-1, -1): continue
			if show_anim_scan and ti == display_turn: continue
			var form: Array = ftl[ti] if ti < ftl.size() else [pos]
			for fh in form:
				var center = _parent.hex_to_pixel(fh.x, fh.y)
				_draw_unit_token(center, u.player, u.models, u.unit_type, true, worm_alpha, ti)
			if ti < max_ti:
				var next_pos = trail[ti + 1]
				if next_pos == Vector2i(-1, -1) or next_pos == pos: continue
				var anchor_center = _parent.hex_to_pixel(pos.x, pos.y)
				var next_center = _parent.hex_to_pixel(next_pos.x, next_pos.y)
				for interp in [0.17, 0.33, 0.50, 0.67, 0.83]:
					var mid = anchor_center.lerp(next_center, interp)
					var interp_frame = ti if interp < 0.5 else ti + 1
					_draw_unit_token_scaled(mid, u.player, u.models, u.unit_type, worm_alpha * _v.interp_alpha_multiplier, _v.interp_token_scale, interp_frame)

	if show_anim_scan:
		# --- 4) Combat sparks (only in CLEAN mode with animation) ---
		for t in display_turn:
			if t >= combat_ev.size(): break
			for ev in combat_ev[t]:
				var aid = ev.get("a", -1)
				var eid = ev.get("b", -1)
				var show_spark = false
				if aid >= 0 and show_timeline_for_uid.call(aid): show_spark = true
				if eid >= 0 and show_timeline_for_uid.call(eid): show_spark = true
				if not show_spark: continue
				var ac = _parent.hex_to_pixel(ev.ac, ev.ar)
				var bc = _parent.hex_to_pixel(ev.bc, ev.br)
				var mid_pt = (ac + bc) * 0.5
				draw_circle(mid_pt, _v.combat_aura_radius * _parent.cam_zoom, Color(_v.color_combat.r, _v.color_combat.g, _v.color_combat.b, _v.combat_aura_alpha))
				_draw_swords(mid_pt)

		# --- 5) Current-turn tokens on top (at formation hexes) ---
		for uid in timelines.size():
			if not show_timeline_for_uid.call(uid): continue
			var trail: Array = timelines[uid]
			var ftl: Array = formations_tl[uid] if uid < formations_tl.size() else []
			var u     = final_units[uid]
			var cur_idx  = mini(display_turn, trail.size() - 1)

			if trail[cur_idx] == Vector2i(-1, -1): continue

			var cur_form: Array = ftl[cur_idx] if cur_idx < ftl.size() else [trail[cur_idx]]

			if u.eliminated and u.elim_turn <= display_turn - 1:
				for fh in cur_form:
					var center = _parent.hex_to_pixel(fh.x, fh.y)
					var r = _v.elim_cross_radius * _parent.cam_zoom
					draw_line(center + Vector2(-r, -r), center + Vector2(r, r),
						Color(_v.elim_cross_color.r, _v.elim_cross_color.g, _v.elim_cross_color.b, _v.elim_cross_alpha), _v.elim_cross_width)
					draw_line(center + Vector2(r, -r), center + Vector2(-r, r),
						Color(_v.elim_cross_color.r, _v.elim_cross_color.g, _v.elim_cross_color.b, _v.elim_cross_alpha), _v.elim_cross_width)
				continue
			for fh in cur_form:
				var center = _parent.hex_to_pixel(fh.x, fh.y)
				_draw_unit_token(center, u.player, u.models, u.unit_type, false, 1.0)

	# --- 6) Fate icons during preview (sword/death/survival) ---
	if is_preview and not _state.preview_diff.is_empty():
		var fate_changes: Array = _state.preview_diff.get("fate_changes", [])
		var icon_size = _parent.HEX_SIZE * _v.fate_icon_scale * _parent.cam_zoom
		for fc in fate_changes:
			var uid_fc: int = fc.uid
			if uid_fc >= timelines.size(): continue
			var u_fc = final_units[uid_fc]
			var trail_fc: Array = timelines[uid_fc]
			var final_pos = Vector2i(-1, -1)
			if u_fc.eliminated:
				var et = mini(u_fc.elim_turn, trail_fc.size() - 1)
				final_pos = trail_fc[et]
			else:
				final_pos = trail_fc[trail_fc.size() - 1]
			if final_pos == Vector2i(-1, -1): continue
			var center = _parent.hex_to_pixel(final_pos.x, final_pos.y)
			var team_tint = _v.color_p1 if u_fc.player == 1 else _v.color_p2
			if fc.fate == "now_dies" and _parent._icon_death:
				var death_off = _v.death_icon_offset * icon_size
				var death_rect = Rect2(center + death_off - Vector2(icon_size * 0.5, icon_size * 0.5), Vector2(icon_size, icon_size))
				draw_texture_rect(_parent._icon_death, death_rect, false, team_tint)
			elif fc.fate == "now_survives" and _parent._icon_survive:
				var surv_off = _v.survival_icon_offset * icon_size
				var surv_rect = Rect2(center + surv_off - Vector2(icon_size * 0.5, icon_size * 0.5), Vector2(icon_size, icon_size))
				draw_texture_rect(_parent._icon_survive, surv_rect, false, team_tint)
		# Sword icons for combat victories
		for uid_s in timelines.size():
			var u_s = final_units[uid_s]
			if u_s.eliminated: continue
			var trail_s: Array = timelines[uid_s]
			var final_pos_s = trail_s[trail_s.size() - 1]
			if final_pos_s == Vector2i(-1, -1): continue
			var has_kill = false
			for uid_e in timelines.size():
				var ue = final_units[uid_e]
				if ue.player == u_s.player: continue
				if not ue.eliminated: continue
				var elim_pos = timelines[uid_e][mini(ue.elim_turn, timelines[uid_e].size() - 1)]
				if elim_pos == Vector2i(-1, -1): continue
				var dist = _parent.hex_dist(final_pos_s.x, final_pos_s.y, elim_pos.x, elim_pos.y)
				if dist <= _parent.COMBAT_RANGE + 2:
					has_kill = true
					break
			if has_kill and _parent._icon_sword:
				var center_s = _parent.hex_to_pixel(final_pos_s.x, final_pos_s.y)
				var s_off = _v.sword_icon_offset * icon_size
				var sword_rect = Rect2(center_s + s_off, Vector2(icon_size, icon_size))
				var team_color = _v.color_p1 if u_s.player == 1 else _v.color_p2
				draw_texture_rect(_parent._icon_sword, sword_rect, false, team_color)

# ============================================================================
# DRAW HELPERS
# ============================================================================

func _draw_unit_token(center: Vector2, player: int, models: int, unit_type: String, is_ghost: bool, alpha: float, fixed_frame: int = -1):
	var a = alpha * (_v.ghost_alpha_multiplier if is_ghost else 1.0)
	var has_sprite = _parent.unit_sprites.has(player) and _parent.unit_sprites[player].has(unit_type)
	if has_sprite:
		var tex: Texture2D = _parent.unit_sprites[player][unit_type]["idle"]
		var info = _parent.SPRITE_FRAMES.get(unit_type, {"idle": 1, "size": 192})
		var frame_size = info["size"]
		var frame_count = info["idle"]
		var frame_idx: int
		if fixed_frame >= 0:
			frame_idx = fixed_frame % frame_count
		else:
			var anim_speed = _v.sprite_anim_speed
			frame_idx = int(fmod(_state.anim_turn * anim_speed * _parent.TURN_DURATION + _state.anim_frac * anim_speed * _parent.TURN_DURATION, frame_count))
		frame_idx = clampi(frame_idx, 0, frame_count - 1)
		var src_rect = Rect2(frame_idx * frame_size, 0, frame_size, frame_size)
		var draw_size = _parent.HEX_SIZE * _v.sprite_draw_scale * _parent.cam_zoom * (frame_size / 192.0)
		var dest_rect = Rect2(center - Vector2(draw_size * 0.5, draw_size * 0.6), Vector2(draw_size, draw_size))
		draw_texture_rect_region(tex, dest_rect, src_rect, Color(1, 1, 1, a))
	else:
		var base = _v.color_p1 if player == 1 else _v.color_p2
		var s = _parent.HEX_SIZE * _v.token_fallback_scale * _parent.cam_zoom
		var col = Color(base.r, base.g, base.b, a)
		var segments = 16
		var circle_pts = PackedVector2Array()
		for i in segments:
			var ang = i * TAU / segments
			circle_pts.append(center + Vector2(cos(ang), sin(ang)) * s)
		draw_colored_polygon(circle_pts, col)

	if not is_ghost and _parent.cam_zoom >= 0.5:
		var font = ThemeDB.fallback_font
		draw_string(font, center + Vector2(-5, 5), str(models),
			HORIZONTAL_ALIGNMENT_LEFT, -1, _v.model_count_font_size, Color(1, 1, 1, a))

func _draw_unit_token_scaled(center: Vector2, player: int, models: int, unit_type: String, alpha: float, scale_factor: float, fixed_frame: int = -1):
	var a = alpha * _v.ghost_alpha_multiplier
	var has_sprite = _parent.unit_sprites.has(player) and _parent.unit_sprites[player].has(unit_type)
	if has_sprite:
		var tex: Texture2D = _parent.unit_sprites[player][unit_type]["idle"]
		var info = _parent.SPRITE_FRAMES.get(unit_type, {"idle": 1, "size": 192})
		var frame_size = info["size"]
		var frame_count = info["idle"]
		var frame_idx = (fixed_frame % frame_count) if fixed_frame >= 0 else 0
		frame_idx = clampi(frame_idx, 0, frame_count - 1)
		var src_rect = Rect2(frame_idx * frame_size, 0, frame_size, frame_size)
		var draw_size = _parent.HEX_SIZE * _v.sprite_draw_scale * _parent.cam_zoom * scale_factor * (frame_size / 192.0)
		var dest_rect = Rect2(center - Vector2(draw_size * 0.5, draw_size * 0.6), Vector2(draw_size, draw_size))
		draw_texture_rect_region(tex, dest_rect, src_rect, Color(1, 1, 1, a))
	else:
		var base = _v.color_p1 if player == 1 else _v.color_p2
		var s = _parent.HEX_SIZE * _v.token_fallback_scale * _parent.cam_zoom * scale_factor
		var col = Color(base.r, base.g, base.b, a)
		var segments = 16
		var circle_pts = PackedVector2Array()
		for i in segments:
			var ang = i * TAU / segments
			circle_pts.append(center + Vector2(cos(ang), sin(ang)) * s)
		draw_colored_polygon(circle_pts, col)

func _draw_banner(center: Vector2, idx: int):
	var sc = _parent.cam_zoom
	var pole_top = center + Vector2(0, -_parent.HEX_SIZE * sc * _v.banner_top_offset)
	var pole_bot = center + Vector2(0,  _parent.HEX_SIZE * sc * _v.banner_bottom_offset)
	draw_line(pole_bot, pole_top, _v.banner_pole_color, _v.banner_pole_width * sc)
	var fw = _parent.HEX_SIZE * sc * _v.flag_width
	var fh = _parent.HEX_SIZE * sc * _v.flag_height
	var ft = pole_top + Vector2(0, fh * 0.05)
	draw_colored_polygon(PackedVector2Array([
		ft, ft + Vector2(fw, fh * 0.5), ft + Vector2(0, fh),
	]), _v.flag_colors[idx % _v.flag_colors.size()])

func _draw_swords(center: Vector2):
	var r = _v.sword_radius * _parent.cam_zoom
	for sign_val in [-1.0, 1.0]:
		var angle = sign_val * PI / 4.0
		var dir   = Vector2(cos(angle), sin(angle))
		var perp  = Vector2(-dir.y, dir.x)
		draw_line(center - dir * r, center + dir * r, _v.color_sword, _v.sword_main_width)
		draw_line(center + dir * r * 0.3 - perp * r * 0.4,
			center + dir * r * 0.3 + perp * r * 0.4, _v.color_sword.darkened(_v.sword_darken), _v.sword_cross_width)

# ============================================================================
# FINAL STATE & REPLAY
# ============================================================================

func _draw_final_state(sim: Dictionary):
	if sim.is_empty():
		return
	var timelines: Array = sim.get("timelines", [])
	var formations_tl: Array = sim.get("formations_timeline", [])
	var final_units: Array = sim.get("units", [])

	# Draw hex grid with final objective control (obj_control set in _process)
	for r in _parent.ROWS:
		for c in _parent.COLS:
			_draw_tile(c, r)

	# Draw all units at their final positions (using formation data)
	for uid in timelines.size():
		_draw_unit_final(uid, final_units, timelines, formations_tl, false, 1.0)

	# Draw preview unit's full timeline on top so player sees their unit's path
	var is_preview = (not _state.preview_sim.is_empty()) and sim == _state.preview_sim
	if is_preview and timelines.size() > 0:
		var puid = timelines.size() - 1
		var combat_ev: Array = sim.get("combat", [])
		var display_turn = mini(_state.anim_turn, _parent.TURNS)
		_draw_single_timeline(puid, final_units, timelines, formations_tl, combat_ev, display_turn, true)

func _draw_replay():
	var sim = _state.confirmed_sim
	if sim.is_empty():
		return

	var timelines: Array = sim.get("timelines", [])
	var final_units: Array = sim.get("units", [])
	var snapshots: Array = sim.get("unit_snapshots", [])
	var vpt: Array = sim.get("vp_per_turn", [])

	if snapshots.is_empty():
		return

	# Draw hex grid (obj_control set in _process)
	for r in _parent.ROWS:
		for c in _parent.COLS:
			_draw_tile(c, r)

	# Draw only the units at their replay_turn position — no ghosts, no trails
	var snap: Array = snapshots[_state.replay_turn] if _state.replay_turn < snapshots.size() else []
	for uid in timelines.size():
		var u_snap = snap[uid] if uid < snap.size() else {}
		var is_elim = u_snap.get("eliminated", false)
		var models = u_snap.get("models", 0)
		var u = final_units[uid]
		var snap_form: Array = u_snap.get("formation", [])
		if snap_form.is_empty():
			var trail: Array = timelines[uid]
			var ti = mini(_state.replay_turn + 1, trail.size() - 1)
			var pos = trail[ti]
			if pos == Vector2i(-1, -1): continue
			snap_form = [pos]

		if is_elim:
			for fh in snap_form:
				var center = _parent.hex_to_pixel(fh.x, fh.y)
				var r = _v.elim_cross_radius * _parent.cam_zoom
				draw_line(center + Vector2(-r, -r), center + Vector2(r, r),
					Color(_v.elim_cross_color.r, _v.elim_cross_color.g, _v.elim_cross_color.b, _v.elim_cross_alpha), _v.elim_cross_width)
				draw_line(center + Vector2(r, -r), center + Vector2(-r, r),
					Color(_v.elim_cross_color.r, _v.elim_cross_color.g, _v.elim_cross_color.b, _v.elim_cross_alpha), _v.elim_cross_width)
			continue

		for fh in snap_form:
			var center = _parent.hex_to_pixel(fh.x, fh.y)
			_draw_unit_token(center, u.player, models, u.unit_type, false, 1.0)

	# Draw combat events for this turn
	var combat_ev: Array = sim.get("combat", [])
	if _state.replay_turn < combat_ev.size():
		for ev in combat_ev[_state.replay_turn]:
			var ac = _parent.hex_to_pixel(ev.ac, ev.ar)
			var bc = _parent.hex_to_pixel(ev.bc, ev.br)
			var mid = (ac + bc) * 0.5
			draw_circle(mid, _v.combat_aura_radius * _parent.cam_zoom, Color(_v.color_combat.r, _v.color_combat.g, _v.color_combat.b, _v.combat_aura_alpha_replay))
			_draw_swords(mid)

	# --- Replay HUD ---
	var font = ThemeDB.fallback_font
	var vp = get_viewport_rect().size

	# Top bar
	draw_rect(Rect2(0, 0, vp.x, 44), Color(0, 0, 0, 0.85))
	var score_txt = ""
	if _state.replay_turn < vpt.size():
		score_txt = "   |   VP: BLUE %d - RED %d" % [vpt[_state.replay_turn][0], vpt[_state.replay_turn][1]]
	var hud_txt = "REPLAY  —  Turn %d/%d   (Left/Right to navigate, Esc to exit)%s" % [_state.replay_turn + 1, _parent.TURNS, score_txt]
	draw_string(font, Vector2(14, 28), hud_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, _v.replay_hud_text)

	# Turn indicator bar
	draw_rect(Rect2(0, 44, vp.x, 4), _v.replay_bar_bg)
	var progress = float(_state.replay_turn + 1) / float(_parent.TURNS)
	draw_rect(Rect2(0, 38, vp.x * progress, 4), _v.color_combat)

	# Turn pips at bottom
	var pip_y = vp.y - 30
	var pip_w = 20.0
	var total_pip_w = pip_w * _parent.TURNS
	var pip_start = (vp.x - total_pip_w) / 2.0
	for t in _parent.TURNS:
		var px = pip_start + t * pip_w
		var is_active = (t == _state.replay_turn)
		var pip_col = _v.color_combat if is_active else _v.pip_inactive_color
		draw_rect(Rect2(px + 2, pip_y, pip_w - 4, 12), pip_col)
		draw_string(font, Vector2(px + 4, pip_y + 10), str(t + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.8) if is_active else Color(0.6, 0.6, 0.6))

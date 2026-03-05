class_name VisualConfig
extends Resource

# ============================================================================
# CORE COLORS
# ============================================================================

@export_group("Team Colors")
@export var color_p1: Color = Color(0.28, 0.58, 1.00, 1.0)
@export var color_p2: Color = Color(1.00, 0.35, 0.28, 1.0)

@export_group("World Colors")
@export var color_background: Color = Color(0.07, 0.10, 0.18, 1.0)
@export var color_hex_fill: Color = Color(0.11, 0.16, 0.26, 1.0)
@export var color_hex_stroke: Color = Color(0.20, 0.28, 0.42, 1.0)
@export var color_combat: Color = Color(1.00, 0.75, 0.10, 1.0)
@export var color_banner: Color = Color(0.85, 0.78, 0.32, 1.0)
@export var color_sword: Color = Color(0.80, 0.80, 0.85, 1.0)

# ============================================================================
# TRAIL RIBBON
# ============================================================================

@export_group("Trail Ribbon")
@export_range(0.0, 1.0) var ribbon_alpha: float = 0.6
@export_range(0.0, 1.0) var ribbon_alpha_preview: float = 0.5
@export_range(0.1, 2.0) var ribbon_width: float = 0.7
@export_range(0.1, 2.0) var ribbon_width_preview: float = 0.6
@export_range(0.0, 1.0) var ribbon_alpha_changed: float = 0.85
@export_range(0.1, 2.0) var ribbon_width_changed: float = 0.85
@export_range(0.1, 3.0) var ribbon_width_hover: float = 1.1

# ============================================================================
# GHOST / WORM TOKENS
# ============================================================================

@export_group("Ghost Tokens")
@export_range(0.0, 1.0) var worm_alpha: float = 0.85
@export_range(0.0, 1.0) var worm_alpha_preview: float = 0.75
@export_range(0.0, 1.0) var worm_alpha_changed: float = 0.95
@export_range(0.0, 1.0) var ghost_alpha_multiplier: float = 0.60
@export_range(0.1, 2.0) var interp_token_scale: float = 0.7
@export_range(0.0, 1.0) var interp_alpha_multiplier: float = 0.85

# ============================================================================
# DISRUPTION VISUALS
# ============================================================================

@export_group("Disruption")
@export var disruption_color: Color = Color(0.8, 0.2, 1.0, 0.9)
@export_range(1.0, 20.0) var disruption_seg_length: float = 6.0
@export_range(1.0, 30.0) var disruption_x_radius: float = 10.0
@export_range(0.5, 5.0) var disruption_x_width: float = 2.5

# ============================================================================
# PATH HIGHLIGHTS
# ============================================================================

@export_group("Path Highlights")
@export_range(0.0, 1.0) var highlight_alpha: float = 0.30
@export_range(0.0, 1.0) var highlight_alpha_preview: float = 0.25
@export_range(0.0, 1.0) var highlight_alpha_changed: float = 0.50

@export_subgroup("Hover")
@export_range(0.0, 1.0) var hover_glow_alpha: float = 0.85
@export_range(0.0, 1.0) var hover_outline_alpha: float = 0.9
@export_range(0.5, 10.0) var hover_outline_width: float = 4.0
@export_range(0.0, 1.0) var hover_ribbon_alpha: float = 0.7

# ============================================================================
# DEPLOY ZONE & MAP OVERLAYS
# ============================================================================

@export_group("Deploy & Overlays")
@export_subgroup("Deploy Zones")
@export_range(0.0, 1.0) var deploy_zone_alpha_active: float = 0.30
@export_range(0.0, 1.0) var deploy_zone_alpha_inactive: float = 0.10

@export_subgroup("Objectives")
@export_range(0.0, 1.0) var objective_zone_alpha: float = 0.25
@export_range(0.0, 1.0) var objective_hex_alpha: float = 0.45
@export var objective_flip_glow: Color = Color(1.0, 0.9, 0.2, 0.15)

@export_subgroup("Heatmap")
@export var heatmap_positive_color: Color = Color(0.15, 1.0, 0.25, 1.0)
@export var heatmap_negative_color: Color = Color(1.0, 0.15, 0.15, 1.0)
@export_range(0.0, 1.0) var heatmap_min_intensity: float = 0.08
@export_range(0.0, 1.0) var heatmap_max_intensity: float = 0.7

@export_subgroup("Deep Strike")
@export var ds_legal_color: Color = Color(0.2, 0.8, 0.8, 0.12)
@export var ds_illegal_color: Color = Color(0.8, 0.2, 0.2, 0.05)

@export_subgroup("Hover Hex")
@export var hover_hex_color: Color = Color(1.0, 1.0, 1.0, 0.20)

# ============================================================================
# CHANGED MODE CROSSFADE
# ============================================================================

@export_group("Changed Mode")
@export_range(0.0, 1.0) var changed_fog_alpha: float = 0.70
@export_range(1.0, 10.0, 0.5) var changed_cycle_duration: float = 4.0
@export_range(0.1, 5.0, 0.1) var changed_show_duration: float = 1.5
@export_range(0.1, 2.0, 0.1) var changed_fade_duration: float = 0.5
@export var changed_old_color: Color = Color(0.75, 0.55, 0.95, 1.0)
@export var changed_new_color: Color = Color(1.0, 0.95, 0.45, 1.0)
@export_range(0.0, 1.0) var changed_ribbon_alpha: float = 0.80
@export_range(0.0, 1.0) var changed_hex_alpha: float = 0.55
@export_range(0.1, 2.0) var changed_ribbon_width: float = 0.9

# ============================================================================
# TERRAIN RENDERING
# ============================================================================

@export_group("Terrain")
@export_range(0.0, 1.0) var terrain_tint_alpha: float = 0.35
@export var forest_outline_color: Color = Color(0.2, 0.5, 0.2, 1.0)
@export var water_outline_color: Color = Color(0.2, 0.4, 0.7, 1.0)
@export_range(0.5, 5.0) var terrain_outline_width: float = 2.5
@export_range(0.0, 1.0) var hex_stroke_alpha: float = 0.5

# ============================================================================
# ELIMINATION CROSS
# ============================================================================

@export_group("Elimination")
@export var elim_cross_color: Color = Color(0.9, 0.2, 0.2, 1.0)
@export_range(1.0, 20.0) var elim_cross_radius: float = 8.0
@export_range(0.5, 5.0) var elim_cross_width: float = 2.5
@export_range(0.0, 1.0) var elim_cross_alpha: float = 0.7
@export_range(0.0, 1.0) var elim_cross_alpha_ghost: float = 0.35

# ============================================================================
# COMBAT AURA
# ============================================================================

@export_group("Combat Aura")
@export_range(1.0, 30.0) var combat_aura_radius: float = 14.0
@export_range(0.0, 1.0) var combat_aura_alpha: float = 0.20
@export_range(0.0, 1.0) var combat_aura_alpha_replay: float = 0.35

# ============================================================================
# BANNERS & FLAGS
# ============================================================================

@export_group("Banners")
@export var banner_pole_color: Color = Color(0.55, 0.45, 0.30, 1.0)
@export_range(0.5, 5.0) var banner_pole_width: float = 1.5
@export_range(0.5, 3.0) var banner_top_offset: float = 1.1
@export_range(0.1, 1.0) var banner_bottom_offset: float = 0.3
@export_range(0.1, 2.0) var flag_width: float = 0.5
@export_range(0.1, 2.0) var flag_height: float = 0.5
@export var flag_colors: Array[Color] = [
	Color(0.85, 0.72, 0.18, 1.0),
	Color(0.72, 0.28, 0.14, 1.0),
	Color(0.18, 0.55, 0.28, 1.0),
]

# ============================================================================
# SPRITE & TOKEN DRAWING
# ============================================================================

@export_group("Sprites & Tokens")
@export_range(1.0, 30.0) var sprite_anim_speed: float = 8.0
@export_range(1.0, 10.0) var sprite_draw_scale: float = 4.3
@export_range(0.1, 2.0) var token_fallback_scale: float = 0.55
@export_range(6, 30) var model_count_font_size: int = 13

# ============================================================================
# FATE ICONS
# ============================================================================

@export_group("Fate Icons")
@export_range(0.5, 5.0) var fate_icon_scale: float = 2.5
@export var death_icon_offset: Vector2 = Vector2(0.5, -0.3)
@export var survival_icon_offset: Vector2 = Vector2(0.0, -1.0)
@export var sword_icon_offset: Vector2 = Vector2(-0.6, -0.8)

# ============================================================================
# SWORD ICON
# ============================================================================

@export_group("Sword Icon")
@export_range(1.0, 20.0) var sword_radius: float = 9.0
@export_range(0.5, 5.0) var sword_main_width: float = 2.0
@export_range(0.5, 5.0) var sword_cross_width: float = 1.5
@export_range(0.0, 1.0) var sword_darken: float = 0.2

# ============================================================================
# ANIMATION TIMING
# ============================================================================

@export_group("Animation")
@export_range(0.1, 2.0, 0.1, "suffix:s") var full_mode_speed: float = 0.3
@export_range(0.1, 2.0, 0.1, "suffix:s") var shift_pulse_period: float = 0.6
@export_range(0.0, 2.0, 0.1) var shift_pulse_amplitude: float = 0.5

# ============================================================================
# REPLAY HUD
# ============================================================================

@export_group("Replay HUD")
@export var replay_bar_bg: Color = Color(0.15, 0.14, 0.12, 1.0)
@export var replay_hud_text: Color = Color(0.95, 0.85, 0.3, 1.0)
@export var pip_inactive_color: Color = Color(0.3, 0.3, 0.3, 0.6)

# ============================================================================
# HUD PANELS
# ============================================================================

@export_group("HUD")
@export var hud_bg_color: Color = Color(0.0, 0.0, 0.0, 0.75)
@export var hud_text_color: Color = Color(0.88, 0.88, 0.88, 1.0)
@export var hud_text_size: int = 18
@export var view_mode_active_color: Color = Color(1.0, 0.9, 0.3, 1.0)
@export var view_mode_inactive_color: Color = Color(0.5, 0.5, 0.5, 1.0)
@export var replay_btn_bg: Color = Color(0.85, 0.75, 0.2, 0.9)
@export var replay_btn_text: Color = Color(0.1, 0.1, 0.1, 1.0)
@export var summary_btn_bg: Color = Color(0.2, 0.55, 0.85, 0.9)
@export var summary_btn_text: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var btn_border_color: Color = Color(1.0, 1.0, 1.0, 0.4)
@export_range(0.5, 5.0) var btn_border_width: float = 1.5

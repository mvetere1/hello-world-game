class_name GameState
extends Node

# ============================================================================
# ENUMS
# ============================================================================

enum Phase { DEPLOY, DONE }
enum ViewMode { CLEAN, CHANGED, FULL, FINAL }

# ============================================================================
# SIGNALS
# ============================================================================

signal sim_changed()
signal phase_changed(new_phase: int)
signal hover_changed(hex: Vector2i)
signal view_mode_changed(mode: int)
signal unit_placed(uid: int)
signal replay_changed(turn: int)

# ============================================================================
# CORE STATE
# ============================================================================

var phase = Phase.DEPLOY
var view_mode = ViewMode.CLEAN
var active_player = 1
var deploy_unit_type := "infantry"
var selecting_unit := true

var placed_p1: Array = []
var placed_p2: Array = []

# ============================================================================
# DEEP STRIKE DEPLOYMENT
# ============================================================================

var ds_selecting_turn := false
var ds_arrival_turn := -1
var ds_legal_hexes := {}
var ds_pending_hex := Vector2i(-1, -1)

# ============================================================================
# SIMULATION RESULTS
# ============================================================================

var confirmed_sim := {}
var preview_sim := {}
var preview_diff := {}

# ============================================================================
# SHIFT SUMMARY POPUP
# ============================================================================

var showing_shift_summary := false
var shift_summary_lines: Array = []
var shift_summary_scroll := 0
var shift_summary_timer := 0.0
var shift_summary_diff := {}
var shift_old_sim := {}

# ============================================================================
# HOVER / CURSOR
# ============================================================================

var hover_hex := Vector2i(-1, -1)
var hover_trail_uid := -1
var _trail_hex_cache := {}
var _trail_hex_cache_ref: Dictionary
var _mouse_pos := Vector2.ZERO

# ============================================================================
# DEPLOY HEATMAP
# ============================================================================

var deploy_heatmap := {}
var _heatmap_queue: Array = []
var _heatmap_base_vp := 0
var _heatmap_base_units: Array = []
var _heatmap_min := 0
var _heatmap_max := 0
var _heatmap_enabled := false
var _deploy_blocked_cache: Dictionary = {}

# ============================================================================
# UI TOGGLES
# ============================================================================

var _log_visible := false
var show_analytics_ui := true

# ============================================================================
# ANIMATION
# ============================================================================

var anim_turn := 0
var anim_frac := 0.0
var _diff_flash_time := 0.0
var _obj_control: Array = []

# ============================================================================
# COMBAT LOG
# ============================================================================

var log_lines: Array = []

# ============================================================================
# REPLAY MODE
# ============================================================================

var replay_mode := false
var replay_turn := 0

# ============================================================================
# BATTLE SUMMARY
# ============================================================================

var show_summary := false
var summary_lines: Array = []
var summary_scroll: int = 0

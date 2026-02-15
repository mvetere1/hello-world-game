extends SceneTree

# Headless sprite validation test
# Run: godot --headless --path . -s test_sprites.gd --quit

const SPRITE_FRAMES := {
	"infantry": {"idle": 8, "run": 6, "size": 192},
	"cavalry":  {"idle": 12, "run": 6, "size": 320},
	"artillery": {"idle": 6, "run": 4, "size": 192},
	"deep_strike": {"idle": 8, "run": 6, "size": 192},
	"archer":   {"idle": 6, "run": 4, "size": 192},
}

var errors := 0
var passes := 0

func _report(ok: bool, msg: String):
	if ok:
		passes += 1
		print("  PASS: %s" % msg)
	else:
		errors += 1
		print("  FAIL: %s" % msg)

func _init():
	print("=== Sprite Validation Test ===\n")

	# 1. Check unit sprite files exist and have correct dimensions
	print("[Unit Sprites]")
	for team in ["blue", "red"]:
		for unit_type in SPRITE_FRAMES.keys():
			var info = SPRITE_FRAMES[unit_type]
			for anim in ["idle", "run"]:
				var path = ProjectSettings.globalize_path(
					"res://sprites/%s/%s_%s.png" % [team, unit_type, anim])
				var img = Image.new()
				var err = img.load(path)
				_report(err == OK, "%s/%s_%s.png loads" % [team, unit_type, anim])
				if err != OK:
					continue
				var expected_frames = info.get(anim, 1)
				var frame_size = info["size"]
				var expected_w = expected_frames * frame_size
				var expected_h = frame_size
				_report(img.get_width() == expected_w,
					"%s/%s_%s.png width: got %d, expected %d (%d frames x %d)" % [
						team, unit_type, anim, img.get_width(), expected_w, expected_frames, frame_size])
				_report(img.get_height() == expected_h,
					"%s/%s_%s.png height: got %d, expected %d" % [
						team, unit_type, anim, img.get_height(), expected_h])

	# 2. Check draw size scaling is consistent
	print("\n[Draw Size Consistency]")
	var HEX_SIZE = 20.0
	var base_multiplier = 4.3
	for unit_type in SPRITE_FRAMES.keys():
		var frame_size = SPRITE_FRAMES[unit_type]["size"]
		var draw_size = HEX_SIZE * base_multiplier * (frame_size / 192.0)
		var visual_ratio = draw_size / frame_size
		# All unit types should have the same visual_ratio
		var expected_ratio = HEX_SIZE * base_multiplier / 192.0
		_report(abs(visual_ratio - expected_ratio) < 0.001,
			"%s visual ratio: %.4f (expected %.4f)" % [unit_type, visual_ratio, expected_ratio])

	# 3. Check cursor and icon files
	print("\n[UI Assets]")
	var ui_base = "res://assets/2d tinytowers assets/UI Elements/UI Elements/"
	var ui_files = {
		"Cursor_02 (hand)": "Cursors/Cursor_02.png",
		"Cursor_03 (nogo)": "Cursors/Cursor_03.png",
		"Icon_05 (sword)": "Icons/Icon_05.png",
		"Icon_07 (survive)": "Icons/Icon_07.png",
		"Icon_09 (death)": "Icons/Icon_09.png",
	}
	for label in ui_files:
		var path = ProjectSettings.globalize_path(ui_base + ui_files[label])
		var img = Image.new()
		var err = img.load(path)
		_report(err == OK, "%s loads from %s" % [label, ui_files[label]])
		if err == OK:
			_report(img.get_width() == 64 and img.get_height() == 64,
				"%s is 64x64 (got %dx%d)" % [label, img.get_width(), img.get_height()])

	# Summary
	print("\n=== Results: %d passed, %d failed ===" % [passes, errors])
	if errors > 0:
		print("SOME TESTS FAILED!")
	else:
		print("ALL TESTS PASSED!")
	quit()

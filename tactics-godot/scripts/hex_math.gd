class_name HexMath
## Pure hex-grid math for flat-top odd-q offset coordinates.
## All functions are static — no instance state, no scene-tree dependency.

static var _grid: GridConfig = preload("res://resources/config/grid_config.tres")

# Flat-top odd-q offset neighbors (depend on whether col is even or odd)
const FLAT_DIRS_EVEN = [
	Vector2i( 1,  0), Vector2i(-1,  0),
	Vector2i( 0,  1), Vector2i( 0, -1),
	Vector2i( 1, -1), Vector2i(-1, -1),
]
const FLAT_DIRS_ODD = [
	Vector2i( 1,  0), Vector2i(-1,  0),
	Vector2i( 0,  1), Vector2i( 0, -1),
	Vector2i( 1,  1), Vector2i(-1,  1),
]

static func is_valid_hex(col: int, row: int) -> bool:
	return col >= 0 and col < _grid.cols and row >= 0 and row < _grid.rows

static func hex_id(col: int, row: int) -> int:
	return col * 1000 + row

static func id_to_hex(id: int) -> Vector2i:
	return Vector2i(id / 1000, id % 1000)

static func hex_neighbors(col: int, row: int) -> Array[Vector2i]:
	var dirs = FLAT_DIRS_ODD if (col & 1) else FLAT_DIRS_EVEN
	var result: Array[Vector2i] = []
	for d in dirs:
		var nc = col + d.x
		var nr = row + d.y
		if HexMath.is_valid_hex(nc, nr):
			result.append(Vector2i(nc, nr))
	return result

static func offset_to_cube(col: int, row: int) -> Vector3i:
	var q = col
	var r = row - (col - (col & 1)) / 2
	return Vector3i(q, r, -q - r)

static func hex_dist(c1: int, r1: int, c2: int, r2: int) -> int:
	var a = HexMath.offset_to_cube(c1, r1)
	var b = HexMath.offset_to_cube(c2, r2)
	return (abs(a.x - b.x) + abs(a.y - b.y) + abs(a.z - b.z)) / 2

static func compute_compact_cluster(anchor: Vector2i, size: int, blocked: Dictionary) -> Array[Vector2i]:
	if size <= 0:
		return []
	var result: Array[Vector2i] = [anchor]
	if size == 1:
		return result
	var used := {HexMath.hex_id(anchor.x, anchor.y): true}
	var frontier: Array[Vector2i] = [anchor]
	while result.size() < size and not frontier.is_empty():
		var candidates: Array[Vector2i] = []
		for fh in frontier:
			for nb in HexMath.hex_neighbors(fh.x, fh.y):
				var nid = HexMath.hex_id(nb.x, nb.y)
				if used.has(nid): continue
				if blocked.has(nid): continue
				if not HexMath.is_valid_hex(nb.x, nb.y): continue
				used[nid] = true
				candidates.append(nb)
		candidates.sort_custom(func(a, b):
			return HexMath.hex_dist(a.x, a.y, anchor.x, anchor.y) < HexMath.hex_dist(b.x, b.y, anchor.x, anchor.y)
		)
		var next_frontier: Array[Vector2i] = []
		for c in candidates:
			if result.size() >= size: break
			result.append(c)
			next_frontier.append(c)
		frontier = next_frontier
	return result

static func formation_dist(form_a: Array, form_b: Array) -> int:
	var best := 999999
	for ha in form_a:
		for hb in form_b:
			var d = HexMath.hex_dist(ha.x, ha.y, hb.x, hb.y)
			if d < best:
				best = d
				if d <= 1: return d
	return best

static func formation_dist_to_hex(formation: Array, target: Vector2i) -> int:
	var best := 999999
	for fh in formation:
		var d = HexMath.hex_dist(fh.x, fh.y, target.x, target.y)
		if d < best:
			best = d
			if d == 0: return 0
	return best

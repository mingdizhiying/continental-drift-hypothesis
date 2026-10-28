class_name TerritoryRules
extends RefCounted
## Double-precision geometry shared by rules and the displayed polygons.
## Vector2 is used only at the final rendering boundary, not in simulation.
const CELL = 64.0
const EPS = 0.0000001
const MASK = 0xffffffff
const SHAPES = {
	"I": [[0, 0], [1, 0], [2, 0], [3, 0]],
	"O": [[0, 0], [1, 0], [0, 1], [1, 1]],
	"T": [[0, 0], [1, 0], [2, 0], [1, 1]],
	"S": [[1, 0], [2, 0], [0, 1], [1, 1]],
	"Z": [[0, 0], [1, 0], [1, 1], [2, 1]],
	"J": [[0, 0], [0, 1], [1, 1], [2, 1]],
	"L": [[2, 0], [0, 1], [1, 1], [2, 1]]}
static var _cache: Dictionary = {}

class RandomStream:
	extends RefCounted
	var state: int
	func _init(seed: int) -> void:
		state = seed & 0xffffffff
	func next_float() -> float:
		state = (state + 0x6D2B79F5) & 0xffffffff
		var t = TerritoryRules.imul32(state ^ (state >> 15), state | 1)
		t = (t ^ ((t + TerritoryRules.imul32(t ^ (t >> 7), t | 61)) & 0xffffffff)) & 0xffffffff
		return float((t ^ (t >> 14)) & 0xffffffff) / 4294967296.0

static func imul32(a: int, b: int) -> int:
	# Split the product to avoid signed 64-bit overflow before the JS uint32 mask.
	return ((a & 65535) * (b & 65535) + (((a >> 16) * (b & 65535) + (a & 65535) * (b >> 16)) << 16)) & MASK

static func create_territory(rng: RandomStream) -> Dictionary:
	var shape = SHAPES.keys()[int(floor(rng.next_float() * 7))]
	var angle = rng.next_float() * 360.0
	var spin = (1.5 + rng.next_float() * 2.5) * (-1 if rng.next_float() < 0.5 else 1)
	return {"shape": shape, "angle": angle, "spin": spin}

static func polygons(c: Dictionary) -> Array:
	var blocks: Array = SHAPES[c.territory.shape]
	var cx = 0.0
	var cy = 0.0
	for b in blocks:
		cx += b[0] + 0.5
		cy += b[1] + 0.5
	cx /= 4.0
	cy /= 4.0
	var angle: float = c.territory.angle * PI / 180.0
	var cosine = cos(angle)
	var sine = sin(angle)
	var result: Array = []
	for b in blocks:
		var polygon: Array = []
		for corner in [[b[0], b[1]], [b[0] + 1, b[1]], [b[0] + 1, b[1] + 1], [b[0], b[1] + 1]]:
			var u: float = (corner[0] - cx) * CELL
			var v: float = (corner[1] - cy) * CELL
			polygon.append({"x": c.x + u * cosine - v * sine, "y": c.y + u * sine + v * cosine})
		result.append(polygon)
	return result

static func cross(a: Dictionary, b: Dictionary, p: Dictionary) -> float:
	return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)

static func intersection(subject: Array, clip: Array) -> Array:
	var out = subject
	for i in clip.size():
		var a = clip[i]
		var b = clip[(i + 1) % clip.size()]
		var input = out
		out = []
		for j in input.size():
			var p = input[j]
			var q = input[(j + 1) % input.size()]
			var cp = cross(a, b, p)
			var cq = cross(a, b, q)
			var ip = cp >= -EPS
			var iq = cq >= -EPS
			if ip:
				out.append(p)
			if ip != iq:
				var t = cp / (cp - cq)
				out.append({"x": p.x + (q.x - p.x) * t, "y": p.y + (q.y - p.y) * t})
	return out

static func area(polygon: Array) -> float:
	var total = 0.0
	for i in polygon.size():
		var a = polygon[i]
		var b = polygon[(i + 1) % polygon.size()]
		total += a.x * b.y - a.y * b.x
	return absf(total) / 2.0

static func point_segment(p: Dictionary, a: Dictionary, b: Dictionary) -> float:
	var dx: float = b.x - a.x
	var dy: float = b.y - a.y
	var t = clampf(((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy), 0.0, 1.0)
	return sqrt(pow(p.x - a.x - t * dx, 2) + pow(p.y - a.y - t * dy, 2))

static func relation(a: Dictionary, b: Dictionary) -> Dictionary:
	var key = [a.x, a.y, a.territory.shape, a.territory.angle, b.x, b.y, b.territory.shape, b.territory.angle]
	if _cache.has(key):
		return _cache[key]
	var ap = polygons(a)
	var bp = polygons(b)
	var overlaps: Array = []
	var overlap_area = 0.0
	var gap = INF
	for p in ap:
		for q in bp:
			var clip = intersection(p, q)
			var size = area(clip)
			if size > EPS:
				overlaps.append(clip)
				overlap_area += size
			for i in 4:
				for j in 4:
					gap = minf(gap, minf(point_segment(p[i], q[j], q[(j + 1) % 4]), point_segment(q[j], p[i], p[(i + 1) % 4])))
	if overlap_area > EPS:
		gap = 0.0
	var result = {"gap": gap, "overlapArea": overlap_area, "overlapRatio": overlap_area / (4 * CELL * CELL), "overlaps": overlaps,
		"type": "冲突" if overlap_area > EPS else ("贸易" if gap <= CELL + EPS else "隔绝")}
	if _cache.size() >= 256:
		_cache.clear()
	_cache[key] = result
	return result

static func radius(c: Dictionary) -> float:
	var local = {"x": 0.0, "y": 0.0, "territory": c.territory}
	var maximum = 0.0
	for polygon in polygons(local):
		for p in polygon:
			maximum = maxf(maximum, sqrt(p.x * p.x + p.y * p.y))
	return maximum

static func packed(polygon: Array) -> PackedVector2Array:
	var result = PackedVector2Array()
	for p in polygon:
		result.append(Vector2(p.x, p.y))
	return result

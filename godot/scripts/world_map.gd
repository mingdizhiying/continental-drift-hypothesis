extends Control
signal city_selected(id: String)
const CITY_SCENE = preload("res://scenes/city_view.tscn")
var state: Dictionary = {}
var views: Dictionary = {}
var world_scale = 1.0
var origin = Vector2.ZERO
var animation: Tween
var display_positions: Dictionary = {}
var relations: Array = []
var overlap_layer: Node2D
var vision: Dictionary = {}

func _ready() -> void:
	overlap_layer = Node2D.new()
	overlap_layer.name = "OverlapRegions"
	overlap_layer.z_index = 5
	$World.add_child(overlap_layer)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	world_scale = minf(size.x / 1000.0, size.y / 600.0)
	origin = (size - Vector2(1000, 600) * world_scale) / 2.0
	$World.position = origin
	$World.scale = Vector2.ONE * world_scale
	queue_redraw()

func update_world(s: Dictionary, selected: String, config: WorldConfig, animate: bool = true) -> void:
	state = s
	var previous_vision = vision
	vision = WorldVision.visibility(s, config.fog_enabled)
	relations = WorldRules.connections(s)
	if animation:
		animation.kill()
	animation = null
	var labels: Array[Vector2] = []
	for i in s.cities.size():
		var c = s.cities[i]
		if not views.has(c.id):
			var view = CITY_SCENE.instantiate()
			$World.add_child(view)
			view.selected.connect(func(id): city_selected.emit(id))
			views[c.id] = view
		var view = views[c.id]
		view.configure(c, config.cities[i], i, c.id == s.current, c.id == selected)
		var level = WorldVision.level(vision, c.id)
		view.apply_vision(level, WorldVision.details_allowed(s, c.id, config.fog_enabled))
		var destination = Vector2(c.x, c.y)
		var was_full: bool = not previous_vision.is_empty() and WorldVision.level(previous_vision, c.id) == "full"
		if animate and display_positions.has(c.id) and (not config.fog_enabled or (was_full and level == "full")):
			if animation == null:
				animation = create_tween().set_parallel(true)
			animation.tween_property(view, "position", destination, 0.35).set_trans(Tween.TRANS_SINE)
		else:
			view.position = destination
		display_positions[c.id] = destination
		if level == "hidden":
			continue
		# Labels may move away from their plate; positions and rule distances do not.
		var label = destination + Vector2(0, 28)
		for offset in [Vector2(0, 28), Vector2(0, -80), Vector2(155, 28), Vector2(-155, 28), Vector2(155, -80), Vector2(-155, -80), Vector2(0, 125)]:
			var candidate = destination + offset
			candidate.x = clampf(candidate.x, 70, 930)
			candidate.y = clampf(candidate.y, 25, 540)
			var clear = true
			for used in labels:
				if absf(used.x - candidate.x) < 130 and absf(used.y - candidate.y) < 75:
					clear = false
					break
			if clear:
				label = candidate
				break
		labels.append(label)
		view.set_label_offset(label - destination)
		view.z_index = 2 if c.id == selected else 1
	for child in overlap_layer.get_children():
		child.queue_free()
	for pair in relations:
		if not WorldVision.pair_visible(s, vision, pair) or WorldVision.level(vision, pair.a) != "full" or WorldVision.level(vision, pair.b) != "full":
			continue
		for polygon in pair.overlaps:
			var region = Polygon2D.new()
			region.polygon = TerritoryRules.packed(polygon)
			region.color = Color(0.89, 0.74, 0.45, 0.6) if pair.type == "休战" else Color(0.9, 0.37, 0.32, 0.6)
			overlap_layer.add_child(region)
	overlap_layer.visible = animation == null
	if animation:
		animation.finished.connect(func():
			overlap_layer.show()
			queue_redraw())
	queue_redraw()

func _process(_delta: float) -> void:
	if animation and animation.is_running():
		queue_redraw()

func _draw() -> void:
	if state.is_empty():
		return
	var board = Rect2(origin, Vector2(1000, 600) * world_scale)
	draw_rect(board, Color("10282e") if vision.global else Color("08151c"))
	if not vision.global:
		# Decorative haze contains no information from any concealed city.
		for i in 16:
			var center = origin + Vector2(90 + fmod(i * 173, 820), 85 + fmod(i * 113, 430)) * world_scale
			for layer in range(3, 0, -1):
				draw_circle(center, (22 + layer * 16) * world_scale, Color(0.19, 0.31, 0.35, 0.025))
		for c in state.cities:
			if not vision.full.has(c.id):
				continue
			for polygon in TerritoryRules.polygons(c):
				var points = PackedVector2Array()
				for p in polygon:
					points.append(origin + Vector2(p.x, p.y) * world_scale)
				draw_colored_polygon(points, Color("17343b"))
	var ink = Color(0.42, 0.64, 0.65, 0.11 if vision.global else 0.035)
	for x in range(0, 1001, 50):
		draw_line(origin + Vector2(x, 0) * world_scale, origin + Vector2(x, 600) * world_scale, ink)
	for y in range(0, 601, 50):
		draw_line(origin + Vector2(0, y) * world_scale, origin + Vector2(1000, y) * world_scale, ink)
	for pair in relations:
		if pair.type == "隔绝" or not WorldVision.pair_visible(state, vision, pair):
			continue
		var a: Vector2 = views[pair.a].position * world_scale + origin
		var b: Vector2 = views[pair.b].position * world_scale + origin
		var color = Color(0.92, 0.39, 0.34, 0.6) if pair.type == "冲突" else (Color(0.89, 0.75, 0.47, 0.55) if pair.type == "休战" else Color(0.48, 0.69, 0.78, 0.4))
		draw_line(a, b, color, 1.3, true)
	for c in state.cities:
		if WorldVision.level(vision, c.id) == "hidden":
			continue
		var start = Vector2(c.origin.x, c.origin.y) * world_scale + origin
		var end: Vector2 = views[c.id].position * world_scale + origin
		if vision.global:
			draw_dashed_line(start, end, Color(0.75, 0.78, 0.7, 0.35), 1.0, 4.0)
			draw_circle(start, 2.3, Color(0.65, 0.73, 0.7, 0.6))
		var label: Vector2 = end + views[c.id].get_node("LabelRoot").position * world_scale
		if label.distance_to(end) > 65 * world_scale:
			draw_line(end, label, Color(0.6, 0.75, 0.7, 0.35), 1, true)

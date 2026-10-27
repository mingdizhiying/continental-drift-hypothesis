extends Node2D
signal selected(id: String)
var city_id: String
var plates: Array[Polygon2D] = []
var outlines: Array[Line2D] = []
var vision_level = "full"

func _ready() -> void:
	for i in 4:
		var plate = $Plate if i == 0 else $Plate.duplicate()
		var outline = $Outline if i == 0 else $Outline.duplicate()
		if i > 0:
			add_child(plate)
			add_child(outline)
		plates.append(plate)
		outlines.append(outline)
	$LabelRoot/Button.pressed.connect(func(): selected.emit(city_id))

func configure(c: Dictionary, definition: CityDefinition, _index: int, current: bool, chosen: bool) -> void:
	city_id = c.id
	set_meta("barrier_complete", c.barrier >= 6)
	set_meta("beacon_lit", c.get("beacon") != null)
	var polygons = TerritoryRules.polygons({"x": 0.0, "y": 0.0, "territory": c.territory})
	for i in 4:
		var points = TerritoryRules.packed(polygons[i])
		plates[i].polygon = points
		plates[i].rotation = 0
		plates[i].color = Color(definition.tint, 0.30 if not chosen else 0.48)
		points.append(points[0])
		outlines[i].points = points
		outlines[i].rotation = 0
		outlines[i].default_color = Color("e2bd79") if chosen else Color(definition.tint, 0.8)
	$Marker.color = Color("edce8c") if current else Color("b6d7ce")
	$Halo.visible = current
	queue_redraw()
	$LabelRoot/Button.text = c.name
	$LabelRoot/Button.button_pressed = chosen
	$LabelRoot/Status.text = ("✦ 誓约生效" if WorldRules.oath_active(c) else "◇ 誓约休眠") if c.oath != null else ("当前治理" if current else "尚未立誓")
	$LabelRoot/Status.modulate = Color("e2bd79") if current else Color("b6c6bf")
	$LabelRoot/Button.tooltip_text = "%s · %s\n点击查看；板块可以重叠，不阻挡漂移。" % [c.name, c.lore]

func set_label_offset(offset: Vector2) -> void:
	$LabelRoot.position = offset

func apply_vision(level: String, details: bool = true) -> void:
	vision_level = level
	visible = level != "hidden"
	for plate in plates:
		plate.visible = level == "full"
	for outline in outlines:
		outline.visible = level == "full"
	$LabelRoot/Button.disabled = level != "full"
	if level == "full" and not details:
		$LabelRoot/Status.text = "接壤领土 · 城内未知"
		$LabelRoot/Button.tooltip_text = "可见接壤领土，城内情况仍被迷雾掩盖。"
	if level == "center":
		$Halo.hide()
		$LabelRoot/Status.text = "贸易城市 · 仅中心点"
		$LabelRoot/Status.modulate = Color("91b6c4")
		$LabelRoot/Button.tooltip_text = "只可见贸易城市中心，领土与城内情况被迷雾掩盖。"
	$Marker.visible = level == "center" or not get_meta("beacon_lit", false)
	queue_redraw()

func _draw() -> void:
	if vision_level != "full":
		return
	if get_meta("barrier_complete", false):
		draw_arc(Vector2.ZERO, 65, 0, TAU, 64, Color("e2bd79"), 2, true)
	if get_meta("beacon_lit", false):
		var gold = Color("f3d487")
		draw_circle(Vector2.ZERO, 18, Color(0.94, 0.77, 0.35, 0.16))
		draw_colored_polygon(PackedVector2Array([Vector2(-6, 9), Vector2(-3, -9), Vector2(3, -9), Vector2(6, 9)]), gold)
		draw_line(Vector2(-7, -9), Vector2(7, -9), gold, 2)
		draw_circle(Vector2(0, -14), 4, Color("fff0b3"))
		for direction in [Vector2(-1, -0.5), Vector2(0, -1), Vector2(1, -0.5)]:
			draw_line(Vector2(0, -14) + direction * 7, Vector2(0, -14) + direction * 14, gold, 1.5, true)

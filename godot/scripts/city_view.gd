extends Node2D
signal selected(id: String)
var city_id: String
var plates: Array[Polygon2D] = []
var outlines: Array[Line2D] = []

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

func _draw() -> void:
	if has_meta("barrier_complete") and get_meta("barrier_complete"):
		draw_arc(Vector2.ZERO, 65, 0, TAU, 64, Color("e2bd79"), 2, true)

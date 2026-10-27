extends Node2D
signal selected(id: String)
var city_id: String

func _ready() -> void:
	var outline: PackedVector2Array = $Plate.polygon.duplicate()
	if not outline.is_empty():
		outline.append(outline[0])
	$Outline.points = outline
	$LabelRoot/Button.pressed.connect(func(): selected.emit(city_id))

func configure(c: Dictionary, definition: CityDefinition, index: int, current: bool, chosen: bool) -> void:
	city_id = c.id
	$Plate.color = Color(definition.tint, 0.38 if not chosen else 0.65)
	$Plate.rotation = index * 0.72
	$Outline.rotation = $Plate.rotation
	$Outline.default_color = Color("e2bd79") if chosen else Color(definition.tint, 0.8)
	$Marker.color = Color("edce8c") if current else Color("b6d7ce")
	$Halo.visible = current
	$LabelRoot/Button.text = c.name
	$LabelRoot/Button.button_pressed = chosen
	$LabelRoot/Status.text = ("✦ 誓约生效" if WorldRules.oath_active(c) else "◇ 誓约休眠") if c.oath != null else ("当前治理" if current else "尚未立誓")
	$LabelRoot/Status.modulate = Color("e2bd79") if current else Color("b6c6bf")
	$LabelRoot/Button.tooltip_text = "%s · %s\n点击查看；板块可以重叠，不阻挡漂移。" % [c.name, c.lore]

func set_label_offset(offset: Vector2) -> void:
	$LabelRoot.position = offset

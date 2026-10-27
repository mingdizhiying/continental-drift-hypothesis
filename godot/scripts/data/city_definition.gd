class_name CityDefinition
extends Resource
## Initial data only. Live state is copied into WorldRules, never written here.
@export var id: String = "ember"
@export var city_name: String = "余烬城"
@export var start: Vector2 = Vector2(180, 180)
@export var velocity: Vector2 = Vector2(2.3, 1.1)
@export var lore: String = "炉火与工艺"
@export_range(0, 100) var food: int = 50
@export_range(0, 100) var peace: int = 60
@export_range(0, 100) var trade: int = 42
@export_range(0, 100) var ecology: int = 70
@export var tint: Color = Color("799c86")

class_name WorldConfig
extends Resource
@export var cities: Array[CityDefinition] = []
@export var actions: Array[ActionDefinition] = []
## Priority order: the first eligible event fires each turn.
@export var events: Array[CitizenEventDefinition] = []
@export_group("迷雾与灯塔")
@export var fog_enabled: bool = true
## Permanent, non-turn-consuming construction. Independent of the eight actions.
@export var beacon_cost: Dictionary = {"trade": 20, "food": 5, "ecology": 3}

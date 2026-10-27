class_name WorldConfig
extends Resource
@export var cities: Array[CityDefinition] = []
@export var actions: Array[ActionDefinition] = []
## Priority order: the first eligible event fires each turn.
@export var events: Array[CitizenEventDefinition] = []

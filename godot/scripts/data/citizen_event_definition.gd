class_name CitizenEventDefinition
extends Resource
@export var id: String = "watch"
@export var title: String = "街巷守望"
@export var condition: String = "没有其他未发生事件满足条件"
@export_multiline var text: String = "居民记录地平线的变化，等待使者的决定。"
@export var effect: Dictionary = {}
@export var repeat: bool = false
## Supported predicates are implemented by WorldRules.event_matches().
@export_enum("hunger", "unrest", "seed", "market", "refugees", "feast", "craft", "isolation", "torch", "watch") var predicate: String = "watch"

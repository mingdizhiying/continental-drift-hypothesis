class_name WorldVision
extends RefCounted
## A single policy is used by map geometry, labels, tabs, details and reports.
## Selection never changes the observing city; only governance migration does.

static func full_view(s: Dictionary, enabled: bool = true) -> bool:
	return not enabled or s.get("fullVisionTurn", -1) == s.turn

static func visibility(s: Dictionary, enabled: bool = true) -> Dictionary:
	var result = {"global": full_view(s, enabled), "full": [], "centers": []}
	var observer = WorldRules.city(s, s.current)
	for c in s.cities:
		if result.global or c.id == s.current:
			result.full.append(c.id)
			continue
		var relation = TerritoryRules.relation(observer, c)
		if relation.gap <= TerritoryRules.EPS:
			result.full.append(c.id)
		elif relation.type == "贸易" and WorldRules.truce_for(s, s.current, c.id).is_empty():
			result.centers.append(c.id)
	return result

static func level(vision: Dictionary, id: String) -> String:
	if vision.full.has(id):
		return "full"
	return "center" if vision.centers.has(id) else "hidden"

static func details_allowed(s: Dictionary, id: String, enabled: bool = true) -> bool:
	return id == s.current or full_view(s, enabled)

static func pair_visible(s: Dictionary, vision: Dictionary, pair: Dictionary) -> bool:
	if vision.global:
		return true
	return (pair.a == s.current or pair.b == s.current) and level(vision, pair.a) != "hidden" and level(vision, pair.b) != "hidden"

static func _mentions_pair(text: String, name: String) -> bool:
	return text.begins_with(name + "↔") or text.contains("↔" + name + "：") or text.contains("↔" + name + "，")

static func _actor(s: Dictionary, turn: int) -> String:
	for entry in s.history:
		if entry.turn == turn and entry.kind == "行动":
			return str(entry.city)
	return s.current

static func history_for_player(s: Dictionary, enabled: bool = true) -> Array:
	if full_view(s, enabled) or s.ended:
		return s.history.filter(func(h): return not h.has("cities"))
	var entries: Array = []
	var actors: Dictionary = {}
	for entry in s.history:
		if entry.kind == "行动":
			actors[entry.turn] = entry.city
	for entry in s.history:
		if entry.has("cities"):
			continue
		var actor_id = str(actors.get(entry.turn, s.current))
		# Personal memories remain readable after leaving a city. Remote ongoing
		# changes and free-form AI world summaries do not bypass current fog.
		if entry.kind in ["开端", "行动", "立誓", "市民事件", "屏障结果", "迁城", "灯塔", "AI屏障复核"]:
			entries.append(entry)
		elif entry.kind == "领地互动":
			if entry.pair.has(actor_id):
				entries.append(entry)
		elif entry.kind == "距离变化":
			var actor = WorldRules.city(s, actor_id)
			if not actor.is_empty() and _mentions_pair(entry.text, actor.name):
				var safe = entry.duplicate(true)
				# No continuously precise boundary distances into concealed territory.
				safe.text = str(entry.text).split("；")[0] + "。"
				entries.append(safe)
		elif entry.kind == "AI影响" and entry.get("city") == actor_id:
			entries.append(entry)
	return entries

static func interactions_for_player(s: Dictionary, enabled: bool = true) -> Array:
	if full_view(s, enabled) or s.ended:
		return s.get("interactions", [])
	var actor = WorldRules.city(s, _actor(s, int(s.turn)))
	if actor.is_empty():
		return []
	return s.get("interactions", []).filter(func(text): return _mentions_pair(str(text), actor.name))

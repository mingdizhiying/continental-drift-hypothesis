class_name CityEconomy
extends RefCounted
## Costs are paid in full before gains. Oaths never refund an active payment.
const LEGACY_LAWS = {
	"fire": {"name": "城内不得燃火", "text": "城内不得燃火", "detail": "安定≥35；采集改为繁荣+9、生态−4；修复不耗生态，但仅+1屏障。"},
	"silence": {"name": "城民不得说谎", "text": "城民不得说谎", "detail": "安定≥35；调查安定+11；公开秘密的安定代价升至24。"},
	"memory": {"name": "所有债务必须偿还", "text": "所有债务必须偿还", "detail": "安定≥35；修复消耗24繁荣、9粮食、4生态、5安定，屏障+3。"}}
const RESOURCE_NAMES = {"food": "粮食", "peace": "安定", "trade": "繁荣", "ecology": "生态", "barrier": "屏障"}

static func spec(config: WorldConfig, action: String, law: String = "") -> Dictionary:
	var result: Dictionary = {}
	for definition in config.actions:
		if definition.id == action:
			result = {"id": action, "name": definition.title, "place": definition.place,
				"cost": definition.cost.duplicate(), "gain": definition.gain.duplicate()}
			break
	if result.is_empty():
		return {"error": "未知行动"}
	if action == "forge" and law == "memory":
		result.cost = {"trade": 24, "food": 9, "ecology": 4, "peace": 5}
		result.gain.barrier = 3
	if action == "forge" and law == "fire":
		result.cost.erase("ecology")
		result.gain.barrier = 1
	if action == "forest" and law == "fire":
		result.cost = {"ecology": 4}
		result.gain = {"trade": 9}
	if action == "investigate" and law == "silence":
		result.gain.peace = 11
	if action == "reveal" and law == "silence":
		result.cost.peace = 24
	return result

static func block(c: Dictionary, action_spec: Dictionary) -> String:
	if action_spec.has("error"):
		return action_spec.error
	if action_spec.id in ["forge", "reveal"] and c.barrier >= 6:
		return "圣光屏障已完成"
	if action_spec.id == "reveal" and c.revealed:
		return "本城秘密已经公开"
	var missing: Array[String] = []
	for key in action_spec.cost:
		if c[key] < action_spec.cost[key]:
			missing.append("%s需%d（现有%d）" % [RESOURCE_NAMES[key], action_spec.cost[key], c[key]])
	return "资源不足：" + "，".join(missing) if not missing.is_empty() else ""

static func apply(c: Dictionary, action_spec: Dictionary) -> Dictionary:
	var blocked = block(c, action_spec)
	if not blocked.is_empty():
		return {"error": blocked}
	var before = c.duplicate(true)
	for key in action_spec.cost:
		c[key] -= action_spec.cost[key]
	for key in action_spec.gain:
		c[key] = mini(6 if key == "barrier" else 100, int(c[key] + action_spec.gain[key]))
	if action_spec.id == "reveal":
		c.revealed = true
	var changes: Array[String] = []
	for key in RESOURCE_NAMES:
		if c[key] != before[key]:
			changes.append("%s %s%d" % [RESOURCE_NAMES[key], "+" if c[key] > before[key] else "", c[key] - before[key]])
	return {"cost": action_spec.cost.duplicate(), "text": "%s（%s）" % [action_spec.name, "，".join(changes) if not changes.is_empty() else "无直接收益，仍承担世界消耗"]}

static func outcome(c: Dictionary) -> Dictionary:
	if c.barrier < 6:
		return {"title": "长夜", "text": "圣光屏障未能成形，居民退往林地，等待下一任使者。"}
	if c.peace >= 60 and c.food >= 20:
		return {"title": "共誓", "text": "圣光屏障展开，安定与粮食支撑城民共同承担守护的代价。"}
	return {"title": "孤光", "text": "圣光屏障已展开，但安定或口粮不足，庇护之下仍有人承受代价。"}

static func describe(values: Dictionary, sign: String) -> String:
	var parts: Array[String] = []
	for key in values:
		parts.append("%s%s%d" % [RESOURCE_NAMES[key], sign, values[key]])
	return "，".join(parts)

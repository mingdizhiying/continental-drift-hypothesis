class_name WorldRules
extends RefCounted
## Deterministic, JSON-compatible rules. Rendering never writes to this state.
const LIMIT = 60
const TENURE = 6
const DRIFT_SPEED = 4
const METRICS = {"food": "粮食", "peace": "安定", "trade": "繁荣", "ecology": "生态"}
const OATH_TYPES = {"anchor": "固定城市位置", "food": "守护粮食储备", "peace": "守护社会安定", "trade": "守护贸易繁荣", "ecology": "守护生态", "fire": "城内不得燃火", "silence": "城民不得说谎", "memory": "所有债务必须偿还"}
const OATH_RULES = {
	"anchor": ["peace", 35, "安定≥35；每轮消耗1繁荣"],
	"food": ["trade", 30, "繁荣≥30；每轮消耗1繁荣"],
	"peace": ["food", 25, "粮食≥25；每轮消耗1粮食"],
	"trade": ["peace", 40, "安定≥40；每轮消耗1生态"],
	"ecology": ["food", 30, "粮食≥30；每轮消耗1繁荣"],
	"fire": ["peace", 35, "安定≥35；采集改为繁荣+9、生态−4；修复不耗生态，但仅+1屏障。无额外每轮消耗"],
	"silence": ["peace", 35, "安定≥35；调查安定+11；公开秘密的安定代价升至24。无额外每轮消耗"],
	"memory": ["peace", 35, "安定≥35；修复消耗24繁荣、9粮食、4生态、5安定，屏障+3。无额外每轮消耗"]}
var config: WorldConfig

func _init(data: WorldConfig = null) -> void:
	config = data if data != null else load("res://data/world.tres")

func initial() -> Dictionary:
	var cities: Array = []
	for i in config.cities.size():
		var d = config.cities[i]
		cities.append({"id": d.id, "name": d.city_name, "x": float(d.start.x), "y": float(d.start.y),
			"origin": {"x": float(d.start.x), "y": float(d.start.y)},
			# Store rule velocities as decimal doubles, avoiding Vector2 float32 drift.
			"vx": snappedf(d.velocity.x, 0.000001), "vy": snappedf(d.velocity.y, 0.000001),
			"lore": d.lore, "food": d.food, "peace": d.peace, "trade": d.trade,
			"ecology": d.ecology, "barrier": 0, "revealed": false, "barrierResults": [], "oath": null, "visits": 1 if i == 0 else 0, "eventSeen": []})
	return {"turn": 0, "current": cities[0].id, "visited": [cities[0].id], "ended": false,
		"ending": null, "events": [], "history": [{"turn": 0, "kind": "开端",
		"text": "你成为造物主的使者，抵达余烬城。每座城市都在漂移，唯有誓约可能留下不变之物。"}], "cities": cities}

static func city(s: Dictionary, id: String) -> Dictionary:
	for c in s.cities:
		if c.id == id:
			return c
	return {}

static func distance(a: Dictionary, b: Dictionary) -> float:
	return sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2))

static func nearest(s: Dictionary, id: String = "") -> Dictionary:
	if id.is_empty():
		id = s.current
	var from = city(s, id)
	var best: Dictionary = {}
	var best_distance = INF
	for c in s.cities:
		if c.id == id:
			continue
		var d = distance(from, c)
		if d < best_distance or (d == best_distance and str(c.id) < str(best.id)):
			best = c
			best_distance = d
	return best

static func connections(s: Dictionary) -> Array:
	var links: Array = []
	for i in s.cities.size():
		for j in range(i + 1, s.cities.size()):
			var a = s.cities[i]
			var b = s.cities[j]
			var d = distance(a, b)
			links.append({"a": a.id, "b": b.id, "distance": int(floor(d + 0.5)),
				"type": "邻接" if d < 180 else ("贸易" if d < 330 else "隔绝")})
	return links

static func parse_oath(raw: String) -> Dictionary:
	var text = raw.strip_edges()
	if text.is_empty() or text.length() > 160:
		return {"error": "请填写1–160字的誓约。"}
	var forbidden = RegEx.create_from_string("毁灭|杀光|无限|全能|永生|无敌")
	if forbidden.search(text):
		return {"error": "请限定一个可守护的事物。"}
	var patterns = {"fire": "不得燃火|禁止燃火|禁火", "silence": "不得说谎|禁止说谎|禁谎", "memory": "债务|偿债", "anchor": "位置|原地|不.{0,3}漂移|停止.{0,3}移动|不.{0,3}移动|坐标",
		"food": "粮|饥饿|饥荒|食物|饱腹", "peace": "和平|交战|战争|安定|冲突|争斗",
		"trade": "贸易|繁荣|商贸|经济", "ecology": "生态|森林|树木|自然|林地"}
	var matches: Array = []
	for key in patterns:
		if RegEx.create_from_string(patterns[key]).search(text):
			matches.append(key)
	if matches.size() != 1:
		return {"error": "每城只能固定一项，请缩小誓约范围。" if not matches.is_empty() else "本地模拟不能理解此誓约，请明确包含位置、粮食、和平、繁荣、生态、不得燃火、不得说谎或偿债。"}
	var type = matches[0]
	var rule = OATH_RULES[type]
	return {"text": text, "type": type, "condition": {"metric": rule[0], "min": rule[1]}, "explanation": rule[2], "source": "本地模拟"}

static func oath_active(c: Dictionary) -> bool:
	return c.get("oath") != null and c[c.oath.condition.metric] >= c.oath.condition.min

static func set_oath(state: Dictionary, oath: Dictionary) -> Dictionary:
	if state.ended:
		return {"error": "世界已结算，请重新开始。"}
	var condition = oath.get("condition", {})
	if not condition is Dictionary:
		return {"error": "誓约判定无效"}
	var minimum = condition.get("min", -1)
	if not OATH_TYPES.has(oath.get("type", "")) or not METRICS.has(condition.get("metric", "")) or not (minimum is float or minimum is int) or not is_finite(float(minimum)) or minimum < 0 or minimum > 100 or not oath.get("text", "") is String or oath.get("text", "").strip_edges().is_empty() or oath.text.length() > 160:
		return {"error": "誓约判定无效"}
	var s = state.duplicate(true)
	var c = city(s, s.current)
	c.oath = oath.duplicate(true)
	c.oath.anchor = {"x": c.x, "y": c.y}
	c.oath.createdAt = s.turn
	log_entry(s, "立誓", "%s：「%s」→%s。实行条件：%s。离任后保留，不推进时间。" % [c.name, oath.text, OATH_TYPES[oath.type], oath.get("explanation", "")], c.id)
	return s

static func change(c: Dictionary, delta: Dictionary) -> void:
	for key in delta:
		c[key] = clampi(int(c[key]) + int(delta[key]), 0, 100)

static func log_entry(s: Dictionary, kind: String, text: String, id: String = "") -> void:
	var entry = {"turn": s.turn, "kind": kind, "text": text}
	if not id.is_empty():
		entry.city = id
	s.history.append(entry)

static func enforce_oaths(s: Dictionary, before: Array) -> void:
	for c in s.cities:
		var old: Dictionary = {}
		for b in before:
			if b.id == c.id:
				old = b
				break
		if old.is_empty() or not oath_active(old):
			continue
		if c.oath.type == "anchor":
			c.x = old.oath.anchor.x
			c.y = old.oath.anchor.y
		else:
			var key = old.oath.type
			if METRICS.has(key):
				var paid = 0
				if s.get("lastAction", {}).get("turn") == s.turn and s.lastAction.city == c.id:
					paid = s.lastAction.cost.get(key, 0)
				c[key] = max(c[key], old[key] - paid)

static func event_matches(id: String, c: Dictionary, s: Dictionary) -> bool:
	match id:
		"hunger": return c.food < 25
		"unrest": return c.peace < 35
		"seed": return c.ecology >= 70
		"market": return distance(c, nearest(s, c.id)) < 330
		"refugees": return nearest(s, c.id).peace < 40
		"feast": return c.food >= 65 and c.peace >= 60
		"craft": return c.trade >= 60
		"isolation": return distance(c, nearest(s, c.id)) > 330
		"torch": return oath_active(c)
		"watch": return true
	return false

func advance(state: Dictionary, action: String) -> Dictionary:
	if state.ended:
		return {"error": "世界已结算。"}
	var s = state.duplicate(true)
	var before: Array = s.cities.duplicate(true)
	var old_links = connections(s)
	var current = city(s, s.current)
	var result = CityEconomy.apply(current, action_spec(current, action))
	if result.has("error"):
		return result
	s.turn += 1
	s.lastAction = {"turn": s.turn, "city": current.id, "action": action, "cost": result.cost}
	var action_entry = {"turn": s.turn, "kind": "行动", "city": current.id, "cost": result.cost, "text": "你在%s%s。" % [current.name, result.text]}
	s.history.append(action_entry)
	for c in s.cities:
		var old = city({"cities": before}, c.id)
		if not oath_active(old) or c.oath.type != "anchor":
			c.x += (c.vx + sin(s.turn / 5.0 + c.origin.x) * 1.1) * DRIFT_SPEED
			c.y += (c.vy + cos(s.turn / 6.0 + c.origin.y) * 1.1) * DRIFT_SPEED
			if c.x < 65 or c.x > 935:
				c.vx *= -1
				c.x = clampf(c.x, 65, 935)
			if c.y < 65 or c.y > 535:
				c.vy *= -1
				c.y = clampf(c.y, 65, 535)
		change(c, {"food": -2})
		if oath_active(old) and not CityEconomy.LEGACY_LAWS.has(c.oath.type):
			change(c, {"food": -1} if c.oath.type == "peace" else ({"ecology": -1} if c.oath.type == "trade" else {"trade": -1}))
	s.links = connections(s)
	s.interactions = []
	var trade_income: Dictionary = {}
	for c in s.cities:
		trade_income[c.id] = 0
	for i in s.links.size():
		var pair = s.links[i]
		var a = city(s, pair.a)
		var b = city(s, pair.b)
		var old = old_links[i]
		var note = ""
		if pair.type == "邻接":
			if min(a.peace, b.peace) < 40:
				change(a, {"peace": -1})
				change(b, {"peace": -1})
				note = "边界摩擦：邻城因不安定互相猜疑"
			else:
				change(a, {"food": 1})
				change(b, {"food": 1})
				grant_trade(a, trade_income)
				grant_trade(b, trade_income)
				note = "邻接合作：交换粮食与工艺"
		elif pair.type == "贸易":
			grant_trade(a, trade_income)
			grant_trade(b, trade_income)
			note = "商路互通：距离允许商队往来"
		if old.type != pair.type:
			log_entry(s, "距离变化", "%s↔%s：%s→%s（%d→%d）。%s" % [a.name, b.name, old.type, pair.type, old.distance, pair.distance, note if not note.is_empty() else "旧商路断开。"])
		if not note.is_empty():
			s.interactions.append("%s↔%s，距离%d：%s。" % [a.name, b.name, pair.distance, note])
	for c in s.cities:
		if distance(c, nearest(s, c.id)) > 330:
			change(c, {"trade": -1, "peace": -1})
	for e in config.events:
		if (e.repeat or not current.eventSeen.has(e.id)) and event_matches(e.predicate, current, s):
			if not e.repeat:
				current.eventSeen.append(e.id)
			change(current, e.effect)
			s.events = [{"name": e.title, "city": current.name, "text": e.text, "condition": e.condition, "effect": e.effect.duplicate()}]
			log_entry(s, "市民事件", "%s·%s：%s 触发条件：%s。" % [current.name, e.title, e.text, e.condition], current.id)
			break
	enforce_oaths(s, before)
	if s.turn % TENURE == 0:
		var outcome = CityEconomy.outcome(current)
		var record = {"turn": s.turn, "title": outcome.title, "text": outcome.text, "food": current.food, "peace": current.peace, "trade": current.trade, "ecology": current.ecology, "barrier": current.barrier}
		current.barrierResults.append(record)
		s.history.append({"turn": s.turn, "kind": "屏障结果", "city": current.id, "text": "%s·%s：%s 屏障%d/6，安定%d/100，粮食%d，繁荣%d，生态%d。" % [current.name, record.title, record.text, current.barrier, current.peace, current.food, current.trade, current.ecology], "result": record})
	s.history.append({"turn": s.turn, "kind": "世界快照", "cities": s.cities.duplicate(true), "text": "第%d轮世界状态已记录。" % s.turn})
	if s.turn == LIMIT:
		s.ended = true
		s.ending = local_ending(s)
	elif s.turn % TENURE == 0:
		var next = nearest(s)
		s.current = next.id
		next.visits += 1
		if not s.visited.has(next.id):
			s.visited.append(next.id)
		log_entry(s, "迁城", "六轮任期结束：离开%s，前往最近的%s（距离%d）。旧城誓约继续生效。" % [current.name, next.name, int(floor(distance(current, next) + 0.5))])
	return s

func action_spec(c: Dictionary, action: String) -> Dictionary:
	return CityEconomy.spec(config, action, str(c.oath.type) if oath_active(c) else "")

static func grant_trade(c: Dictionary, income: Dictionary) -> void:
	if income[c.id] < 2:
		change(c, {"trade": 1})
		income[c.id] += 1

static func local_ending(s: Dictionary) -> Dictionary:
	var values: Dictionary = {}
	for key in METRICS:
		var total = 0.0
		for c in s.cities:
			total += c[key]
		values[key] = int(floor(total / s.cities.size() + 0.5))
	var actions = s.history.filter(func(h): return h.kind == "行动")
	var vows = s.history.filter(func(h): return h.kind == "立誓")
	var title = "饥荒中的漂流" if values.food < 25 else ("分裂的群岛" if values.peace < 40 else ("繁荣的代价" if values.ecology < 35 else ("流动的共同体" if values.trade >= 65 else "未完成的世界")))
	var completed = s.cities.filter(func(c): return c.barrier >= 6).size()
	var text = "圣光屏障已在%d座城市展开。六十轮过去，城市仍在移动。你完成%d次行动，留下%d次誓约记录，亲历%d座城市。平均粮食%d、安定%d、繁荣%d、生态%d。" % [completed, actions.size(), vows.size(), s.visited.size(), values.food, values.peace, values.trade, values.ecology]
	var restorations = actions.filter(func(h): return h.text.contains("修复林地")).size()
	text += "建设与耕种消耗的林地成为未来的代价。" if values.ecology < 35 else "你留下的%d次誓约与%d次林地修复，是这段历史中可追溯的守护行动。" % [vows.size(), restorations]
	text += "许多城市仍在寻找足够的食物。" if values.food < 25 else "粮食储备决定了城市能否继续等待下一个邻居。"
	var evidence: Array = []
	for h in s.history.filter(func(h): return h.kind == "屏障结果") + vows.slice(0, 6) + s.history.filter(func(h): return h.kind == "迁城").slice(-3) + s.history.filter(func(h): return h.kind == "距离变化").slice(-3) + actions.slice(-3):
		evidence.append("第%d轮：%s" % [h.turn, h.text])
	var barriers: Array = []
	for c in s.cities:
		var outcome = CityEconomy.outcome(c)
		barriers.append({"city": c.name, "title": outcome.title, "text": outcome.text, "barrier": c.barrier, "peace": c.peace, "food": c.food, "governed": c.visits > 0})
	return {"title": title, "source": "本地模拟", "text": text, "values": values, "barriers": barriers, "evidence": evidence}

static func apply_ai_turn(state: Dictionary, data: Dictionary, before: Dictionary) -> Dictionary:
	if not data.get("summary") is String or data.summary.length() > 1500 or not data.get("effects") is Array or data.effects.size() > 6:
		return {"error": "AI响应格式无效"}
	var s = state.duplicate(true)
	var seen: Array = []
	for effect in data.effects:
		if not effect is Dictionary:
			return {"error": "AI城市影响无效"}
		var c = city(s, str(effect.get("cityId", "")))
		if c.is_empty() or seen.has(c.id) or not effect.get("reason") is String or effect.reason.length() > 300 or not effect.get("delta", {}) is Dictionary:
			return {"error": "AI城市影响无效或重复"}
		seen.append(c.id)
		var parts: Array = []
		for key in effect.get("delta", {}):
			var value = effect.delta[key]
			if not METRICS.has(key) or not (value is int or value is float) or not is_finite(float(value)) or value != floor(value) or abs(value) > 3:
				return {"error": "AI影响超出允许范围"}
			parts.append("%s %s%d" % [METRICS[key], "+" if value > 0 else "", value])
		change(c, effect.get("delta", {}))
		log_entry(s, "AI影响", "%s：%s；%s" % [c.name, effect.reason, "，".join(parts)], c.id)
	enforce_oaths(s, before.cities)
	if s.turn % TENURE == 0:
		var c = city(s, before.current)
		if not c.barrierResults.is_empty() and c.barrierResults[-1].turn == s.turn:
			var record = c.barrierResults[-1]
			var outcome = CityEconomy.outcome(c)
			record.merge({"title": outcome.title, "text": outcome.text, "food": c.food, "peace": c.peace, "trade": c.trade, "ecology": c.ecology}, true)
			# JS structuredClone preserves this shared record; Godot duplicate(true)
			# duplicates each dictionary value, so explicitly restore its live reference.
			for entry in s.history:
				if entry.kind == "屏障结果" and entry.turn == s.turn and entry.city == c.id:
					entry.result = record
			log_entry(s, "AI屏障复核", "%s：%s，安定%d，粮食%d。" % [c.name, record.title, c.peace, c.food], c.id)
	log_entry(s, "AI判定", data.summary)
	s.history.append({"turn": s.turn, "kind": "AI后快照", "cities": s.cities.duplicate(true), "text": "真实AI影响结算后的世界状态。"})
	if s.ended:
		s.ending = local_ending(s)
	return s

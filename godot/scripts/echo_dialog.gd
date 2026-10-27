extends AcceptDialog

func _ready() -> void:
	%InteractionToggle.toggled.connect(func(expanded):
		%InteractionSummary.visible = expanded
		%InteractionToggle.text = "本轮互动汇总  ▾" if expanded else "本轮互动汇总  ▸")

static func escaped(text: String) -> String:
	return text.replace("[", "[lb]")

func present(state: Dictionary, bounds: Vector2, resolution: String = "") -> void:
	if state.turn == 0 or visible:
		return
	title = "第%d轮 · 世界回响" % state.turn
	get_ok_button().text = "查看世界结局" if state.ended else "继续治理"
	%InteractionToggle.set_pressed_no_signal(false)
	%InteractionToggle.text = "本轮互动汇总  ▸"
	%InteractionSummary.hide()
	var text = "[color=#e2bd79][font_size=24]第%d轮 · 世界回响[/font_size][/color]\n" % state.turn
	if not resolution.is_empty():
		text += "\n" + escaped(resolution) + "\n"
	text += "\n[color=#e2bd79]市民事件[/color]\n"
	for event in state.events:
		var effects = CityEconomy.describe(event.effect, "+")
		# Negative event changes need their own sign rather than a '+-' prefix.
		var changes: Array[String] = []
		for key in event.effect:
			changes.append("%s %s%d" % [WorldRules.METRICS[key], "+" if event.effect[key] > 0 else "", event.effect[key]])
		effects = "，".join(changes) if not changes.is_empty() else "无数值变化"
		text += "\n[b]%s · %s[/b]\n%s\n触发条件：%s\n影响：%s\n" % [escaped(event.city), escaped(event.name), escaped(event.text), escaped(event.condition), effects]
	text += "\n[color=#e2bd79]城市关系切换[/color]\n"
	var records = state.history.filter(func(h): return h.turn == state.turn)
	var changes = records.filter(func(h): return h.kind == "距离变化")
	if changes.is_empty():
		text += "\n本轮没有城市关系切换。\n"
	for record in changes:
		var reason = "领地边界距离超过一格，商路断开。"
		if record.text.contains("→休战"):
			reason = "外交调停协议开始生效。"
		elif record.text.contains("→冲突"):
			reason = "当前领地发生重叠，且没有有效休战协议。"
		elif record.text.contains("→贸易"):
			reason = "当前领地没有重叠，边界距离不超过一格，且没有有效休战协议。"
		text += "\n%s\n原因：%s\n" % [escaped(record.text), reason]
	var milestones = records.filter(func(h): return h.kind in ["屏障结果", "迁城", "AI屏障复核", "AI判定"])
	if not milestones.is_empty() or state.ended:
		text += "\n[color=#e2bd79]任期与世界动态[/color]\n"
		for record in milestones:
			text += "\n" + escaped(record.text) + "\n"
		if state.ended:
			text += "\n第六十轮已结束。关闭本轮回响后，主界面顶部将显示世界结局与六城屏障结果。\n"
	%EchoBody.text = text
	var interactions: Array[String] = []
	for line in state.get("interactions", []):
		interactions.append(escaped(line))
	%InteractionSummary.text = "\n\n".join(interactions) if not interactions.is_empty() else "本轮没有贸易、争夺或休战互动。"
	popup_centered(Vector2i(minf(840, bounds.x - 48), minf(720, bounds.y - 48)))
	%BodyScroll.scroll_vertical = 0
	get_ok_button().grab_focus()

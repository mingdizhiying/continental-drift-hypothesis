extends PanelContainer
@export var config: WorldConfig
var rules: WorldRules
var state: Dictionary
var selected: String
var pending: Dictionary = {}
var busy = false
var city_buttons: Dictionary = {}

func _ready() -> void:
	rules = WorldRules.new(config)
	for i in config.actions.size():
		var action = config.actions[i]
		var button: Button = %Actions.get_child(i)
		button.text = action.title
		button.set_meta("action_id", action.id)
		button.pressed.connect(perform.bind(action.id))
	for i in CityEconomy.LEGACY_LAWS.size():
		var key = CityEconomy.LEGACY_LAWS.keys()[i]
		var law = CityEconomy.LEGACY_LAWS[key]
		%LegacyLaws.get_child(i).tooltip_text = law.detail + "与其他誓约共用唯一槽，需判定并确认。"
		%LegacyLaws.get_child(i).pressed.connect(func():
			%OathInput.text = law.text
			clear_pending()
			judge_oath())
	for c in config.cities:
		var button = Button.new()
		button.text = c.city_name
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(select_city.bind(c.id))
		%CityTabs.add_child(button)
		city_buttons[c.id] = button
	%WorldMap.city_selected.connect(select_city)
	%JudgeButton.pressed.connect(judge_oath)
	%ConfirmButton.pressed.connect(confirm_oath)
	%OathInput.text_changed.connect(clear_pending)
	%AIEnabled.toggled.connect(func(enabled):
		clear_pending()
		%AIStatus.text = "真实 AI 模式：请求失败时明确回退本地模拟。" if enabled else "本地模拟：关键词判定誓约、规则演化世界。"
		get_node("Margin/Layout/Header/Mode").text = "真实 AI · 失败时回退" if enabled else "本地模拟 · GODOT 原生版")
	%ResetButton.pressed.connect(reset_world)
	%ExportButton.pressed.connect(func():
		%ExportDialog.current_file = "大陆漂移假说-第%d轮.json" % state.turn
		%ExportDialog.popup_centered(Vector2i(900, 600)))
	%ExportDialog.file_selected.connect(export_history)
	%RulesButton.pressed.connect(show_rules)
	%EndingButton.pressed.connect(show_ending)
	reset_world()

static func escape_bb(text: String) -> String:
	return text.replace("[", "[lb]")

func clear_pending() -> void:
	pending = {}
	%OathPreview.text = ""
	%ConfirmButton.hide()

func reset_world() -> void:
	if busy:
		return
	state = rules.initial()
	selected = state.current
	clear_pending()
	%OathInput.text = ""
	%EndingDialog.hide()
	%AIStatus.text = "新世界已生成。" + ("真实 AI 模式；请求失败时回退本地模拟。" if %AIEnabled.button_pressed else "当前使用本地模拟。")
	render(false)

func select_city(id: String) -> void:
	if busy:
		return
	selected = id
	clear_pending()
	render(false)

func render(animate: bool = false) -> void:
	var current = WorldRules.city(state, state.current)
	var c = WorldRules.city(state, selected)
	var can_act: bool = not busy and not state.ended and selected == state.current
	%Clock.text = "世界时间  %02d / 60" % state.turn
	%Current.text = "当前治理  " + current.name
	%Tenure.text = "任期  已结束" if state.ended else "剩余任期  %d 轮" % (6 - int(state.turn) % 6)
	%Next.text = "世界已结算" if state.ended else "最近下一站  " + WorldRules.nearest(state).name
	%CityName.text = c.name
	%CityRole.text = "当前治理" if c.id == state.current else "远方城市 · 仅查看"
	%CityDescription.text = "%s · 曾治理%d次\n位置 (%d, %d) · 距当前城 %d" % [c.lore, c.visits, round(c.x), round(c.y), round(WorldRules.distance(current, c))]
	var metric_nodes = {"food": %Food, "peace": %Peace, "trade": %Trade, "ecology": %Ecology}
	for key in metric_nodes:
		metric_nodes[key].get_node("Title").text = "%s  %d / 100" % [WorldRules.METRICS[key], c[key]]
		metric_nodes[key].get_node("Bar").value = c[key]
	for button in %Actions.get_children():
		var spec = rules.action_spec(c, button.get_meta("action_id"))
		var blocked = CityEconomy.block(c, spec)
		button.disabled = not can_act or not blocked.is_empty()
		button.text = spec.name + ("\n资源不足" if blocked.begins_with("资源不足") else ("\n" + blocked if not blocked.is_empty() else ""))
		button.tooltip_text = "%s\n支付：%s\n获得：%s\n%s" % [spec.place, CityEconomy.describe(spec.cost, "−") if not spec.cost.is_empty() else "无", CityEconomy.describe(spec.gain, "+") if not spec.gain.is_empty() else "无直接收益，仍推进一轮", blocked]
	for button in %LegacyLaws.get_children():
		button.disabled = not can_act
	var outcome = CityEconomy.outcome(c)
	%BarrierStatus.text = "圣光屏障 %d / 6 · %s" % [c.barrier, outcome.title if c.barrier >= 6 else "尚未展开"]
	if not c.barrierResults.is_empty():
		%BarrierStatus.text += "\n第%d轮任期结果：%s" % [c.barrierResults[-1].turn, c.barrierResults[-1].title]
	%JudgeButton.disabled = not can_act
	%ConfirmButton.disabled = not can_act
	%ConfirmButton.visible = not pending.is_empty()
	%OathInput.editable = can_act
	%AIEnabled.disabled = busy or state.ended
	%ResetButton.disabled = busy
	%ExportButton.disabled = busy
	for id in city_buttons:
		city_buttons[id].set_pressed_no_signal(id == selected)
		city_buttons[id].disabled = busy
	if c.oath != null:
		%OathState.text = "「%s」\n%s · %s" % [c.oath.text, "生效" if WorldRules.oath_active(c) else "休眠", c.oath.explanation]
	else:
		%OathState.text = "此城尚未立誓。每城一条，离任后保留。"
	var echoes: Array[String] = []
	for e in state.events:
		var impacts: Array[String] = []
		for key in e.effect:
			impacts.append("%s %s%d" % [WorldRules.METRICS[key], "+" if e.effect[key] > 0 else "", e.effect[key]])
		echoes.append("[color=#e2bd79]%s · %s[/color]  %s\n条件：%s；影响：%s" % [escape_bb(e.city), escape_bb(e.name), escape_bb(e.text), escape_bb(e.condition), "，".join(impacts) if not impacts.is_empty() else "无数值变化"])
	for line in state.get("interactions", []).slice(0, 6):
		echoes.append(escape_bb(line))
	%Echo.text = "\n".join(echoes) if not echoes.is_empty() else "等待第一次行动，城市将在六十轮中逐渐改变关系。\n选择右侧行动推进世界；点击地图或下方城名查看城市。"
	var history = state.history.filter(func(h): return not h.has("cities")).slice(-30)
	history.reverse()
	var log_lines: Array[String] = []
	for h in history:
		log_lines.append("[color=#a7bdb5]第%02d轮 · %s[/color]  %s" % [h.turn, escape_bb(h.kind), escape_bb(h.text)])
	%History.text = "\n".join(log_lines)
	%History.scroll_to_line(0)
	%EndingButton.visible = state.ended
	%WorldMap.update_world(state, selected, config, animate)

func judge_oath() -> void:
	if busy or state.ended or selected != state.current:
		return
	clear_pending()
	var raw = %OathInput.text.strip_edges()
	if raw.is_empty() or raw.length() > 160:
		%OathPreview.text = "请填写1–160字的誓约。"
		return
	busy = true
	render()
	var result: Dictionary
	if %AIEnabled.button_pressed:
		%AIStatus.text = "正在请求 AI 判定誓约……"
		var data: Dictionary = await %AIClient.request("oath", {"state": state, "text": raw})
		if data.get("accepted") is bool and not data.accepted:
			%OathPreview.text = str(data.get("reason", "AI 拒绝了这个誓约。"))
			%AIStatus.text = "AI 已明确拒绝，未改用本地判定。"
			busy = false
			render()
			return
		if data.get("accepted") == true and data.get("oath") is Dictionary:
			result = data.oath.duplicate(true)
			result.text = raw
			result.source = "真实AI"
			if not result.get("explanation") is String or result.explanation.length() > 500 or WorldRules.set_oath(state, result).has("error"):
				data = {"error": "AI 誓约格式无效"}
			else:
				%AIStatus.text = "誓约条件由真实 AI 判定。"
		else:
			data = {"error": data.get("error", "AI 誓约格式无效")}
		if data.has("error"):
			%AIStatus.text = "AI 未生效：%s。改用本地模拟。" % data.error
			result = WorldRules.parse_oath(raw)
	else:
		result = WorldRules.parse_oath(raw)
	if result.has("error"):
		%OathPreview.text = result.error
	else:
		pending = result
		var c = WorldRules.city(state, state.current)
		%OathPreview.text = "%s · %s\n%s；当前%s条件。确认替换，不推进时间。" % [WorldRules.OATH_TYPES[result.type], result.source, result.explanation, "满足" if c[result.condition.metric] >= result.condition.min else "不满足"]
	busy = false
	render()

func confirm_oath() -> void:
	if pending.is_empty() or busy or state.ended or selected != state.current:
		return
	var next = WorldRules.set_oath(state, pending)
	if next.has("error"):
		%OathPreview.text = next.error
		return
	state = next
	clear_pending()
	%OathInput.text = ""
	render()

func perform(action: String) -> void:
	if busy or state.ended or selected != state.current:
		return
	busy = true
	clear_pending()
	render()
	var before = state
	var next = rules.advance(state, action)
	if next.has("error"):
		%AIStatus.text = next.error
		busy = false
		render()
		return
	if %AIEnabled.button_pressed:
		%AIStatus.text = "正在请求本轮 AI 世界影响……"
		var data: Dictionary = await %AIClient.request("turn", {"before": before, "state": next, "action": action})
		var applied = data if data.has("error") else WorldRules.apply_ai_turn(next, data, before)
		if applied.has("error"):
			%AIStatus.text = "AI 未生效：%s；本轮使用本地规则。" % applied.error
		else:
			next = applied
			%AIStatus.text = "本轮真实 AI 已判定城市影响；每指标限制为 ±3。"
		if next.ended:
			%AIStatus.text = "正在请求 AI 结局……"
			var ending: Dictionary = await %AIClient.request("ending", {"state": next})
			if valid_ending(ending):
				ending.source = "真实AI"
				next.ending.merge(ending, true)
				%AIStatus.text = "真实 AI 结局已生成；历史证据可导出核对。"
			else:
				%AIStatus.text = "最终 AI 结算未生效：%s；显示本地历史结算。" % ending.get("error", "结局格式无效")
	state = next
	selected = state.current
	busy = false
	render(true)
	if state.ended:
		show_ending()

static func valid_ending(data: Dictionary) -> bool:
	if not data.get("title") is String or data.title.length() > 100 or not data.get("text") is String or data.text.length() > 6000 or not data.get("evidence") is Array or data.evidence.size() > 20:
		return false
	for e in data.evidence:
		if not e is String or e.length() > 1000:
			return false
	return true

func export_history(path: String) -> bool:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		%Footer.text = "导出失败：无法写入所选位置。"
		return false
	file.store_string(JSON.stringify(state, "  "))
	var success = file.get_error() == OK
	file.close()
	%Footer.text = "完整历史已导出：" + path if success else "导出失败：文件写入未完成。"
	return success

func show_ending() -> void:
	if not state.ended:
		return
	var ending = state.ending
	var text = "[color=#e2bd79][font_size=28]%s[/font_size][/color]\n%s\n\n%s\n\n[color=#e2bd79]历史依据[/color]\n" % [escape_bb(ending.title), escape_bb(ending.source), escape_bb(ending.text)]
	for c in ending.get("barriers", []):
		text += "%s：%s · 屏障%d/6，安定%d，粮食%d%s\n" % [c.city, c.title, c.barrier, c.peace, c.food, "" if c.governed else "（尚未治理）"]
	for evidence in ending.evidence:
		text += "\n" + escape_bb(evidence) + "\n"
	%EndingDialog.get_node("Content").text = text
	%EndingDialog.popup_centered(Vector2i(800, 620))

func show_rules() -> void:
	var text = "[color=#e2bd79][font_size=24]城市终将远行，你留下什么不变？[/font_size][/color]\n\n每次行动推进一轮；所有城市漂移并演化。每六轮自动前往最近的其他城市，允许返回旧城，第六十轮结算。大陆板块允许重叠，距离按城市中心计算。\n\n[color=#e2bd79]城市治理[/color]\n"
	for action in config.actions:
		text += "%s：支付%s，获得%s。\n" % [escape_bb(action.title), CityEconomy.describe(action.cost, "−") if not action.cost.is_empty() else "无", CityEconomy.describe(action.gain, "+") if not action.gain.is_empty() else "无直接收益"]
	text += "\n所有行动先完整支付，资源不足、重复公开秘密或屏障已完成时不耗回合。每轮基础粮食消耗2。屏障6且安定≥60、粮食≥20为共誓，否则为孤光；未完成为长夜。每六轮记录结果，第六十轮汇总十次任期。禁火、禁谎、偿债与五种守护共用唯一誓约槽，按轮初条件生效。守护不返还主动支付的成本。\n"
	text += "\n[color=#e2bd79]誓约火炬[/color]\n输入 → 判定条件 → 确认。每城只保留一条，替换与查看不推进时间；离任后保留。\n本地支持五种守护和三种旧城法则，每次只能选择一项。实行条件按轮初状态判断；数值保护以轮初值减主动支付成本为下限。位置誓约恢复时回到立誓坐标。\n"
	for key in WorldRules.OATH_RULES:
		text += "%s：%s。\n" % [WorldRules.OATH_TYPES[key], WorldRules.OATH_RULES[key][2]]
	text += "\n[color=#e2bd79]十种市民事件[/color]\n每轮在刚治理的城市触发一个；按以下顺序选择首个满足条件且未发生的事件。\n"
	for e in config.events:
		text += "%s：%s；%s。\n" % [escape_bb(e.title), escape_bb(e.condition), "可重复" if e.repeat else "每城最多一次"]
	text += "\n[color=#e2bd79]距离关系与 AI[/color]\n距离 <180 为邻接，<330 为贸易，其余隔绝。没有碰撞或合并规则。\n默认完整离线运行。真实 AI 需另外启动仓库中的 Node.js 代理，密钥只保存在代理端；请求失败会明确回退。\n\n[color=#e2bd79]进度与导出[/color]\n导出 JSON 包含全部行动、誓约、迁城和逐轮快照。此版与原型一致，关闭或重开世界会清空进度，暂不支持读档。"
	%RulesDialog.get_node("Content").text = text
	%RulesDialog.popup_centered(Vector2i(780, 660))

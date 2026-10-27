extends PanelContainer
@export var config: WorldConfig
## -1 generates a new seed. Set an integer to replay the same initial territories.
@export var initial_seed: int = -1
var rules: WorldRules
var state: Dictionary
var selected: String
var pending: Dictionary = {}
var busy = false
var city_buttons: Dictionary = {}
var ending_revealed = false
var last_turn_status = "本轮使用本地规则模拟。"

func _ready() -> void:
	get_window().title = "大陆漂移假说 · Godot 迷雾与灯塔"
	rules = WorldRules.new(config)
	%Tabs.set_tab_title(0, "治理")
	%Tabs.set_tab_title(1, "誓约")
	%Tabs.set_tab_title(2, "领地外交")
	for i in config.actions.size():
		var action = config.actions[i]
		var button: Button = %Actions.get_child(i)
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
	%BeaconButton.pressed.connect(light_beacon)
	%MediateButton.pressed.connect(func():
		var index = %DiplomacyTarget.selected
		if index >= 0 and not %DiplomacyTarget.disabled:
			perform("mediate", str(%DiplomacyTarget.get_item_metadata(index))))
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
	%FullEndingButton.pressed.connect(show_ending)
	%OpenEchoButton.pressed.connect(open_echo)
	%EchoDialog.confirmed.connect(_on_echo_closed)
	%EchoDialog.canceled.connect(_on_echo_closed)
	%EchoDialog.visibility_changed.connect(func():
		$Margin.modulate = Color(0.48, 0.48, 0.48) if %EchoDialog.visible else Color.WHITE)
	%HistoryToggle.toggled.connect(func(expanded):
		%History.visible = expanded
		%HistoryToggle.text = "世界历史  ▾" if expanded else "世界历史  ▸")
	%EchoDialog.theme = theme
	%EndingDialog.theme = theme
	%RulesDialog.theme = theme
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
	state = rules.initial(initial_seed)
	ending_revealed = false
	last_turn_status = "本轮使用本地规则模拟。"
	%EchoDialog.hide()
	%HistoryToggle.set_pressed_no_signal(false)
	%HistoryToggle.text = "世界历史  ▸"
	%History.hide()
	%Tabs.current_tab = 0
	%Footer.text = "每行动推进一轮 · 每六轮迁往最近的其他城市 · 立誓不推进时间 · 第六十轮结算"
	selected = state.current
	clear_pending()
	%OathInput.text = ""
	%EndingDialog.hide()
	%AIStatus.text = "新世界已生成。" + ("真实 AI 模式；请求失败时回退本地模拟。" if %AIEnabled.button_pressed else "当前使用本地模拟。")
	render(false)

func select_city(id: String) -> void:
	if busy or %EchoDialog.visible:
		return
	if WorldVision.level(WorldVision.visibility(state, config.fog_enabled), id) != "full":
		return
	selected = id
	clear_pending()
	render(false)

func render(animate: bool = false) -> void:
	var vision = WorldVision.visibility(state, config.fog_enabled)
	if WorldVision.level(vision, selected) != "full":
		selected = state.current
	var current = WorldRules.city(state, state.current)
	var c = WorldRules.city(state, selected)
	var details = WorldVision.details_allowed(state, selected, config.fog_enabled)
	var can_act: bool = not busy and not state.ended and selected == state.current
	%Clock.text = "世界时间  %02d / 60" % state.turn
	%Current.text = "当前治理  " + current.name
	%Tenure.text = "任期  已结束" if state.ended else "剩余任期  %d 轮" % (6 - int(state.turn) % 6)
	%Next.text = "世界已结算" if state.ended else "最近下一站  " + WorldRules.nearest(state).name
	if config.fog_enabled and not vision.global and not state.ended:
		%Next.text = "下一站  迁城时揭晓"
	%CityName.text = c.name
	%CityRole.text = "当前治理" if c.id == state.current else "远方城市 · 仅查看"
	%CityDescription.text = "%s · 曾治理%d次\n位置 (%d, %d) · 距当前城 %d" % [c.lore, c.visits, round(c.x), round(c.y), round(WorldRules.distance(current, c))]
	%Food.get_parent().visible = details
	%Tabs.visible = details
	%VisibilityNotice.visible = not details
	if not details:
		%CityRole.text = "可见领土 · 城内情况未知"
		%CityDescription.text = "接壤领土 · %s 型\n中心 (%d, %d)" % [c.territory.shape, round(c.x), round(c.y)]
	%FogStatus.text = "迷雾：仅本城与接壤领土；贸易城市只可见中心点。"
	if vision.global:
		%FogStatus.text = "灯塔照耀：本轮全图可见，下一次成功行动后恢复迷雾。" if config.fog_enabled else "全图观察模式（迷雾已在工程配置中关闭）"
	render_diplomacy(c, can_act)
	var metric_nodes = {"food": %Food, "peace": %Peace, "trade": %Trade, "ecology": %Ecology}
	for key in metric_nodes:
		metric_nodes[key].get_node("Title").text = "%s  %d / 100" % [WorldRules.METRICS[key], c[key]]
		metric_nodes[key].get_node("Bar").value = c[key]
	for button in %Actions.get_children():
		var spec = rules.action_spec(c, button.get_meta("action_id"))
		var blocked = CityEconomy.block(c, spec)
		button.configure(spec, blocked, can_act)
	for button in %LegacyLaws.get_children():
		button.disabled = not can_act
	var outcome = CityEconomy.outcome(c)
	%BarrierStatus.text = "圣光屏障 %d / 6 · %s" % [c.barrier, outcome.title if c.barrier >= 6 else "尚未展开"]
	if not c.barrierResults.is_empty():
		%BarrierStatus.text += "\n第%d轮任期结果：%s" % [c.barrierResults[-1].turn, c.barrierResults[-1].title]
	var beacon_blocked = rules.beacon_block(state) if selected == state.current else "仅当前治理城市可点亮"
	%BeaconButton.disabled = not can_act or not beacon_blocked.is_empty()
	%BeaconButton.text = "灯塔已永久点亮" if c.get("beacon") != null else "永久点亮灯塔 · 不耗回合"
	%BeaconStatus.text = "灯塔 · 中心与旋转已永久固定" if c.get("beacon") != null else "灯塔 · 点亮后永久固定城市"
	%BeaconCost.text = "支付：%s。点亮时获得一轮全图视野。" % (CityEconomy.describe(config.beacon_cost, "−") if not config.beacon_cost.is_empty() else "无")
	if not beacon_blocked.is_empty():
		%BeaconCost.text += "\n" + beacon_blocked
	%JudgeButton.disabled = not can_act
	%ConfirmButton.disabled = not can_act
	%ConfirmButton.visible = not pending.is_empty()
	%OathInput.editable = can_act
	%AIEnabled.disabled = busy or state.ended
	%ResetButton.disabled = busy
	%ExportButton.disabled = busy
	for id in city_buttons:
		var level = WorldVision.level(vision, id)
		city_buttons[id].visible = level != "hidden"
		city_buttons[id].set_pressed_no_signal(id == selected)
		city_buttons[id].disabled = busy or level != "full"
		city_buttons[id].tooltip_text = "只可见贸易城市中心" if level == "center" else "查看可见领土"
	if c.oath != null:
		%OathState.text = "「%s」\n%s · %s" % [c.oath.text, "生效" if WorldRules.oath_active(c) else "休眠", c.oath.explanation]
	else:
		%OathState.text = "此城尚未立誓。每城一条，离任后保留。"
	%OpenEchoButton.disabled = busy or state.turn == 0
	%OpenEchoButton.text = "查看第%d轮回响" % state.turn if state.turn > 0 else "查看本轮回响"
	var history = WorldVision.history_for_player(state, config.fog_enabled).slice(-30)
	history.reverse()
	var log_lines: Array[String] = []
	for h in history:
		log_lines.append("[color=#a7bdb5]第%02d轮 · %s[/color]  %s" % [h.turn, escape_bb(h.kind), escape_bb(h.text)])
	%History.text = "\n".join(log_lines)
	%History.scroll_to_line(0)
	%EndingButton.visible = state.ended
	%EndingPanel.visible = state.ended and ending_revealed
	if state.ended:
		%EndingHeading.text = "世界结算 · %s · %s" % [state.ending.source, state.ending.title]
		%EndingSummary.text = state.ending.text
		var summaries: Array[String] = []
		for entry in state.ending.get("barriers", []):
			summaries.append("%s：%s（%d/6）" % [entry.city, entry.title, entry.barrier])
		%EndingCities.text = "  ·  ".join(summaries)
	%WorldMap.update_world(state, selected, config, animate)

func light_beacon() -> void:
	if busy or state.ended or selected != state.current or %EchoDialog.visible:
		return
	var next = rules.light_beacon(state)
	if next.has("error"):
		%Footer.text = next.error
		return
	state = next
	clear_pending()
	%Footer.text = "灯塔已永久点亮，中心与旋转固定。本轮全图可见，下一次成功行动后恢复迷雾。"
	render()

func judge_oath() -> void:
	if busy or state.ended or selected != state.current or %EchoDialog.visible:
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
	if pending.is_empty() or busy or state.ended or selected != state.current or %EchoDialog.visible:
		return
	var next = WorldRules.set_oath(state, pending)
	if next.has("error"):
		%OathPreview.text = next.error
		return
	state = next
	clear_pending()
	%OathInput.text = ""
	render()

func perform(action: String, target_id: String = "") -> void:
	if busy or state.ended or selected != state.current or %EchoDialog.visible:
		return
	busy = true
	clear_pending()
	render()
	var before = state
	var next = rules.advance(state, action, target_id)
	if next.has("error"):
		%AIStatus.text = next.error
		%Footer.text = next.error
		busy = false
		render()
		return
	var resolution_notes: Array[String] = []
	if %AIEnabled.button_pressed:
		%AIStatus.text = "正在请求本轮 AI 世界影响……"
		var data: Dictionary = await %AIClient.request("turn", {"before": before, "state": next, "action": action})
		var applied = data if data.has("error") else WorldRules.apply_ai_turn(next, data, before)
		if applied.has("error"):
			%AIStatus.text = "AI 未生效：%s；本轮使用本地规则。" % applied.error
		else:
			next = applied
			%AIStatus.text = "本轮真实 AI 已判定城市影响；每指标限制为 ±3。"
		resolution_notes.append(%AIStatus.text)
		if next.ended:
			%AIStatus.text = "正在请求 AI 结局……"
			var ending: Dictionary = await %AIClient.request("ending", {"state": next})
			if valid_ending(ending):
				ending.source = "真实AI"
				next.ending.merge(ending, true)
				%AIStatus.text = "真实 AI 结局已生成；历史证据可导出核对。"
			else:
				%AIStatus.text = "最终 AI 结算未生效：%s；显示本地历史结算。" % ending.get("error", "结局格式无效")
			resolution_notes.append(%AIStatus.text)
		%AIStatus.text = "\n".join(resolution_notes)
	last_turn_status = "\n".join(resolution_notes) if not resolution_notes.is_empty() else "本轮使用本地规则模拟。"
	%Footer.text = last_turn_status.replace("\n", " ")
	state = next
	selected = state.current
	busy = false
	render(true)
	open_echo()

func open_echo() -> void:
	if busy or state.turn == 0 or %EchoDialog.visible:
		return
	%EchoDialog.present(state, get_viewport_rect().size, last_turn_status, config.fog_enabled)

func _on_echo_closed() -> void:
	call_deferred("_after_echo_closed")

func _after_echo_closed() -> void:
	if state.ended:
		ending_revealed = true
		render()
		%EndingHeading.grab_focus()
	elif state.turn > 0:
		%OpenEchoButton.grab_focus()

func render_diplomacy(c: Dictionary, can_act: bool) -> void:
	%TerritoryStatus.text = "%s 型 · 朝向 %.1f° · %s %.2f°/轮\n世界种子 %d" % [c.territory.shape, c.territory.angle, "顺时针" if c.territory.spin > 0 else "逆时针", abs(c.territory.spin), state.seed]
	var vision = WorldVision.visibility(state, config.fog_enabled)
	if config.fog_enabled and not vision.global:
		%TerritoryStatus.text = "%s 型 · 朝向 %.1f° · %s %.2f°/轮" % [c.territory.shape, c.territory.angle, "顺时针" if c.territory.spin > 0 else "逆时针", abs(c.territory.spin)]
	if c.get("beacon") != null:
		%TerritoryStatus.text = "%s 型 · 朝向 %.1f°\n灯塔永久点亮：中心与旋转固定" % [c.territory.shape, c.territory.angle]
	var lines: Array[String] = []
	for pair in WorldRules.connections(state):
		if pair.a != c.id and pair.b != c.id:
			continue
		if not WorldVision.pair_visible(state, vision, pair):
			continue
		var other = WorldRules.city(state, pair.b if pair.a == c.id else pair.a)
		if WorldVision.level(vision, other.id) == "center":
			lines.append("%s：贸易 · 只可见城市中心" % other.name)
			continue
		var line = "%s：%s · 间距 %.2f 格" % [other.name, pair.type, pair.gap / TerritoryRules.CELL]
		if pair.overlapArea > 0:
			var percentage: float = pair.overlapRatio * 100
			line += " · 重叠 " + ("<0.1%" if percentage < 0.1 else "%.1f%%" % percentage)
		if pair.has("truceUntil"):
			line += " · 休战至第%d轮" % pair.truceUntil
		lines.append(line)
	%Relations.text = "\n".join(lines)
	if lines.is_empty():
		%Relations.text = "迷雾中没有可观察的邻接领土或贸易城市。"
	var old_target = ""
	if %DiplomacyTarget.selected >= 0:
		old_target = str(%DiplomacyTarget.get_item_metadata(%DiplomacyTarget.selected))
	%DiplomacyTarget.clear()
	var targets = WorldRules.diplomacy_targets(state)
	for target in targets:
		var index = %DiplomacyTarget.item_count
		%DiplomacyTarget.add_item(target.name)
		%DiplomacyTarget.set_item_metadata(index, target.id)
		if target.id == old_target:
			%DiplomacyTarget.select(index)
	if targets.is_empty():
		%DiplomacyTarget.add_item("当前没有可调停的领地冲突")
	%DiplomacyTarget.disabled = not can_act or targets.is_empty()
	%MediateButton.disabled = not can_act or targets.is_empty() or c.trade < WorldRules.DIPLOMACY_COST
	%DiplomacyHint.text = "繁荣不足，需8繁荣。" if c.trade < WorldRules.DIPLOMACY_COST else "从本次结算起双方休战三轮，不产生彼此的争夺和贸易，第三城互动照常。"

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
	var bounds = get_viewport_rect().size
	%EndingDialog.popup_centered(Vector2i(minf(800, bounds.x - 48), minf(680, bounds.y - 48)))

func show_rules() -> void:
	var text = "[color=#e2bd79][font_size=24]城市终将远行，你留下什么不变？[/font_size][/color]\n\n每次有效行动推进一轮，所有城市漂移与旋转；查看和立誓不消耗轮次。每六轮按城市中心距离迁往最近的其他城市，允许返回旧城，第六十轮结算。每局随机四格板块、朝向和旋转速度，允许重叠穿过，不阻挡或合并。\n\n[color=#e2bd79]城市治理[/color]\n"
	for action in config.actions:
		text += "%s：支付%s，获得%s。\n" % [escape_bb(action.title), CityEconomy.describe(action.cost, "−") if not action.cost.is_empty() else "无", CityEconomy.describe(action.gain, "+") if not action.gain.is_empty() else "无直接收益"]
	text += "\n所有行动先完整支付，资源不足、重复公开秘密或屏障已完成时不耗回合。每轮基础粮食消耗2。屏障6且安定≥60、粮食≥20为共誓，否则为孤光；未完成为长夜。每六轮记录结果，第六十轮汇总十次任期。禁火、禁谎、偿债与五种守护共用唯一誓约槽，按轮初条件生效。守护不返还主动支付的成本。\n"
	text += "\n[color=#e2bd79]誓约火炬[/color]\n输入 → 判定条件 → 确认。每城只保留一条，替换与查看不推进时间；离任后保留。\n本地支持五种守护和三种旧城法则，每次只能选择一项。实行条件按轮初状态判断；数值保护以轮初值减主动支付成本为下限。位置誓约恢复时回到立誓坐标。\n"
	for key in WorldRules.OATH_RULES:
		text += "%s：%s。\n" % [WorldRules.OATH_TYPES[key], WorldRules.OATH_RULES[key][2]]
	text += "\n[color=#e2bd79]十种市民事件[/color]\n每轮在刚治理的城市触发一个；按以下顺序选择首个满足条件且未发生的事件。\n"
	for e in config.events:
		text += "%s：%s；%s。\n" % [escape_bb(e.title), escape_bb(e.condition), "可重复" if e.repeat else "每城最多一次"]
	text += "\n[color=#e2bd79]领地关系、外交与 AI[/color]\n每格64单位，按旋转多边形的实际重叠面积和边界间距判断关系。重叠争夺双方粮食、安定和繁荣；未重叠且间距不超过一格时贸易，远离所有领地时隔绝。贸易每城每轮合计封顶4粮食、8繁荣。\n外交调停需8繁荣并推进一轮，选择当前重叠且未休战的其他城市；从本轮起休战三轮，双方不争夺、不贸易，与第三城互动照常。\n默认完整离线运行。真实 AI 需启动 tools/godot-proxy.mjs，密钥只保存在代理端；请求失败会明确回退。\n\n[color=#e2bd79]进度与导出[/color]\n导出 JSON 包含种子、领地形状/角度/角速度、外交协议、支付成本、任期结果、全部行动和逐轮快照。关闭或重开世界会清空进度，暂不支持读档。"
	text += "\n\n[color=#e2bd79]迷雾与灯塔[/color]\n默认只能看见当前治理城市的领土、与它实际接触或重叠的领土，以及通商城市的中心点；贸易中心不显示领土，接壤城市不显示城内指标。选择其他可见领土不会扩大视野，迷雾不会阻止世界继续演化或最近城市迁移。\n点亮灯塔支付%s，不推进轮次，也不触发市民事件。灯塔在本局永久点亮，中心与旋转都固定，离任后仍保留，不能重复付费点亮。旧位置誓约不会覆盖灯塔的固定坐标。\n点亮时立即获得当前轮的全图视野；查看、立誓、失败操作均不消耗，下一次成功行动结算后恢复迷雾。灯塔不持续提供远方视野。完整JSON导出仍包含隐藏世界数据，供复盘调试。" % (CityEconomy.describe(config.beacon_cost, "−") if not config.beacon_cost.is_empty() else "无")
	%RulesDialog.get_node("Content").text = text
	var bounds = get_viewport_rect().size
	%RulesDialog.popup_centered(Vector2i(minf(780, bounds.x - 48), minf(680, bounds.y - 48)))

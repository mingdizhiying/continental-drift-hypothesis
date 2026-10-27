extends SceneTree
var failures: Array[String] = []
var game: Control
var screenshot_dir = ""
var echo_count = 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshots="):
			screenshot_dir = arg.trim_prefix("--screenshots=")
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func action_button(id: String) -> Button:
	for button in game.get_node("%Actions").get_children():
		if button.get_meta("action_id") == id:
			return button
	return null

func capture(name: String) -> void:
	if screenshot_dir.is_empty():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	root.get_texture().get_image().save_png(screenshot_dir.path_join(name + ".png"))

func close_echo() -> void:
	if game.get_node("%EchoDialog").visible:
		game.get_node("%EchoDialog").get_ok_button().pressed.emit()
		await process_frame

func action(id: String, close: bool = true, pointer: bool = false) -> void:
	var turn: int = game.state.turn
	var count_before = echo_count
	check(not action_button(id).disabled, "Unexpected disabled action: " + id)
	if pointer:
		await process_frame
		var point = action_button(id).get_global_rect().get_center()
		var motion = InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		root.push_input(motion, true)
		var click = InputEventMouseButton.new()
		click.position = point
		click.global_position = point
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		root.push_input(click, true)
		click = click.duplicate()
		click.pressed = false
		root.push_input(click, true)
	else:
		action_button(id).pressed.emit()
	await process_frame
	check(game.state.turn == turn + 1, "Action did not advance one turn: " + id)
	check(game.get_node("%EchoDialog").visible, "Successful action did not open echo: " + id)
	check(echo_count == count_before + 1, "Action opened echo more than once: " + id)
	check(not game.get_node("%EchoDialog").get_node("%InteractionSummary").visible, "Interaction summary not initially folded")
	if close:
		await close_echo()

func economic_fixture() -> void:
	for i in game.state.cities.size():
		var c = game.state.cities[i]
		c.territory = {"shape": "O", "angle": 0.0, "spin": 0.0}
		c.x = 400.0 if i == 0 else (560.0 if i == 1 else 850.0)
		c.y = 300.0 if i < 2 else 450.0
		c.vx = -sin(0.2 + c.origin.x) * 1.1
		c.vy = -cos(1.0 / 6.0 + c.origin.y) * 1.1
		c.eventSeen = ["hunger", "unrest", "seed", "market", "refugees", "feast", "craft", "isolation", "torch"]
	game.render()

func run() -> void:
	root.size = Vector2i(1440, 960)
	game = load("res://scenes/main.tscn").instantiate()
	game.initial_seed = 123
	root.add_child(game)
	game.get_node("%EchoDialog").visibility_changed.connect(func():
		if game.get_node("%EchoDialog").visible:
			echo_count += 1)
	await process_frame
	await process_frame
	check(game.state.turn == 0, "Initial state missing")
	check(game.get_node("%OpenEchoButton").disabled, "Opening echo enabled before first turn")
	check(not game.get_node("%History").visible, "History not initially folded")
	check(game.get_node("%Tabs").get_tab_count() == 3, "Missing editable UI tabs")
	await capture("initial")
	game.get_node("%CityTabs").get_child(2).pressed.emit()
	check(game.selected == "tide" and action_button("farm").disabled, "Remote city action lock failed")
	game.perform("farm")
	check(game.state.turn == 0 and echo_count == 0, "Remote action advanced world or opened echo")
	game.get_node("%WorldMap").city_selected.emit("ember")
	game.get_node("%Tabs").current_tab = 1
	game.get_node("%OathInput").text = "愿此城永不缺粮"
	game.get_node("%JudgeButton").pressed.emit()
	check(not game.pending.is_empty() and game.state.cities[0].oath == null, "Preview changed state")
	game.get_node("%ConfirmButton").pressed.emit()
	check(game.state.turn == 0 and game.state.cities[0].oath.type == "food", "Confirmation failed")
	game.get_node("%OathInput").text = "守护森林"
	game.judge_oath()
	game.get_node("%OathInput").text = "永远和平"
	game.get_node("%OathInput").text_changed.emit()
	check(game.pending.is_empty(), "Edited text left stale preview")
	game.judge_oath()
	game.confirm_oath()
	check(game.state.cities[0].oath.type == "peace" and echo_count == 0, "Oath replacement opened echo")
	await capture("oath")
	game.get_node("%Tabs").current_tab = 0
	await action("farm", false, true)
	await capture("echo")
	var turn = game.state.turn
	game.perform("observe")
	game.select_city("tide")
	check(game.state.turn == turn and game.selected == game.state.current, "Modal failed to block background actions")
	var dialog = game.get_node("%EchoDialog")
	dialog.get_node("%InteractionToggle").button_pressed = true
	check(dialog.get_node("%InteractionSummary").visible, "Interaction fold toggle failed")
	await capture("echo-expanded")
	await close_echo()
	check(game.get_node("%OpenEchoButton").has_focus(), "Focus did not return to echo entry")
	var before_reopen = echo_count
	game.get_node("%OpenEchoButton").pressed.emit()
	game.get_node("%OpenEchoButton").pressed.emit()
	await process_frame
	check(echo_count == before_reopen + 1 and game.state.turn == 1, "Reopening echo duplicated modal or advanced time")
	check(not dialog.get_node("%InteractionSummary").visible, "Reopen did not fold interactions")
	var escape = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await process_frame
	await process_frame
	check(not dialog.visible, "Esc did not close echo")
	if dialog.visible:
		await close_echo()
	for i in 5:
		await action("farm", i < 4)
	check(game.state.turn == 6 and game.state.current == WorldRules.nearest(game.state, "ember").id, "Six-turn migration failed")
	check(dialog.get_node("%EchoBody").text.contains("六轮任期结束") and dialog.get_node("%EchoBody").text.contains("屏障"), "Milestones missing from echo")
	await close_echo()
	check(game.selected == game.state.current and game.state.cities[0].oath != null, "Migration UI lost oath or selection")
	var export_path = "user://ui-test-history.json"
	check(game.export_history(export_path), "Export failed")
	var exported = JSON.parse_string(FileAccess.get_file_as_string(export_path))
	check(exported.turn == 6 and exported.seed == 123 and exported.has("truces") and exported.history.size() == game.state.history.size(), "Incomplete export")
	await create_timer(0.4).timeout
	await capture("turn-06")
	var saved = game.state.duplicate(true)
	for c in game.state.cities:
		c.x = 500.0
		c.y = 300.0
	game.render(false)
	for i in 6:
		game.get_node("%CityTabs").get_child(i).pressed.emit()
		check(game.selected == game.state.cities[i].id, "Overlapping city unreachable")
	await capture("overlap")
	game.state = saved
	game.selected = game.state.current
	game.render(false)
	for i in 54:
		await action("observe", i < 53)
	check(game.state.ended and game.state.turn == 60, "UI could not finish 60 rounds")
	check(game.state.history.filter(func(h): return h.kind == "屏障结果").size() == 10 and game.state.ending.barriers.size() == 6, "Ending evidence missing")
	check(dialog.visible and not game.get_node("%EndingPanel").visible and not game.get_node("%EndingDialog").visible, "Ending shown before final echo closes")
	await capture("final-echo")
	await close_echo()
	check(game.get_node("%EndingPanel").visible and game.get_node("%EndingHeading").has_focus(), "Closing final echo did not reveal/focus top ending")
	for button in game.get_node("%Actions").get_children():
		check(button.disabled, "Action enabled after ending")
	await capture("ending")
	game.get_node("%FullEndingButton").pressed.emit()
	check(game.get_node("%EndingDialog").visible, "Full ending dialog missing")
	await capture("ending-details")
	game.get_node("%EndingDialog").get_ok_button().pressed.emit()
	game.get_node("%HistoryToggle").button_pressed = true
	check(game.get_node("%History").visible, "History expand failed")
	game.get_node("%HistoryToggle").button_pressed = false
	game.get_node("%RulesButton").pressed.emit()
	check(game.get_node("%RulesDialog").visible and game.get_node("%RulesDialog/Content").text.contains("街巷守望"), "Event guide missing")
	game.get_node("%RulesDialog").hide()
	game.reset_world()
	check(game.state.turn == 0 and not game.get_node("%History").visible and not game.get_node("%EndingPanel").visible and game.get_node("%OpenEchoButton").disabled, "Reset did not clear presentation state")
	game.get_node("%Tabs").current_tab = 1
	game.get_node("%LegacyLaws").get_child(0).pressed.emit()
	check(game.pending.get("type") == "fire" and game.state.cities[0].oath == null, "Fire shortcut skipped confirmation")
	game.confirm_oath()
	check(action_button("forge").get_node("Margin/Content/Gain").text.contains("屏障+1"), "Law gain not visible on card")
	check(not action_button("forge").get_node("Margin/Content/Cost").text.contains("生态"), "Law cost not visible on card")
	game.get_node("%LegacyLaws").get_child(2).pressed.emit()
	check(game.pending.get("type") == "memory", "Debt shortcut failed")
	game.confirm_oath()
	economic_fixture()
	game.get_node("%Tabs").current_tab = 0
	for id in ["forge", "forest", "farm", "investigate", "forge", "investigate"]:
		await action(id)
	check(game.state.cities[0].barrier == 6 and game.state.cities[0].barrierResults[0].title == "共誓", "Debt route failed")
	await create_timer(0.4).timeout
	await capture("debt-route")
	game.select_city("ember")
	check(action_button("forge").disabled, "Completed barrier repair enabled")
	game.reset_world()
	game.state.cities[0].trade = 0
	game.render()
	var before_failure = echo_count
	check(action_button("forge").disabled and action_button("forge").get_node("Margin/Content/Reason").text.contains("繁荣需18"), "Missing visible payment reason")
	game.perform("forge")
	check(game.state.turn == 0 and echo_count == before_failure, "Failed payment advanced turn or opened echo")
	game.reset_world()
	for i in 2:
		var c = game.state.cities[i]
		c.x = 400.0
		c.y = 300.0
		c.territory = {"shape": "O", "angle": 0.0, "spin": 0.0}
	game.get_node("%Tabs").current_tab = 2
	game.render()
	await capture("diplomacy")
	check(not game.get_node("%MediateButton").disabled, "Diplomacy disabled for overlap")
	game.get_node("%MediateButton").pressed.emit()
	await process_frame
	check(game.state.turn == 1 and not WorldRules.truce_for(game.state, "ember", "grove").is_empty() and game.state.lastAction.cost.trade == 8, "Diplomacy action failed")
	check(dialog.visible and dialog.get_node("%EchoBody").text.contains("外交调停协议开始生效"), "Diplomacy echo missing")
	await close_echo()
	await create_timer(0.4).timeout
	await capture("truce")
	game.reset_world()
	root.size = Vector2i(1200, 880)
	await capture("compact")
	if failures.is_empty():
		print("PASS: 60-turn UI, mouse hit testing, one echo per success, modal locks, Esc/focus, folds/reopen, final-echo-to-ending flow, visible dynamic costs, debt route, diplomacy, export and reset.")
		quit(0)
	else:
		for failure in failures:
			printerr(failure)
		quit(1)

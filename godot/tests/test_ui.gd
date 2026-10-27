extends SceneTree
var failures: Array[String] = []
var game: Control
var screenshot_dir = ""

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

func run() -> void:
	root.size = Vector2i(1440, 960)
	game = load("res://scenes/main.tscn").instantiate()
	game.initial_seed = 123
	root.add_child(game)
	await process_frame
	await process_frame
	check(game.state.turn == 0, "Initial state missing")
	await capture("initial")
	game.get_node("%CityTabs").get_child(2).pressed.emit()
	check(game.selected == "tide", "City tab did not select remote city")
	check(game.get_node("%Actions").get_child(0).disabled, "Remote city actions enabled")
	game.perform("farm")
	check(game.state.turn == 0, "Remote action advanced world")
	game.get_node("%WorldMap").city_selected.emit("ember")
	check(game.selected == "ember", "Map selection signal not connected")
	game.get_node("%OathInput").text = "愿此城永不缺粮"
	game.get_node("%JudgeButton").pressed.emit()
	check(not game.pending.is_empty(), "Oath preview missing")
	check(game.state.cities[0].oath == null and game.state.turn == 0, "Preview changed state")
	game.get_node("%ConfirmButton").pressed.emit()
	check(game.state.cities[0].oath.type == "food", "Confirmation did not set oath")
	check(game.state.turn == 0, "Oath advanced time")
	game.get_node("%OathInput").text = "守护森林"
	game.get_node("%JudgeButton").pressed.emit()
	game.get_node("%OathInput").text = "永远和平"
	game.get_node("%OathInput").text_changed.emit()
	check(game.pending.is_empty(), "Edited text left stale preview")
	game.get_node("%JudgeButton").pressed.emit()
	game.get_node("%ConfirmButton").pressed.emit()
	check(game.state.cities[0].oath.type == "peace", "Oath replacement failed")
	for i in 6:
		game.get_node("%Actions").get_child(0).pressed.emit()
	check(game.state.turn == 6 and game.state.current == WorldRules.nearest(game.state, "ember").id, "Six-turn migration failed in UI")
	check(game.selected == game.state.current, "UI selection did not follow migration")
	check(game.state.cities[0].oath != null, "Old-city oath lost")
	var export_path = "user://ui-test-history.json"
	check(game.export_history(export_path), "Export failed")
	var exported = JSON.parse_string(FileAccess.get_file_as_string(export_path))
	check(exported.turn == 6 and exported.history.size() == game.state.history.size(), "Incomplete history export")
	await create_timer(0.5).timeout
	await capture("turn-06")
	var saved = game.state.duplicate(true)
	for c in game.state.cities:
		c.x = 500.0
		c.y = 300.0
	game.render(false)
	for i in 6:
		game.get_node("%CityTabs").get_child(i).pressed.emit()
		check(game.selected == game.state.cities[i].id, "Overlapping city unreachable")
	await process_frame
	await capture("overlap")
	game.state = saved
	game.selected = game.state.current
	game.render(false)
	for i in 54:
		action_button("observe").pressed.emit()
	check(game.state.ended and game.state.turn == 60, "UI could not reach ending")
	check(game.state.history.filter(func(h): return h.kind == "屏障结果").size() == 10, "Ten tenure results missing")
	check(game.state.ending.barriers.size() == 6, "Six-city barrier summary missing")
	check(game.get_node("%EndingDialog").visible, "Ending dialog did not open")
	check(game.get_node("%JudgeButton").disabled, "Oaths enabled after ending")
	for button in game.get_node("%Actions").get_children():
		check(button.disabled, "Action enabled after ending")
	await process_frame
	await capture("ending")
	game.get_node("%EndingDialog").hide()
	game.get_node("%RulesButton").pressed.emit()
	check(game.get_node("%RulesDialog").visible, "Rules dialog missing")
	check(game.get_node("%RulesDialog/Content").text.contains("街巷守望"), "Event guide incomplete")
	game.get_node("%RulesDialog").hide()
	game.get_node("%ResetButton").pressed.emit()
	check(game.state.turn == 0 and game.state.cities[0].oath == null, "Reset failed")
	game.get_node("%LegacyLaws").get_child(2).pressed.emit()
	check(game.pending.get("type") == "memory", "Debt law quick preview failed")
	check(game.state.cities[0].oath == null, "Law shortcut skipped confirmation")
	game.confirm_oath()
	for i in game.state.cities.size():
		var c = game.state.cities[i]
		c.territory = {"shape": "O", "angle": 0.0, "spin": 0.0}
		c.x = 400.0 if i == 0 else (560.0 if i == 1 else 850.0)
		c.y = 300.0 if i < 2 else 450.0
		c.vx = -sin(0.2 + c.origin.x) * 1.1
		c.vy = -cos(1.0 / 6.0 + c.origin.y) * 1.1
		c.eventSeen = ["hunger", "unrest", "seed", "market", "refugees", "feast", "craft", "isolation", "torch"]
	game.render()
	for id in ["forge", "forest", "farm", "investigate", "forge", "investigate"]:
		action_button(id).pressed.emit()
	check(game.state.turn == 6 and game.state.cities[0].barrier == 6, "Debt route could not build barrier")
	check(game.state.cities[0].barrierResults[0].title == "共誓", "Debt route outcome mismatch")
	await create_timer(0.4).timeout
	await capture("debt-route")
	game.select_city("ember")
	check(action_button("forge").disabled, "Finished barrier can still be repaired")
	game.reset_world()
	game.state.cities[0].trade = 0
	game.render()
	check(action_button("forge").disabled and action_button("forge").tooltip_text.contains("资源不足"), "Missing payment reason")
	game.perform("forge")
	check(game.state.turn == 0, "Failed payment advanced turn")
	game.reset_world()
	for i in 2:
		var c = game.state.cities[i]
		c.x = 400.0
		c.y = 300.0
		c.territory = {"shape": "O", "angle": 0.0, "spin": 0.0}
	game.render()
	check(not game.get_node("%MediateButton").disabled, "Diplomacy disabled for overlap")
	game.get_node("%MediateButton").pressed.emit()
	check(game.state.turn == 1 and not WorldRules.truce_for(game.state, "ember", "grove").is_empty(), "Diplomacy button failed")
	check(game.state.lastAction.cost.trade == 8, "Diplomacy payment missing")
	await create_timer(0.4).timeout
	await capture("truce")
	game.reset_world()
	root.size = Vector2i(1200, 880)
	await process_frame
	await capture("compact")
	if failures.is_empty():
		print("PASS: UI selection, remote locks, preview/confirmation, replacement, migration, overlap selection, export, 60-turn ending, guide and reset.")
		quit(0)
	else:
		for failure in failures:
			printerr(failure)
		quit(1)

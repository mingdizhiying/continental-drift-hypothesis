extends SceneTree
## Tests against a local fake proxy, never a real model provider.
var failures: Array[String] = []
var game: Control
var proxy = ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--proxy="):
			proxy = arg.trim_prefix("--proxy=")
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func run() -> void:
	if proxy.is_empty():
		printerr("Use tools/test-godot.mjs to start the fake proxy.")
		quit(1)
		return
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.get_node("%AIEnabled").set_pressed_no_signal(true)
	var client = game.get_node("%AIClient")
	client.endpoint = proxy + "/accept"
	game.get_node("%OathInput").text = "永不缺粮"
	await game.judge_oath()
	check(game.pending.get("source") == "真实AI", "Accepted proxy oath missing")
	check(game.state.cities[0].oath == null, "AI preview mutated state")
	game.confirm_oath()
	check(game.state.turn == 0 and game.state.cities[0].oath.source == "真实AI", "AI confirmation failed")
	client.endpoint = proxy + "/reject"
	game.get_node("%OathInput").text = "守护森林"
	await game.judge_oath()
	check(game.pending.is_empty(), "Explicit rejection fell back to local acceptance")
	check(game.get_node("%OathPreview").text.contains("模拟拒绝"), "Rejection reason missing")
	check(game.state.cities[0].oath.type == "food", "Rejected oath replaced old oath")
	for route in ["invalid", "invalid-condition", "unavailable", "bad-json"]:
		client.endpoint = proxy + "/" + route
		await game.judge_oath()
		check(game.pending.get("source") == "本地模拟", route + ": local fallback missing")
		check(game.get_node("%AIStatus").text.contains("改用本地模拟"), route + ": fallback not disclosed")
	game.clear_pending()
	client.endpoint = proxy + "/accept"
	await game.perform("observe")
	check(game.state.turn == 1, "AI action did not advance one turn")
	check(game.state.history.filter(func(h): return h.kind == "AI后快照").size() == 1, "AI turn effects not recorded")
	check(game.state.cities[0].food >= 50, "Proxy influence bypassed oath")
	client.endpoint = proxy + "/invalid"
	await game.perform("observe")
	check(game.state.turn == 2, "Invalid AI result blocked local turn")
	check(game.state.history.filter(func(h): return h.kind == "AI后快照").size() == 1, "Invalid AI effect applied")
	check(game.get_node("%AIStatus").text.contains("本轮使用本地规则"), "Invalid AI fallback not disclosed")
	for route in ["accept", "invalid"]:
		game.reset_world()
		for i in 59:
			game.state = game.rules.advance(game.state, "observe")
		game.selected = game.state.current
		client.endpoint = proxy + "/" + route
		await game.perform("observe")
		check(game.state.turn == 60 and game.state.ended, "Proxy ending blocked completion")
		check(game.state.ending.source == ("真实AI" if route == "accept" else "本地模拟"), route + ": wrong ending source")
		game.get_node("%EndingDialog").hide()
	if failures.is_empty():
		print("PASS: FAKE proxy HTTP transport, oath acceptance/rejection, invalid JSON/conditions, 503 fallback, bounded turn effects and ending fallback. No live model was tested.")
		quit(0)
	else:
		for failure in failures:
			printerr(failure)
		quit(1)

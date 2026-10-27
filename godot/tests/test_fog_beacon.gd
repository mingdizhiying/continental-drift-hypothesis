extends SceneTree
var failures: Array[String] = []
var screenshot_dir = ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshots="):
			screenshot_dir = arg.trim_prefix("--screenshots=")
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func fixture(rules: WorldRules) -> Dictionary:
	var s = rules.initial(123)
	var positions = [[350, 300], [478, 300], [510, 300], [606, 300], [900, 460], [100, 120]]
	for i in s.cities.size():
		var c = s.cities[i]
		c.x = float(positions[i][0])
		c.y = float(positions[i][1])
		c.territory = {"shape": "O", "angle": 0.0, "spin": 0.0}
	return s

func capture(name: String) -> void:
	if screenshot_dir.is_empty():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(screenshot_dir)
	root.get_texture().get_image().save_png(screenshot_dir.path_join(name + ".png"))

func run() -> void:
	var rules = WorldRules.new()
	var s = fixture(rules)
	var vision = WorldVision.visibility(s)
	check(not vision.global and vision.full == ["ember", "grove"], "Own/contact territories must be fully visible")
	check(vision.centers == ["tide"], "Trade must reveal only its center")
	check(WorldVision.level(vision, "archive") == "hidden", "Visibility incorrectly chained through adjacent city")
	check(not WorldVision.details_allowed(s, "grove"), "Neighbor reveals internal city details")
	var corner = s.duplicate(true)
	corner.cities[1].x = 478.0
	corner.cities[1].y = 428.0
	check(WorldVision.level(WorldVision.visibility(corner), "grove") == "full", "Corner contact should count as touching")
	var near = s.duplicate(true)
	near.cities[1].x += 0.01
	check(WorldVision.level(WorldVision.visibility(near), "grove") == "center", "Trade radius confused with actual contact")
	var truce = s.duplicate(true)
	truce.truces = [{"a": "ember", "b": "tide", "from": 0, "until": 3}, {"a": "ember", "b": "grove", "from": 0, "until": 3}]
	var truce_vision = WorldVision.visibility(truce)
	check(WorldVision.level(truce_vision, "grove") == "full" and WorldVision.level(truce_vision, "tide") == "hidden", "Truce should keep actual contact visible but grant no trade-center vision")
	var before = s.duplicate(true)
	var lit = rules.light_beacon(s)
	check(s == before, "Lighting mutated original state")
	check(lit.turn == 0 and lit.current == s.current and lit.events == s.events, "Lighting advanced round or citizen event")
	check(lit.cities[0].trade == 22 and lit.cities[0].food == 45 and lit.cities[0].ecology == 67 and lit.cities[0].peace == 60, "Beacon payment mismatch")
	for i in 6:
		check(lit.cities[i].x == s.cities[i].x and lit.cities[i].y == s.cities[i].y and lit.cities[i].territory.angle == s.cities[i].territory.angle, "Lighting moved/rotated a city")
	check(WorldVision.full_view(lit) and WorldVision.visibility(lit).full.size() == 6, "Lighting did not immediately reveal full map")
	check(lit.cities[0].beacon.anchor == {"x": 350.0, "y": 300.0, "angle": 0.0}, "Beacon anchor mismatch")
	check(rules.light_beacon(lit).has("error"), "Repeat lighting accepted")
	var unchanged = lit.duplicate(true)
	check(rules.advance(lit, "not-an-action").has("error") and lit == unchanged and WorldVision.full_view(lit), "Failed action consumed reveal")
	var vowed = WorldRules.set_oath(lit, WorldRules.parse_oath("永远和平"))
	check(vowed.turn == 0 and WorldVision.full_view(vowed), "Oath consumed reveal")
	var next = rules.advance(lit, "observe")
	check(next.turn == 1 and not WorldVision.full_view(next), "Reveal did not expire after next successful action")
	check(next.cities[0].beacon != null and rules.light_beacon(next).has("error"), "Permanent beacon lost or flash repeatable")
	var poor = s.duplicate(true)
	poor.cities[0].trade = 19
	var poor_before = poor.duplicate(true)
	check(rules.light_beacon(poor).has("error") and poor == poor_before and not WorldVision.full_view(poor), "Failed payment mutated state or revealed map")
	var paid = WorldRules.set_oath(s, WorldRules.parse_oath("守护贸易繁荣"))
	paid = rules.light_beacon(paid)
	check(paid.cities[0].trade == 22, "Oath refunded beacon cost immediately")
	paid = rules.advance(paid, "observe")
	check(paid.cities[0].trade >= 22 and paid.cities[0].trade < 42, "Next round refunded beacon cost")
	var dormant = WorldRules.set_oath(s, WorldRules.parse_oath("固定位置"))
	dormant.cities[0].peace = 0
	dormant.cities[0].x = 400.0
	dormant.cities[0].territory.spin = 3.0
	dormant.cities[0].territory.angle = 37.0
	dormant = rules.light_beacon(dormant)
	dormant.cities[0].peace = 60
	for i in 12:
		dormant = rules.advance(dormant, "observe")
		check(dormant.cities[0].x == 400.0 and dormant.cities[0].y == 300.0 and dormant.cities[0].territory.angle == 37.0, "Beacon did not freeze center/rotation or lost priority over old anchor oath")
	check(not WorldVision.full_view(dormant), "Permanent beacon kept global vision forever")
	check(dormant.history.filter(func(h): return h.kind == "迁城").size() == 2, "Beacon blocked governance migration")
	dormant.current = "ember"
	check(rules.light_beacon(dormant).has("error"), "Returning to lit city allowed duplicate payment")
	var roundtrip = JSON.parse_string(JSON.stringify(dormant))
	check(roundtrip.cities[0].beacon.anchor.angle == 37 and roundtrip.cities[0].beacon.litAt == 0 and roundtrip.fullVisionTurn == 0, "Export lost beacon/reveal data")
	var fresh = rules.initial(123)
	check(fresh.cities.all(func(c): return c.beacon == null) and not WorldVision.full_view(fresh), "New world retained old beacons")
	var ended = s.duplicate(true)
	ended.ended = true
	check(rules.light_beacon(ended).has("error"), "Beacon accepted after ending")
	var data = rules.config.duplicate(true)
	var custom = WorldRules.new(data)
	for cost in [{"trade": -1}, {"barrier": 1}, {"food": 1.5}]:
		data.beacon_cost = cost
		check(custom.light_beacon(s).has("error"), "Invalid editable beacon cost accepted")

	# Actual scene/UI checks use default fog; the baseline UI suite separately
	# tests original v0.3.2 interactions with its independent fog-off config.
	root.size = Vector2i(1440, 960)
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_seed = 123
	root.add_child(game)
	await process_frame
	game.state = fixture(game.rules)
	game.render()
	await process_frame
	var map = game.get_node("%WorldMap")
	check(map.views.ember.visible and map.views.grove.visible and not map.views.archive.visible, "Fog map did not hide distant city")
	check(map.views.tide.visible and map.views.tide.get_node("LabelRoot/Button").disabled, "Trade center not visible/disabled")
	check(map.views.tide.plates.all(func(p): return not p.visible) and map.views.grove.plates.all(func(p): return p.visible), "Trade center leaked territory or contact territory missing")
	check(not game.city_buttons.archive.visible and game.city_buttons.tide.disabled and game.city_buttons.grove.visible, "City tabs bypass fog")
	check(game.get_node("%Next").text.contains("揭晓"), "Next-city prediction leaks hidden city")
	await capture("fog-contact-trade")
	game.select_city("archive")
	check(game.selected == "ember", "Hidden city selectable")
	game.select_city("tide")
	check(game.selected == "ember", "Center-only city selectable")
	game.select_city("grove")
	check(game.selected == "grove" and not game.get_node("%Food").get_parent().visible and not game.get_node("%Tabs").visible, "Contact city leaked internal details")
	check(not map.views.archive.visible, "Selecting a neighbor expanded observing area")
	game.light_beacon()
	check(game.state.cities[1].beacon == null and game.state.cities[0].beacon == null, "Lit a remote city")
	game.select_city("ember")
	game.get_node("%BeaconButton").pressed.emit()
	check(game.state.turn == 0 and game.state.cities[0].beacon != null and not game.get_node("%EchoDialog").visible, "Beacon UI advanced time or opened round echo")
	check(map.views.values().all(func(v): return v.visible and v.vision_level == "full"), "UI lighting did not reveal all territory")
	check(game.get_node("%BeaconButton").disabled and game.get_node("%FogStatus").text.contains("本轮全图"), "Beacon state/reveal explanation missing")
	await capture("beacon-full-map")
	game.select_city("archive")
	check(game.selected == "archive" and game.get_node("%Food").get_parent().visible, "Flash did not allow full inspection")
	game.select_city("ember")
	await game.perform("observe")
	check(not WorldVision.full_view(game.state) and map.vision.full.size() < 6, "UI did not restore fog after action")
	check(game.get_node("%EchoDialog").visible, "Normal action stopped opening echo")
	game.get_node("%EchoDialog").get_ok_button().pressed.emit()
	await process_frame
	await create_timer(0.4).timeout
	await capture("beacon-fixed-fog-returned")
	game.state.history.append({"turn": game.state.turn, "kind": "AI判定", "text": "不可泄露的远方信息"})
	game.render()
	check(not game.get_node("%History").text.contains("不可泄露"), "Free-form AI world summary bypassed fog")
	game.open_echo()
	check(not game.get_node("%EchoDialog").get_node("%EchoBody").text.contains("不可泄露"), "Echo bypassed fog")
	game.get_node("%EchoDialog").get_ok_button().pressed.emit()
	await process_frame
	game.reset_world()
	check(not WorldVision.full_view(game.state) and game.state.cities[0].beacon == null, "UI reset retained reveal")
	root.size = Vector2i(1200, 880)
	await capture("fog-compact")
	if failures.is_empty():
		print("PASS: fog contact/trade/hidden/chain policy, scene information gates, beacon payment/no-turn/one-round reveal, permanent center+rotation freeze, oath priority, migration, reset and export.")
		quit(0)
	else:
		for failure in failures:
			printerr(failure)
		quit(1)

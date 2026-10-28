extends SceneTree

var failures: Array[String] = []
var comparisons = 0

func _initialize() -> void:
	call_deferred("run")

func frame(s: Dictionary) -> Dictionary:
	# Fog/beacons extend the Godot game. Unlit beacons must not change the
	# pinned v0.3.2 simulation; compare all original city fields unchanged.
	var cities: Array = []
	for source in s.cities:
		var c = source.duplicate(true)
		c.erase("beacon")
		cities.append(c)
	return {"turn": s.turn, "current": s.current, "visited": s.visited, "ended": s.ended,
		"cities": cities, "events": s.events, "interactions": s.get("interactions", []),
		"links": s.get("links", []), "historyCount": s.history.size(),
		"lastAction": s.get("lastAction"),
		"seed": s.seed, "truces": s.truces,
		"historyTail": s.history.filter(func(h): return not h.has("cities")).slice(-5), "ending": s.ending}

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func compare(actual: Variant, expected: Variant, path: String) -> void:
	if failures.size() > 20:
		return
	comparisons += 1
	if (actual is float or actual is int) and (expected is float or expected is int):
		check(abs(float(actual) - float(expected)) < 0.0000001, "%s: %s != %s" % [path, actual, expected])
	elif actual is Dictionary and expected is Dictionary:
		check(actual.size() == expected.size(), "%s: dictionary keys differ" % path)
		for key in expected:
			check(actual.has(key), "%s: missing %s" % [path, key])
			if actual.has(key):
				compare(actual[key], expected[key], path + "." + str(key))
	elif actual is Array and expected is Array:
		check(actual.size() == expected.size(), "%s: array sizes differ (%s/%s)" % [path, actual.size(), expected.size()])
		for i in mini(actual.size(), expected.size()):
			compare(actual[i], expected[i], path + "[%d]" % i)
	else:
		check(actual == expected, "%s: %s != %s" % [path, actual, expected])

func run() -> void:
	var rules = WorldRules.new()
	var path = ProjectSettings.globalize_path("res://").path_join("../godot-test-data/reference.json")
	if not FileAccess.file_exists(path):
		printerr("Run node tools/godot-reference.mjs from the repository first.")
		quit(1)
		return
	var scenarios = JSON.parse_string(FileAccess.get_file_as_string(path))
	for scenario in scenarios:
		var s = rules.initial(int(scenario.seed))
		var last_before = s
		compare(frame(s), scenario.frames[0], scenario.name + "/initial")
		for i in scenario.ops.size():
			var op = scenario.ops[i]
			var next = s
			match op.kind:
				"oath": next = WorldRules.set_oath(s, WorldRules.parse_oath(op.text))
				"patch": WorldRules.city(s, op.city).merge(op.values, true)
				"worldPatch": s.merge(op.values.duplicate(true), true)
				"ai": next = WorldRules.apply_ai_turn(s, op.data, last_before)
				_:
					last_before = s
					next = rules.advance(s, op.action, op.get("targetId", ""))
			if op.has("expectedError"):
				check(next.get("error") == op.expectedError, scenario.name + ": rejection mismatch " + str(next.get("error")))
			else:
				check(not next.has("error"), scenario.name + ": unexpected rejection")
				s = next
			compare(frame(s), scenario.frames[i + 1], scenario.name + "/%d" % i)
		print("Reference scenario: ", scenario.name)
	for text in ["", "无限资源", "守护粮食与和平", "大家幸福"]:
		check(WorldRules.parse_oath(text).has("error"), "Must reject oath: " + text)
	var original = rules.initial()
	var protected = WorldRules.set_oath(original, WorldRules.parse_oath("永不缺粮"))
	check(original.cities[0].oath == null, "set_oath mutated input")
	var n = rules.advance(protected, "observe")
	check(protected.turn == 0, "advance mutated input")
	var data = {"summary": "测试保护", "effects": [{"cityId": "ember", "delta": {"food": -3}, "reason": "保护边界"}]}
	var a = WorldRules.apply_ai_turn(n, data, protected)
	check(a.cities[0].food >= protected.cities[0].food, "AI bypassed oath")
	data.effects[0].delta.food = 100
	check(WorldRules.apply_ai_turn(n, data, protected).has("error"), "Unbounded AI accepted")
	data.effects[0].delta.food = 1
	data.effects.append(data.effects[0].duplicate(true))
	check(WorldRules.apply_ai_turn(n, data, protected).has("error"), "Duplicate AI city accepted")
	var end = rules.initial()
	for i in 60:
		end = rules.advance(end, "observe")
	check(rules.advance(end, "observe").has("error"), "Actions after ending accepted")
	check(WorldRules.set_oath(end, WorldRules.parse_oath("守护森林")).has("error"), "Oath after ending accepted")
	var roundtrip = JSON.parse_string(JSON.stringify(end))
	compare(roundtrip, end, "JSON export roundtrip")
	if failures.is_empty():
		print("PASS: %d scenarios, %d recursive comparisons; oath, AI, immutability, ending and JSON checks." % [scenarios.size(), comparisons])
		quit(0)
	else:
		for failure in failures:
			printerr(failure)
		quit(1)

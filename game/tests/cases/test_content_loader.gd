extends RefCounted
## Самопроверка загрузчика контента.
##
## Главный кейс здесь — ЭКВИВАЛЕНТНОСТЬ: миссия, собранная из словаря, обязана
## совпасть с той, что собирает фикстура кодом. Два пути к одной модели расходятся
## молча, и заметить это можно только сравнением. Числа взяты из
## `tests/fixtures/small_mission.gd` дословно.

const Assert := preload("res://tests/assert.gd")
const Problems := preload("res://content/problems.gd")
const Loader := preload("res://content/loader.gd")
const Fixture := preload("res://tests/fixtures/small_mission.gd")


## Словарь-двойник фикстуры: тот же граф, но выраженный данными.
func _fixture_data() -> Dictionary:
	return {
		"id": "small",
		"nodes": {
			"dock": {"floor": 1, "tags": ["entry"]},
			"hall": {"floor": 1, "tags": []},
			"office2": {"floor": 2, "tags": []},
			"vault": {"floor": 2, "tags": ["locked_room"]},
			"it4": {"floor": 4, "tags": []},
			"archive0": {"floor": 0, "tags": ["cold_archive"]},
		},
		"edges": [
			{"id": "e_dock_hall", "a": "dock", "b": "hall", "kind": "corridor", "steps": 1, "noise": 0},
			{"id": "e_hall_office", "a": "hall", "b": "office2", "kind": "stairs", "steps": 3, "noise": 0},
			{"id": "e_office_it", "a": "office2", "b": "it4", "kind": "stairs", "steps": 12, "noise": 0},
			{"id": "e_office_vault", "a": "office2", "b": "vault", "kind": "door", "steps": 1, "noise": 8, "locked": true},
			{"id": "e_hall_lift", "a": "hall", "b": "it4", "kind": "lift_main", "steps": 2, "noise": 4},
			{"id": "e_dock_freight", "a": "dock", "b": "archive0", "kind": "lift_freight", "steps": 3, "noise": 4},
			{"id": "e_hall_archive", "a": "hall", "b": "archive0", "kind": "stairs", "steps": 3, "noise": 0},
		],
		"patrols": [{"id": "guard_1", "route": ["hall", "office2"], "period": 2}],
		"sensors": [
			{"id": "s_hall", "nodes": ["hall"]},
			{"id": "s_it", "nodes": ["it4"]},
		],
		"objective": "archive0",
	}


func run() -> Array:
	var t := Assert.new()

	# 1. Загрузка словаря: миссия собрана.
	var res := Loader.load_mission(_fixture_data(), {"mission.01.title": "Т"})
	t.is_true("словарь загружен без проблем", (res["problems"] as Array).is_empty())
	t.is_true("миссия собрана", res["mission"] != null)

	# 2. ЭКВИВАЛЕНТНОСТЬ: словарь даёт ровно ту же модель, что и код.
	var loaded = res["mission"]
	var built = Fixture.build()
	t.eq("id совпадает", loaded.id, built.id)
	t.eq("objective совпадает", loaded.objective, built.objective)
	t.eq("помещений столько же", loaded.nodes.size(), built.nodes.size())
	t.eq("рёбер столько же", loaded.edges.size(), built.edges.size())
	t.eq("патрулей столько же", loaded.patrols.size(), built.patrols.size())
	t.eq("сенсоров столько же", loaded.sensors.size(), built.sensors.size())
	for node_id in built.nodes:
		t.eq("помещение %s: этаж" % node_id, loaded.nodes[node_id]["floor"], built.nodes[node_id]["floor"])
		t.eq("помещение %s: теги" % node_id, loaded.nodes[node_id]["tags"], built.nodes[node_id]["tags"])
	for i in built.edges.size():
		for field in ["id", "a", "b", "kind", "steps", "noise", "locked"]:
			t.eq("ребро %d: %s" % [i, field], loaded.edges[i][field], built.edges[i][field])
	for i in built.patrols.size():
		for field in ["id", "route", "period"]:
			t.eq("патруль %d: %s" % [i, field], loaded.patrols[i][field], built.patrols[i][field])
	for i in built.sensors.size():
		for field in ["id", "nodes"]:
			t.eq("сенсор %d: %s" % [i, field], loaded.sensors[i][field], built.sensors[i][field])
	t.is_true("миссия из словаря валидна по mission.validate()", (loaded.validate() as Array).is_empty())

	# 3. Типы: JSON приходит с float-числами, ядро ждёт int.
	var from_json := _fixture_data()
	from_json["edges"][1]["steps"] = 3.0
	from_json["nodes"]["hall"]["floor"] = 1.0
	from_json["patrols"][0]["period"] = 2.0
	var json_res := Loader.load_mission(from_json)
	t.is_true("float-числа приняты", (json_res["problems"] as Array).is_empty())
	t.is_true("шаги стали int", typeof(json_res["mission"].edges[1]["steps"]) == TYPE_INT)
	t.is_true("этаж стал int", typeof(json_res["mission"].nodes["hall"]["floor"]) == TYPE_INT)
	t.is_true("период стал int", typeof(json_res["mission"].patrols[0]["period"]) == TYPE_INT)

	# 4. Строка JSON грузится тем же путём.
	var json_text := '{"id":"j","nodes":{"a":{"floor":1,"tags":["entry"]},"b":{"floor":1,"tags":[]}},' \
		+ '"edges":[{"id":"e_ab","a":"a","b":"b","kind":"corridor","steps":1,"noise":0}],' \
		+ '"patrols":[],"sensors":[],"objective":"b"}'
	var parsed := Loader.load_text(json_text)
	t.is_true("строка JSON разобрана", (parsed["problems"] as Array).is_empty())
	t.eq("из строки собрана цель", parsed["mission"].objective, "b")

	# 5. Битый JSON — проблема разбора, а не падение.
	var broken := Loader.load_text("{не json")
	t.is_true("битый JSON — проблема", not (broken["problems"] as Array).is_empty())
	t.is_true("битый JSON: миссии нет", broken["mission"] == null)
	t.eq("битый JSON: код", String(broken["problems"][0]["code"]), Problems.MISSING_FIELD)

	# 6. Отсутствующее обязательное поле — MISSING_FIELD, а не падение в add_edge.
	var no_route := _fixture_data()
	no_route["patrols"][0].erase("route")
	var missing_res := Loader.load_mission(no_route)
	t.is_true("патруль без маршрута — MISSING_FIELD",
		Problems.has(missing_res["problems"], Problems.MISSING_FIELD))

	var no_objective := _fixture_data()
	no_objective.erase("objective")
	t.is_true("миссия без цели — MISSING_FIELD",
		Problems.has(Loader.load_mission(no_objective)["problems"], Problems.MISSING_FIELD))

	# 7. Неверный тип не доезжает до ядра.
	var bad_steps := _fixture_data()
	bad_steps["edges"][0]["steps"] = "много"
	t.is_true("шаги строкой — WRONG_TYPE",
		Problems.has(Loader.load_mission(bad_steps)["problems"], Problems.WRONG_TYPE))

	# 8. Некорректная миссия не отдаётся вовсе: иначе ядро получило бы полумиссию.
	t.is_true("при проблемах миссии нет", Loader.load_mission(bad_steps)["mission"] == null)

	# 9. План грузится отдельно: маршрут, выход, состав.
	var plan := Loader.load_plan({
		"route": ["dock", "hall", "archive0"],
		"exit_node": "dock",
		"agents": [{"id": "kira", "role": "tactician", "understanding": 3}],
	})
	t.is_true("план собран", plan != null)
	t.eq("маршрут плана", plan.route, ["dock", "hall", "archive0"])
	t.eq("выход плана", plan.exit_node, "dock")
	t.eq("состав плана", plan.agents.size(), 1)

	# 10. План без маршрута — не падение, а явная пустота: setup сам скажет «маршрут пуст».
	var empty_plan := Loader.load_plan({})
	t.is_true("план без данных собран", empty_plan != null)
	t.is_true("маршрут пуст", empty_plan.route.is_empty())

	return t.results

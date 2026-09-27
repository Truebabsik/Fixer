extends RefCounted
## Загрузчик контента: словарь или JSON → модель миссии.
##
## Зачем отдельный модуль. `sim/` не должен знать про JSON: там чистая логика графа.
## Всё, что связано с формой файла — отсутствующие поля, числа как float после разбора,
## приведение типов — живёт здесь и только здесь.
##
## Правило: сначала валидатор, потом сборка. Если словарь негоден, миссия НЕ собирается
## вовсе: полумиссия в ядре хуже отказа, потому что падает позже и непонятнее.

const Problems := preload("res://content/problems.gd")
const Validator := preload("res://content/validator.gd")
const Mission := preload("res://sim/mission.gd")
const Plan := preload("res://sim/plan.gd")


## Разбор строки JSON и загрузка. Возвращает тот же результат, что load_mission.
static func load_text(json_text: String, texts: Dictionary = {}) -> Dictionary:
	var parsed = JSON.parse_string(json_text)
	if parsed == null:
		return _fail(Problems.missing_field("(корень)", "корректный JSON"),
			"строка не разбирается как JSON")
	return load_mission(parsed, texts)


## Возвращает {"mission": Mission|null, "texts": Dictionary, "problems": Array}.
## mission == null ровно тогда, когда problems непуст.
static func load_mission(data, texts: Dictionary = {}) -> Dictionary:
	var problems: Array = Validator.validate(data, texts)
	if not problems.is_empty():
		return {"mission": null, "texts": {}, "problems": problems}
	var mission := Mission.new()
	mission.id = String(data.get("id", ""))
	for node_id in data["nodes"]:
		var node: Dictionary = data["nodes"][node_id]
		mission.add_node(String(node_id), to_int(node["floor"]), _string_list(node.get("tags", [])))
	for e in data["edges"]:
		mission.add_edge(String(e["id"]), String(e["a"]), String(e["b"]), String(e["kind"]),
			to_int(e["steps"]), to_int(e["noise"]), bool(e.get("locked", false)))
	for p in data.get("patrols", []):
		mission.add_patrol(String(p["id"]), _string_list(p["route"]), to_int(p.get("period", 4)))
	for s in data.get("sensors", []):
		mission.add_sensor(String(s["id"]), _string_list(s["nodes"]))
	mission.objective = String(data["objective"])
	mission.set_data({
		"windows": _deep(data.get("windows", [])),
		"intel": _deep(data.get("intel", [])),
		"access_points": _deep(data.get("access_points", [])),
		"texts": texts.duplicate(true),
	})
	return {"mission": mission, "texts": texts.duplicate(true), "problems": []}


## План грузится отдельно от миссии: он приходит из фазы планирования, а не из контента
## уровня. Отсутствующие поля — не ошибка: `Sim.setup` сам проверяет маршрут и скажет
## «маршрут пуст» понятнее, чем загрузчик.
static func load_plan(data: Dictionary) -> Plan:
	var plan := Plan.new()
	if data.has("route"):
		plan.route = _string_list(data["route"])
	if data.has("exit_node"):
		plan.exit_node = String(data["exit_node"])
	if data.has("exit_backup_node"):
		plan.exit_backup_node = String(data["exit_backup_node"])
	if data.has("cargo_heavy"):
		plan.cargo_heavy = bool(data["cargo_heavy"])
	if data.has("agents") and typeof(data["agents"]) == TYPE_ARRAY:
		var agents: Array = []
		for a in data["agents"]:
			agents.append({
				"id": String(a.get("id", "")),
				"role": String(a.get("role", "tactician")),
				"understanding": to_int(a.get("understanding", 3)),
			})
		plan.agents = agents
	return plan


## Число как int. JSON в Godot отдаёт числа float, а `add_*` типизированы: без
## приведения движок откажется принимать значение.
static func to_int(value) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_FLOAT:
		return int(round(value))
	return 0


static func _string_list(value) -> Array:
	var out: Array = []
	if typeof(value) != TYPE_ARRAY:
		return out
	for item in value:
		out.append(String(item))
	return out


static func _deep(value):
	return value.duplicate(true) if value is Array or value is Dictionary else value


static func _fail(problem: Dictionary, _why: String) -> Dictionary:
	return {"mission": null, "texts": {}, "problems": [problem]}

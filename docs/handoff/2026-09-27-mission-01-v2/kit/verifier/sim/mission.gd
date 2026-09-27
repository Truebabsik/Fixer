extends RefCounted
## Описание миссии: граф помещений, патрули, сенсоры, цель.
## Только данные и валидация — никакой логики хода.

const EDGE_KINDS := ["door", "corridor", "lift_main", "lift_freight", "stairs"]

## Разделы данных, которые ядру передаёт контент-конвейер (content/loader.gd).
## Это НЕ рантайм-состояние: ядро их читает, но не меняет. `data` держит разделы,
## чья форма ещё не устоялась в жёстком API миссии — окна, разведданные, точки
## доступа, тексты, название уровня.
##
## Умолчания разные: разделы-списки начинаются пустым массивом, `title_key` — пустой
## строкой. Поэтому список и умолчания разведены, а не собраны одним циклом.
const DATA_SECTIONS := ["windows", "intel", "access_points", "texts", "title_key"]
## Держать в согласии с `Validator.ARRAY_SECTIONS` (`content/validator.gd`): там — ВСЕ
## шесть корневых массивов ФАЙЛА (`edges`, `patrols`, `sensors` живут в жёстком API миссии
## и через `data` не едут), здесь — что модель принимает в `data`. Списки не равны
## дословно, но новая секция контента обязана появиться в обоих, иначе файл пройдёт
## валидатор, а раздел молча не доедет до модели (`set_data` его не знает).
const DATA_ARRAY_SECTIONS := ["windows", "intel", "access_points", "texts"]

var id: String = ""
var nodes: Dictionary = {}
var edges: Array = []
var patrols: Array = []
var sensors: Array = []
var objective: String = ""

## Разделы контента, не входящие в жёсткое API выше. Фикстура собирает миссию
## прежним API, поэтому пустые разделы — валидное состояние.
var data: Dictionary = {}


func _init() -> void:
	for section in DATA_ARRAY_SECTIONS:
		data[section] = []
	data["title_key"] = ""


## Принять разделы контента. Ключи, которых схема не знает, здесь не проверяются:
## это дело `content/validator.gd`, а не модели миссии.
func set_data(sections: Dictionary) -> void:
	for section in DATA_SECTIONS:
		if sections.has(section):
			data[section] = sections[section]


func add_node(node_id: String, floor: int, tags: Array = []) -> void:
	nodes[node_id] = {"floor": floor, "tags": tags}


func add_edge(edge_id: String, a: String, b: String, kind: String, steps: int, noise: int, locked := false) -> void:
	edges.append({"id": edge_id, "a": a, "b": b, "kind": kind, "steps": steps, "noise": noise, "locked": locked})


func add_patrol(patrol_id: String, route: Array, period := 4) -> void:
	patrols.append({"id": patrol_id, "route": route, "period": period})


func add_sensor(sensor_id: String, node_ids: Array) -> void:
	sensors.append({"id": sensor_id, "nodes": node_ids})


func edge(edge_id: String) -> Dictionary:
	for e in edges:
		if String(e["id"]) == edge_id:
			return e
	return {}


## Рёбра узла, отсортированные по id: фиксированный порядок обхода ради детерминизма.
func edges_at(node_id: String) -> Array:
	var out: Array = []
	for e in edges:
		if String(e["a"]) == node_id or String(e["b"]) == node_id:
			out.append(e)
	out.sort_custom(func(x, y): return String(x["id"]) < String(y["id"]))
	return out


func edge_between(a: String, b: String) -> Dictionary:
	for e in edges_at(a):
		var ea := String(e["a"])
		var eb := String(e["b"])
		if (ea == a and eb == b) or (eb == a and ea == b):
			return e
	return {}


func other_end(e: Dictionary, node_id: String) -> String:
	return String(e["b"]) if String(e["a"]) == node_id else String(e["a"])


## Пустой список = миссия валидна. Иначе — человекочитаемые проблемы.
func validate() -> Array:
	var problems: Array = []
	if nodes.is_empty():
		problems.append("нет ни одного помещения")
	if objective == "":
		problems.append("цель не задана")
	elif not nodes.has(objective):
		problems.append("цель ссылается на несуществующее помещение %s" % objective)
	for e in edges:
		if not nodes.has(String(e["a"])):
			problems.append("ребро %s ссылается на несуществующее помещение %s" % [e["id"], e["a"]])
		if not nodes.has(String(e["b"])):
			problems.append("ребро %s ссылается на несуществующее помещение %s" % [e["id"], e["b"]])
		if not EDGE_KINDS.has(String(e["kind"])):
			problems.append("ребро %s: неизвестный вид %s" % [e["id"], e["kind"]])
	for p in patrols:
		for n in p["route"]:
			if not nodes.has(String(n)):
				problems.append("патруль %s ссылается на несуществующее помещение %s" % [p["id"], n])
	for s in sensors:
		for n in s["nodes"]:
			if not nodes.has(String(n)):
				problems.append("сенсор %s ссылается на несуществующее помещение %s" % [s["id"], n])
	return problems


## Непрерывность маршрута: между соседними точками должно быть ребро.
func validate_route(route: Array) -> Array:
	var problems: Array = []
	for i in range(route.size() - 1):
		if edge_between(String(route[i]), String(route[i + 1])).is_empty():
			problems.append("между %s и %s нет ребра" % [route[i], route[i + 1]])
	return problems

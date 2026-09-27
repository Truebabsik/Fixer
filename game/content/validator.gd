extends RefCounted
## Валидатор контента: словарь миссии (+ тексты) → список проблем с кодами.
##
## Зачем отдельно от `Mission.validate()`. Та проверяет уже собранную модель и отдаёт
## русские строки. Здесь — проверка ФАЙЛА: типы, неизвестные ключи, дубли, достижимость,
## инварианты окон. Разные вопросы, разные ответы: «миссия внутри несогласована» и
## «файл контента неверен, вот где». Дублирование ссылочных проверок осознанно.
##
## Валидатор ничего не чинит и не бросает: на любой дефект — проблема в списке.
## Проверки, зависящие от уже испорченного поля, пропускаются: одна ошибка в файле
## не должна порождать десяток следствий, среди которых автор не найдёт причину.

const Problems := preload("res://content/problems.gd")
## Виды рёбер живут в `sim/mission.gd`: валидатор их не дублирует, а спрашивает,
## чтобы список не разошёлся с ядром (соглашение §6.1: только const preload).
const Mission := preload("res://sim/mission.gd")

const ROOT_KEYS := ["id", "title_key", "nodes", "edges", "patrols", "sensors",
	"objective", "windows", "intel", "access_points", "note"]
const NODE_KEYS := ["floor", "tags", "note"]
const EDGE_KEYS := ["id", "a", "b", "kind", "steps", "noise", "locked", "note"]
const PATROL_KEYS := ["id", "route", "period", "note"]
const SENSOR_KEYS := ["id", "nodes", "note"]
const WINDOW_KEYS := ["id", "kind", "trigger", "text_key", "options", "silence", "note"]
const OPTION_KEYS := ["id", "text_key", "complexity", "cost", "effects", "note"]
const COST_KEYS := ["noise", "delay", "note"]
const SILENCE_KEYS := ["text_key", "good", "neutral", "bad", "safe", "note"]
const TRIGGER_KEYS := ["type", "edge", "node", "sensor", "note"]
const EFFECT_KEYS := ["type", "edge", "value", "id", "want", "needs", "fallback", "note"]
const INTEL_KEYS := ["channel", "observed_at", "entries", "note"]
const INTEL_ENTRY_KEYS := ["kind", "id", "route", "period", "nodes", "node", "count",
	"age_hours", "false", "note_key", "note"]
const POINT_KEYS := ["id", "node", "kind", "text_key", "actions", "note"]
const ACTION_KEYS := ["id", "text_key", "complexity", "cost", "effects", "note"]

## Виды эффектов, известные ядру. Всё остальное — только через engine_proposal.
const EFFECT_TYPES := ["unlock", "noise", "delay", "noop", "engine_proposal", "money", "trace"]
const POINT_KINDS := ["terminal", "door_panel", "camera", "climate"]
const TRIGGER_TYPES := ["locked_edge", "node_entered", "guard_in_sensor"]
const INTEL_KINDS := ["patrol", "sensor", "guard_count", "door_state"]
const SILENCE_QUALITIES := ["good", "neutral", "bad", "safe"]

## Свои агенты заняты движком: под этими id в patrols нельзя.
const RESERVED_AGENT_IDS := ["kira", "echo"]

## Ключи вне данных, которые обязаны существовать всегда (см. 04-texts.md §4
## постановки). Они не считаются висячими, даже если ни одно окно на них не ссылается.
const UNUSED_OK_PREFIXES := ["mission.", "negotiation.", "team.", "log.", "voice.",
	"final.", "outcome.", "results."]


## problems = validate(mission_dict, texts ?= {}).
static func validate(data, texts: Dictionary = {}) -> Array:
	if typeof(data) != TYPE_DICTIONARY:
		return [Problems.wrong_type("(корень)", "словарь", type_string(typeof(data)))]
	var problems: Array = []

	_check_root_keys(data, problems)
	var nodes := _check_nodes(data, problems)
	_check_edges(data, nodes, problems)
	_check_patrols(data, nodes, problems)
	_check_sensors(data, nodes, problems)
	_check_objective(data, nodes, problems)
	_check_reachability(data, nodes, problems)
	_check_windows(data, _known_ids(data, "edges"), _known_ids(data, "sensors"), problems)
	_check_intel(data, _known_ids(data, "patrols"), problems)
	_check_access_points(data, nodes, problems)
	_check_texts(data, texts, problems)
	return problems


## Множество id раздела — для проверки ссылок на него.
static func _known_ids(data: Dictionary, section: String) -> Dictionary:
	var out := {}
	if not data.has(section) or typeof(data[section]) != TYPE_ARRAY:
		return out
	for item in data[section]:
		if typeof(item) == TYPE_DICTIONARY and item.has("id"):
			out[String(item["id"])] = true
	return out


# --- структура ----------------------------------------------------------------

static func _check_root_keys(data: Dictionary, problems: Array) -> void:
	for key in data:
		if not ROOT_KEYS.has(String(key)):
			problems.append(Problems.unknown_key(String(key), String(key)))
	for required in [["nodes", TYPE_DICTIONARY], ["edges", TYPE_ARRAY], ["objective", TYPE_STRING]]:
		var name: String = required[0]
		if not data.has(name):
			problems.append(Problems.missing_field(name, type_string(required[1])))
		else:
			_expect_type(data[name], required[1], name, problems)


static func _check_nodes(data: Dictionary, problems: Array) -> Dictionary:
	var nodes: Dictionary = {}
	if not data.has("nodes") or typeof(data["nodes"]) != TYPE_DICTIONARY:
		return nodes
	if (data["nodes"] as Dictionary).is_empty():
		problems.append(Problems.empty_section("nodes"))
		return nodes
	for node_id in data["nodes"]:
		var node = data["nodes"][node_id]
		var path := "nodes.%s" % String(node_id)
		if typeof(node) != TYPE_DICTIONARY:
			problems.append(Problems.wrong_type(path, "словарь", type_string(typeof(node))))
			continue
		_check_keys(node, NODE_KEYS, path, problems)
		if not node.has("floor"):
			problems.append(Problems.missing_field("%s.floor" % path, "int"))
		else:
			_expect_int(node["floor"], "%s.floor" % path, problems)
		if node.has("tags"):
			_check_string_array(node["tags"], "%s.tags" % path, problems)
		nodes[String(node_id)] = node
	return nodes


static func _check_edges(data: Dictionary, nodes: Dictionary, problems: Array) -> void:
	if not data.has("edges") or typeof(data["edges"]) != TYPE_ARRAY:
		return
	var seen: Array = []
	for i in (data["edges"] as Array).size():
		var e = data["edges"][i]
		var path := "edges[%d]" % i
		if typeof(e) != TYPE_DICTIONARY:
			problems.append(Problems.wrong_type(path, "словарь", type_string(typeof(e))))
			continue
		_check_keys(e, EDGE_KEYS, path, problems)
		for required in ["id", "a", "b", "kind", "steps", "noise"]:
			if not e.has(required):
				problems.append(Problems.missing_field("%s.%s" % [path, required],
					"int" if required in ["steps", "noise"] else "String"))
		var eid := _string_or(e.get("id", ""), "%s.id" % path, problems)
		if eid != "":
			if seen.has(eid):
				problems.append(Problems.duplicate_id("edges", eid))
			else:
				seen.append(eid)
		var a := _string_or(e.get("a", ""), "%s.a" % path, problems)
		var b := _string_or(e.get("b", ""), "%s.b" % path, problems)
		for side in [[a, "a"], [b, "b"]]:
			if String(side[0]) != "" and not nodes.is_empty() and not nodes.has(String(side[0])):
				problems.append(Problems.bad_ref("%s.%s" % [path, side[1]],
					"нет помещения «%s»" % String(side[0])))
		if a != "" and a == b:
			problems.append(Problems.bad_value(path, "ребро в себя (петля): a и b совпадают"))
		if e.has("kind"):
			var kind := _string_or(e["kind"], "%s.kind" % path, problems)
			if kind != "" and not Mission.EDGE_KINDS.has(kind):
				problems.append(Problems.bad_value("%s.kind" % path,
					"неизвестный вид «%s», допустимы: %s" % [kind, ", ".join(Mission.EDGE_KINDS)]))
		if e.has("steps"):
			var steps: Variant = _int_or(e["steps"], "%s.steps" % path, problems)
			if steps != null and int(steps) < 1:
				problems.append(Problems.bad_value("%s.steps" % path, "шагов должно быть ≥ 1"))
		if e.has("noise"):
			var noise: Variant = _int_or(e["noise"], "%s.noise" % path, problems)
			if noise != null and int(noise) < 0:
				problems.append(Problems.bad_value("%s.noise" % path, "шум не может быть отрицательным"))
		if e.has("locked") and typeof(e["locked"]) != TYPE_BOOL:
			problems.append(Problems.wrong_type("%s.locked" % path, "bool", type_string(typeof(e["locked"]))))


static func _check_patrols(data: Dictionary, nodes: Dictionary, problems: Array) -> void:
	if not data.has("patrols") or typeof(data["patrols"]) != TYPE_ARRAY:
		return
	var seen: Array = []
	for i in (data["patrols"] as Array).size():
		var p = data["patrols"][i]
		var path := "patrols[%d]" % i
		if typeof(p) != TYPE_DICTIONARY:
			problems.append(Problems.wrong_type(path, "словарь", type_string(typeof(p))))
			continue
		_check_keys(p, PATROL_KEYS, path, problems)
		if not p.has("id"):
			problems.append(Problems.missing_field("%s.id" % path, "String"))
		var pid := _string_or(p.get("id", ""), "%s.id" % path, problems)
		if pid != "":
			if seen.has(pid) or RESERVED_AGENT_IDS.has(pid):
				problems.append(Problems.duplicate_id("patrols", pid))
			else:
				seen.append(pid)
		if not p.has("route"):
			problems.append(Problems.missing_field("%s.route" % path, "Array"))
		else:
			var route: Variant = _string_array_or(p["route"], "%s.route" % path, problems)
			if route != null:
				if (route as Array).size() < 2:
					problems.append(Problems.bad_value("%s.route" % path, "маршрут патруля короче двух точек"))
				for n in route:
					if not nodes.is_empty() and not nodes.has(String(n)):
						problems.append(Problems.bad_ref("%s.route" % path, "нет помещения «%s»" % String(n)))
		if p.has("period"):
			var period: Variant = _int_or(p["period"], "%s.period" % path, problems)
			if period != null and int(period) < 1:
				problems.append(Problems.bad_value("%s.period" % path, "период должен быть ≥ 1"))


static func _check_sensors(data: Dictionary, nodes: Dictionary, problems: Array) -> void:
	if not data.has("sensors") or typeof(data["sensors"]) != TYPE_ARRAY:
		return
	var seen: Array = []
	for i in (data["sensors"] as Array).size():
		var s = data["sensors"][i]
		var path := "sensors[%d]" % i
		if typeof(s) != TYPE_DICTIONARY:
			problems.append(Problems.wrong_type(path, "словарь", type_string(typeof(s))))
			continue
		_check_keys(s, SENSOR_KEYS, path, problems)
		if not s.has("id"):
			problems.append(Problems.missing_field("%s.id" % path, "String"))
		var sid := _string_or(s.get("id", ""), "%s.id" % path, problems)
		if sid != "":
			if seen.has(sid):
				problems.append(Problems.duplicate_id("sensors", sid))
			else:
				seen.append(sid)
		if not s.has("nodes"):
			problems.append(Problems.missing_field("%s.nodes" % path, "Array"))
			continue
		var list: Variant = _string_array_or(s["nodes"], "%s.nodes" % path, problems)
		if list == null:
			continue
		if (list as Array).is_empty():
			problems.append(Problems.bad_value("%s.nodes" % path, "сенсор без помещений бессмыслен"))
		for n in list:
			if not nodes.is_empty() and not nodes.has(String(n)):
				problems.append(Problems.bad_ref("%s.nodes" % path, "нет помещения «%s»" % String(n)))


static func _check_objective(data: Dictionary, nodes: Dictionary, problems: Array) -> void:
	if not data.has("objective") or typeof(data["objective"]) != TYPE_STRING:
		return
	var objective := String(data["objective"])
	if objective == "":
		problems.append(Problems.bad_value("objective", "цель не задана"))
	elif not nodes.is_empty() and not nodes.has(objective):
		problems.append(Problems.bad_ref("objective", "нет помещения «%s»" % objective))


# --- достижимость -------------------------------------------------------------

## От любого входа до цели и обратно. Граф неориентированный: ребро проходимо в обе
## стороны, и это уже закреплено проверкой симметрии окна.
static func _check_reachability(data: Dictionary, nodes: Dictionary, problems: Array) -> void:
	if nodes.is_empty() or not data.has("edges") or typeof(data["edges"]) != TYPE_ARRAY:
		return
	if not data.has("objective") or typeof(data["objective"]) != TYPE_STRING:
		return
	var objective := String(data["objective"])
	if not nodes.has(objective):
		return
	var entries := _entry_nodes(nodes)
	if entries.is_empty():
		problems.append(Problems.unreachable("nodes", "нет ни одного помещения с тегом entry — группу некуда ставить"))
		return
	for entry in entries:
		if not _reaches(entry, objective, data["edges"]):
			problems.append(Problems.unreachable("objective",
				"от входа «%s» до цели «%s» нет пути" % [entry, objective]))


static func _entry_nodes(nodes: Dictionary) -> Array:
	var out: Array = []
	for node_id in nodes:
		var tags = nodes[node_id].get("tags", [])
		if typeof(tags) == TYPE_ARRAY and (tags as Array).has("entry"):
			out.append(String(node_id))
	return out


static func _reaches(from: String, to: String, edges: Array) -> bool:
	var seen := {from: true}
	var queue: Array = [from]
	while not queue.is_empty():
		var current := String(queue.pop_front())
		if current == to:
			return true
		for e in edges:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			var a := String(e.get("a", ""))
			var b := String(e.get("b", ""))
			var next := ""
			if a == current:
				next = b
			elif b == current:
				next = a
			if next != "" and not seen.has(next):
				seen[next] = true
				queue.append(next)
	return false


# --- окна ---------------------------------------------------------------------

static func _check_windows(data: Dictionary, known_edges: Dictionary, known_sensors: Dictionary, problems: Array) -> void:
	if not data.has("windows") or typeof(data["windows"]) != TYPE_ARRAY:
		return
	var seen: Array = []
	for i in (data["windows"] as Array).size():
		var w = data["windows"][i]
		var path := "windows[%d]" % i
		if typeof(w) != TYPE_DICTIONARY:
			problems.append(Problems.wrong_type(path, "словарь", type_string(typeof(w))))
			continue
		_check_keys(w, WINDOW_KEYS, path, problems)
		var wid := _string_or(w.get("id", ""), "%s.id" % path, problems)
		if wid == "":
			problems.append(Problems.missing_field("%s.id" % path, "String"))
			wid = path
		elif seen.has(wid):
			problems.append(Problems.duplicate_id("windows", wid))
		else:
			seen.append(wid)
		if not w.has("text_key"):
			problems.append(Problems.missing_field("%s.text_key" % path, "String"))
		var trigger_type := _check_trigger(w, wid, known_edges, known_sensors, problems)
		_check_options(w, wid, problems)
		_check_silence(w, wid, trigger_type, problems)


static func _check_trigger(w: Dictionary, wid: String, known_edges: Dictionary,
		known_sensors: Dictionary, problems: Array) -> String:
	if not w.has("trigger"):
		problems.append(Problems.missing_field("windows.%s.trigger" % wid, "словарь"))
		return ""
	var trigger = w["trigger"]
	var path := "windows.%s.trigger" % wid
	if typeof(trigger) != TYPE_DICTIONARY:
		problems.append(Problems.wrong_type(path, "словарь", type_string(typeof(trigger))))
		return ""
	_check_keys(trigger, TRIGGER_KEYS, path, problems)
	if not trigger.has("type"):
		problems.append(Problems.missing_field("%s.type" % path, "String"))
		return ""
	var type := _string_or(trigger["type"], "%s.type" % path, problems)
	if type == "":
		return ""
	if not TRIGGER_TYPES.has(type):
		problems.append(Problems.bad_value("%s.type" % path,
			"неизвестный триггер «%s», допустимы: %s" % [type, ", ".join(TRIGGER_TYPES)]))
		return ""
	match type:
		"locked_edge":
			_check_ref_key(trigger, "edge", "ребра", path, known_edges, problems)
		"node_entered":
			_check_ref_key(trigger, "node", "помещения", path, {}, problems)
		"guard_in_sensor":
			_check_ref_key(trigger, "sensor", "сенсора", path, known_sensors, problems)
	return type


## Поле обязательно, и по возможности ссылается на существующий объект.
static func _check_ref_key(obj: Dictionary, key: String, what: String, path: String,
		known: Dictionary, problems: Array) -> void:
	if not obj.has(key):
		problems.append(Problems.missing_field("%s.%s" % [path, key], "String"))
		return
	var value := _string_or(obj[key], "%s.%s" % [path, key], problems)
	if value != "" and not known.is_empty() and not known.has(value):
		problems.append(Problems.bad_ref("%s.%s" % [path, key], "нет %s «%s»" % [what, value]))


static func _check_options(w: Dictionary, wid: String, problems: Array) -> void:
	if not w.has("options"):
		problems.append(Problems.missing_field("windows.%s.options" % wid, "Array"))
		return
	if typeof(w["options"]) != TYPE_ARRAY:
		problems.append(Problems.wrong_type("windows.%s.options" % wid, "Array", type_string(typeof(w["options"]))))
		return
	var options: Array = w["options"]
	if options.is_empty():
		problems.append(Problems.empty_section("windows.%s.options" % wid))
		return
	var seen: Array = []
	for i in options.size():
		var o = options[i]
		var path := "windows.%s.options[%d]" % [wid, i]
		if typeof(o) != TYPE_DICTIONARY:
			problems.append(Problems.wrong_type(path, "словарь", type_string(typeof(o))))
			continue
		_check_keys(o, OPTION_KEYS, path, problems)
		for required in ["id", "text_key", "complexity", "cost"]:
			if not o.has(required):
				problems.append(Problems.missing_field("%s.%s" % [path, required], "String"))
		var oid := _string_or(o.get("id", ""), "%s.id" % path, problems)
		if oid == "silence":
			problems.append(Problems.silence_as_option(wid))
		elif oid != "":
			if seen.has(oid):
				problems.append(Problems.duplicate_id("windows.%s.options" % wid, oid))
			else:
				seen.append(oid)
		if o.has("complexity"):
			var complexity: Variant = _int_or(o["complexity"], "%s.complexity" % path, problems)
			if complexity != null and (int(complexity) < 1 or int(complexity) > 3):
				problems.append(Problems.bad_value("%s.complexity" % path, "сложность от 1 до 3"))
		if o.has("cost"):
			var cost = o["cost"]
			var cost_path := "%s.cost" % path
			if typeof(cost) != TYPE_DICTIONARY:
				problems.append(Problems.wrong_type(cost_path, "словарь", type_string(typeof(cost))))
			else:
				_check_keys(cost, COST_KEYS, cost_path, problems)
				for field in ["noise", "delay"]:
					if cost.has(field):
						var v: Variant = _int_or(cost[field], "%s.%s" % [cost_path, field], problems)
						if v != null and int(v) < 0:
							problems.append(Problems.bad_value("%s.%s" % [cost_path, field],
								"цена не может быть отрицательной"))
		if o.has("effects"):
			_check_effects(o["effects"], "%s.effects" % path, problems)


static func _check_silence(w: Dictionary, wid: String, trigger_type: String, problems: Array) -> void:
	var path := "windows.%s.silence" % wid
	if not w.has("silence"):
		problems.append(Problems.missing_silence(wid))
		return
	var silence = w["silence"]
	if typeof(silence) != TYPE_DICTIONARY:
		problems.append(Problems.wrong_type(path, "словарь", type_string(typeof(silence))))
		return
	_check_keys(silence, SILENCE_KEYS, path, problems)
	if not silence.has("text_key"):
		problems.append(Problems.missing_field("%s.text_key" % path, "String"))
	var complete := true
	for quality in SILENCE_QUALITIES:
		if not silence.has(quality):
			complete = false
	if not complete:
		problems.append(Problems.missing_silence(wid))
	for quality in SILENCE_QUALITIES:
		if not silence.has(quality):
			continue
		var q_path := "%s.%s" % [path, quality]
		_check_effects(silence[quality], q_path, problems)
		## Открывать ребро имеет смысл только у окна, привязанного к двери: окно
		## «группа вошла в помещение» открывает то, чего в нём нет.
		if trigger_type != "" and trigger_type != "locked_edge":
			for effect in _as_effect_list(silence[quality]):
				if String(effect.get("type", "")) == "unlock":
					problems.append(Problems.bad_value(q_path,
						"unlock у окна с триггером «%s»: открывать нечего" % trigger_type))


static func _check_effects(raw, path: String, problems: Array) -> void:
	if typeof(raw) != TYPE_ARRAY:
		problems.append(Problems.wrong_type(path, "Array", type_string(typeof(raw))))
		return
	var effects: Array = raw
	for i in effects.size():
		var e = effects[i]
		var e_path := "%s[%d]" % [path, i]
		if typeof(e) != TYPE_DICTIONARY:
			problems.append(Problems.wrong_type(e_path, "словарь", type_string(typeof(e))))
			continue
		_check_keys(e, EFFECT_KEYS, e_path, problems)
		if not e.has("type"):
			problems.append(Problems.missing_field("%s.type" % e_path, "String"))
			continue
		var type := _string_or(e["type"], "%s.type" % e_path, problems)
		if type == "":
			continue
		if not EFFECT_TYPES.has(type):
			problems.append(Problems.bad_value("%s.type" % e_path,
				"неизвестный эффект «%s»; для нового поведения нужен engine_proposal" % type))
			continue
		match type:
			"unlock":
				if not e.has("edge"):
					problems.append(Problems.missing_field("%s.edge" % e_path, "String"))
			"noise", "delay":
				if not e.has("value"):
					problems.append(Problems.missing_field("%s.value" % e_path, "int"))
				else:
					var v: Variant = _int_or(e["value"], "%s.value" % e_path, problems)
					if v != null and int(v) < 0:
						problems.append(Problems.bad_value("%s.value" % e_path, "значение не может быть отрицательным"))
			"engine_proposal":
				for required in ["id", "want", "needs", "fallback"]:
					if not e.has(required):
						problems.append(Problems.missing_field("%s.%s" % [e_path, required],
							"без fallback окно останется без эффекта"))


## Эффект в молчании может быть как массивом, так и одиночным объектом — оба формата
## равнозначны (см. постановку, §7). Здесь приводим к массиву для единой проверки.
static func _as_effect_list(raw) -> Array:
	if typeof(raw) == TYPE_ARRAY:
		return raw
	if typeof(raw) == TYPE_DICTIONARY:
		return [raw]
	return []


# --- разведка и точки доступа -------------------------------------------------

static func _check_intel(data: Dictionary, known_patrols: Dictionary, problems: Array) -> void:
	if not data.has("intel") or typeof(data["intel"]) != TYPE_ARRAY:
		return
	for i in (data["intel"] as Array).size():
		var block = data["intel"][i]
		var path := "intel[%d]" % i
		if typeof(block) != TYPE_DICTIONARY:
			problems.append(Problems.wrong_type(path, "словарь", type_string(typeof(block))))
			continue
		_check_keys(block, INTEL_KEYS, path, problems)
		if not block.has("channel"):
			problems.append(Problems.missing_field("%s.channel" % path, "String"))
			continue
		var channel := _string_or(block["channel"], "%s.channel" % path, problems)
		if not block.has("entries") or typeof(block["entries"]) != TYPE_ARRAY:
			problems.append(Problems.missing_field("%s.entries" % path, "Array"))
			continue
		var lies := 0
		var entries: Array = block["entries"]
		for j in entries.size():
			var entry = entries[j]
			var e_path := "%s.entries[%d]" % [path, j]
			if typeof(entry) != TYPE_DICTIONARY:
				problems.append(Problems.wrong_type(e_path, "словарь", type_string(typeof(entry))))
				continue
			_check_keys(entry, INTEL_ENTRY_KEYS, e_path, problems)
			if not entry.has("kind"):
				problems.append(Problems.missing_field("%s.kind" % e_path, "String"))
				continue
			var kind := _string_or(entry["kind"], "%s.kind" % e_path, problems)
			if not INTEL_KINDS.has(kind):
				problems.append(Problems.bad_value("%s.kind" % e_path,
					"неизвестный вид данных «%s», допустимы: %s" % [kind, ", ".join(INTEL_KINDS)]))
			## Данные разведки ссылаются на патруль по id: ссылка обязана существовать,
			## иначе призрак на карте будет указывать в никуда.
			if kind == "patrol" and entry.has("id"):
				var patrol_id := _string_or(entry["id"], "%s.id" % e_path, problems)
				if patrol_id != "" and not known_patrols.is_empty() and not known_patrols.has(patrol_id):
					problems.append(Problems.bad_ref("%s.id" % e_path, "нет патруля «%s»" % patrol_id))
			if bool(entry.get("false", false)):
				lies += 1
		## Ложь агентуры — часть уровня, а не бросок: ровно один подброшенный пункт (D30).
		if channel == "agents" and lies != 1:
			problems.append(Problems.intel_lie_count(channel, lies))


static func _check_access_points(data: Dictionary, nodes: Dictionary, problems: Array) -> void:
	if not data.has("access_points") or typeof(data["access_points"]) != TYPE_ARRAY:
		return
	var seen: Array = []
	for i in (data["access_points"] as Array).size():
		var ap = data["access_points"][i]
		var path := "access_points[%d]" % i
		if typeof(ap) != TYPE_DICTIONARY:
			problems.append(Problems.wrong_type(path, "словарь", type_string(typeof(ap))))
			continue
		_check_keys(ap, POINT_KEYS, path, problems)
		for required in ["id", "node", "kind", "text_key"]:
			if not ap.has(required):
				problems.append(Problems.missing_field("%s.%s" % [path, required], "String"))
		var aid := _string_or(ap.get("id", ""), "%s.id" % path, problems)
		if aid != "":
			if seen.has(aid):
				problems.append(Problems.duplicate_id("access_points", aid))
			else:
				seen.append(aid)
		var node := _string_or(ap.get("node", ""), "%s.node" % path, problems)
		if node != "" and not nodes.is_empty() and not nodes.has(node):
			problems.append(Problems.bad_ref("%s.node" % path, "нет помещения «%s»" % node))
		if ap.has("kind"):
			var kind := _string_or(ap["kind"], "%s.kind" % path, problems)
			if kind != "" and not POINT_KINDS.has(kind):
				problems.append(Problems.bad_value("%s.kind" % path, "неизвестный вид точки «%s»" % kind))
		if not ap.has("actions") or typeof(ap["actions"]) != TYPE_ARRAY:
			continue
		var actions: Array = ap["actions"]
		if actions.is_empty():
			problems.append(Problems.empty_section("%s.actions" % path))
		var seen_actions: Array = []
		for j in actions.size():
			var action = actions[j]
			var a_path := "%s.actions[%d]" % [path, j]
			if typeof(action) != TYPE_DICTIONARY:
				problems.append(Problems.wrong_type(a_path, "словарь", type_string(typeof(action))))
				continue
			_check_keys(action, ACTION_KEYS, a_path, problems)
			for required in ["id", "text_key", "complexity", "cost"]:
				if not action.has(required):
					problems.append(Problems.missing_field("%s.%s" % [a_path, required], "String"))
			var act_id := _string_or(action.get("id", ""), "%s.id" % a_path, problems)
			if act_id != "":
				if seen_actions.has(act_id):
					problems.append(Problems.duplicate_id("%s.actions" % path, act_id))
				else:
					seen_actions.append(act_id)
			if action.has("effects"):
				_check_effects(action["effects"], "%s.effects" % a_path, problems)


# --- тексты -------------------------------------------------------------------

## Собирает все ключи, на которые ссылаются данные, сверяет с текстами и ищет висячие.
static func _check_texts(data: Dictionary, texts: Dictionary, problems: Array) -> void:
	var used := _collect_text_keys(data)
	for entry in used:
		if not texts.is_empty() and not texts.has(String(entry["key"])):
			problems.append(Problems.missing_text(String(entry["path"]), String(entry["key"])))
	for key in texts:
		if _is_key_used(used, String(key)):
			continue
		if _is_unused_ok(String(key)):
			continue
		problems.append(Problems.dangling_text(String(key)))


static func _collect_text_keys(data: Dictionary) -> Array:
	var out: Array = []
	_walk_text_keys(data, "", out)
	return out


## Обход всего словаря в поиске полей, оканчивающихся на `_key`. Так новый раздел
## не останется без проверки текстов: не нужно перечислять поля руками.
static func _walk_text_keys(value, path: String, out: Array) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		for key in value:
			var child_path := "%s.%s" % [path, String(key)] if path != "" else String(key)
			if String(key).ends_with("_key") and typeof(value[key]) == TYPE_STRING:
				out.append({"path": child_path, "key": String(value[key])})
			else:
				_walk_text_keys(value[key], child_path, out)
	elif typeof(value) == TYPE_ARRAY:
		var arr: Array = value
		for i in arr.size():
			_walk_text_keys(arr[i], "%s[%d]" % [path, i], out)


static func _is_key_used(used: Array, key: String) -> bool:
	for entry in used:
		if String(entry["key"]) == key:
			return true
	return false


static func _is_unused_ok(key: String) -> bool:
	for prefix in UNUSED_OK_PREFIXES:
		if key.begins_with(prefix):
			return true
	return false


# --- мелкие проверки значений -------------------------------------------------

static func _check_keys(obj: Dictionary, allowed: Array, path: String, problems: Array) -> void:
	for key in obj:
		if not allowed.has(String(key)):
			problems.append(Problems.unknown_key("%s.%s" % [path, String(key)], String(key)))


static func _expect_type(value, expected: int, path: String, problems: Array) -> void:
	if typeof(value) != expected:
		problems.append(Problems.wrong_type(path, type_string(expected), type_string(typeof(value))))


## Число: целое значение. Дробное — WRONG_TYPE, а не BAD_VALUE: JSON в Godot отдаёт
## float, и «1.5 шага» — это ошибка формы, а не диапазона.
static func _expect_int(value, path: String, problems: Array) -> void:
	if typeof(value) == TYPE_INT:
		return
	if typeof(value) == TYPE_FLOAT and is_equal_approx(value, floor(value)):
		return
	problems.append(Problems.wrong_type(path, "int", type_string(typeof(value))))


## Возвращает int или null, если значение не число нужной формы.
static func _int_or(value, path: String, problems: Array):
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_FLOAT and is_equal_approx(value, floor(value)):
		return int(value)
	problems.append(Problems.wrong_type(path, "int", type_string(typeof(value))))
	return null


static func _string_or(value, path: String, problems: Array) -> String:
	if typeof(value) != TYPE_STRING:
		problems.append(Problems.wrong_type(path, "String", type_string(typeof(value))))
		return ""
	return String(value)


static func _check_string_array(value, path: String, problems: Array) -> void:
	if typeof(value) != TYPE_ARRAY:
		problems.append(Problems.wrong_type(path, "Array", type_string(typeof(value))))
		return
	for i in (value as Array).size():
		if typeof(value[i]) != TYPE_STRING:
			problems.append(Problems.wrong_type("%s[%d]" % [path, i], "String", type_string(typeof(value[i]))))


## Массив строк или null, если это не массив (проблема уже добавлена).
static func _string_array_or(value, path: String, problems: Array):
	if typeof(value) != TYPE_ARRAY:
		problems.append(Problems.wrong_type(path, "Array", type_string(typeof(value))))
		return null
	for i in (value as Array).size():
		if typeof(value[i]) != TYPE_STRING:
			problems.append(Problems.wrong_type("%s[%d]" % [path, i], "String", type_string(typeof(value[i]))))
			return null
	return value

extends RefCounted
## Самопроверка валидатора контента. Один кейс на код проблемы: так видно, что
## каждая проверка ловит ровно свой дефект, а не «что-то не то».
##
## Основа — корректная миссия, в которой каждый тест ломает ровно одно место:
## иначе непонятно, какая именно проверка сработала.

const Assert := preload("res://tests/assert.gd")
const Problems := preload("res://content/problems.gd")
const Validator := preload("res://content/validator.gd")


## Корректная миссия: вход, коридор, цель за запертой дверью, патруль, сенсор, окно.
## Числа и топология минимальны: тест про валидатор, а не про баланс.
func _good() -> Dictionary:
	return {
		"id": "t_mission",
		"title_key": "mission.01.title",
		"nodes": {
			"entry": {"floor": 1, "tags": ["entry"]},
			"hall": {"floor": 1, "tags": []},
			"vault": {"floor": 1, "tags": []},
		},
		"edges": [
			{"id": "e_entry_hall", "a": "entry", "b": "hall", "kind": "corridor", "steps": 1, "noise": 0},
			{"id": "e_hall_vault", "a": "hall", "b": "vault", "kind": "door", "steps": 1, "noise": 0, "locked": true},
		],
		"patrols": [{"id": "guard_1", "route": ["hall", "entry"], "period": 4}],
		"sensors": [{"id": "s_hall", "nodes": ["hall"]}],
		"objective": "vault",
		"windows": [{
			"id": "w_door",
			"trigger": {"type": "locked_edge", "edge": "e_hall_vault"},
			"text_key": "window.w_door.text",
			"options": [
				{"id": "breach", "text_key": "window.w_door.breach", "complexity": 1,
					"cost": {"noise": 8, "delay": 0},
					"effects": [{"type": "unlock", "edge": "e_hall_vault"}]},
			],
			"silence": {
				"text_key": "window.w_door.silence",
				"good": [{"type": "unlock", "edge": "e_hall_vault"}],
				"neutral": [{"type": "delay", "value": 3}],
				"bad": [{"type": "delay", "value": 3}, {"type": "noise", "value": 5}],
				"safe": [{"type": "delay", "value": 3}, {"type": "unlock", "edge": "e_hall_vault"}],
			},
		}],
		"intel": [{
			"channel": "hack",
			"observed_at": 0,
			"entries": [{"kind": "sensor", "nodes": ["hall"], "age_hours": 8, "false": false}],
		}],
		"access_points": [{"id": "ap_hall", "node": "hall", "kind": "terminal",
			"text_key": "ap.ap_hall.text",
			"actions": [{"id": "copy", "text_key": "ap.ap_hall.copy", "complexity": 1,
				"cost": {"steps": 4}, "effects": [{"type": "noop"}]}]}],
	}


## Тексты ко всем ключам корректной миссии — ровно те, что она использует.
func _texts_for(m: Dictionary) -> Dictionary:
	return {
		"mission.01.title": "ТЕСТ",
		"window.w_door.text": "Дверь.",
		"window.w_door.breach": "Выбить.",
		"window.w_door.silence": "Кира обходит.",
		"ap.ap_hall.text": "Терминал.",
		"ap.ap_hall.copy": "Скопировать.",
	}


func _codes(problems: Array) -> Array:
	var out: Array = []
	for p in problems:
		out.append(String(p["code"]))
	return out


func run() -> Array:
	var t := Assert.new()

	# 0. Корректная миссия проходит чисто — иначе все проверки ниже бессмысленны.
	t.is_true("корректная миссия валидна", Validator.validate(_good()).is_empty())

	# 1. Структура: корень не словарь.
	t.eq("корень не словарь", _codes(Validator.validate([])), [Problems.WRONG_TYPE])

	# 2. Обязательные поля.
	for field in ["nodes", "edges", "objective"]:
		var m := _good()
		m.erase(field)
		t.is_true("нет %s — MISSING_FIELD" % field, Problems.has(Validator.validate(m), Problems.MISSING_FIELD))

	var empty := _good()
	empty["nodes"] = {}
	t.is_true("пустой nodes — EMPTY_SECTION", Problems.has(Validator.validate(empty), Problems.EMPTY_SECTION))

	# 3. Типы.
	var bad_nodes := _good()
	bad_nodes["nodes"] = "не словарь"
	t.is_true("nodes не словарь — WRONG_TYPE", Problems.has(Validator.validate(bad_nodes), Problems.WRONG_TYPE))

	var bad_steps := _good()
	bad_steps["edges"][0]["steps"] = "много"
	t.is_true("steps строкой — WRONG_TYPE", Problems.has(Validator.validate(bad_steps), Problems.WRONG_TYPE))

	var bad_floor := _good()
	bad_floor["nodes"]["hall"]["floor"] = 1.5
	t.is_true("floor дробный — WRONG_TYPE", Problems.has(Validator.validate(bad_floor), Problems.WRONG_TYPE))

	# 4. Неизвестный ключ сообщается, а `note` разрешён в любом объекте.
	var unknown := _good()
	unknown["edges"][0]["speed"] = 3
	t.is_true("неизвестный ключ ребра", Problems.has(Validator.validate(unknown), Problems.UNKNOWN_KEY))

	var noted := _good()
	noted["edges"][0]["note"] = "пояснение для нас"
	t.is_true("note разрешён", Validator.validate(noted).is_empty())

	# 5. Уникальность id внутри раздела.
	var dup := _good()
	dup["patrols"].append({"id": "guard_1", "route": ["hall", "entry"], "period": 4})
	t.is_true("дубль id патруля", Problems.has(Validator.validate(dup), Problems.DUPLICATE_ID))

	var reserved := _good()
	reserved["patrols"].append({"id": "kira", "route": ["hall", "entry"], "period": 4})
	t.is_true("id именного занят", Problems.has(Validator.validate(reserved), Problems.DUPLICATE_ID))

	# 6. Значения вне допустимого.
	var bad_kind := _good()
	bad_kind["edges"][0]["kind"] = "teleport"
	t.is_true("неизвестный kind — BAD_VALUE", Problems.has(Validator.validate(bad_kind), Problems.BAD_VALUE))

	var zero_steps := _good()
	zero_steps["edges"][0]["steps"] = 0
	t.is_true("steps = 0 — BAD_VALUE", Problems.has(Validator.validate(zero_steps), Problems.BAD_VALUE))

	var neg_noise := _good()
	neg_noise["edges"][0]["noise"] = -1
	t.is_true("шум отрицательный — BAD_VALUE", Problems.has(Validator.validate(neg_noise), Problems.BAD_VALUE))

	var zero_period := _good()
	zero_period["patrols"][0]["period"] = 0
	t.is_true("period = 0 — BAD_VALUE", Problems.has(Validator.validate(zero_period), Problems.BAD_VALUE))

	var short_route := _good()
	short_route["patrols"][0]["route"] = ["hall"]
	t.is_true("патруль из одной точки — BAD_VALUE", Problems.has(Validator.validate(short_route), Problems.BAD_VALUE))

	var empty_sensor := _good()
	empty_sensor["sensors"][0]["nodes"] = []
	t.is_true("сенсор без помещений — BAD_VALUE", Problems.has(Validator.validate(empty_sensor), Problems.BAD_VALUE))

	var loop_edge := _good()
	loop_edge["edges"][0]["b"] = "entry"
	t.is_true("петля ребра — BAD_VALUE", Problems.has(Validator.validate(loop_edge), Problems.BAD_VALUE))

	# 7. Ссылочная целостность.
	var bad_edge := _good()
	bad_edge["edges"][0]["b"] = "нет_такого"
	t.is_true("ребро в пустоту — BAD_REF", Problems.has(Validator.validate(bad_edge), Problems.BAD_REF))

	var bad_objective := _good()
	bad_objective["objective"] = "нет_такого"
	t.is_true("цель в пустоту — BAD_REF", Problems.has(Validator.validate(bad_objective), Problems.BAD_REF))

	var bad_patrol := _good()
	bad_patrol["patrols"][0]["route"] = ["hall", "нет_такого"]
	t.is_true("патруль в пустоту — BAD_REF", Problems.has(Validator.validate(bad_patrol), Problems.BAD_REF))

	var bad_window := _good()
	bad_window["windows"][0]["trigger"]["edge"] = "нет_такого"
	t.is_true("окно на несуществующее ребро — BAD_REF",
		Problems.has(Validator.validate(bad_window), Problems.BAD_REF))

	var bad_point := _good()
	bad_point["access_points"][0]["node"] = "нет_такого"
	t.is_true("точка доступа в пустоту — BAD_REF",
		Problems.has(Validator.validate(bad_point), Problems.BAD_REF))

	# 8. Достижимость: цель отрезана от входа.
	var cut := _good()
	cut["edges"] = [cut["edges"][0]]
	t.is_true("цель недостижима — UNREACHABLE", Problems.has(Validator.validate(cut), Problems.UNREACHABLE))

	var no_entry := _good()
	no_entry["nodes"]["entry"]["tags"] = []
	t.is_true("нет ни одного входа — UNREACHABLE", Problems.has(Validator.validate(no_entry), Problems.UNREACHABLE))

	# 9. Окна: молчание обязательно и не может быть вариантом.
	var no_silence := _good()
	no_silence["windows"][0].erase("silence")
	t.is_true("окно без молчания — MISSING_SILENCE",
		Problems.has(Validator.validate(no_silence), Problems.MISSING_SILENCE))

	var silence_option := _good()
	silence_option["windows"][0]["options"].append({"id": "silence", "text_key": "x", "complexity": 1,
		"cost": {"noise": 0, "delay": 0}, "effects": []})
	t.is_true("молчание как вариант — SILENCE_AS_OPTION",
		Problems.has(Validator.validate(silence_option), Problems.SILENCE_AS_OPTION))

	for quality in ["good", "neutral", "bad", "safe"]:
		var partial := _good()
		partial["windows"][0]["silence"].erase(quality)
		t.is_true("молчание без %s — MISSING_SILENCE" % quality,
			Problems.has(Validator.validate(partial), Problems.MISSING_SILENCE))

	var bad_complexity := _good()
	bad_complexity["windows"][0]["options"][0]["complexity"] = 7
	t.is_true("сложность вне 1–3 — BAD_VALUE",
		Problems.has(Validator.validate(bad_complexity), Problems.BAD_VALUE))

	var dup_option := _good()
	dup_option["windows"][0]["options"].append(dup_option["windows"][0]["options"][0].duplicate(true))
	t.is_true("дубль варианта — DUPLICATE_ID",
		Problems.has(Validator.validate(dup_option), Problems.DUPLICATE_ID))

	var bad_trigger := _good()
	bad_trigger["windows"][0]["trigger"] = {"type": "магия"}
	t.is_true("неизвестный триггер — BAD_VALUE",
		Problems.has(Validator.validate(bad_trigger), Problems.BAD_VALUE))

	var unlock_in_node_window := _good()
	unlock_in_node_window["windows"][0]["trigger"] = {"type": "node_entered", "node": "vault"}
	unlock_in_node_window["windows"][0]["silence"]["good"] = [{"type": "unlock", "edge": "e_hall_vault"}]
	t.is_true("unlock в молчании окна не про дверь — BAD_VALUE",
		Problems.has(Validator.validate(unlock_in_node_window), Problems.BAD_VALUE))

	# 10. Точки доступа: действия непусты, стоимость в шагах.
	var no_actions := _good()
	no_actions["access_points"][0]["actions"] = []
	t.is_true("точка доступа без действий — EMPTY_SECTION",
		Problems.has(Validator.validate(no_actions), Problems.EMPTY_SECTION))

	# 11. Разведка: у агентуры обязан быть ровно один подброшенный пункт.
	var agents_ok := _good()
	agents_ok["intel"] = [{
		"channel": "agents", "observed_at": 0,
		"entries": [{"kind": "sensor", "nodes": ["hall"], "age_hours": 6, "false": true}],
	}]
	t.is_true("агентура с одной ложью проходит", Validator.validate(agents_ok).is_empty())

	var agents_none := _good()
	agents_none["intel"] = [{
		"channel": "agents", "observed_at": 0,
		"entries": [{"kind": "sensor", "nodes": ["hall"], "age_hours": 6, "false": false}],
	}]
	t.is_true("агентура без лжи — INTEL_LIE_COUNT",
		Problems.has(Validator.validate(agents_none), Problems.INTEL_LIE_COUNT))

	var agents_two := _good()
	agents_two["intel"] = [{
		"channel": "agents", "observed_at": 0,
		"entries": [
			{"kind": "sensor", "nodes": ["hall"], "age_hours": 6, "false": true},
			{"kind": "sensor", "nodes": ["entry"], "age_hours": 6, "false": true},
		],
	}]
	t.is_true("агентура с двумя ложьями — INTEL_LIE_COUNT",
		Problems.has(Validator.validate(agents_two), Problems.INTEL_LIE_COUNT))

	var bad_patrol_ref := _good()
	bad_patrol_ref["intel"] = [{
		"channel": "hack", "observed_at": 0,
		"entries": [{"kind": "patrol", "id": "guard_нет", "route": ["hall"], "period": 4,
			"age_hours": 8, "false": false}],
	}]
	t.is_true("разведка ссылается на несуществующий патруль — BAD_REF",
		Problems.has(Validator.validate(bad_patrol_ref), Problems.BAD_REF))

	# 12. Тексты: недостающий ключ и висячий ключ.
	var texts := _texts_for(_good())
	t.is_true("полный набор текстов проходит", Validator.validate(_good(), texts).is_empty())

	var texts_missing := _texts_for(_good())
	texts_missing.erase("window.w_door.text")
	t.is_true("нет ключа текста окна — MISSING_TEXT",
		Problems.has(Validator.validate(_good(), texts_missing), Problems.MISSING_TEXT))

	var texts_extra := _texts_for(_good())
	texts_extra["window.не_нужен.text"] = "лишнее"
	t.is_true("висячий ключ текста — DANGLING_TEXT",
		Problems.has(Validator.validate(_good(), texts_extra), Problems.DANGLING_TEXT))

	return t.results

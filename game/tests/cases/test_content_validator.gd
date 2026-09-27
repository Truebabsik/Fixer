extends RefCounted
## Самопроверка валидатора контента. Один кейс на код проблемы: так видно, что
## каждая проверка ловит ровно свой дефект, а не «что-то не то».
##
## Основа — корректная миссия, в которой каждый тест ломает ровно одно место:
## иначе непонятно, какая именно проверка сработала.

const Assert := preload("res://tests/assert.gd")
const Problems := preload("res://content/problems.gd")
const Validator := preload("res://content/validator.gd")

## ЭТАЛОН обязательных системных ключей — независимая копия перечня из постановки
## (`docs/handoff/2026-09-26-mission-content/04-texts.md` §4 плюс блоки §3.1–3.2).
## Список намеренно НЕ берётся из `Validator.REQUIRED_TEXT_KEYS`: эталон, производный от
## проверяемого, не поймал бы ни одного ключа, выпавшего из списка валидатора
## (`docs/agents/review-checklist.md` §2 — «ассерт, который не может покраснеть»).
## Две стороны держатся вместе кейсом 14: цикл снимает каждый ключ эталона по одному
## (список валидатора не короче эталона), положительный ассерт на полном наборе — что он
## не длиннее.
const REQUIRED_TEXTS := [
	"mission.01.title",
	"negotiation.intro", "negotiation.term.money", "negotiation.term.time",
	"negotiation.term.truth", "negotiation.mediator.recognize",
	"negotiation.mediator.answer.press", "negotiation.mediator.answer.yield",
	"negotiation.dossier.offer", "negotiation.dossier.read", "negotiation.deal",
	"team.kira.available", "team.echo.available", "team.market.intro",
	"log.silence", "log.command.kira", "log.command.echo", "log.command.you",
	"log.radio.jammed", "log.radio.intercepted", "log.alarm.raised", "log.ghost.mismatch",
	"voice.kira.ack", "voice.kira.command", "voice.echo.joke",
	"final.read", "final.hand_over", "final.destroy",
	"outcome.extracted", "outcome.caught", "outcome.timeout",
	"results.summary",
]


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
			"kind": "locked_edge",
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
				"neutral": [{"type": "delay", "value": 3}, {"type": "unlock", "edge": "e_hall_vault"}],
				"bad": [{"type": "delay", "value": 3}, {"type": "noise", "value": 5},
					{"type": "unlock", "edge": "e_hall_vault"}],
				"safe": [{"type": "unlock", "edge": "e_hall_vault"}],
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


## Тексты ко всем ключам корректной миссии — ровно те, что она использует, ПЛЮС
## обязательные системные ключи (`REQUIRED_TEXTS`). Фикстура изображает ТЕКСТЫ СДАЧИ,
## а сдача без системных ключей неполна (04-texts.md §4), и сверка, включённая словарём,
## требует и их: без них положительные ассерты ниже («проблем нет») краснели бы на
## ключах, которых фикстура и не должна выводить из данных. Значения условны — сверяется
## наличие ключа, а не текст.
func _texts_for(m: Dictionary) -> Dictionary:
	var out := {
		"mission.01.title": "ТЕСТ",
		"window.w_door.text": "Дверь.",
		"window.w_door.breach": "Выбить.",
		"window.w_door.silence": "Кира обходит.",
		"ap.ap_hall.text": "Терминал.",
		"ap.ap_hall.copy": "Скопировать.",
	}
	for key in REQUIRED_TEXTS:
		if not out.has(key):
			out[key] = "текст обязательного ключа"
	return out


## Корректная миссия С полями презентации: координаты помещений, подписи (`name_key`),
## название комплекса и этажи. Отдельная фикстура, а не правка `_good()`: обратная
## совместимость формы — часть требования, и держится она тем, что `_good()` этих полей
## НЕ имеет (кейс 15а). Здесь же проверяются обе половины формы: `pos` с отрицательной
## координатой (схема этажа вправе уходить в минус) и этаж с номером `-1` строкой.
func _good_presented() -> Dictionary:
	var m := _good()
	m["facility_key"] = "facility.meridian"
	m["nodes"]["entry"]["pos"] = {"x": 0, "y": 0}
	m["nodes"]["entry"]["name_key"] = "room.entry"
	m["nodes"]["hall"]["pos"] = {"x": 4, "y": 0}
	m["nodes"]["hall"]["name_key"] = "room.hall"
	m["nodes"]["vault"]["pos"] = {"x": 8, "y": -4}
	m["nodes"]["vault"]["name_key"] = "room.vault"
	m["floors"] = {
		"-1": {"name_key": "floor.-1"},
		"1": {"name_key": "floor.1"},
	}
	return m


## Тексты к полям презентации. Список рукописный и НЕ выводится из данных: вывести его
## значит повторить данные и не поймать ни пропавший ключ, ни лишний.
func _presentation_texts() -> Dictionary:
	var out := _texts_for(_good())
	out["room.entry"] = "ВХОД"
	out["room.hall"] = "ХОЛЛ"
	out["room.vault"] = "ХРАНИЛИЩЕ"
	out["floor.-1"] = "ПОДВАЛ // ХОЛОДНЫЙ АРХИВ"
	out["floor.1"] = "ЭТАЖ 1 // ПРИЁМНАЯ"
	out["facility.meridian"] = "МЕРИДИАН // АРХИВНЫЙ КОМПЛЕКС"
	return out


func _codes(problems: Array) -> Array:
	var out: Array = []
	for p in problems:
		out.append(String(p["code"]))
	return out


## Коды проблем, у которых путь начинается с `prefix`. Нужно там, где одна мутация
## законно задевает два правила и «список непуст» ничего не доказывает.
func _codes_at(problems: Array, prefix: String) -> Array:
	var out: Array = []
	for p in problems:
		if String(p["path"]).begins_with(prefix):
			out.append(String(p["code"]))
	return out


## Сообщение проблемы на конкретном пути. Нужно там, где проверять надо не только код:
## «ожидался String» на поле-массиве проходил мимо тестов, потому что сверялись код и путь
## (класс M3), а читает автор именно сообщение. Имена типов в сообщениях — по норме
## (`строка`/`массив`/`целое`/`словарь`), английских там быть не должно.
func _message_at(problems: Array, path: String) -> String:
	for p in problems:
		if String(p["path"]) == path:
			return String(p["message"])
	return ""


## Пути проблем — там, где сверяется «ровно это место», а не «проблема вообще есть».
func _paths(problems: Array) -> Array:
	var out: Array = []
	for p in problems:
		out.append(String(p["path"]))
	return out


## Диагнозы, в сообщении которых НАЗВАН ключ: список `Problems.brief`. Так проверяется
## «проблема про этот ключ», чего «список непуст» не различает: без этого ассерт про
## удалённый ключ проходил бы на любом чужом диагнозе.
func _problems_naming(problems: Array, key: String) -> Array:
	var out: Array = []
	for p in problems:
		if String(p["message"]).contains(key):
			out.append(Problems.brief(p))
	return out


## Называет ли ДАННЫЕ этот ключ. Список берётся у валидатора (`_collect_text_keys`):
## вопрос здесь — «ссылаются ли данные на ключ», а не «есть ли он в фикстуре».
func _key_in(entries: Array, key: String) -> bool:
	for entry in entries:
		if String(entry["key"]) == key:
			return true
	return false


## Нарушения нормы имён типов: по строке на каждую проблему `MISSING_FIELD`/`WRONG_TYPE`,
## чьё сообщение не назвало тип по-русски или назвало его по-английски. Пустой список —
## норма соблюдена.
##
## Английские имена ищутся по ГРАНИЦАМ СЛОВ: `contains("int")` ловил бы подстроку в
## `intel[0].entries[0]`, а `contains("Array")` — ничего не доказывал бы про `array`.
func _type_name_norm_violations(problems: Array) -> Array:
	var russian := ["строка", "массив", "целое", "логическое", "дробное", "словарь", "ничто"]
	var english := RegEx.new()
	english.compile("\\b(String|Array|Dictionary|int|float|bool|Nil)\\b")
	var out: Array = []
	for p in problems:
		var code := String(p["code"])
		if code != Problems.MISSING_FIELD and code != Problems.WRONG_TYPE:
			continue
		var message := String(p["message"])
		var named := false
		for word in russian:
			if message.contains(word):
				named = true
				break
		var alien := english.search(message)
		if not named or alien != null:
			out.append("%s %s: %s" % [code, String(p["path"]), message])
	return out


## Проблемы `MISSING_FIELD`/`WRONG_TYPE` — сколько их в списке. Нужно, чтобы корпусный
## ассерт нормы не проходил «зелено по умолчанию» на опустевшем корпусе.
func _typed_count(problems: Array) -> int:
	var count := 0
	for p in problems:
		var code := String(p["code"])
		if code == Problems.MISSING_FIELD or code == Problems.WRONG_TYPE:
			count += 1
	return count


func run() -> Array:
	var t := Assert.new()

	# ПОЛИТИКА ПО ТЕКСТАМ, обязательная для всего файла. У `Validator.validate` второй
	# аргумент ОБЯЗАТЕЛЕН и умолчания не имеет: `null` — «этот кейс тексты НЕ проверяет»,
	# словарь — «проверяет» (в том числе пустой: «текстов нет»). Здесь `null` стоит
	# ОСОЗНАННО: у каждого кейса ниже свой предмет, и лишний MISSING_TEXT на `*_key`
	# сломал бы сверку «ровно эти коды на этом пути». Сверку ключей держат адресные кейсы
	# 12/12б, а положительные ассерты («проблем нет») получают словарь: иначе они
	# говорили бы «всё хорошо», ничего не сверив, — ровно тот дефект, что закрыт здесь.
	# Исключение — единственное: там, где мутация сама уносит `*_key` из данных
	# (опустошение раздела, кейс 2), стоит `null`: рукописная фикстура стала бы висячей,
	# и кейс краснел бы на DANGLING_TEXT про фикстуру. Подставлять туда словарь, собранный
	# ИЗ ТЕХ ЖЕ данных, нельзя: он совпал бы по построению, то есть сверка выглядела бы
	# включённой, ничего не умея поймать.
	#
	# `_texts_for` с этой задачи несёт ещё и обязательные системные ключи (`REQUIRED_TEXTS`):
	# сверка текстов-словарём требует и их, а фикстура изображает тексты СДАЧИ. Поэтому
	# положительные ассерты остаются положительными, а держат обязательность кейс 14 и
	# адресные снятия в нём.

	# 0. Корректная миссия проходит чисто — иначе все проверки ниже бессмысленны.
	# Тексты — настоящие: положительный ассерт обязан включать и сверку ключей.
	t.is_true("корректная миссия валидна",
		Validator.validate(_good(), _texts_for(_good())).is_empty())

	# 1. Структура: корень не словарь.
	t.eq("корень не словарь", _codes(Validator.validate([], null)), [Problems.WRONG_TYPE])

	# 2. Обязательные поля. Разделы-массивы обязаны быть на корне (02-format.md §1),
	# но пустой массив — нормальная миссия: «патрулей нет» допустимо, «ключа нет» — нет.
	for field in ["id", "title_key", "nodes", "edges", "patrols", "sensors", "objective",
			"windows", "intel", "access_points"]:
		var m := _good()
		m.erase(field)
		t.is_true("нет %s — MISSING_FIELD" % field, Problems.has(Validator.validate(m, null), Problems.MISSING_FIELD))

	# Предмет здесь — «пустой раздел допустим», а не тексты, поэтому вторым аргументом идёт
	# `null` (явный отказ от сверки). Рукописную фикстуру `_texts_for` сюда передать нельзя:
	# опустошённый раздел уносит с собой свои `*_key`, и фикстура стала бы висячей —
	# кейс краснел бы на DANGLING_TEXT про фикстуру, а не про пустой раздел. Обратное
	# направление (ключ данных без текста и текст без ключа) держит кейс 12.
	for section in ["patrols", "sensors", "windows", "intel", "access_points"]:
		var empty_section := _good()
		empty_section[section] = []
		t.is_true("пустой %s допустим" % section, Validator.validate(empty_section, null).is_empty())

	var blank_title := _good()
	blank_title["title_key"] = ""
	t.is_true("пустой title_key — BAD_VALUE", Problems.has(Validator.validate(blank_title, null), Problems.BAD_VALUE))

	# C1. Неверный тип необязательного раздела: валидатор обязан назвать болезнь,
	# иначе загрузчик пойдёт циклом по словарю и упадёт внутри цикла.
	for section in ["patrols", "sensors", "windows", "intel", "access_points"]:
		var bad_section := _good()
		bad_section[section] = {"guard_1": {"route": ["hall", "entry"]}}
		t.eq("раздел %s словарём — WRONG_TYPE" % section,
			_codes_at(Validator.validate(bad_section, null), section), [Problems.WRONG_TYPE])

	var empty := _good()
	empty["nodes"] = {}
	t.is_true("пустой nodes — EMPTY_SECTION", Problems.has(Validator.validate(empty, null), Problems.EMPTY_SECTION))

	# 3. Типы.
	var bad_nodes := _good()
	bad_nodes["nodes"] = "не словарь"
	t.is_true("nodes не словарь — WRONG_TYPE", Problems.has(Validator.validate(bad_nodes, null), Problems.WRONG_TYPE))

	var bad_steps := _good()
	bad_steps["edges"][0]["steps"] = "много"
	t.is_true("steps строкой — WRONG_TYPE", Problems.has(Validator.validate(bad_steps, null), Problems.WRONG_TYPE))

	var bad_floor := _good()
	bad_floor["nodes"]["hall"]["floor"] = 1.5
	t.is_true("floor дробный — WRONG_TYPE", Problems.has(Validator.validate(bad_floor, null), Problems.WRONG_TYPE))

	# 4. Неизвестный ключ сообщается, а `note` разрешён в любом объекте.
	var unknown := _good()
	unknown["edges"][0]["speed"] = 3
	t.is_true("неизвестный ключ ребра", Problems.has(Validator.validate(unknown, null), Problems.UNKNOWN_KEY))

	var noted := _good()
	noted["edges"][0]["note"] = "пояснение для нас"
	t.is_true("note разрешён", Validator.validate(noted, _texts_for(noted)).is_empty())

	# I8. `note` разрешён, но только строкой: 5 или {"a": 1} — ложь в пояснении.
	for bad_note in [5, {"a": 1}, true]:
		var noted_bad := _good()
		noted_bad["edges"][0]["note"] = bad_note
		t.is_true("note %s — WRONG_TYPE" % str(bad_note),
			Problems.has(Validator.validate(noted_bad, null), Problems.WRONG_TYPE))

	# 5. Уникальность id внутри раздела.
	var dup := _good()
	dup["patrols"].append({"id": "guard_1", "route": ["hall", "entry"], "period": 4})
	t.is_true("дубль id патруля", Problems.has(Validator.validate(dup, null), Problems.DUPLICATE_ID))

	# M3. Зарезервированный id — не повтор: сообщение обязано отличаться.
	var reserved := _good()
	reserved["patrols"].append({"id": "kira", "route": ["hall", "entry"], "period": 4})
	var reserved_problems := Validator.validate(reserved, null)
	t.is_true("id именного занят — RESERVED_ID", Problems.has(reserved_problems, Problems.RESERVED_ID))
	t.is_false("id именного — это не DUPLICATE_ID", Problems.has(reserved_problems, Problems.DUPLICATE_ID))

	# 6. Значения вне допустимого.
	var bad_kind := _good()
	bad_kind["edges"][0]["kind"] = "teleport"
	t.is_true("неизвестный kind — BAD_VALUE", Problems.has(Validator.validate(bad_kind, null), Problems.BAD_VALUE))

	var zero_steps := _good()
	zero_steps["edges"][0]["steps"] = 0
	t.is_true("steps = 0 — BAD_VALUE", Problems.has(Validator.validate(zero_steps, null), Problems.BAD_VALUE))

	var neg_noise := _good()
	neg_noise["edges"][0]["noise"] = -1
	t.is_true("шум отрицательный — BAD_VALUE", Problems.has(Validator.validate(neg_noise, null), Problems.BAD_VALUE))

	var zero_period := _good()
	zero_period["patrols"][0]["period"] = 0
	t.is_true("period = 0 — BAD_VALUE", Problems.has(Validator.validate(zero_period, null), Problems.BAD_VALUE))

	var short_route := _good()
	short_route["patrols"][0]["route"] = ["hall"]
	t.is_true("патруль из одной точки — BAD_VALUE", Problems.has(Validator.validate(short_route, null), Problems.BAD_VALUE))

	var empty_sensor := _good()
	empty_sensor["sensors"][0]["nodes"] = []
	t.is_true("сенсор без помещений — BAD_VALUE", Problems.has(Validator.validate(empty_sensor, null), Problems.BAD_VALUE))

	var loop_edge := _good()
	loop_edge["edges"][0]["b"] = "entry"
	t.is_true("петля ребра — BAD_VALUE", Problems.has(Validator.validate(loop_edge, null), Problems.BAD_VALUE))

	# I7. Два ребра между одной парой помещений: второе станет невидимым.
	var twin := _good()
	twin["edges"].append({"id": "e_entry_hall_2", "a": "entry", "b": "hall", "kind": "corridor",
		"steps": 2, "noise": 0})
	t.is_true("второе ребро между парой — BAD_VALUE",
		Problems.has(Validator.validate(twin, null), Problems.BAD_VALUE))

	# Порядок концов не важен: {a, b} — неупорядоченная пара.
	var twin_reversed := _good()
	twin_reversed["edges"].append({"id": "e_hall_entry_2", "a": "hall", "b": "entry", "kind": "corridor",
		"steps": 2, "noise": 0})
	t.is_true("второе ребро обратным порядком — BAD_VALUE",
		Problems.has(Validator.validate(twin_reversed, null), Problems.BAD_VALUE))

	# I6. Разрыв маршрута патруля: соседние точки обязаны быть соединены ребром.
	var broken_route := _good()
	broken_route["patrols"][0]["route"] = ["entry", "vault"]
	var broken_problems := Validator.validate(broken_route, null)
	t.eq("разрыв маршрута — BAD_VALUE на patrols[0].route",
		_codes_at(broken_problems, "patrols[0].route"), [Problems.BAD_VALUE])

	# 7. Ссылочная целостность.
	var bad_edge := _good()
	bad_edge["edges"][0]["b"] = "нет_такого"
	t.is_true("ребро в пустоту — BAD_REF", Problems.has(Validator.validate(bad_edge, null), Problems.BAD_REF))

	var bad_objective := _good()
	bad_objective["objective"] = "нет_такого"
	t.is_true("цель в пустоту — BAD_REF", Problems.has(Validator.validate(bad_objective, null), Problems.BAD_REF))

	var bad_patrol := _good()
	bad_patrol["patrols"][0]["route"] = ["hall", "нет_такого"]
	t.is_true("патруль в пустоту — BAD_REF", Problems.has(Validator.validate(bad_patrol, null), Problems.BAD_REF))

	var bad_window := _good()
	bad_window["windows"][0]["trigger"]["edge"] = "нет_такого"
	t.is_true("окно на несуществующее ребро — BAD_REF",
		Problems.has(Validator.validate(bad_window, null), Problems.BAD_REF))

	var bad_point := _good()
	bad_point["access_points"][0]["node"] = "нет_такого"
	t.is_true("точка доступа в пустоту — BAD_REF",
		Problems.has(Validator.validate(bad_point, null), Problems.BAD_REF))

	# I1. `node_entered` ссылается на помещение — ссылка обязана проверяться.
	var bad_node_trigger := _good()
	bad_node_trigger["windows"][0]["trigger"] = {"type": "node_entered", "node": "нет_такого"}
	bad_node_trigger["windows"][0]["silence"]["good"] = [{"type": "delay", "value": 1}]
	t.eq("триггер на несуществующее помещение — BAD_REF на trigger.node",
		_codes_at(Validator.validate(bad_node_trigger, null), "windows.w_door.trigger.node"), [Problems.BAD_REF])

	# C2. Ссылка на ребро проверяется ВЕЗДЕ, где она встречается: в варианте,
	# в четырёх исходах молчания и в fallback предложения движку.
	var bad_unlock_option := _good()
	bad_unlock_option["windows"][0]["options"][0]["effects"] = [{"type": "unlock", "edge": "нет_такого"}]
	t.eq("unlock варианта на несуществующее ребро — BAD_REF",
		_codes_at(Validator.validate(bad_unlock_option, null), "windows.w_door.options[0].effects[0].edge"),
		[Problems.BAD_REF])

	for quality in ["good", "neutral", "bad", "safe"]:
		var bad_unlock_silence := _good()
		bad_unlock_silence["windows"][0]["silence"][quality] = [{"type": "unlock", "edge": "нет_такого"}]
		t.eq("unlock в молчании «%s» на несуществующее ребро — BAD_REF" % quality,
			_codes_at(Validator.validate(bad_unlock_silence, null),
				"windows.w_door.silence.%s[0].edge" % quality), [Problems.BAD_REF])

	var bad_fallback := _good()
	bad_fallback["windows"][0]["options"][0]["effects"] = [{
		"type": "engine_proposal", "id": "lure", "want": "инженер выйдет", "needs": "состояние поста",
		"fallback": {"type": "unlock", "edge": "нет_такого"},
	}]
	t.eq("fallback на несуществующее ребро — BAD_REF",
		_codes_at(Validator.validate(bad_fallback, null), "windows.w_door.options[0].effects[0].fallback[0].edge"),
		[Problems.BAD_REF])

	# 8. Достижимость: цель отрезана от входа.
	var cut := _good()
	cut["edges"] = [cut["edges"][0]]
	t.is_true("цель недостижима — UNREACHABLE", Problems.has(Validator.validate(cut, null), Problems.UNREACHABLE))

	var no_entry := _good()
	no_entry["nodes"]["entry"]["tags"] = []
	t.is_true("нет ни одного входа — UNREACHABLE", Problems.has(Validator.validate(no_entry, null), Problems.UNREACHABLE))

	# п. 15. Обратный путь проверяется ЯВНО: обход идёт ОТ ЦЕЛИ до входа. Проба —
	# отдельный компонент: и вход, и цель стоят, но между ними нет ни одного ребра.
	var reverse_cut := _good()
	reverse_cut["nodes"]["hall"]["tags"] = []
	reverse_cut["edges"] = [{"id": "e_hall_vault", "a": "hall", "b": "vault",
		"kind": "door", "steps": 1, "noise": 0}]
	reverse_cut["patrols"] = []
	reverse_cut["sensors"] = []
	reverse_cut["windows"] = []
	reverse_cut["intel"] = []
	reverse_cut["access_points"] = []
	t.eq("обратный путь отрезан — UNREACHABLE на objective",
		_codes_at(Validator.validate(reverse_cut, null), "objective"),
		[Problems.UNREACHABLE, Problems.UNREACHABLE])

	# 9. Окна: молчание обязательно и не может быть вариантом.
	var no_silence := _good()
	no_silence["windows"][0].erase("silence")
	t.is_true("окно без молчания — MISSING_SILENCE",
		Problems.has(Validator.validate(no_silence, null), Problems.MISSING_SILENCE))

	var silence_option := _good()
	silence_option["windows"][0]["options"].append({"id": "silence", "text_key": "x", "complexity": 1,
		"cost": {"noise": 0, "delay": 0}, "effects": []})
	t.is_true("молчание как вариант — SILENCE_AS_OPTION",
		Problems.has(Validator.validate(silence_option, null), Problems.SILENCE_AS_OPTION))

	for quality in ["good", "neutral", "bad", "safe"]:
		var partial := _good()
		partial["windows"][0]["silence"].erase(quality)
		t.is_true("молчание без %s — MISSING_SILENCE" % quality,
			Problems.has(Validator.validate(partial, null), Problems.MISSING_SILENCE))

	var bad_complexity := _good()
	bad_complexity["windows"][0]["options"][0]["complexity"] = 7
	t.is_true("сложность вне 1–3 — BAD_VALUE",
		Problems.has(Validator.validate(bad_complexity, null), Problems.BAD_VALUE))

	var dup_option := _good()
	dup_option["windows"][0]["options"].append(dup_option["windows"][0]["options"][0].duplicate(true))
	t.is_true("дубль варианта — DUPLICATE_ID",
		Problems.has(Validator.validate(dup_option, null), Problems.DUPLICATE_ID))

	# п. 20. Два РАЗНЫХ варианта с одинаковой ценой и эффектами бессмысленны: выбор
	# между ними ничего не меняет. Сверять только id недостаточно.
	var twin_options := _good()
	twin_options["windows"][0]["options"].append({"id": "pick", "text_key": "window.w_door.pick",
		"complexity": 2, "cost": {"noise": 8, "delay": 0},
		"effects": [{"type": "unlock", "edge": "e_hall_vault"}]})
	t.eq("два варианта с одной ценой и эффектами — DUPLICATE_ID на втором",
		_codes_at(Validator.validate(twin_options, null), "windows.w_door.options[1]"), [Problems.DUPLICATE_ID])

	# Порядок эффектов значим: та же цена, другой порядок — уже другой приказ.
	var reordered := _good()
	reordered["windows"][0]["options"][0]["cost"] = {"noise": 0, "delay": 3}
	reordered["windows"][0]["options"][0]["effects"] = [{"type": "noise", "value": 1},
		{"type": "unlock", "edge": "e_hall_vault"}]
	var reordered2 := _good()
	reordered2["windows"][0]["options"][0]["cost"] = {"noise": 0, "delay": 3}
	reordered2["windows"][0]["options"][0]["effects"] = [{"type": "unlock", "edge": "e_hall_vault"},
		{"type": "noise", "value": 1}]
	t.is_true("разный порядок эффектов проходит",
		Validator.validate(reordered, _texts_for(reordered)).is_empty())
	t.is_true("разный порядок эффектов проходит (зеркало)",
		Validator.validate(reordered2, _texts_for(reordered2)).is_empty())

	# M5. `kind` окна обязателен и из перечисления.
	var no_kind := _good()
	no_kind["windows"][0].erase("kind")
	t.is_true("окно без kind — MISSING_FIELD",
		Problems.has(Validator.validate(no_kind, null), Problems.MISSING_FIELD))

	var bad_window_kind := _good()
	bad_window_kind["windows"][0]["kind"] = "магия"
	t.is_true("неизвестный kind окна — BAD_VALUE",
		Problems.has(Validator.validate(bad_window_kind, null), Problems.BAD_VALUE))
	t.eq("неизвестный kind окна — одна проблема на поле",
		_codes_at(Validator.validate(bad_window_kind, null), "windows.w_door.kind"), [Problems.BAD_VALUE])

	# P6. `kind` обязан совпадать с `trigger.type`. Рантайм-вид окна ядро строит ИЗ ТРИГГЕРА
	# (`sim/window.gd:kind_for`), а `kind` на него не влияет вовсе: пока сверки не было,
	# расхождение проходило молча, и автор думал, что выбрал вид окна.
	var kind_mismatch := _good()
	kind_mismatch["windows"][0]["kind"] = "node_entered"
	var kind_mismatch_problems: Array = Validator.validate(kind_mismatch, null)
	t.eq("kind разошёлся с trigger.type — BAD_VALUE на kind",
		_codes_at(kind_mismatch_problems, "windows.w_door.kind"), [Problems.BAD_VALUE])
	# Путь проблемы окна — по id окна, а не по индексу в массиве: так он совпадает
	# с путями вариантов и молчания (`windows.w_door.options[0]`) и читается автором.
	#
	# Проблема читается ТОЛЬКО после проверки размера: при снятом правиле сверки проблем
	# может не быть вовсе, и `problems[0]` ронял бы кейс рантаймом (`Out of bounds get
	# index '0'`). Раннер печатал бы LOAD FAIL и не выполнял остаток файла (~130
	# проверок) — вердикт красный, но имени поломанного правила не видно.
	t.is_true("kind разошёлся с trigger.type — проблема вообще есть",
		not kind_mismatch_problems.is_empty())
	var first_path := ""
	if not kind_mismatch_problems.is_empty():
		first_path = String((kind_mismatch_problems[0] as Dictionary).get("path", ""))
	t.eq("путь проблемы окна — по id", first_path, "windows.w_door.kind")

	var bad_trigger := _good()
	bad_trigger["windows"][0]["trigger"] = {"type": "магия"}
	t.is_true("неизвестный триггер — BAD_VALUE",
		Problems.has(Validator.validate(bad_trigger, null), Problems.BAD_VALUE))

	var unlock_in_node_window := _good()
	unlock_in_node_window["windows"][0]["trigger"] = {"type": "node_entered", "node": "vault"}
	unlock_in_node_window["windows"][0]["silence"]["good"] = [{"type": "unlock", "edge": "e_hall_vault"}]
	t.is_true("unlock в молчании окна не про дверь — BAD_VALUE",
		Problems.has(Validator.validate(unlock_in_node_window, null), Problems.BAD_VALUE))

	# Выполнимость окна у двери. Окно срабатывает один раз за миссию (§4.2), а приказ
	# может быть не отдан: если молчание не открывает ИМЕННО это ребро, группа останется
	# перед запертой дверью навсегда. Варианты в зачёт не идут.
	var no_unlock_silence := _good()
	for quality in ["good", "neutral", "bad", "safe"]:
		no_unlock_silence["windows"][0]["silence"][quality] = [{"type": "delay", "value": 3}]
	t.eq("молчание не открывает ребро окна — UNWINNABLE_EDGE",
		_codes_at(Validator.validate(no_unlock_silence, null), "windows.w_door.silence"),
		[Problems.UNWINNABLE_EDGE])
	# Запертое ребро, unlock во всех четырёх исходах (`_good`, п. 0 выше) — чисто; запертое
	# без unlock — ровно одна проблема. Правило смотрит на РЕБРО, а не на имя триггера.
	t.eq("запертое ребро без unlock в молчании — ровно одна проблема",
		_codes(Validator.validate(no_unlock_silence, null)), [Problems.UNWINNABLE_EDGE])

	# P5. Окно у НЕзапертого ребра: `locked_edge`-триггер не сработает ни разу — запирать
	# нечего, окно не откроется, сцены не будет. Это отдельный дефект контента со своим
	# кодом, а не невыполнимость: группу здесь ничто не держит.
	var open_edge_window := _good()
	open_edge_window["edges"][1].erase("locked")
	t.eq("окно на незапертом ребре — WINDOW_ON_OPEN_EDGE на trigger.edge",
		_codes_at(Validator.validate(open_edge_window, null), "windows.w_door.trigger.edge"),
		[Problems.WINDOW_ON_OPEN_EDGE])
	t.is_false("окно на незапертом ребре — не UNWINNABLE_EDGE",
		Problems.has(Validator.validate(open_edge_window, null), Problems.UNWINNABLE_EDGE))

	# P9. «Заперто» — только честный bool, и это проверяется, а не подразумевается.
	# Чтение запертости через `bool(...)` на не-bool — не приведение, а дефект: строка
	# роняет вызов рантайм-сбоем движка (`bool("да")` — не существующий конструктор),
	# число тихо коэрцируется (`bool(1)` — истина), и ребро с `locked: 1` считалось
	# запертым. Поэтому не-bool ребро называет `WRONG_TYPE` — и БОЛЬШЕ НИЧЕГО: о запертости
	# судить не по чему, а второе следствие на один дефект запрещено шапкой валидатора.
	for wrong_locked in ["да", 1]:
		var non_bool_locked := _good()
		non_bool_locked["edges"][1]["locked"] = wrong_locked
		var non_bool_problems := Validator.validate(non_bool_locked, null)
		t.eq("locked = %s — ровно WRONG_TYPE, без каскада" % str(wrong_locked),
			_codes(non_bool_problems), [Problems.WRONG_TYPE])

	# А это и есть настоящий дефект «окно на незапертом ребре»: `locked` — честный bool
	# false. Отличать его от испорченного поля обязательно: у испорченного диагноз уже
	# назван, а здесь окно действительно не сработает ни разу.
	var honest_unlocked := _good()
	honest_unlocked["edges"][1]["locked"] = false
	t.eq("locked = false — WINDOW_ON_OPEN_EDGE, без WRONG_TYPE",
		_codes(Validator.validate(honest_unlocked, null)), [Problems.WINDOW_ON_OPEN_EDGE])

	# P11. «ЗАПИРАЕМО» = заперто замком ИЛИ перекрывается тревогой. Окно `w_stuck_lift`
	# поставки миссии 01 висит на ребре `e_freight_4_0` (`lift_freight`), которое закрывает
	# тревога, а не замок: прежняя проверка (по `bool(locked)`) называла такое окно
	# `WINDOW_ON_OPEN_EDGE` — «сцены не будет» про сцену, которая есть.
	#
	# Виды рёбер, перекрываемых тревогой, валидатор СПРАШИВАЕТ у ядра
	# (`Response.blockable_kind`), а не перечисляет у себя: второй список разошёлся бы
	# с ядром молча — тот же класс, что `TRIGGER_TYPES`/`WINDOW_KINDS`.
	var alarm_edge := _good()
	alarm_edge["edges"][1]["locked"] = false
	alarm_edge["edges"][1]["kind"] = "lift_main"
	var alarm_problems: Array = Validator.validate(alarm_edge, null)
	t.is_false("окно на перекрытом тревогой ребре — не WINDOW_ON_OPEN_EDGE",
		Problems.has(alarm_problems, Problems.WINDOW_ON_OPEN_EDGE))

	# Обратная сторона, без неё проверка выродилась бы в «WINDOW_ON_OPEN_EDGE не выдаём
	# никогда»: ребро вида, который тревога не перекрывает, остаётся дефектом с прежним
	# диагнозом и на прежнем пути.
	var stair_edge := _good()
	stair_edge["edges"][1]["locked"] = false
	stair_edge["edges"][1]["kind"] = "stairs"
	t.eq("окно на незапираемом ребре (лестница) — WINDOW_ON_OPEN_EDGE",
		_codes_at(Validator.validate(stair_edge, null), "windows.w_door.trigger.edge"),
		[Problems.WINDOW_ON_OPEN_EDGE])

	# У запираемого тревогой ребра работает ПРЕЖНЯЯ проверка выполнимости: окно срабатывает
	# один раз за миссию, и хотя бы один исход молчания обязан открывать ИМЕННО это ребро —
	# иначе группа останется перед перекрытым лифтом навсегда. Это и есть правило, на которое
	# опирается ledger задачи («`wait_rescue` у окна ★27 — риск игрока, а не тупик»).
	var alarm_no_unlock := _good()
	alarm_no_unlock["edges"][1]["locked"] = false
	alarm_no_unlock["edges"][1]["kind"] = "lift_main"
	for quality in ["good", "neutral", "bad", "safe"]:
		alarm_no_unlock["windows"][0]["silence"][quality] = [{"type": "delay", "value": 1}]
	t.eq("запираемое тревогой ребро без unlock в молчании — UNWINNABLE_EDGE",
		_codes_at(Validator.validate(alarm_no_unlock, null), "windows.w_door.silence"),
		[Problems.UNWINNABLE_EDGE])

	# P5. Битая ссылка на ребро — ОДИН дефект, одно следствие: раньше выходило две проблемы
	# (BAD_REF и UNWINNABLE_EDGE), и автор искал вторую причину, которой нет.
	var broken_edge_window := _good()
	broken_edge_window["windows"][0]["trigger"]["edge"] = "нет_такого"
	t.eq("битая ссылка окна на ребро — ровно одна проблема",
		_codes(Validator.validate(broken_edge_window, null)), [Problems.BAD_REF])

	# Форма молчания неполна — корень назван, и о выполнимости не судим: второго следствия
	# у одной ошибки быть не должно (шапка `validator.gd`). Кейс собран так, что молчание
	# НЕ открывает ребро: без пропуска здесь вышло бы два диагноза на одну ошибку.
	var silence_missing_quality := _good()
	for quality in ["good", "neutral", "bad", "safe"]:
		silence_missing_quality["windows"][0]["silence"][quality] = [{"type": "delay", "value": 3}]
	silence_missing_quality["windows"][0]["silence"].erase("safe")
	t.eq("молчание без исхода safe и без unlock — только MISSING_SILENCE",
		_codes(Validator.validate(silence_missing_quality, null)), [Problems.MISSING_SILENCE])

	# То же про форму элемента: одиночный объект — ошибка формы (`WRONG_TYPE`, §4.5), и
	# разбирать его как эффект нечем. Диагноз один.
	var silence_single_object := _good()
	for quality in ["good", "neutral", "bad", "safe"]:
		silence_single_object["windows"][0]["silence"][quality] = [{"type": "delay", "value": 3}]
	silence_single_object["windows"][0]["silence"]["good"] = {"type": "delay", "value": 3}
	t.eq("одиночный объект в молчании — только WRONG_TYPE, без UNWINNABLE",
		_codes(Validator.validate(silence_single_object, null)),
		[Problems.WRONG_TYPE])

	var unlock_only_in_safe := _good()
	for quality in ["good", "neutral", "bad"]:
		unlock_only_in_safe["windows"][0]["silence"][quality] = [{"type": "delay", "value": 3}]
	unlock_only_in_safe["windows"][0]["silence"]["safe"] = [{"type": "unlock", "edge": "e_hall_vault"}]
	t.is_true("unlock только в safe — миссия выполнима",
		not Problems.has(Validator.validate(unlock_only_in_safe, null), Problems.UNWINNABLE_EDGE))

	var unlock_via_fallback := _good()
	for quality in ["good", "neutral", "bad", "safe"]:
		unlock_via_fallback["windows"][0]["silence"][quality] = [{
			"type": "engine_proposal", "id": "hold_door", "want": "дверь открыта, пока инженер выходит",
			"needs": "таймер возврата", "fallback": {"type": "unlock", "edge": "e_hall_vault"},
		}]
	t.is_true("unlock через fallback — миссия выполнима",
		not Problems.has(Validator.validate(unlock_via_fallback, null), Problems.UNWINNABLE_EDGE))

	# Зачёт идёт только по ТОМУ ЖЕ ребру: fallback на соседнюю дверь миссию не спасает.
	var fallback_other_edge := _good()
	for quality in ["good", "neutral", "bad", "safe"]:
		fallback_other_edge["windows"][0]["silence"][quality] = [{
			"type": "engine_proposal", "id": "hold_door", "want": "дверь открыта",
			"needs": "таймер", "fallback": {"type": "unlock", "edge": "e_entry_hall"},
		}]
	t.is_true("fallback на другое ребро — UNWINNABLE_EDGE",
		Problems.has(Validator.validate(fallback_other_edge, null), Problems.UNWINNABLE_EDGE))

	# Группа «молчание без unlock» — ровно одна проблема, не четыре: автор читает
	# причину окна, а не четыре её отпечатка.
	var one_message := _good()
	for quality in ["good", "neutral", "bad", "safe"]:
		one_message["windows"][0]["silence"][quality] = [{"type": "delay", "value": 1}]
	t.eq("одна проблема на окно, а не на каждый исход",
		_codes_at(Validator.validate(one_message, null), "windows.w_door.silence"), [Problems.UNWINNABLE_EDGE])

	var node_window_without_unlock := _good()
	node_window_without_unlock["windows"][0]["trigger"] = {"type": "node_entered", "node": "vault"}
	t.is_true("окно не про дверь без unlock проходит",
		not Problems.has(Validator.validate(node_window_without_unlock, null), Problems.UNWINNABLE_EDGE))

	# 10. Точки доступа: действия непусты, стоимость в шагах.
	var no_actions := _good()
	no_actions["access_points"][0]["actions"] = []
	t.is_true("точка доступа без действий — EMPTY_SECTION",
		Problems.has(Validator.validate(no_actions, null), Problems.EMPTY_SECTION))

	var no_actions_field := _good()
	no_actions_field["access_points"][0].erase("actions")
	t.eq("точка доступа без поля actions — MISSING_FIELD",
		_codes_at(Validator.validate(no_actions_field, null), "access_points[0].actions"), [Problems.MISSING_FIELD])

	# I4 + M6: `cost.steps` обязателен, целый и ≥ 0.
	var no_steps := _good()
	no_steps["access_points"][0]["actions"][0]["cost"] = {}
	t.eq("действие без cost.steps — MISSING_FIELD",
		_codes_at(Validator.validate(no_steps, null), "access_points[0].actions[0].cost.steps"), [Problems.MISSING_FIELD])

	var neg_steps := _good()
	neg_steps["access_points"][0]["actions"][0]["cost"] = {"steps": -1}
	t.eq("cost.steps < 0 — BAD_VALUE",
		_codes_at(Validator.validate(neg_steps, null), "access_points[0].actions[0].cost.steps"), [Problems.BAD_VALUE])

	var str_steps := _good()
	str_steps["access_points"][0]["actions"][0]["cost"] = {"steps": "четыре"}
	t.eq("cost.steps строкой — WRONG_TYPE",
		_codes_at(Validator.validate(str_steps, null), "access_points[0].actions[0].cost.steps"), [Problems.WRONG_TYPE])

	# P10. `trace_key` — известное НЕОБЯЗАТЕЛЬНОЕ поле точки доступа (04-texts.md §3.4):
	# ключ текста подсказки следа. Схема его не знала, и три обязательных ключа `ap.*.trace`
	# поставки миссии 01 висели вне данных — проверять было нечего (правило 23).
	#
	# Два ассерта ниже держат РАЗНЫЕ половины, и вторая не следует из первой:
	# поле принято схемой И ключ из него попал в сверку текстов (`_walk_text_keys` обходит
	# поля с суффиксом `_key`). Положительный ассерт «проходит целиком» их не заменяет:
	# он верен и тогда, когда обход ключей сломан, а текстов не передано.
	var with_trace := _good()
	with_trace["access_points"][0]["trace_key"] = "ap.ap_hall.trace"
	var trace_texts := _texts_for(with_trace)
	trace_texts["ap.ap_hall.trace"] = "Подсказка следа."
	t.is_false("trace_key — не неизвестный ключ",
		Problems.has(Validator.validate(with_trace, trace_texts), Problems.UNKNOWN_KEY))
	t.is_false("ключ ap.*.trace не висячий: trace_key собран сверкой текстов",
		Problems.has(Validator.validate(with_trace, trace_texts), Problems.DANGLING_TEXT))
	t.is_true("точка доступа с trace_key проходит целиком",
		Validator.validate(with_trace, trace_texts).is_empty())

	# Тип необязательного поля проверяется, а не подразумевается: без проверки испорченное
	# поле не названо ничем — сбор текстовых ключей берёт только строки, и число молча
	# выпадает из сверки. Но проверка типа второго диагноза НЕ отменяет: на `trace_key: 5`
	# выходят ДВА диагноза, и оба обязаны быть под ассертом. Прежняя версия звала
	# `validate` с `texts = null`, поэтому каскада не видела вовсе и держала половину.
	var bad_trace := _good()
	bad_trace["access_points"][0]["trace_key"] = 5
	var bad_trace_texts := _texts_for(bad_trace)
	bad_trace_texts["ap.ap_hall.trace"] = "Подсказка следа."
	var bad_trace_problems := Validator.validate(bad_trace, bad_trace_texts)
	t.eq("trace_key числом — WRONG_TYPE на своём пути",
		_codes_at(bad_trace_problems, "access_points[0].trace_key"), [Problems.WRONG_TYPE])
	t.eq("trace_key числом — текст его ключа остался висячим: DANGLING_TEXT",
		_codes_at(bad_trace_problems, "texts.ap.ap_hall.trace"), [Problems.DANGLING_TEXT])

	# P12. ТЕКСТОВЫЕ КЛЮЧИ ПРОВЕРЯЮТСЯ ПО ТИПУ, а не только на присутствие
	# (`validator.gd:_check_text_key`): испорченное поле молча выпадало из сбора ключей
	# (`_walk_text_keys` берёт только строки), и автору приезжал `DANGLING_TEXT` про текст,
	# которого он не терял, — без имени испорченного поля.
	#
	# Проверка типа второго диагноза НЕ отменяет: поле действительно оставляет свой текст
	# без ссылки, поэтому на испорченное поле выходят ДВА диагноза — `WRONG_TYPE` про поле
	# и `DANGLING_TEXT` про его текст. Каскад оставлен осознанно (как у `trace_key` выше),
	# и обе половины закреплены ассертами.
	#
	# Поля проверяются ПО ОДНОМУ: общий хелпер доказывает правило, но не то, что каждое
	# поле к нему подключено. Ключ качества молчания (`silence.<quality>_key`) — новая
	# форма: его обязан принимать `_silence_keys()`, и он обязан попадать в сбор текстов,
	# иначе все 44 ключа качеств поставки висели бы вне сверки.
	var keyed := _good()
	keyed["windows"][0]["text_key"] = "window.w_door.text"
	keyed["windows"][0]["silence"]["good_key"] = "window.w_door.silence.good"
	keyed["access_points"][0]["text_key"] = "ap.ap_hall.text"
	keyed["access_points"][0]["actions"][0]["text_key"] = "ap.ap_hall.copy"
	var keyed_texts := _texts_for(keyed)
	keyed_texts["window.w_door.silence.good"] = "Эхо вскрывает дверь."
	t.is_true("silence.good_key — известное схеме поле и ключ собран сверкой текстов",
		Validator.validate(keyed, keyed_texts).is_empty())

	# Положительная половина держит только «схема знает поле»: она верна и тогда, когда
	# ключ качества не собирается (сверять просто нечего). Поэтому отсутствие текста у
	# ключа качества обязано называться СВОИМ путём — иначе сбор ключ не видит.
	#
	# Путь здесь ИНДЕКСНЫЙ (`windows[0]`), а не по id окна: `_walk_text_keys` обходит файл,
	# а не разобранную модель, и id ему неоткуда взять. У проверок типа путь другой
	# (`windows.w_door.silence.good_key`) — пути двух диагнозов об одном поле не совпадают.
	var keyed_missing := _texts_for(keyed)
	keyed_missing.erase("window.w_door.silence.good")
	t.eq("нет текста у ключа качества — MISSING_TEXT на пути поля",
		_codes_at(Validator.validate(keyed, keyed_missing), "windows[0].silence.good_key"),
		[Problems.MISSING_TEXT])

	# Испорченные ключи: по одному на каждое поле из минимума (п. C задания).
	var bad_window_text := _good()
	bad_window_text["windows"][0]["text_key"] = 5
	var bad_window_text_problems := Validator.validate(bad_window_text, _texts_for(bad_window_text))
	t.eq("windows[].text_key числом — WRONG_TYPE на своём пути",
		_codes_at(bad_window_text_problems, "windows.w_door.text_key"), [Problems.WRONG_TYPE])
	t.eq("windows[].text_key числом — текст его ключа остался висячим: DANGLING_TEXT",
		_codes_at(bad_window_text_problems, "texts.window.w_door.text"), [Problems.DANGLING_TEXT])
	## Третий ассерт держит ГРАНИЦУ каскада: у одной ошибки ровно два следствия, и на
	## стороне поля — только `WRONG_TYPE`. Он же покрывает охрану `_walk_text_keys`
	## («собираем только строки»): сними её — число 5 уедет в сверку ключом «5», и к двум
	## диагнозам добавится третий, `MISSING_TEXT`. Проба N1 в отчёте называет этот ассерт.
	t.eq("windows[].text_key числом — ровно два диагноза, третьего нет",
		_codes(bad_window_text_problems), [Problems.WRONG_TYPE, Problems.DANGLING_TEXT])

	var bad_option_text := _good()
	bad_option_text["windows"][0]["options"][0]["text_key"] = 5
	t.eq("options[].text_key числом — WRONG_TYPE на своём пути",
		_codes_at(Validator.validate(bad_option_text, _texts_for(bad_option_text)),
			"windows.w_door.options[0].text_key"), [Problems.WRONG_TYPE])

	var bad_silence_text := _good()
	bad_silence_text["windows"][0]["silence"]["text_key"] = 5
	t.eq("silence.text_key числом — WRONG_TYPE на своём пути",
		_codes_at(Validator.validate(bad_silence_text, _texts_for(bad_silence_text)),
			"windows.w_door.silence.text_key"), [Problems.WRONG_TYPE])

	var bad_quality_text := _good()
	bad_quality_text["windows"][0]["silence"]["good_key"] = 5
	var bad_quality_texts := _texts_for(bad_quality_text)
	bad_quality_texts["window.w_door.silence.good"] = "Эхо вскрывает дверь."
	var bad_quality_problems := Validator.validate(bad_quality_text, bad_quality_texts)
	t.eq("silence.good_key числом — WRONG_TYPE на своём пути",
		_codes_at(bad_quality_problems, "windows.w_door.silence.good_key"), [Problems.WRONG_TYPE])
	t.eq("silence.good_key числом — текст качества остался висячим: DANGLING_TEXT",
		_codes_at(bad_quality_problems, "texts.window.w_door.silence.good"), [Problems.DANGLING_TEXT])

	var bad_point_text := _good()
	bad_point_text["access_points"][0]["text_key"] = 5
	t.eq("access_points[].text_key числом — WRONG_TYPE на своём пути",
		_codes_at(Validator.validate(bad_point_text, _texts_for(bad_point_text)),
			"access_points[0].text_key"), [Problems.WRONG_TYPE])

	var bad_action_text := _good()
	bad_action_text["access_points"][0]["actions"][0]["text_key"] = 5
	t.eq("access_points[].actions[].text_key числом — WRONG_TYPE на своём пути",
		_codes_at(Validator.validate(bad_action_text, _texts_for(bad_action_text)),
			"access_points[0].actions[0].text_key"), [Problems.WRONG_TYPE])

	# Два поля минимума, у которых проверка типа была и раньше, но кейса не было:
	# `title_key` (корень) и `note_key` (разведка). Без ассерта «проверено» держалось бы
	# чтением кода — ровно тот класс, из-за которого этот раздел и появился.
	var bad_title := _good()
	bad_title["title_key"] = 5
	t.eq("title_key числом — WRONG_TYPE на своём пути",
		_codes_at(Validator.validate(bad_title, null), "title_key"), [Problems.WRONG_TYPE])

	var bad_note_key := _good()
	bad_note_key["intel"][0]["entries"][0]["note_key"] = 5
	t.eq("intel[].entries[].note_key числом — WRONG_TYPE на своём пути",
		_codes_at(Validator.validate(bad_note_key, null), "intel[0].entries[0].note_key"),
		[Problems.WRONG_TYPE])

	# I4 + M6: цена и эффекты варианта обязательны, сложность — 1..3.
	for field in ["noise", "delay"]:
		var no_cost_field := _good()
		no_cost_field["windows"][0]["options"][0]["cost"].erase(field)
		t.eq("у варианта нет cost.%s — MISSING_FIELD" % field,
			_codes_at(Validator.validate(no_cost_field, null), "windows.w_door.options[0].cost.%s" % field),
			[Problems.MISSING_FIELD])

	var no_effects := _good()
	no_effects["windows"][0]["options"][0].erase("effects")
	t.eq("у варианта нет effects — MISSING_FIELD",
		_codes_at(Validator.validate(no_effects, null), "windows.w_door.options[0].effects"), [Problems.MISSING_FIELD])

	var empty_effects := _good()
	empty_effects["windows"][0]["options"][0]["effects"] = []
	t.is_true("пустой effects допустим",
		Validator.validate(empty_effects, _texts_for(empty_effects)).is_empty())

	# P8. Тип в MISSING_FIELD — по ФАКТУ поля, а не общий «String». Раньше отсутствие
	# `effects` (массив), `cost` (словарь) и `complexity` (число) обещало строку: тесты
	# сверяли код и путь, поэтому ложь в сообщении не ловилась (класс M3).
	var no_effects_field := _good()
	no_effects_field["windows"][0]["options"][0].erase("effects")
	var no_effects_field_problems := Validator.validate(no_effects_field, null)
	t.eq("нет options[].effects — MISSING_FIELD на своём пути",
		_codes_at(no_effects_field_problems, "windows.w_door.options[0].effects"), [Problems.MISSING_FIELD])
	t.is_true("нет options[].effects — обещан массив (по-русски)",
		_message_at(no_effects_field_problems, "windows.w_door.options[0].effects").contains("массив"))
	# Ассерт ниже НЕ вырожден: проба с английским именем в этом сообщении («ожидалось:
	# String» на поле `effects`) краснит именно его. Но он ИЗБЫТОЧЕН — то же нарушение
	# называет корпусный ассерт нормы (кейс 13), и норму держит он. Оставлен как
	# именованная страховка от возврата «ожидался String»: имя провала говорит о поле.
	t.is_false("нет options[].effects — в сообщении нет «ожидался String»",
		_message_at(no_effects_field_problems, "windows.w_door.options[0].effects").contains("String"))

	var no_option_cost := _good()
	no_option_cost["windows"][0]["options"][0].erase("cost")
	t.is_true("нет options[].cost — обещан словарь",
		_message_at(Validator.validate(no_option_cost, null), "windows.w_door.options[0].cost").contains("словарь"))

	var no_action_cost := _good()
	no_action_cost["access_points"][0]["actions"][0].erase("cost")
	t.is_true("нет actions[].cost — обещан словарь",
		_message_at(Validator.validate(no_action_cost, null), "access_points[0].actions[0].cost").contains("словарь"))

	var no_action_complexity := _good()
	no_action_complexity["access_points"][0]["actions"][0].erase("complexity")
	t.is_true("нет actions[].complexity — обещано целое",
		_message_at(Validator.validate(no_action_complexity, null),
			"access_points[0].actions[0].complexity").contains("целое"))

	# Обязательный `fallback` — нестрока: прежнее сообщение подставляло в слот ожидаемого
	# типа целую фразу, и автор читал «ожидался без fallback окно останется без эффекта».
	var no_fallback := _good()
	no_fallback["windows"][0]["options"][0]["effects"] = [{
		"type": "engine_proposal", "id": "lure", "want": "инженер выйдет", "needs": "состояние поста",
	}]
	var no_fallback_problems := Validator.validate(no_fallback, null)
	t.eq("у engine_proposal нет fallback — MISSING_FIELD",
		_codes_at(no_fallback_problems, "windows.w_door.options[0].effects[0].fallback"),
		[Problems.MISSING_FIELD])
	t.is_true("нет fallback — тип назван, а не фраза",
		_message_at(no_fallback_problems,
			"windows.w_door.options[0].effects[0].fallback").contains("словарь эффекта"))

	# Пустой `fallback` — не «не тот тип»: тип как раз верный, пусто СОДЕРЖИМОЕ. Прежнее
	# сообщение («ожидался словарь эффекта, получен Array») врало и отправляло автора
	# менять тип там, где менять надо содержимое.
	var empty_fallback := _good()
	empty_fallback["windows"][0]["options"][0]["effects"] = [{
		"type": "engine_proposal", "id": "lure", "want": "инженер выйдет", "needs": "состояние поста",
		"fallback": [],
	}]
	var empty_fallback_problems := Validator.validate(empty_fallback, null)
	t.eq("пустой fallback — BAD_VALUE на своём пути",
		_codes_at(empty_fallback_problems, "windows.w_door.options[0].effects[0].fallback"),
		[Problems.BAD_VALUE])
	t.is_true("пустой fallback — в сообщении сказано «пустой», а не «другой тип»",
		_message_at(empty_fallback_problems,
			"windows.w_door.options[0].effects[0].fallback").contains("пустой"))

	# Защита в глубину самого валидатора: мусор в `fallback` не должен его ронять.
	# `fallback` — единственное место, где форма терпит и объект, и массив (§7), поэтому
	# именно сюда попадает что угодно. Прежний `_opens_edge(effect: Dictionary, ...)`
	# абортировал прогон рантаймом на первом же не-словаре.
	var garbage_fallback := _good()
	garbage_fallback["windows"][0]["silence"]["good"] = [{
		"type": "engine_proposal", "id": "lure", "want": "инженер выйдет", "needs": "состояние поста",
		"fallback": [5],
	}]
	t.eq("число в fallback — WRONG_TYPE, а не падение",
		_codes_at(Validator.validate(garbage_fallback, null), "windows.w_door.silence.good[0].fallback"),
		[Problems.WRONG_TYPE])

	var dict_type_effect := _good()
	dict_type_effect["windows"][0]["silence"]["good"] = [{"type": {"не": "строка"}}]
	t.eq("словарь в type эффекта — WRONG_TYPE, а не падение",
		_codes_at(Validator.validate(dict_type_effect, null), "windows.w_door.silence.good[0].type"),
		[Problems.WRONG_TYPE])

	# 11. Разведка: у агентуры обязан быть ровно один подброшенный пункт.
	var agents_ok := _good()
	agents_ok["intel"] = [{
		"channel": "agents", "observed_at": 0,
		"entries": [{"kind": "sensor", "nodes": ["hall"], "age_hours": 6, "false": true}],
	}]
	t.is_true("агентура с одной ложью проходит",
		Validator.validate(agents_ok, _texts_for(agents_ok)).is_empty())

	var agents_none := _good()
	agents_none["intel"] = [{
		"channel": "agents", "observed_at": 0,
		"entries": [{"kind": "sensor", "nodes": ["hall"], "age_hours": 6, "false": false}],
	}]
	t.is_true("агентура без лжи — INTEL_LIE_COUNT",
		Problems.has(Validator.validate(agents_none, null), Problems.INTEL_LIE_COUNT))

	var agents_two := _good()
	agents_two["intel"] = [{
		"channel": "agents", "observed_at": 0,
		"entries": [
			{"kind": "sensor", "nodes": ["hall"], "age_hours": 6, "false": true},
			{"kind": "sensor", "nodes": ["entry"], "age_hours": 6, "false": true},
		],
	}]
	t.is_true("агентура с двумя ложьями — INTEL_LIE_COUNT",
		Problems.has(Validator.validate(agents_two, null), Problems.INTEL_LIE_COUNT))

	var bad_patrol_ref := _good()
	bad_patrol_ref["intel"] = [{
		"channel": "hack", "observed_at": 0,
		"entries": [{"kind": "patrol", "id": "guard_нет", "route": ["hall"], "period": 4,
			"age_hours": 8, "false": false}],
	}]
	t.is_true("разведка ссылается на несуществующий патруль — BAD_REF",
		Problems.has(Validator.validate(bad_patrol_ref, null), Problems.BAD_REF))

	# Поля разведки, объявленные схемой (§5), проверяются по типу: маршрут призрака — список
	# строк, период и счётчик — целые, пометка лжи — булево. Раньше этих проверок не было
	# вовсе: `"route": "floor3"` проходил молча, и «скелет проверен валидатором» ничего не
	# говорило про маршруты в разведке.
	var intel_bad_route := _good()
	intel_bad_route["intel"][0]["entries"][0]["route"] = "hall"
	t.eq("intel route строкой — WRONG_TYPE",
		_codes_at(Validator.validate(intel_bad_route, null), "intel[0].entries[0].route"), [Problems.WRONG_TYPE])

	var intel_bad_false := _good()
	intel_bad_false["intel"][0]["entries"][0]["false"] = "да"
	t.eq("intel false строкой — WRONG_TYPE",
		_codes_at(Validator.validate(intel_bad_false, null), "intel[0].entries[0].false"), [Problems.WRONG_TYPE])

	# Одна ошибка — одно следствие: не-bool пометка `false` у агентуры даёт ТОЛЬКО
	# `WRONG_TYPE`. Раньше к ней добавлялся `INTEL_LIE_COUNT` (счёт лож падал до нуля),
	# и автор искал недостающую ложь вместо кривого поля.
	var agents_bad_false := _good()
	agents_bad_false["intel"] = [{
		"channel": "agents", "observed_at": 0,
		"entries": [{"kind": "sensor", "nodes": ["hall"], "age_hours": 6, "false": "да"}],
	}]
	t.eq("не-bool `false` у агентуры — только WRONG_TYPE, без INTEL_LIE_COUNT",
		_codes(Validator.validate(agents_bad_false, null)), [Problems.WRONG_TYPE])

	var intel_bad_count := _good()
	intel_bad_count["intel"] = [{"channel": "hack", "observed_at": 0,
		"entries": [{"kind": "guard_count", "node": "hall", "count": "один", "age_hours": 8}]}]
	t.eq("intel count строкой — WRONG_TYPE",
		_codes_at(Validator.validate(intel_bad_count, null), "intel[0].entries[0].count"), [Problems.WRONG_TYPE])

	# Маршрут призрака с графом НЕ сверяется: призрак обязан врать, и в подброшенном
	# расписании скелета назван этаж, которого в миссии нет. Ложь — часть уровня (D30).
	var ghost_route_unknown_node := _good()
	ghost_route_unknown_node["intel"] = [{"channel": "hack", "observed_at": 0,
		"entries": [{"kind": "patrol", "id": "guard_1", "route": ["hall", "этаж_которого_нет"],
			"period": 4, "age_hours": 8, "false": false}]}]
	t.is_true("маршрут призрака не сверяется с графом",
		Validator.validate(ghost_route_unknown_node, _texts_for(ghost_route_unknown_node)).is_empty())

	# M6. Возраст данных обязателен (02-format.md §5) и неотрицателен; снимок — тоже.
	var no_age := _good()
	no_age["intel"] = [{"channel": "hack", "observed_at": 0,
		"entries": [{"kind": "sensor", "nodes": ["hall"]}]}]
	t.eq("пункт разведки без age_hours — MISSING_FIELD",
		_codes_at(Validator.validate(no_age, null), "intel[0].entries[0].age_hours"), [Problems.MISSING_FIELD])

	var neg_age := _good()
	neg_age["intel"] = [{"channel": "hack", "observed_at": 0,
		"entries": [{"kind": "sensor", "nodes": ["hall"], "age_hours": -1}]}]
	t.eq("age_hours < 0 — BAD_VALUE",
		_codes_at(Validator.validate(neg_age, null), "intel[0].entries[0].age_hours"), [Problems.BAD_VALUE])

	var neg_observed := _good()
	neg_observed["intel"][0]["observed_at"] = -2
	t.eq("observed_at < 0 — BAD_VALUE",
		_codes_at(Validator.validate(neg_observed, null), "intel[0].observed_at"), [Problems.BAD_VALUE])

	# M2. Ключи пояснений разведки адресуются по каналу и пометке: собрать их из данных
	# нельзя, поэтому без префикса `intel.` они получали ложный DANGLING_TEXT.
	var intel_texts := _texts_for(_good())
	intel_texts["intel.hack.patrol_false"] = "Подброшенное расписание."
	t.is_true("ключ intel.<канал>.<пометка> не висячий",
		Validator.validate(_good(), intel_texts).is_empty())

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

	# 12б. СЕМАНТИКА ВТОРОГО АРГУМЕНТА — три входа на ОДНИХ данных, и все три различимы.
	# Раньше здесь стояло умолчание `{}`, и «сверка выключена» было неотличимо от «текстов
	# нет»: `validate(data)` возвращал «проблем нет», ничего не сверив. Теперь отказ — это
	# `null`, и он проверяется отдельно от пустого словаря.
	#
	# Число ключей берётся у самого валидатора, а не вписано константой: вписанное число
	# разошлось бы с `_good()` при первом же новом поле, и проверка начала бы врать.
	# Приватность здесь по соглашению (подчёркивание), как и у `Loader._items` в кейсе
	# загрузчика: публичную обёртку держали бы только ради теста.
	var data_text_keys: Array = Validator._collect_text_keys(_good())
	t.is_true("у `_good()` есть ключи текстов (иначе три кейса ниже вырождены): %d"
		% data_text_keys.size(), data_text_keys.size() > 0)

	# (а) `null` — сверки нет вовсе: ни MISSING_TEXT, ни DANGLING_TEXT, хотя ключи есть.
	t.eq("texts = null — проблем про тексты нет",
		_codes(Validator.validate(_good(), null)), [])

	# (б) `{}` — «текстов нет»: осмысленное утверждение, и тогда отсутствуют ВСЕ ключи
	# данных — и все обязательные системные ключи, которых данные не называют вовсе.
	# Именно этот ассерт краснеет, если сверку ключей случайно отключить.
	#
	# Ключ, лежащий И в данных, И в обязательном списке (`mission.01.title`), назван здесь
	# ОДИН раз — как `MISSING_TEXT` на своём поле: второго диагноза ему не выписывают
	# (`validator.gd:_check_required_texts`), и кейс 14 держит это отдельным ассертом.
	var expected_missing: Array = []
	for _i in data_text_keys.size():
		expected_missing.append(Problems.MISSING_TEXT)
	for key in REQUIRED_TEXTS:
		if not _key_in(data_text_keys, key):
			expected_missing.append(Problems.MISSING_REQUIRED_TEXT)
	t.eq("texts = {} — диагноз на каждый отсутствующий ключ (%d)" % expected_missing.size(),
		_codes(Validator.validate(_good(), {})), expected_missing)

	# 12в. ТРЕТЬЕ состояние второго аргумента: не `null` и не словарь. Тип у `texts` не указан
	# намеренно (иначе `null` — законное «сверку не делаю» — не прошёл бы на вход), поэтому
	# компилятор ловит ЗАБЫВАНИЕ аргумента, но не подстановку НЕ ТОГО. Проба на прежнем коде:
	# вызов со строкой отдавал `problems = 0`, а движок печатал в stderr `Nonexistent function
	# 'has' in base 'String'` и обрывал `_check_texts` на первой же строке — «проблем нет»
	# стояло на рантайм-ошибке, а stderr вердиктом не является (§6.1.1). Триггер правдоподобен:
	# у `load_text(json_text: String, texts)` рядом два строковых параметра.
	#
	# Проверяются все четыре не-словаря: строка — та самая описка, число и логическое —
	# перепутанный порядок аргументов. Сверка при этом НЕ выполняется вовсе (иначе к дефекту
	# вызова добавился бы `MISSING_TEXT` на каждый ключ данных — второе следствие одной ошибки).
	#
	# ЧЕТВЁРТЫЙ вход — `[]`, и он здесь главный. У строки, числа и `false` метода `has` нет:
	# на сломанном «сверку ведём всегда» `_check_texts` падает рантаймом на первой же строке
	# (`Nonexistent function 'has' in base 'String'`) и успевает добавить только `WRONG_TYPE`,
	# поэтому кейс остаётся ЗЕЛЁНЫМ, хотя наблюдаемое поведение изменилось, — а stderr
	# вердиктом не является (§6.1.1). Так имена этих ассертов держались на том, что выбранные
	# типы падают РАНЬШЕ сверки. У `Array` метод `has` есть, поэтому сломанный код доживает
	# до каскада: верный даёт ровно `["WRONG_TYPE"]`, сломанный — `WRONG_TYPE` плюс
	# `MISSING_TEXT` на каждый ключ данных, и ассерт ниже называет расхождение.
	#
	# Заодно `[]` проходит норму имён типов (кейс 13): сообщение читается «ожидалось:
	# словарь, получено: массив».
	#
	# Про типы ВНЕ таблицы (кейс 13): `Problems.type_name` для них честно откатывается на
	# `type_string`, поэтому «получено: Object / Callable / Vector2» — документированный
	# откат, а не дефект. Из JSON такие значения недостижимы: разбор даёт только `null`,
	# число, строку, массив и словарь, — а прочие типы приходят исключительно прямым вызовом
	# из GDScript. Корпус кейса 13 из достижимых типов и собран, и шире таблицы норма не
	# обещает.
	var wrong_texts_norm: Array = []
	for wrong_texts in ["мусор-строка", 7, false, []]:
		var wrong_texts_problems: Array = Validator.validate(_good(), wrong_texts)
		t.eq("texts = %s — ровно WRONG_TYPE, без сверки" % str(wrong_texts),
			_codes(wrong_texts_problems), [Problems.WRONG_TYPE])
		# Ассерты читают сообщение через `_message_at`, а не через `problems[0]`: со снятой
		# проверкой список пуст, и обращение по индексу уронило бы кейс рантаймом вместо
		# именованного провала (тот же класс, что разобран у `kind` ↔ `trigger.type`).
		#
		# Сверяются ОБЕ половины сообщения, и каждая — в своём слоте. Прежний
		# `contains("словарь")` держал только ожидаемую половину: проба F (фактический тип
		# в вызове подменён на `TYPE_ARRAY`) оставляла набор зелёным (728/0), потому что
		# подменялось ровно то, чего ассерт не читал.
		t.is_true("texts = %s — проблема на пути (тексты), ожидание названо" % str(wrong_texts),
			_message_at(wrong_texts_problems, "(тексты)").contains("ожидалось: словарь"))
		# Ожидание берётся у самого аргумента, а не вписано словом: ассерт обязан держать
		# связь «фактический тип в сообщении ← тип аргумента», а не «в сообщении есть слово».
		t.is_true("texts = %s — фактический тип назван" % str(wrong_texts),
			_message_at(wrong_texts_problems, "(тексты)").contains(
				"получено: %s" % Problems.type_name(typeof(wrong_texts))))
		wrong_texts_norm.append_array(wrong_texts_problems)

	# 12a. НЕПОКРЫТЫЕ ПРАВИЛА. Шапка файла объявляет «один кейс на код», и план задачи 2 —
	# то же. Ниже — правила, у которых кейса не было: мутационная проба снимала правило,
	# а реальный набор оставался зелёным, то есть правило держалось ничем.
	#
	# Каждый вход ломает РОВНО одно место, а ожидание — точный список кодов на своём пути
	# (`_codes_at`), а не «проблема есть». Иначе кейс проходил бы на чужом диагнозе: так
	# уже случалось с `kind` ↔ `trigger.type`, где «список непуст» ничего не доказывал.
	#
	# Все входы — из одной корректной миссии (`_good`), поэтому любой лишний код в
	# ожидании сразу виден: он означал бы каскад, которого шапка валидатора не допускает.

	# 12a-1. Вариантов у окна не может быть ноль (validator.gd:550): окно без выбора —
	# не окно, у него нет ни одного приказа. Список пуст — EMPTY_SECTION на самом пути.
	var empty_options := _good()
	empty_options["windows"][0]["options"] = []
	t.eq("у окна ноль вариантов — EMPTY_SECTION",
		_codes_at(Validator.validate(empty_options, null), "windows.w_door.options"),
		[Problems.EMPTY_SECTION])

	# 12a-2. id варианта уникален внутри окна (validator.gd:575). Сверка идёт по id, а не
	# только по подписи «цена + эффекты»: сломай только её — два одинаковых id пройдут.
	var dup_option_id := _good()
	dup_option_id["windows"][0]["options"].append({"id": "breach", "text_key": "window.w_door.breach2",
		"complexity": 2, "cost": {"noise": 3, "delay": 1},
		"effects": [{"type": "delay", "value": 1}]})
	# Путь у `DUPLICATE_ID` варианта — раздел окна (`windows.w_door.options`), а не индекс:
	# id повторяется в окне, и автору нужен раздел. Проверяется и код, и ЧИСЛО проблем
	# (одна, а не две) — иначе кейс пройдёт на каскаде «повтор подписи».
	var dup_option_problems := Validator.validate(dup_option_id, null)
	t.eq("повтор id варианта внутри окна — DUPLICATE_ID ровно одна",
		_codes_at(dup_option_problems, "windows.w_door.options"),
		[Problems.DUPLICATE_ID])

	# 12a-3. `cost.noise`/`cost.delay` ≥ 0 (validator.gd:600): отрицательная цена — не цена.
	for field in ["noise", "delay"]:
		var neg_cost := _good()
		neg_cost["windows"][0]["options"][0]["cost"][field] = -1
		t.eq("cost.%s < 0 — BAD_VALUE" % field,
			_codes_at(Validator.validate(neg_cost, null), "windows.w_door.options[0].cost.%s" % field),
			[Problems.BAD_VALUE])

	# 12a-4. `noise.value`/`delay.value` ≥ 0 (validator.gd:768). Положительный вход рядом:
	# значение 5 в молчании `_good` проходит, и «поле не читается вовсе» не спрячется.
	for effect_type in ["noise", "delay"]:
		var neg_value := _good()
		neg_value["windows"][0]["silence"]["bad"] = [{"type": effect_type, "value": -1}]
		t.eq("эффект %s со значением < 0 — BAD_VALUE" % effect_type,
			_codes_at(Validator.validate(neg_value, null), "windows.w_door.silence.bad[0].value"),
			[Problems.BAD_VALUE])

	# 12a-5. Тип эффекта из EFFECT_TYPES (validator.gd:751): неизвестный эффект — не эффект,
	# а `engine_proposal` для нового поведения. Сломанное правило пропустило бы «магию»
	# молча, и ядро получило бы эффект, которого не умеет.
	var bad_effect_type := _good()
	bad_effect_type["windows"][0]["options"][0]["effects"][0]["type"] = "магия"
	t.eq("неизвестный тип эффекта — BAD_VALUE",
		_codes_at(Validator.validate(bad_effect_type, null), "windows.w_door.options[0].effects[0].type"),
		[Problems.BAD_VALUE])

	# 12a-6. Тип триггера из TRIGGER_TYPES (validator.gd:514). Путь — на поле триггера:
	# снятое правило оставляло «магию» без диагноза.
	var bad_trigger_type := _good()
	bad_trigger_type["windows"][0]["trigger"] = {"type": "магия", "node": "vault"}
	t.eq("неизвестный тип триггера — BAD_VALUE",
		_codes_at(Validator.validate(bad_trigger_type, null), "windows.w_door.trigger.type"),
		[Problems.BAD_VALUE])

	# 12a-7. Ребро в себя (validator.gd:238): петля бесполезна — она не ведёт никуда.
	var self_loop := _good()
	self_loop["edges"][0]["b"] = "entry"
	t.eq("ребро в себя — BAD_VALUE на самом ребре",
		_codes_at(Validator.validate(self_loop, null), "edges[0]"), [Problems.BAD_VALUE])

	# 12a-8. Соседние точки маршрута патруля соединены ребром (validator.gd:299): движок
	# путь не ищет и на разрыве охранник застрянет. `entry → vault` ребра не имеет:
	# есть только `entry → hall` и `hall → vault`.
	var route_gap := _good()
	route_gap["patrols"][0]["route"] = ["entry", "vault"]
	t.eq("разрыв между соседними точками патруля — BAD_VALUE на route",
		_codes_at(Validator.validate(route_gap, null), "patrols[0].route"), [Problems.BAD_VALUE])

	# 12a-9. `intel[].entries[].kind` из INTEL_KINDS (validator.gd:860).
	var bad_intel_kind := _good()
	bad_intel_kind["intel"] = [{"channel": "hack", "observed_at": 0,
		"entries": [{"kind": "слух", "node": "hall", "count": 1, "age_hours": 8, "false": false}]}]
	t.eq("неизвестный вид данных разведки — BAD_VALUE",
		_codes_at(Validator.validate(bad_intel_kind, null), "intel[0].entries[0].kind"),
		[Problems.BAD_VALUE])

	# 12a-10. `observed_at` отрицательный (validator.gd:838): снимок «до начала операции» —
	# не снимок. Положительный ноль в `_good` проходит, поэтому проверка не вырождена.
	var neg_observed_at := _good()
	neg_observed_at["intel"][0]["observed_at"] = -1
	t.eq("observed_at < 0 — BAD_VALUE",
		_codes_at(Validator.validate(neg_observed_at, null), "intel[0].observed_at"),
		[Problems.BAD_VALUE])

	# 12a-11. id окна не повторяется (validator.gd:462). Окно-двойник берётся полной копией:
	# тогда у него нет ни одной СВОЕЙ болезни, и единственный диагноз — повтор id.
	var dup_window := _good()
	dup_window["windows"].append((_good()["windows"][0] as Dictionary).duplicate(true))
	t.eq("повтор id окна — DUPLICATE_ID",
		_codes_at(Validator.validate(dup_window, null), "windows"), [Problems.DUPLICATE_ID])

	# 13. НОРМА ИМЁН ТИПОВ. Держится проверкой, а не комментарием: корпус точечных дефектов
	# (по одному на миссию — без каскадов) плюс три разных фактических типа, и КАЖДОЕ
	# сообщение `MISSING_FIELD`/`WRONG_TYPE` обязано назвать тип по-русски и не содержать
	# английских имён. Попытка вернуть `type_string(...)` в новое сообщение краснит этот кейс.
	var norm_corpus: Array = []
	for broken in [no_effects_field, no_option_cost, no_action_cost, no_action_complexity,
			no_fallback, empty_fallback, silence_single_object]:
		norm_corpus.append_array(Validator.validate(broken, null))
	var norm_other := _good()
	norm_other["nodes"]["hall"]["floor"] = "первый"           # строка вместо целого
	norm_other["edges"][0]["locked"] = "да"                  # строка вместо логического
	norm_other["windows"][0]["trigger"] = ["не", "словарь"]  # массив вместо словаря
	norm_corpus.append_array(Validator.validate(norm_other, null))
	## Плюс третий вход второго аргумента (кейс 12в): у него нет ни миссии, ни поля —
	## только форма аргумента, и сообщение обязано подчиняться той же норме имён типов.
	norm_corpus.append_array(wrong_texts_norm)

	# Пустой корпус — провал, а не «зелено по умолчанию»: исчезнувшие дефекты не должны
	# делать проверку нормы бессодержательной.
	var typed_checked := _typed_count(norm_corpus)
	t.is_true("корпус нормированных сообщений непуст (проверено: %d)" % typed_checked,
		typed_checked > 0)
	var norm_violations := _type_name_norm_violations(norm_corpus)
	t.eq("норма имён типов (нарушения: %s)" % "; ".join(norm_violations), norm_violations, [])

	# 14. ОБЯЗАТЕЛЬНЫЕ СИСТЕМНЫЕ КЛЮЧИ (04-texts.md §4 и §3.1–3.2). Долг над
	# `UNUSED_OK_PREFIXES` («обязательные группы не проверяются: текстов ноль, и такая
	# проверка давала бы только ложные срабатывания») закрыт вместе с этим кейсом: тексты
	# поставки есть, и пропажа обязательного ключа — реальный дефект контента.
	#
	# Почему прежней сверки для этих ключей НЕ ХВАТАЛО: у `log.silence` нет поля `*_key`
	# в данных, поэтому `_collect_text_keys` его не видит вовсе. Ключ мог исчезнуть из
	# поставки, и прогон оставался бы зелёным, а игра — без строки молчания, без
	# «КОМАНДУЕТ» и без итогов.
	#
	# Эталон — `REQUIRED_TEXTS` в этом файле, а не константа валидатора (см. её шапку).
	# Две стороны держатся вместе: цикл ниже снимает КАЖДЫЙ ключ эталона по одному —
	# значит список валидатора не короче эталона; положительный ассерт на полном наборе —
	# значит не длиннее (лишнее требование сделало бы его красным).
	t.eq("эталон обязательных ключей — 32 ключа перечня (04-texts.md §4 + §3.1–3.2)",
		REQUIRED_TEXTS.size(), 32)
	var seen_keys: Dictionary = {}
	var repeats: Array = []
	for key in REQUIRED_TEXTS:
		if seen_keys.has(key):
			repeats.append(key)
		else:
			seen_keys[key] = true
	t.eq("в эталоне нет повторов: %s" % (", ".join(repeats) if not repeats.is_empty() else "(нет)"),
		repeats, [])

	var full_texts := _texts_for(_good())
	t.is_true("полный набор (ключи данных + эталон обязательных) проходит без проблем",
		Validator.validate(_good(), full_texts).is_empty())

	# 14а. Отрицательный контроль ПЕРВЫЙ: системный ключ БЕЗ поля в данных. Диагноз обязан
	# называть ИМЕННО этот ключ, и ровно один: «список непуст» здесь не доказывает ничего.
	var no_log := _texts_for(_good())
	no_log.erase("log.silence")
	var no_log_problems: Array = Validator.validate(_good(), no_log)
	t.eq("нет обязательного ключа log.silence — ровно один диагноз",
		_codes(no_log_problems), [Problems.MISSING_REQUIRED_TEXT])
	t.eq("нет log.silence — путь в пространстве имён текстов, а не поля данных",
		_paths(no_log_problems), ["texts.log.silence"])
	t.is_true("нет log.silence — сообщение называет ключ",
		_message_at(no_log_problems, "texts.log.silence").contains("log.silence"))

	# 14б. Отрицательный контроль ВТОРОЙ: ключ, который ЛЕЖИТ В ДАННЫХ. Новое правило не
	# «перекрывает» прежнюю сверку молча: диагноз остаётся про этот ключ и на его поле.
	var no_data_key := _texts_for(_good())
	no_data_key.erase("window.w_door.text")
	var no_data_key_problems: Array = Validator.validate(_good(), no_data_key)
	t.eq("нет ключа из данных (window.w_door.text) — ровно MISSING_TEXT",
		_codes(no_data_key_problems), [Problems.MISSING_TEXT])
	t.eq("нет window.w_door.text — путь на поле данных",
		_paths(no_data_key_problems), ["windows[0].text_key"])
	t.is_true("нет window.w_door.text — сообщение называет ключ",
		_message_at(no_data_key_problems, "windows[0].text_key").contains("window.w_door.text"))

	# 14в. ОДИН КЛЮЧ — ОДИН ДИАГНОЗ. `mission.01.title` лежит И в данных (`title_key`),
	# И в обязательном списке: два диагноза (`MISSING_TEXT` от сверки данных и
	# `MISSING_REQUIRED_TEXT` от нового правила) отправляли бы автора искать вторую
	# причину, которой нет. Ровно один — и он на поле данных, где ключ и живёт.
	var no_title := _texts_for(_good())
	no_title.erase("mission.01.title")
	var no_title_problems: Array = Validator.validate(_good(), no_title)
	t.eq("mission.01.title и в данных, и в обязательных — ровно ОДИН диагноз",
		_codes(no_title_problems), [Problems.MISSING_TEXT])
	t.eq("mission.01.title отсутствует — путь на поле данных, а не в текстах",
		_paths(no_title_problems), ["title_key"])
	t.is_true("mission.01.title отсутствует — сообщение называет ключ",
		_message_at(no_title_problems, "title_key").contains("mission.01.title"))

	# 14г. И то же по одному на КАЖДЫЙ ключ эталона. Цикл держит список валидатора от
	# молчаливого усыхания: ключ, выпавший из `REQUIRED_TEXT_KEYS`, перестаёт называться,
	# и провал приходит с ЕГО именем, а не «проблема где-то в обязательных текстах».
	# Число диагнозов сверяется дважды — «он называет ключ» и «других диагнозов нет»:
	# первый ассерт верен и тогда, когда к верному диагнозу добавился лишний.
	for key in REQUIRED_TEXTS:
		var gapped := _texts_for(_good())
		gapped.erase(key)
		var gapped_problems: Array = Validator.validate(_good(), gapped)
		t.eq("снят обязательный ключ «%s» — есть диагноз про него" % key,
			_problems_naming(gapped_problems, key).size(), 1)
		t.eq("снят обязательный ключ «%s» — и он единственный" % key,
			gapped_problems.size(), 1)

	# 15. ФОРМА ПРЕЗЕНТАЦИИ: координаты помещений, подписи, название комплекса и этажи
	# (`design-presentation-data.md` §2 и §8; `levels/mission-01.md` §3–4). Поля
	# НЕобязательные, и это проверяется с обеих сторон: миссия БЕЗ них обязана оставаться
	# валидной и грузиться (15а), миссия С ними — тоже (15б), а каждый вид поломки
	# обязан называться своим диагнозом на своём пути (15в–15к).
	#
	# Что краснит каждая проба (имена ассертов — в отчёте задачи 10): «сделать `floors`
	# обязательным» — 15а; «убрать `pos`/`name_key` из `NODE_KEYS`» — 15б; «не проверять
	# тип `name_key`/`facility_key`/`floors[].name_key`» — 15в: ключ молча выпадает из
	# сбора текстов (`_walk_text_keys` берёт только строки), и его текст объявляется висячим.

	# 15а. Обратная совместимость формы: у `_good()` нет ни `pos`, ни `name_key`, ни
	# `floors`, ни `facility_key` — и это полноценная миссия, а не «неполная».
	t.is_true("миссия без pos/name_key/floors/facility_key валидна",
		Validator.validate(_good(), _texts_for(_good())).is_empty())

	# 15б. Миссия С полями презентации проходит целиком, вместе со сверкой текстов, —
	# и поля эти ИЗВЕСТНЫ схеме (`UNKNOWN_KEY` не выдаётся). Второй ассерт не следует из
	# первого: положительный верен и тогда, когда `UNKNOWN_KEY` не выдаётся вовсе.
	var shown := _good_presented()
	t.is_true("миссия с pos/name_key/floors/facility_key валидна",
		Validator.validate(shown, _presentation_texts()).is_empty())
	t.is_false("pos/name_key/floors/facility_key — известные схеме поля (нет UNKNOWN_KEY)",
		Problems.has(Validator.validate(shown, _presentation_texts()), Problems.UNKNOWN_KEY))

	# Отрицательные координаты — законная форма схемы этажа, а не `BAD_VALUE`.
	var negative := _good_presented()
	negative["nodes"]["vault"]["pos"] = {"x": -4, "y": -8}
	t.is_true("отрицательные координаты допустимы",
		Validator.validate(negative, _presentation_texts()).is_empty())

	# 15в. Ключи презентации УЧАСТВУЮТ в сверке текстов — обходом `*_key`, а не отдельной
	# проверкой: снятый текст обязан назваться `MISSING_TEXT` на СВОЁМ пути. Путь сверяется
	# целиком, а не «где-то есть проблема»: иначе ассерт проходил бы на чужом диагнозе.
	for pair in [["room.hall", "nodes.hall.name_key"],
			["floor.1", "floors.1.name_key"],
			["facility.meridian", "facility_key"]]:
		var gapped := _presentation_texts()
		gapped.erase(String(pair[0]))
		t.eq("нет текста «%s» — MISSING_TEXT на пути %s" % [String(pair[0]), String(pair[1])],
			_codes_at(Validator.validate(shown, gapped), String(pair[1])), [Problems.MISSING_TEXT])

	# 15г. Обратное направление: ключ семейств `room.`/`floor.`/`facility.` без данных —
	# висячий. `UNUSED_OK_PREFIXES` для них НЕ расширен намеренно: эти ключи выводятся из
	# данных и обязаны быть к ним привязаны, иначе подпись на схеме никем не проверена.
	for extra_key in ["room.нет_такого", "floor.9", "facility.другой"]:
		var extra := _presentation_texts()
		extra[extra_key] = "ЛИШНЕЕ"
		t.eq("лишний ключ «%s» — DANGLING_TEXT" % extra_key,
			_codes_at(Validator.validate(shown, extra), "texts.%s" % extra_key),
			[Problems.DANGLING_TEXT])

	# 15д. `pos`: не словарь — `WRONG_TYPE` на самом поле; неполная и нецелая форма —
	# диагноз на СВОЕЙ оси. Строка вместо числа — ровно та описка, ради которой тип
	# проверяется по факту поля, а не подразумевается.
	## Классы не-словарей проверяются ВСЕ: массив и строка — разные значения, и «массив
	## прошёл» не доказывает, что не-словарь ловится вообще.
	for bad_pos in [[4, 0], "4,0"]:
		var pos_not_dict := _good_presented()
		pos_not_dict["nodes"]["hall"]["pos"] = bad_pos
		t.eq("pos %s — WRONG_TYPE на поле" % str(bad_pos),
			_codes_at(Validator.validate(pos_not_dict, _presentation_texts()), "nodes.hall.pos"),
			[Problems.WRONG_TYPE])

	var pos_string_x := _good_presented()
	pos_string_x["nodes"]["hall"]["pos"] = {"x": "5", "y": 0}
	t.eq("pos.x строкой — WRONG_TYPE на оси",
		_codes_at(Validator.validate(pos_string_x, _presentation_texts()), "nodes.hall.pos.x"),
		[Problems.WRONG_TYPE])

	var pos_no_y := _good_presented()
	pos_no_y["nodes"]["hall"]["pos"] = {"x": 4}
	t.eq("pos без y — MISSING_FIELD на оси",
		_codes_at(Validator.validate(pos_no_y, _presentation_texts()), "nodes.hall.pos.y"),
		[Problems.MISSING_FIELD])

	var pos_half := _good_presented()
	pos_half["nodes"]["hall"]["pos"] = {"x": 4, "y": 1.5}
	t.eq("pos.y дробный — WRONG_TYPE на оси",
		_codes_at(Validator.validate(pos_half, _presentation_texts()), "nodes.hall.pos.y"),
		[Problems.WRONG_TYPE])

	# Список полей координаты закрыт: чужая ось — не «координата без оси», а неизвестное поле.
	var pos_unknown_axis := _good_presented()
	pos_unknown_axis["nodes"]["hall"]["pos"] = {"x": 4, "y": 0, "z": 1}
	t.eq("ось z в pos — UNKNOWN_KEY на поле координаты",
		_codes_at(Validator.validate(pos_unknown_axis, _presentation_texts()), "nodes.hall.pos.z"),
		[Problems.UNKNOWN_KEY])

	# 15е. `name_key` помещения числом — `WRONG_TYPE` на своём пути, и кейс обязан дожить до
	# своих ассертов (урок F1 ревью 2): ни `String(...)` на сломанном поле, ни `problems[0]`
	# здесь нет — путь и код читаются с охраной (`_codes_at`, размер до индексации).
	# Второе следствие то же и по той же причине, что у `trace_key`: ключ не собрался —
	# текст остался без ссылки.
	var bad_name := _good_presented()
	bad_name["nodes"]["hall"]["name_key"] = 5
	var bad_name_problems := Validator.validate(bad_name, _presentation_texts())
	t.eq("name_key числом — WRONG_TYPE на своём пути",
		_codes_at(bad_name_problems, "nodes.hall.name_key"), [Problems.WRONG_TYPE])
	t.eq("name_key числом — текст «room.hall» остался висячим",
		_codes_at(bad_name_problems, "texts.room.hall"), [Problems.DANGLING_TEXT])
	t.eq("name_key числом — диагнозов ровно два, третьего нет",
		bad_name_problems.size(), 2)

	# 15ж. Корневой `facility_key` числом — `WRONG_TYPE` на корне, и текст остаётся висячим.
	var bad_facility := _good_presented()
	bad_facility["facility_key"] = 5
	var bad_facility_problems := Validator.validate(bad_facility, _presentation_texts())
	t.eq("facility_key числом — WRONG_TYPE на поле",
		_codes_at(bad_facility_problems, "facility_key"), [Problems.WRONG_TYPE])
	t.eq("facility_key числом — текст «facility.meridian» висячий",
		_codes_at(bad_facility_problems, "texts.facility.meridian"), [Problems.DANGLING_TEXT])

	# 15з. `floors` — СЛОВАРЬ, а не седьмой раздел-массив. Массив вместо словаря назван
	# `WRONG_TYPE` на своём пути; заодно видно, что `floors` НЕ попал в `ARRAY_SECTIONS`:
	# попади он туда, `[]` был бы законным «этажей нет» и прошёл бы молча.
	for bad_floors in [[], "этажи", 7]:
		var floors_not_dict := _good_presented()
		floors_not_dict["floors"] = bad_floors
		t.eq("floors = %s — WRONG_TYPE на своём пути" % str(bad_floors),
			_codes_at(Validator.validate(floors_not_dict, _presentation_texts()), "floors"),
			[Problems.WRONG_TYPE])

	# 15и. Запись этажа: не словарь — `WRONG_TYPE`; без `name_key` — `MISSING_FIELD`;
	# `name_key` не строкой — `WRONG_TYPE`. Три разных дефекта, три разных диагноза.
	var floor_not_dict := _good_presented()
	floor_not_dict["floors"]["1"] = "ЭТАЖ 1"
	t.eq("запись этажа строкой — WRONG_TYPE на записи",
		_codes_at(Validator.validate(floor_not_dict, _presentation_texts()), "floors.1"),
		[Problems.WRONG_TYPE])
	## Каскад тот же, что у `name_key`: ключ не собрался — его текст остался без ссылки.
	## Диагнозов ровно два, и оба названы; третьего на одну ошибку не выписано.
	t.eq("запись этажа строкой — диагнозов ровно два",
		Validator.validate(floor_not_dict, _presentation_texts()).size(), 2)

	var floor_no_name := _good_presented()
	floor_no_name["floors"]["1"] = {}
	t.eq("запись этажа без name_key — MISSING_FIELD",
		_codes_at(Validator.validate(floor_no_name, _presentation_texts()), "floors.1.name_key"),
		[Problems.MISSING_FIELD])

	var floor_bad_name := _good_presented()
	floor_bad_name["floors"]["1"]["name_key"] = 5
	t.eq("floors[].name_key числом — WRONG_TYPE",
		_codes_at(Validator.validate(floor_bad_name, _presentation_texts()), "floors.1.name_key"),
		[Problems.WRONG_TYPE])

	# 15к. Этаж, на котором помещений нет, дефектом НЕ является: `floors` — подписи для
	# показа, и сверки номеров с `nodes[].floor` у валидатора нет (решение названо в отчёте
	# задачи 10). Ассерт держит это решение от молчаливого расширения правила.
	var extra_floor := _good_presented()
	extra_floor["floors"]["9"] = {"name_key": "floor.9"}
	var extra_floor_texts := _presentation_texts()
	extra_floor_texts["floor.9"] = "ЭТАЖ 9 // ЧЕРДАК"
	t.is_true("этаж без помещений не диагноз",
		Validator.validate(extra_floor, extra_floor_texts).is_empty())

	return t.results

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
## Нужен ради `REQUIRED_TEXT_KEYS`: фикстура текстов обязана нести системные ключи
## (см. `_texts_for`), а эталон их перечня живёт в кейсе валидатора.
const Validator := preload("res://content/validator.gd")
const Fixture := preload("res://tests/fixtures/small_mission.gd")
## Нужен ровно для одного ассерта: состав по умолчанию сверяется с умолчанием `Plan`,
## чтобы «два бойца» не оказались числом, вписанным в кейс.
const Plan := preload("res://sim/plan.gd")


## Словарь-двойник фикстуры: тот же граф, но выраженный данными. Все корневые ключи
## постановки (§1) на месте, включая пустые разделы: «ключа нет» — не миссия.
func _fixture_data() -> Dictionary:
	return {
		"id": "small",
		"title_key": "mission.small.title",
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
		"windows": Fixture.WINDOWS.duplicate(true),
		"intel": [],
		"access_points": [],
	}


## Ключи текстов, которые требует фикстура: собираются из самого словаря обходом
## полей `*_key`. Так набор не разойдётся с фикстурой, если она получит новое окно.
##
## Плюс обязательные системные ключи (`Validator.REQUIRED_TEXT_KEYS`): сверка текстов,
## включённая словарём, требует и их, а фикстура изображает ТЕКСТЫ СДАЧИ. Без них
## «словарь загружен без проблем» краснело бы на ключах, которых фикстура и не должна
## выводить из данных: у `log.silence` поля в данных нет вовсе. Независимый эталон этих
## ключей живёт в `test_content_validator.gd` (§14) и там же доказано, что список
## валидатора не короче эталона; здесь он намеренно не дублируется.
func _texts_for(value) -> Dictionary:
	var out: Dictionary = {}
	_collect_keys(value, out)
	for key in Validator.REQUIRED_TEXT_KEYS:
		out[String(key)] = "ТЕКСТ"
	return out


func _collect_keys(value, out: Dictionary) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		for key in value:
			if String(key).ends_with("_key") and typeof(value[key]) == TYPE_STRING:
				out[String(value[key])] = "ТЕКСТ"
			else:
				_collect_keys(value[key], out)
	elif typeof(value) == TYPE_ARRAY:
		for item in (value as Array):
			_collect_keys(item, out)


## Множества ключей, а не только их количество: лишний ключ при том же размере
## (подменённый id) иначе прошёл бы незамеченным.
func _keys(items) -> Array:
	var out: Array = []
	for key in items:
		out.append(String(key))
	out.sort()
	return out


## Ключи раздела-массива по полю id — так сравнение не зависит от порядка (детерминизм).
func _ids(items: Array, field: String) -> Array:
	var out: Array = []
	for item in items:
		out.append(String(item[field]))
	out.sort()
	return out


## Коды проблем по порядку. Нужен там, где ответ — не «среди проблем есть WRONG_TYPE»,
## а ровно один диагноз: каскад `MISSING_TEXT` после неверного типа виден только в полном
## списке кодов, размер списка его от «ничего лишнего» не отличает.
func _codes(problems: Array) -> Array:
	var out: Array = []
	for p in problems:
		out.append(String(p["code"]))
	return out


func run() -> Array:
	var t := Assert.new()

	# 1. Загрузка словаря: миссия собрана.
	var fixture_data := _fixture_data()
	var res := Loader.load_mission(fixture_data, _texts_for(fixture_data))
	t.is_true("словарь загружен без проблем", (res["problems"] as Array).is_empty())
	t.is_true("миссия собрана", res["mission"] != null)
	## Ранний выход ПОСЛЕ ассертов, но ДО первых обращений к модели: без него провал
	## валидатора (например, фикстура текстов разошлась с обязательными системными
	## ключами) ронял кейс рантаймом на `loaded.id`, и раннер печатал `LOAD FAIL` —
	## красное БЕЗ имени сломанного правила, потому что `run()` не возвращал и уже
	## собранных ассертов. С выходом провал называет ассерт, а не «кейс пуст».
	if res["mission"] == null:
		return t.results

	# 2. ЭКВИВАЛЕНТНОСТЬ: словарь даёт ровно ту же модель, что и код. Сравниваются и
	# размеры, и МНОЖЕСТВА ключей: «все эталонные узлы на месте» не запрещает лишний.
	var loaded = res["mission"]
	var built = Fixture.build()
	t.eq("id совпадает", loaded.id, built.id)
	t.eq("objective совпадает", loaded.objective, built.objective)
	t.eq("помещений столько же", loaded.nodes.size(), built.nodes.size())
	t.eq("рёбер столько же", loaded.edges.size(), built.edges.size())
	t.eq("патрулей столько же", loaded.patrols.size(), built.patrols.size())
	t.eq("сенсоров столько же", loaded.sensors.size(), built.sensors.size())
	t.eq("помещения: те же ключи", _keys(loaded.nodes), _keys(built.nodes))
	t.eq("рёбра: те же id", _ids(loaded.edges, "id"), _ids(built.edges, "id"))
	t.eq("патрули: те же id", _ids(loaded.patrols, "id"), _ids(built.patrols, "id"))
	t.eq("сенсоры: те же id", _ids(loaded.sensors, "id"), _ids(built.sensors, "id"))
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
	# Окна едут в payload: сравнение по значению, а не по наличию ключа.
	t.eq("окон столько же", (loaded.data["windows"] as Array).size(), (built.data["windows"] as Array).size())
	t.eq("окна совпадают по значению", loaded.data["windows"], built.data["windows"])
	# I3. Название уровня не теряется молча: оно доезжает до модели.
	t.eq("title_key доехал до модели", String(loaded.data.get("title_key", "")), "mission.small.title")
	t.is_true("миссия из словаря валидна по mission.validate()", (loaded.validate() as Array).is_empty())

	# 3. Типы: JSON приходит с float-числами, ядро ждёт int.
	var from_json := _fixture_data()
	from_json["edges"][1]["steps"] = 3.0
	from_json["nodes"]["hall"]["floor"] = 1.0
	from_json["patrols"][0]["period"] = 2.0
	var json_res := Loader.load_mission(from_json, _texts_for(from_json))
	t.is_true("float-числа приняты", (json_res["problems"] as Array).is_empty())
	t.is_true("шаги стали int", typeof(json_res["mission"].edges[1]["steps"]) == TYPE_INT)
	t.is_true("этаж стал int", typeof(json_res["mission"].nodes["hall"]["floor"]) == TYPE_INT)
	t.is_true("период стал int", typeof(json_res["mission"].patrols[0]["period"]) == TYPE_INT)

	# 4. Строка JSON грузится тем же путём. Все разделы постановки §1 на месте:
	# иначе проверялась бы не загрузка, а работа валидатора.
	#
	# Тексты передаются ЯВНО и здесь, и ниже: у `load_text`/`load_mission` умолчания нет
	# (`null` — «сверку не делаю», словарь — «сверяю»). Строка несёт `title_key`, поэтому
	# словарь передаётся настоящий, а не пустой: пустой означал бы «текстов нет» и дал бы
	# MISSING_TEXT — то есть проверялся бы не разбор JSON, а отсутствие текстов.
	# Ключ данных здесь один, а обязательные системные ключи добавляются те же, что и в
	# `_texts_for`: словарь из одной строки «текстов нет» не изображает.
	var json_text := '{"id":"j","title_key":"mission.j.title",' \
		+ '"nodes":{"a":{"floor":1,"tags":["entry"]},"b":{"floor":1,"tags":[]}},' \
		+ '"edges":[{"id":"e_ab","a":"a","b":"b","kind":"corridor","steps":1,"noise":0}],' \
		+ '"patrols":[],"sensors":[],"objective":"b",' \
		+ '"windows":[],"intel":[],"access_points":[]}'
	var json_texts := {"mission.j.title": "Операция «J»"}
	for key in Validator.REQUIRED_TEXT_KEYS:
		json_texts[String(key)] = "ТЕКСТ"
	var parsed := Loader.load_text(json_text, json_texts)
	t.is_true("строка JSON разобрана", (parsed["problems"] as Array).is_empty())
	t.eq("из строки собрана цель", parsed["mission"].objective, "b")

	# 5. Битый JSON — проблема разбора со строкой и причиной, а не падение.
	# `null` здесь осознанно: до валидатора вызов не доходит вовсе, сверять нечего.
	var broken := Loader.load_text('{\n  "id": "j",\n  "nodes": {\n}', null)
	t.is_true("битый JSON — проблема", not (broken["problems"] as Array).is_empty())
	t.is_true("битый JSON: миссии нет", broken["mission"] == null)
	# Первая проблема читается ТОЛЬКО после проверки, что она есть. Со снятым правилом
	# разбора (список пуст) `problems[0]` уронил бы кейс рантаймом (`Out of bounds get
	# index '0'`), раннер напечатал бы LOAD FAIL и не выполнил остаток файла — включая
	# сверку кодов `load_text` ниже. Красное без имени сломанного правила: тот же класс,
	# что разобран у `kind` ↔ `trigger.type` в `test_content_validator.gd`.
	var broken_problems: Array = broken["problems"]
	var broken_code := ""
	var broken_message := ""
	if not broken_problems.is_empty():
		broken_code = String((broken_problems[0] as Dictionary).get("code", ""))
		broken_message = String((broken_problems[0] as Dictionary).get("message", ""))
	t.eq("битый JSON: код", broken_code, Problems.BAD_JSON)
	t.is_true("битый JSON: причина названа", broken_message.contains("Expected '}'"))
	t.is_true("битый JSON: строка названа", broken_message.contains("строка 3"))
	# Отказ не подменяет выбор вызывающего: `texts` возвращается тем же, что передали.
	# Прежний `{}` в этом месте сообщал «текстов нет» тому, кто сказал «сверку не делаю».
	t.eq("битый JSON: texts = null остался null", broken["texts"], null)

	# 6. Отсутствующее обязательное поле — MISSING_FIELD, а не падение в add_edge.
	#
	# Тексты идут словарём, собранным ИЗ САМИХ ДАННЫХ (`_texts_for`), а не `null`: кейс
	# проверяет, что кроме объявленного дефекта миссия проходит чисто, и только так список
	# проблем равен дефекту. `null` здесь ослабил бы проверку ровно до класса, который
	# закрывает этот заход: «выглядит успешным, ничего не сверив».
	var no_route := _fixture_data()
	no_route["patrols"][0].erase("route")
	var missing_res := Loader.load_mission(no_route, _texts_for(no_route))
	t.is_true("патруль без маршрута — MISSING_FIELD",
		Problems.has(missing_res["problems"], Problems.MISSING_FIELD))
	# Та же дисциплина на отказе валидатора: словарь вернулся словарём, `null` — `null`.
	# Без этих двух ассертов подмена `_deep(texts)` на `{}` в пути отказа прошла бы молча.
	t.eq("отказ валидатора: переданный словарь вернулся тем же",
		missing_res["texts"], _texts_for(no_route))
	t.eq("отказ валидатора: texts = null остался null",
		Loader.load_mission(no_route, null)["texts"], null)

	var no_objective := _fixture_data()
	no_objective.erase("objective")
	t.is_true("миссия без цели — MISSING_FIELD",
		Problems.has(Loader.load_mission(no_objective, _texts_for(no_objective))["problems"],
			Problems.MISSING_FIELD))

	# 7. Неверный тип не доезжает до ядра.
	var bad_steps := _fixture_data()
	bad_steps["edges"][0]["steps"] = "много"
	t.is_true("шаги строкой — WRONG_TYPE",
		Problems.has(Loader.load_mission(bad_steps, _texts_for(bad_steps))["problems"],
			Problems.WRONG_TYPE))

	# 8. Некорректная миссия не отдаётся вовсе: иначе ядро получило бы полумиссию.
	t.is_true("при проблемах миссии нет",
		Loader.load_mission(bad_steps, _texts_for(bad_steps))["mission"] == null)

	# 7a. Второй аргумент НЕВЕРНОГО ТИПА. Тип у `texts` не указан намеренно (иначе `null` —
	# законное «сверку не делаю» — не прошёл бы на вход), поэтому компилятор ловит
	# ЗАБЫВАНИЕ аргумента, но не подстановку НЕ ТОГО. До правки `load_mission(data,
	# "мусор-строка")` отдавал `problems = 0` и СОБРАННУЮ миссию, а движок печатал в stderr
	# `Nonexistent function 'has' in base 'String'` и обрывал `_check_texts` на первой строке:
	# «проблем нет» стояло на рантайм-ошибке, а stderr вердиктом не является (§6.1.1).
	# Все четыре входа проверяются потому, что правдоподобны все: строку подставляет описка,
	# число и логическое — перепутанный порядок аргументов, а `[]` — единственный из них
	# с методом `has`, и потому единственный, на котором видна ВТОРАЯ половина контракта.
	# Без него сломанное «сверку ведём всегда» дописывало `WRONG_TYPE` и падало рантаймом
	# внутри `_check_texts` на первой же строке: список оставался из одной проблемы, и все
	# ассерты кейса оставались зелёными при изменившемся поведении (727/0, stderr вердиктом
	# не является, §6.1.1). У `Array` метод `has` есть, поэтому сломанный код доживает
	# до каскада `MISSING_TEXT`, и сверка кодов ниже его называет.
	for wrong_texts in ["мусор-строка", 7, false, []]:
		var wrong_type_res := Loader.load_mission(_fixture_data(), wrong_texts)
		var wrong_type_problems: Array = wrong_type_res["problems"]
		# Сверяется список кодов ЦЕЛИКОМ, а не «одна проблема и среди них WRONG_TYPE»:
		# размер не отличает верное «сверку пропустили» от сломанного «сверка идёт всегда»
		# именно на том входе, ради которого кейс расширен, — а лишний `MISSING_TEXT` здесь
		# означал бы второе следствие одной ошибки вызова.
		t.eq("texts = %s — ровно [WRONG_TYPE], без сверки" % str(wrong_texts),
			_codes(wrong_type_problems), [Problems.WRONG_TYPE])
		t.is_true("texts = %s — миссия не собрана" % str(wrong_texts), wrong_type_res["mission"] == null)

	# Тот же дефект по второму входу, и он — сам триггер описки: у
	# `load_text(json_text: String, texts)` рядом оказываются два СТРОКОВЫХ параметра,
	# поэтому «передал текст вместо словаря текстов» здесь вероятнее всего.
	var swapped_texts := Loader.load_text(json_text, "mission.j.title")
	t.is_true("load_text: строка вместо словаря текстов — миссии нет",
		swapped_texts["mission"] == null)
	# Сверяется СПИСОК КОДОВ, а не размер списка. Размер не отличает верное «сверку
	# пропустили» от сломанного «сверка идёт всегда» (лишний `MISSING_TEXT` при том же
	# первом диагнозе) и не называет сам диагноз: проба, подменяющая `WRONG_TYPE` на
	# `BAD_VALUE`, оставляла `size() == 1` и `mission == null` верными. Тот же образец,
	# что у двойника выше (`load_mission`), — иначе два входа одного контракта
	# проверялись бы с разной строгостью.
	t.eq("load_text: строка вместо словаря текстов — ровно [WRONG_TYPE], без сверки",
		_codes(swapped_texts["problems"]), [Problems.WRONG_TYPE])

	# 8a. C1, защита в глубину: раздел не того типа — загрузчик обязан ЗАВЕРШИТЬСЯ,
	# а не уйти циклом по ключам словаря. Зависание здесь проявилось бы таймаутом прогона.
	# `_texts_for` берётся от ИСПОРЧЕННОГО словаря: подменённый раздел уносит с собой свои
	# `*_key`, и словарь остаётся в согласии с данными — иначе к дефекту добавился бы
	# DANGLING_TEXT на ключи унесённых окон, которого кейс не проверяет.
	for section in ["patrols", "sensors", "windows", "intel", "access_points"]:
		var bad_section := _fixture_data()
		bad_section[section] = {"не": "массив"}
		var section_res := Loader.load_mission(bad_section, _texts_for(bad_section))
		t.is_true("раздел %s словарём: миссии нет" % section, section_res["mission"] == null)
		t.is_true("раздел %s словарём: WRONG_TYPE" % section,
			Problems.has(section_res["problems"], Problems.WRONG_TYPE))

	var text_section := _fixture_data()
	text_section["patrols"] = "guard_1"
	t.is_true("раздел строкой: миссии нет",
		Loader.load_mission(text_section, _texts_for(text_section))["mission"] == null)

	# 8в. P2. Защита в глубину загрузчика `_items` покрыта постоянной проверкой. Публичным
	# путём она недостижима (валидатор срабатывает раньше и миссии не отдаёт), но это
	# ОСОЗНАННЫЙ второй слой: убери его — и цикл пойдёт по ключам словаря и упадёт рантаймом
	# внутри `load_mission`. Приватность здесь по соглашению (подчёркивание), а не запрет:
	# публичную обёртку держали бы только ради теста — лишний API без потребителя.
	t.eq("_items: словарь вместо массива — пустой массив, а не ключи",
		Loader._items({"patrols": {"guard_1": {"route": []}}}, "patrols"), [])
	t.eq("_items: строка вместо массива — пустой массив",
		Loader._items({"patrols": "guard_1"}, "patrols"), [])
	t.eq("_items: ключа нет — пустой массив", Loader._items({}, "patrols"), [])
	t.eq("_items: массив отдаётся как есть", Loader._items({"patrols": [1, 2]}, "patrols"), [1, 2])
	## Тип проверяется ЯВНО, отдельно от равенства с `[]`. Правда о языке, проверенная пробой
	## на этой же версии движка: `{} == []` НЕ истинно. С затипизированными операндами это
	## ошибка РАЗБОРА (`Invalid operands "Dictionary" and "Array" for "==" operator`),
	## с нетипизированными — рантайм-ошибка `Invalid operands 'Dictionary' and 'Array' in
	## operator '=='`, которая обрывает текущую функцию. Неявного равенства разнотипных
	## контейнеров в GDScript нет, и прежнее обоснование («равенство с `[]` всё равно
	## выполнялось бы») было ЛОЖНЫМ: на нём охрану можно было снять, посчитав её
	## основанной на несуществующем свойстве языка.
	##
	## Что верно: по обнаружению равенство её ДУБЛИРУЕТ. `Assert._same` (`tests/assert.gd:26-32`)
	## сравнивает `typeof` первым делом и на разных типах возвращает false, не выполняя `==`
	## вовсе (проверено: `t.eq({}, [])` — false, без ошибки). Поэтому сломанная охрана
	## (`return data.get(section, [])`) краснит и ассерт выше: словарь не равен `[]`.
	## Ассерт оставлен — ради ИМЕНИ провала: `t.eq` печатает расхождение словаря с массивом,
	## а этот называет сам контракт («вернулся МАССИВ, не словарь») и не зависит от того,
	## как `_same` сравнивает типы внутри. Вырожденным он не является: на снятой охране
	## он краснеет. Из пяти входов различие это важно у СЛОВАРЯ — он единственный, что
	## итерируется по ключам и роняет `load_mission`, то есть ради него охрана и стоит.
	var from_dict = Loader._items({"patrols": {"guard_1": {}}}, "patrols")
	t.eq("_items: словарь вместо массива — вернулся МАССИВ, не словарь",
		typeof(from_dict), TYPE_ARRAY)

	# 8b. I5. `to_int` на мусоре не выдумывает значение. Возврат null — «числа здесь нет»,
	# а не 0: тихий ноль превращал строку и словарь в валидные числа.
	t.eq("to_int: целое", Loader.to_int(7), 7)
	t.eq("to_int: float с целым значением", Loader.to_int(4.0), 4)
	t.eq("to_int: float с дробным значением", Loader.to_int(1.5), null)
	t.eq("to_int: строка", Loader.to_int("много"), null)
	t.eq("to_int: словарь", Loader.to_int({"a": 1}), null)
	t.eq("to_int: пусто", Loader.to_int(null), null)

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

	# 11. `cargo_heavy` — только честный bool, и это проверяется, а не подразумевается.
	# Чтение флага через `bool(...)`: строка роняет `load_plan` рантайм-сбоем движка
	# (`bool("да")` — не существующий конструктор), число тихо коэрцируется (`bool(1)` —
	# истина). Положительный вход нужен рядом с отрицательными: без него «флаг не
	# берётся вовсе» проходило бы как «не-bool не коэрцируется».
	t.is_true("cargo_heavy: честный true берётся", Loader.load_plan({"cargo_heavy": true}).cargo_heavy)
	t.is_false("cargo_heavy: строка — не флаг", Loader.load_plan({"cargo_heavy": "да"}).cargo_heavy)
	t.is_false("cargo_heavy: число — не флаг", Loader.load_plan({"cargo_heavy": 1}).cargo_heavy)
	t.is_false("cargo_heavy: ключа нет — false", Loader.load_plan({}).cargo_heavy)

	# 12. C1. `load_plan` — тотальная функция: мусор в поле не роняет вызов, а МОЛЧА
	# игнорируется (поле остаётся значением по умолчанию `Plan`). Прежний `String(data[...])`
	# на не-строке — рантайм-сбой движка (`Nonexistent 'String' constructor`), который
	# прерывает вызов до `quit()`: прогон не завершается, а висит.
	#
	# Проверка ловит поломку именно потому, что ассерты идут ПОСЛЕ вызова: вернувшийся
	# `String(...)` уронит кейс внутри `load_plan`, и раннер напечатает LOAD FAIL с именем
	# кейса — то есть красное. Ни один вход здесь не «похож на правильный»: иначе проверка
	# ничего не говорила бы про охрану типов.
	var garbage_exits := [["a"], {"a": "b"}, 5, true, null]
	for garbage in garbage_exits:
		var plan_garbage_exit := Loader.load_plan({"exit_node": garbage, "exit_backup_node": garbage})
		t.is_true("exit_node %s — план собран, не падение" % str(garbage), plan_garbage_exit != null)
		t.eq("exit_node %s — поле не задано" % str(garbage), plan_garbage_exit.exit_node, "")
		t.eq("exit_backup_node %s — поле не задано" % str(garbage), plan_garbage_exit.exit_backup_node, "")

	for garbage in ["не массив", {"dock": true}, 7, true, null]:
		var plan_garbage_route := Loader.load_plan({"route": garbage})
		t.is_true("route %s — план собран, не падение" % str(garbage), plan_garbage_route != null)
		t.eq("route %s — маршрут пуст" % str(garbage), plan_garbage_route.route, [])

	# Тот же сбой внутри МАССИВА: охрана «route — массив» его не ловила, а `String({})`
	# роняет вызов так же, как `String("...")` на самом поле. Не-строки отсеиваются.
	var mixed_route := Loader.load_plan({"route": ["dock", {}, ["hall"], 7, true, null, "vault"]})
	t.eq("route со мусором внутри — только строки", mixed_route.route, ["dock", "vault"])

	# 13. C2. Понимание из мусора не доезжает до ядра ни нулём, ни null. `to_int` на
	# не-числе отдаёт null (I5), а `sim.gd` читает поле через `int(...)` — и `int(null)`
	# это молчаливый НОЛЬ. Понимание — механика найма (D9/D31), поэтому негодное значение
	# не переносится в запись: поле отсутствует, и умолчание плана (3) остаётся в силе.
	for garbage in [2.5, "много", {"a": 1}, true, null, []]:
		var plan_garbage_understanding := Loader.load_plan({"agents": [
			{"id": "kira", "role": "tactician", "understanding": garbage}]})
		var agent_garbage: Dictionary = plan_garbage_understanding.agents[0]
		t.is_false("understanding %s — поля нет в записи" % str(garbage),
			agent_garbage.has("understanding"))
		t.is_false("understanding %s — null в ядро не едет" % str(garbage),
			agent_garbage.get("understanding", 3) == null)

	# Положительный вход рядом с отрицательными: без него «значение не берётся вовсе»
	# проходило бы как «значение не берётся никогда».
	var plan_good_understanding := Loader.load_plan({"agents": [
		{"id": "kira", "role": "tactician", "understanding": 5},
		{"id": "echo", "role": "comms", "understanding": 2.0}]})
	t.eq("understanding: честное целое взято", plan_good_understanding.agents[0]["understanding"], 5)
	t.eq("understanding: float с целым значением взят", plan_good_understanding.agents[1]["understanding"], 2)
	t.eq("understanding: умолчание — честное целое, не null",
		Loader.load_plan({"agents": [{"id": "kira"}]}).agents[0].get("understanding", 3), 3)

	# Запись без строкового `id` смысла не имеет: ядро ведёт бойца по id (`sim.gd:95`),
	# и молчаливая подстановка `""` столкнула бы двух таких бойцов в одном словаре
	# `positions`. Такая запись отбрасывается ЦЕЛИКОМ, соседние годные остаются.
	var plan_junk_agents := Loader.load_plan({"agents": [
		{"id": "kira", "role": "tactician", "understanding": 3},
		{"role": "comms"},
		{"id": 7},
		"не словарь",
		[],
	]})
	t.eq("записи без строкового id отброшены, состав сохранён", plan_junk_agents.agents.size(), 1)
	t.eq("уцелевшая запись — та самая", plan_junk_agents.agents[0]["id"], "kira")

	# 13a. ПЯТЬ случаев состава — по отдельности и с ТОЧНЫМ результатом (размер И
	# содержимое): «не пусто» здесь ничего не доказывало бы, потому что умолчание `Plan` —
	# тоже непустой боевой состав, и подмена одного другим проходила бы незамеченной.
	#
	# 1) Явный ПУСТОЙ список: план говорит «бойцов нет». Это значение, а не мусор, и
	# уважается как есть (прежний `if not parsed_agents.is_empty()` давал здесь kira+echo).
	var plan_empty_agents := Loader.load_plan({"agents": []})
	t.eq("agents = [] — ровно пустой состав", plan_empty_agents.agents, [])

	# 2) Мусор ВМЕСТО списка: поле игнорируется, остаётся умолчание `Plan` (C1). Сверка
	# идёт по значению и с самим умолчанием, а не с числом 2 из этого кейса.
	var plan_no_agents := Loader.load_plan({"agents": "не массив"})
	t.eq("agents = строка — поле игнорируется, состав из умолчания `Plan`",
		plan_no_agents.agents, Plan.new().agents)
	t.eq("умолчание — те самые бойцы, а не пустота",
		_ids(plan_no_agents.agents, "id"), ["echo", "kira"])

	# 3) Элемент без `id` — не боец: запись отбрасывается, подстановки `""` нет. Список
	# объявлен явно, поэтому ответ — пустой состав, а НЕ умолчание: иначе явный список
	# молча подменялся бы боевым составом — та же тихая подмена, что и с `[]`.
	var plan_no_id_agent := Loader.load_plan({"agents": [{"role": "comms"}]})
	t.eq("agents = [элемент без id] — запись отброшена, состав пуст", plan_no_id_agent.agents, [])
	var plan_no_valid_agents := Loader.load_plan({"agents": ["мусор", {"role": "comms"}]})
	t.eq("agents = [мусор, элемент без id] — годных нет, состав пуст (не умолчание)",
		plan_no_valid_agents.agents, [])

	# 4) Корректный состав: сверяются САМИ записи, включая умолчание `role` и Понимание,
	# а не только размер списка. Порядок записей сохраняется как объявлен.
	var plan_full_agents := Loader.load_plan({"agents": [
		{"id": "kira", "role": "tactician", "understanding": 3},
		{"id": "echo", "role": "comms", "understanding": 5},
	]})
	t.eq("корректный состав — ровно эти две записи",
		plan_full_agents.agents, [
			{"id": "kira", "role": "tactician", "understanding": 3},
			{"id": "echo", "role": "comms", "understanding": 5},
		])

	# 5) Дубль `id`: вторая запись отбрасывается ЦЕЛИКОМ, остаётся ПЕРВАЯ (порядок записи
	# задаёт приоритет). Это ровно та опасность, которой обоснован отказ от пустого `id`:
	# `Sim` ведёт бойцов по id в одном словаре `positions`, ключ там один — вторая запись
	# столкнулась бы с первой, и боец исчез бы из отчёта и дампа без единого сообщения.
	# Отброшена именно ВТОРАЯ, а не первая: у записей разные `role` и Понимание, поэтому
	# сверяется СОДЕРЖИМОЕ уцелевшей записи, а не только размер списка.
	var plan_dup_agents := Loader.load_plan({"agents": [
		{"id": "kira", "role": "tactician", "understanding": 3},
		{"id": "kira", "role": "comms", "understanding": 5},
	]})
	t.eq("agents = [дубль id] — ровно одна запись", plan_dup_agents.agents.size(), 1)
	t.eq("agents = [дубль id] — осталась ПЕРВАЯ запись", plan_dup_agents.agents, [
		{"id": "kira", "role": "tactician", "understanding": 3}])

	# Тот же дубль, но записи разнесены: двойник стоит в ХВОСТЕ списка, а между двумя его
	# копиями — годная запись `echo`. Так видно, что отбраковка идёт по встреченному id,
	# а не «усечением хвоста от дубля»: ошибочная реализация потеряла бы `echo`, тогда как
	# верная отбрасывает именно третью запись (у неё свой `role`), сохраняя соседа на месте
	# и порядок записей.
	var plan_dup_between := Loader.load_plan({"agents": [
		{"id": "kira", "role": "tactician", "understanding": 3},
		{"id": "echo", "role": "comms", "understanding": 2},
		{"id": "kira", "role": "scout", "understanding": 7},
	]})
	t.eq("дубль id в середине — двойник отброшен, соседи сохранены", plan_dup_between.agents, [
		{"id": "kira", "role": "tactician", "understanding": 3},
		{"id": "echo", "role": "comms", "understanding": 2},
	])

	# `cargo_heavy` читается по тому же правилу «только честный тип».
	var flags := Loader.load_plan({"cargo_heavy": "да"})
	t.is_false("cargo_heavy: мусор — умолчание false", flags.cargo_heavy)

	# 14. `_string_of`: приведение, которого у движка нет. `String(...)` на не-строке —
	# рантайм-сбой, поэтому «не строка → пустая» живёт отдельной функцией и покрыто.
	t.eq("_string_of: строка", Loader._string_of("dock"), "dock")
	t.eq("_string_of: число", Loader._string_of(7), "")
	t.eq("_string_of: массив", Loader._string_of(["a"]), "")
	t.eq("_string_of: словарь", Loader._string_of({"a": 1}), "")
	t.eq("_string_of: пусто", Loader._string_of(null), "")
	t.eq("_string_of: запасное значение на мусоре", Loader._string_of(7, "tactician"), "tactician")
	t.eq("_string_of: запасное значение не подменяет строку",
		Loader._string_of("comms", "tactician"), "comms")

	# 15. `_string_list` отсеивает не-строки, а не роняет вызов: `String({})` внутри списка
	# уронил бы `load_mission`/`load_plan` так же, как `String(...)` на самом поле.
	t.eq("_string_list: только строки", Loader._string_list(["a", {}, ["b"], 3, true, null, "c"]), ["a", "c"])
	t.eq("_string_list: не массив — пусто", Loader._string_list({"a": 1}), [])
	t.eq("_string_list: ключа нет — пусто", Loader._string_list(null), [])

	return t.results

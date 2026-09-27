extends RefCounted
## ТРИ ПУТИ К ОДНОЙ МИССИИ — доказательство эквивалентности.
##
## Задача этапа: одна миссия, полученная тремя способами, обязана дать ОДНО И ТО ЖЕ
## в четырёх представлениях. Расхождение путей молча — подтверждённый дважды дефект
## (ревью первой волны: доказывалось наличие эталонных узлов, но не отсутствие лишних;
## ревью задачи 4: `data` не сравнивалась вовсе), поэтому здесь сверяются:
##
##   1. МОДЕЛЬ      — все поля `Mission`: id, objective, помещения с этажом и тегами,
##                    рёбра со всеми семью полями, патрули, сенсоры;
##   2. `data`      — разделы контента; перечень берётся из `Mission.DATA_SECTIONS`
##                    (единственный источник правды), а не переписывается здесь руками:
##                    windows, intel, routes, texts, title_key.
##                    Это ОТДЕЛЬНОЕ представление: отпечаток прогона может совпасть при
##                    расхождении `data` и наоборот, поэтому сверка нужна и по нему;
##   3. ПЛАН        — вторая половина третьей точки входа: `load_mission` (миссия) ПЛЮС
##                    `load_plan` (маршрут, выходы, груз, состав). У плана нет валидатора,
##                    поэтому его поведение (явный `[]`, дубли `id`, мусор в поле) надо
##                    проверять отдельно и на всех путях;
##   4. ОТПЕЧАТОК   — `Harness.digest` одного и того же прогона (тот же сценарий приказов,
##                    тот же seed).
##
## Пути:
##   КОД     — `tests/fixtures/small_mission.gd`: граф собран вызовами `add_*`;
##   СЛОВАРЬ — `content/loader.gd:load_mission(canonical, texts)`;
##   JSON    — `content/loader.gd:load_text(JSON.stringify(canonical), texts)`.
##
## Тексты передаются словарём на ВСЕХ трёх путях, иначе сверка ключей не идёт вовсе
## (`null` — «сверку не делаю») и доказательство про тексты пустое.
##
## Сравниваются И МНОЖЕСТВА, И РАЗМЕРЫ, и каждое поле по отдельности. «Все эталонные
## узлы на месте» недостаточно: лишний узел с ребром проходил такой набор незамеченным
## (ревью первой волны). Отсюда `_nodes_of` / `_edges_of` / `_patrols_of` / `_sensors_of` —
## пары «путь=значение» по каждому помещению и каждому ребру: лишняя запись меняет и
## размер, и содержимое пары, и провал называет поле, а не «модели не равны».

const Assert := preload("res://tests/assert.gd")
const Loader := preload("res://content/loader.gd")
const Fixture := preload("res://tests/fixtures/small_mission.gd")
const Mission := preload("res://sim/mission.gd")
const Plan := preload("res://sim/plan.gd")
const Harness := preload("res://sim/harness.gd")
## Нужен ради `REQUIRED_TEXT_KEYS`: сверка текстов-словарём требует и обязательные
## системные ключи (см. `_canonical_texts`), а их перечень живёт у валидатора.
const Validator := preload("res://content/validator.gd")

## Метка отсутствующего поля в парах «путь=значение»: пропажа поля обязана быть ВИДНА
## сравнению (и названа провалом), а не ронять кейс рантаймом.
const NO_FIELD := "ПОЛЯ НЕТ"


## Канон — единственный источник значений в этом кейсе. Граф и разделы контента повторяют
## `tests/fixtures/small_mission.gd` (числа шагов подобраны под перекос уровня: из подвала
## уйти можно, с 4-го этажа — нет).
##
## `windows` здесь РУКОПИСНЫЕ, и это не дублирование ради дублирования, а условие
## невырожденности кейса, найденное ПРОБОЙ. Пока канон брал `Fixture.WINDOWS`, содержимое
## `data` на пути «код» и на пути «словарь» приходило из ОДНОЙ константы — сравнение не
## могло покраснеть от правки фикстуры: `"neutral": delay 3 → 4` в `small_mission.gd`
## оставляло набор зелёным. Теперь записи независимы, и расхождение путей видно.
## Цена названа прямо: правка окон в фикстуре требует такой же правки здесь — и провал
## называет поле, а не «модели не равны».
##
## Разделы `intel` и `routes` НЕ пустые намеренно. Пустой раздел проходит сравнение
## «в обе стороны» независимо от того, кладёт ли загрузчик раздел в модель вообще:
## доказательство было бы вырожденным ровно на тех двух разделах, которые в прошлый раз
## не сравнивались. Точки доступа из формы убраны: терминал выражается вариантом окна.
##
## Копии (`duplicate(true)`) обязательны на каждом обращении: `load_mission` не мутирует
## вход (это проверено), но кейс не должен разделять состояние между кругами и пробами.
func _canonical() -> Dictionary:
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
			{"id": "e_office_vault", "a": "office2", "b": "vault", "kind": "door", "steps": 1, "noise": 8,
				"locked": true},
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
		"windows": [{
			"id": "w_locked_door",
			"kind": "locked_edge",
			"trigger": {"type": "locked_edge", "edge": "e_office_vault"},
			"text_key": "window.w_locked_door.text",
			"options": [
				{"id": "breach", "text_key": "window.w_locked_door.breach", "complexity": 1,
					"cost": {"noise": 8, "delay": 0},
					"effects": [{"type": "unlock", "edge": "e_office_vault"}]},
				{"id": "pick", "text_key": "window.w_locked_door.pick", "complexity": 2,
					"cost": {"noise": 1, "delay": 2},
					"effects": [{"type": "unlock", "edge": "e_office_vault"}]},
			],
			"silence": {
				"text_key": "window.w_locked_door.silence",
				"good": [{"type": "unlock", "edge": "e_office_vault"}],
				"neutral": [{"type": "delay", "value": 3}, {"type": "unlock", "edge": "e_office_vault"}],
				"bad": [{"type": "delay", "value": 3}, {"type": "noise", "value": 5},
					{"type": "unlock", "edge": "e_office_vault"}],
				"safe": [{"type": "delay", "value": 3}, {"type": "unlock", "edge": "e_office_vault"}],
			},
		}],
		"intel": [{
			"channel": "hack",
			"observed_at": 0,
			"entries": [{"kind": "sensor", "nodes": ["hall"], "age_hours": 8, "false": false}],
		}],
		"routes": [{"id": "main", "entry": "dock", "exit": "dock",
			"route": ["dock", "hall", "office2", "vault", "office2", "hall", "archive0", "hall", "dock"]}],
	}


## Тексты — ВСЕ ключи канона и только они. Собираются обходом данных по полям `*_key`
## (`title_key` тоже оканчивается на `_key`, поэтому попадает сюда сам): набор не
## разойдётся с каноном, если в нём появится новое окно или действие.
##
## Почему не руками: рукописный список ключей пришлось бы править при каждой правке
## канона, и провал случался бы на `MISSING_TEXT` — то есть на текстах, а не на том,
## что забыли. Здесь же проверяется ровно то, что заявлено: тексты есть под все ключи,
## и лишних ключей нет (висячий ключ даёт `DANGLING_TEXT` и красный прогон).
##
## Плюс обязательные системные ключи (`Validator.REQUIRED_TEXT_KEYS`): канон описывает
## миссию, а сверка текстов-словарём требует и тексты СИСТЕМЫ (04-texts.md §4), которых
## в данных канона нет вовсе. Независимый эталон этих ключей — в `test_content_validator.gd`
## (§14), здесь он намеренно не дублируется: тут проверяется, что все три пути к модели
## проходят с ПОЛНЫМ набором текстов.
func _canonical_texts(data) -> Dictionary:
	var out: Dictionary = {}
	_collect_keys(data, out)
	for key in Validator.REQUIRED_TEXT_KEYS:
		out[String(key)] = "ТЕКСТ"
	return out


func _collect_keys(value, out: Dictionary) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		for key in value:
			if _key_form(key).ends_with("_key") and typeof(value[key]) == TYPE_STRING:
				out[String(value[key])] = "ТЕКСТ"
			else:
				_collect_keys(value[key], out)
	elif typeof(value) == TYPE_ARRAY:
		for item in (value as Array):
			_collect_keys(item, out)


# --- пары «путь=значение»: сравнение со всеми полями и без зависимости от порядка ------

## Охраняемое чтение по ключу или по индексу: если контейнер не того типа, ключа нет или
## индекс за границей — возвращается `fallback`, а не аборт `run()`.
##
## Зачем (N2, чек-лист §4 «индексация без охраны размера»). Прямое `by_json.edges[3]`,
## `nodes["it4"]`, `patrols[0]`, `edge(...)["locked"]` на сломанном коде роняет вызов
## рантаймом: кейс предъявляет НОЛЬ ассертов, и НИ ОДНА проверка файла ниже не
## выполняется (пробы до правки: `Invalid access of index '3'` на `:460`, `… 'it4'` на
## `:462`, `… '0'` на `:463`, `… 'locked'` на `:581`; `probe: tests: 0`, код 2).
## На полном наборе та же природа выглядит как `LOAD FAIL  res://tests/cases/
## test_three_paths.gd: кейс не предъявил ни одного ассерта` при 621 проверке из 900.
## С охраной тот же сломанный код даёт провал ПО ИМЕНИ, и файл доходит до конца.
func _at(container, key, fallback = null):
	if typeof(container) == TYPE_DICTIONARY:
		return (container as Dictionary).get(key, fallback)
	if typeof(container) == TYPE_ARRAY and typeof(key) == TYPE_INT:
		var items := container as Array
		if key >= 0 and key < items.size():
			return items[key]
	return fallback


## Есть ли поле у словаря. Отдельно от `_at`: само значение поля может быть `null`, и
## «поля нет» не должно выглядеть как «поле равно null».
func _has(container, key) -> bool:
	return typeof(container) == TYPE_DICTIONARY and (container as Dictionary).has(key)


func _nodes_of(m) -> Array:
	var ids: Array = []
	for node_id in m.nodes:
		ids.append(String(node_id))
	ids.sort()
	var out: Array = []
	for node_id in ids:
		var node = m.nodes[node_id]
		out.append("%s|floor=%s|tags=%s" % [node_id, str(_at(node, "floor", NO_FIELD)),
			str(_at(node, "tags", NO_FIELD))])
	return out


func _edges_of(m) -> Array:
	var out: Array = []
	for i in m.edges.size():
		var e = m.edges[i]
		out.append("%d|id=%s|a=%s|b=%s|kind=%s|steps=%s|noise=%s|locked=%s" % [i,
			str(_at(e, "id", NO_FIELD)), str(_at(e, "a", NO_FIELD)), str(_at(e, "b", NO_FIELD)),
			str(_at(e, "kind", NO_FIELD)), str(_at(e, "steps", NO_FIELD)),
			str(_at(e, "noise", NO_FIELD)), str(_at(e, "locked", NO_FIELD))])
	return out


func _patrols_of(m) -> Array:
	var out: Array = []
	for i in m.patrols.size():
		var p = m.patrols[i]
		out.append("%d|id=%s|route=%s|period=%s" % [i, str(_at(p, "id", NO_FIELD)),
			str(_at(p, "route", NO_FIELD)), str(_at(p, "period", NO_FIELD))])
	return out


func _sensors_of(m) -> Array:
	var out: Array = []
	for i in m.sensors.size():
		var s = m.sensors[i]
		out.append("%d|id=%s|nodes=%s" % [i, str(_at(s, "id", NO_FIELD)),
			str(_at(s, "nodes", NO_FIELD))])
	return out


func _plan_of(p) -> Array:
	var out: Array = ["route=%s" % str(p.route), "exit_node=%s" % str(p.exit_node),
		"exit_backup_node=%s" % str(p.exit_backup_node), "cargo_heavy=%s" % str(p.cargo_heavy)]
	for i in p.agents.size():
		var a: Dictionary = p.agents[i]
		out.append("agent[%d]|id=%s|role=%s|understanding=%s" % [i, str(a.get("id", "")),
			str(a.get("role", "")), str(a.get("understanding", "—"))])
	return out


## Сравнение моделей по частям с ИМЕНОВАННЫМИ ассертами: провал называет представление
## (помещения, рёбра, …), а не «модели не равны». Обе стороны — `Array` пар строк, поэтому
## `Assert.eq` сравнивает их строго, без неявного равенства контейнеров.
func _compare_models(t, what: String, a, b) -> void:
	t.eq("%s: помещений столько же" % what, a.nodes.size(), b.nodes.size())
	t.eq("%s: рёбер столько же" % what, a.edges.size(), b.edges.size())
	t.eq("%s: патрулей столько же" % what, a.patrols.size(), b.patrols.size())
	t.eq("%s: сенсоров столько же" % what, a.sensors.size(), b.sensors.size())
	t.eq("%s: id миссии" % what, a.id, b.id)
	t.eq("%s: цель" % what, a.objective, b.objective)
	t.eq("%s: помещения целиком" % what, _nodes_of(a), _nodes_of(b))
	t.eq("%s: рёбра целиком" % what, _edges_of(a), _edges_of(b))
	t.eq("%s: патрули целиком" % what, _patrols_of(a), _patrols_of(b))
	t.eq("%s: сенсоры целиком" % what, _sensors_of(a), _sensors_of(b))


## Канонический вид раздела контента — для сравнения `data` JSON-пути с остальными.
##
## Зачем он нужен. `data` — АВТОРСКАЯ форма и кладётся в модель КАК ЕСТЬ (`_deep` копия,
## без приведения типов): JSON приносит числа float (`1.0`), а словарь и фикстура — int
## (`1`). Для словарей Godot `1 == 1.0` ЛОЖНО, поэтому строгое сравнение ругалось бы на
## форму записи, а не на расхождение путей. Тип чисел МОДЕЛИ (`steps`, `floor`, `period`)
## проверяется отдельно и строго (`typeof(...) == TYPE_INT`) — это и есть обещание
## контракта; в `data` числа остаются такими, какими их дал формат.
##
## Что при этом НЕ теряется: сравнение идёт по ЗНАЧЕНИЮ. Целое и равное ему дробное дают
## одну запись (`1.0` → `число:1`), а РАЗНЫЕ значения — разные (`1` против `2`; `1.5`
## против `2`). Дробное показано как есть, а не срезано приведением к int. Сведение
## целого и равного ему дробного — ЕДИНСТВЕННОЕ послабление канонического вида, и оно
## названо здесь прямо: это форма записи формата, а не значение данных.
func _canonical_form(value) -> Array:
	if typeof(value) == TYPE_DICTIONARY:
		## Пары «вид ключа → сам ключ»: сортируем по виду (он всегда строка), а значение
		## берём ИСХОДНЫМ ключом. Прежний `String(key)` на нестроковом ключе падал
		## рантаймом (`Nonexistent 'String' constructor`) и функция возвращала `[]` —
		## то есть РАЗНЫЕ данные сравнивались как равные (проба ревью M2, чек-лист §2).
		var pairs: Array = []
		for key in value:
			pairs.append([_key_form(key), key])
		pairs.sort_custom(func(x, y): return x[0] < y[0])
		var out: Array = []
		for pair in pairs:
			out.append("%s=%s" % [pair[0], _canonical_text(_canonical_form(value[pair[1]]))])
		return out
	if typeof(value) == TYPE_ARRAY:
		var items: Array = []
		for item in (value as Array):
			items.append(_canonical_text(_canonical_form(item)))
		return ["[%s]" % ",".join(items)]
	return _leaf_form(value)


## Лист значения. Ветвь числа отдельная: целое и равное ему дробное — одна запись.
func _leaf_form(value) -> Array:
	if typeof(value) == TYPE_FLOAT:
		if is_equal_approx(value, floor(value)):
			return ["число:%d" % int(value)]
		return ["число:%s" % str(value)]
	if typeof(value) == TYPE_INT:
		return ["число:%d" % value]
	if typeof(value) == TYPE_STRING:
		return ["строка:%s" % value]
	if typeof(value) == TYPE_BOOL:
		return ["логическое:%s" % str(value)]
	return ["ничто:%s" % str(value)]


## Ключ словаря в каноническом виде. Нестроковый ключ НЕ приводится конструктором
## `String(...)`: на не-строке он падает рантаймом, а возвращённый из-за этого `[]` делал
## РАЗНЫЕ данные равными (M2). Тип входит в вид, поэтому `1` и `"1"` — разные ключи, как
## и в самом словаре.
func _key_form(key) -> String:
	if typeof(key) == TYPE_STRING:
		return String(key)
	return "%d:%s" % [typeof(key), str(key)]


## Строка канонического вида — форма для ЧТЕНИЯ провала: сравниваются те же данные,
## но одним элементом списка, иначе вложенные массивы в отчёте нечитаемы.
func _canonical_text(form: Array) -> String:
	return "[%s]" % ", ".join(form)


## Сравнение разделов контента — по каждому разделу отдельно, с размером и значением.
## Перечень разделов берётся из `Mission.DATA_SECTIONS`, а НЕ переписывается здесь руками:
## рукописный список был подтверждённой дырой (проба ревью P12) — новый раздел схемы,
## пронесённый загрузчиком, в сверку не попадал, хотя комментарий обещал обратное. Теперь
## расширение схемы автоматически попадает в цикл ниже, и расхождение путей видно.
##
## `json_side` — из-за формы записи чисел в `data` (см. `_canonical_form`): у JSON-пути
## значения сравниваются в каноническом виде, у словаря и фикстуры — строго, как есть.
func _compare_payload(t, what: String, a, b, json_side := false) -> void:
	t.eq("%s: разделов столько же" % what, a.size(), b.size())
	var keys_a: Array = []
	for key in a:
		keys_a.append(_key_form(key))
	keys_a.sort()
	var keys_b: Array = []
	for key in b:
		keys_b.append(_key_form(key))
	keys_b.sort()
	t.eq("%s: множества разделов" % what, keys_a, keys_b)
	for section in Mission.DATA_SECTIONS:
		t.is_true("%s: раздел %s есть" % [what, section], a.has(section) and b.has(section))
		if not (a.has(section) and b.has(section)):
			continue
		if typeof(a[section]) == TYPE_ARRAY:
			t.eq("%s: %s — размер" % [what, section], (a[section] as Array).size(),
				(b[section] as Array).size())
		if json_side:
			t.eq("%s: %s — значение" % [what, section], _canonical_form(a[section]),
				_canonical_form(b[section]))
		else:
			t.eq("%s: %s — значение" % [what, section], a[section], b[section])


func run() -> Array:
	var t := Assert.new()

	# --- 0. Канон и его тексты. Всё остальное в кейсе считается от них. ---------------
	var texts := _canonical_texts(_canonical())
	t.is_true("канон: тексты непусты (иначе сверка ключей была бы пустой)", texts.size() > 0)
	# Ключи `*_key` канона лежат и вне окон, поэтому «тексты непусты» — не только про окна.
	# Точка доступа из формы убрана: её тексты (`ap.*`) ушли вместе с разделом, а действие
	# терминала выражается вариантом окна — то есть тем же полем `options[].text_key`,
	# которое проверяет второй ассерт ниже (по ключу ОКНА, а не терминала).
	t.is_true("канон: title_key попал в тексты", texts.has("mission.small.title"))
	t.is_true("канон: текст варианта окна попал в тексты", texts.has("window.w_locked_door.breach"))
	t.is_true("канон: текст базового молчания попал в тексты", texts.has("window.w_locked_door.silence"))

	# --- 0б. Канонический вид не вырожден на нестроковом ключе ------------------------
	# Нестроковый ключ словаря — тот же класс, что «ассерт, который не может покраснеть»:
	# прежний `String(key)` падал рантаймом и функция возвращала `[]`, поэтому ДВА РАЗНЫХ
	# словаря сравнивались как равные (проба ревью M2). Сейчас ключ называется вместе с
	# типом, и проверки ниже это закрепляют: они краснеют на старом поведении.
	t.eq("канонический вид: нестроковый ключ не потерян", _canonical_form({1: "a"}).size(), 1)
	t.is_true("канонический вид: разные нестроковые ключи не равны",
		_canonical_form({1: "a"}) != _canonical_form({2: "a"}))
	t.is_true("канонический вид: нестроковый ключ не сливается со строковым «1»",
		_canonical_form({1: "a"}) != _canonical_form({"1": "a"}))

	# --- 1. ПУТЬ «СЛОВАРЬ» -----------------------------------------------------------
	var dict_res := Loader.load_mission(_canonical(), texts)
	t.is_true("словарь: проблем нет", (dict_res["problems"] as Array).is_empty())
	t.is_true("словарь: миссия собрана", dict_res["mission"] != null)
	if dict_res["mission"] == null:
		return t.results
	var by_dict = dict_res["mission"]

	# --- 2. ПУТЬ «JSON»: текст собран ИЗ СЛОВАРЯ (не из руки) -------------------------
	# Сборка из словаря, а не рукописная строка: так проверяется и потеря полей при
	# сериализации, и float/int после разбора. Рукописный JSON проверял бы только
	# разбор, не сверяя два пути между собой.
	#
	# Текст собирается ОДИН раз и тем же значением идёт в `load_text`: вторая сборка
	# `JSON.stringify` на том же словаре была бы вторым вызовом, за который никто не
	# отвечает, а `JSON.parse_string` для проверки разбора — третьим.
	var json_text := JSON.stringify(_canonical())
	var json_parsed = JSON.parse_string(json_text)
	t.is_true("JSON: текст канона разобран", json_parsed != null)
	var json_res := Loader.load_text(json_text, texts)
	t.is_true("JSON: проблем нет", (json_res["problems"] as Array).is_empty())
	t.is_true("JSON: миссия собрана", json_res["mission"] != null)
	if json_res["mission"] == null:
		return t.results
	var by_json = json_res["mission"]

	# --- 3. ПУТЬ «КОД»: граф — фикстура, разделы — та же полезная нагрузка ------------
	# Фикстура собирает граф вызовами `add_*`, а разделы контента кладёт `set_data` —
	# тем же вызовом, что и `load_mission`. Это и делает третий путь сравним: у фикстуры
	# нет и не должно быть второго способа задать `data`.
	var by_code = Fixture.build()
	# ЧТО фикстура кладёт в `data` САМА — сверяется с каноном ДО `set_data`. Это
	# единственное место, где рукописный канон и рукописная фикстура сходятся напрямую,
	# и без него расхождение между ними не падало бы тестом: проба «поменять цену
	# молчания в `Fixture.WINDOWS`» оставляла набор зелёным, потому что дальше `set_data`
	# перезаписывал разделы каноном и обе стороны сравнения становились одной записью.
	# Проверка намеренно стоит до перезаписи: она стережёт сам рукописный двойник.
	t.eq("код: фикстура сама кладёт окна канона", by_code.data["windows"], _canonical()["windows"])
	by_code.set_data({
		"windows": _canonical()["windows"],
		"intel": _canonical()["intel"],
		"routes": _canonical()["routes"],
		"texts": texts.duplicate(true),
		"title_key": String(_canonical()["title_key"]),
	})
	t.is_true("код: миссия фикстуры валидна", (by_code.validate() as Array).is_empty())

	# --- 4. МОДЕЛЬ: три пути по кругу, со всеми полями --------------------------------
	_compare_models(t, "код ↔ словарь", by_code, by_dict)
	_compare_models(t, "код ↔ JSON", by_code, by_json)
	_compare_models(t, "словарь ↔ JSON", by_dict, by_json)

	# --- 5. `data` — ОТДЕЛЬНОЕ представление, сверяется по значению -------------------
	# У JSON-пути числа в `data` — float по природе формата, поэтому его сторона
	# сравнивается в каноническом виде (см. `_canonical_form`); у словаря и фикстуры
	# сравнение строгое. Типы чисел МОДЕЛИ проверяются отдельно (§6) и строго.
	_compare_payload(t, "код ↔ словарь", by_code.data, by_dict.data)
	_compare_payload(t, "код ↔ JSON", by_code.data, by_json.data, true)
	_compare_payload(t, "словарь ↔ JSON", by_dict.data, by_json.data, true)

	# Положительные контроли: сравнение разделов не вырождено и что-то значит.
	#
	# Почему они нужны отдельно от `_compare_payload`. Проба «поменять цену молчания в
	# фикстуре» (`small_mission.gd`: `neutral delay 3 → 4`) оставляла набор зелёным ДВАЖДЫ:
	# сначала потому, что канон брал `Fixture.WINDOWS` (обе стороны сравнения — одна
	# константа), потом потому, что обе стороны `_compare_payload` выводятся из канона.
	# Сравнение двух производных одного источника уличить сам источник не может, поэтому
	# раздел пути «словарь» сверяется с каноном НАПРЯМУЮ и строго (у JSON-пути строгого
	# равенства быть не может — см. ниже).
	#
	# Чего здесь СОЗНАТЕЛЬНО нет (M4): контроля «раздел (код) равен канону». Он был и был
	# тавтологией — `by_code.set_data` кладёт раздел ИЗ ТОГО ЖЕ канона несколькими строками
	# выше, поэтому такой ассерт проверял присваивание самому себе, а не путь «код».
	# Проба «`set_data` — пустышка» показывает, что снятие этих трёх ассертов ничего не
	# теряет: сломанный `set_data` роняет и путь «словарь» (загрузчик пользуется тем же
	# вызовом), и провал называется именами контролей ниже — «разведка (словарь) равна
	# канону», «тексты доехали разделом», «фикстура сама кладёт окна канона». Единственный
	# независимый контроль пути «код» — «код: фикстура сама кладёт окна канона»: там стороны
	# из РАЗНЫХ источников (рукописная фикстура против канона).
	#
	# Терять при этом нечего и в другую сторону: пропажу раздела у ПУТИ «СЛОВАРЬ» ловит
	# `_compare_payload` («intel — размер»/«— значение», проба «загрузчик отдаёт `[]`»),
	# а не снятые ассерты: у пути «код» раздел приходит из канона, у словаря — из загрузчика.
	t.is_true("data: разделы непусты — окна, разведка, тексты",
		not by_dict.data["windows"].is_empty() and not by_dict.data["intel"].is_empty()
		and not by_dict.data["texts"].is_empty())
	t.eq("data: окон ровно столько, сколько в каноне",
		(by_dict.data["windows"] as Array).size(), (_canonical()["windows"] as Array).size())
	t.eq("data: окна (словарь) равны канону", by_dict.data["windows"], _canonical()["windows"])
	t.eq("data: разведка (словарь) равна канону", by_dict.data["intel"], _canonical()["intel"])
	## Маршруты ЕДУТ в `payload`, и это проверяется, а не подразумевается: раздел объявлен
	## в `Mission.DATA_ARRAY_SECTIONS` (перенос раздела в модель — правка ядра, сделанная
	## отдельной задачей), поэтому все три пути кладут его в `data`. Ассерт называет оба
	## конца: раздел ЕСТЬ у каждого пути (иначе «доехал» держалось бы на одном пути) и он
	## НЕПУСТ — иначе `has("routes")` был бы верен и на пустом умолчании модели. Размер и
	## значение сверяет `_compare_payload` выше — по `Mission.DATA_SECTIONS`, а не по
	## списку, переписанному здесь руками.
	t.is_true("data: маршруты доехали в payload из всех трёх путей",
		by_dict.data.has("routes") and by_code.data.has("routes") and by_json.data.has("routes"))
	## Значение читается через `get(..., NO_FIELD)`: снятый раздел обязан назваться ЭТИМ
	## ассертом, а не уронить `run()` обращением к несуществующему ключу (тогда раннер
	## печатает `LOAD FAIL`, и провал перестаёт называть сломанное правило).
	var dict_routes = by_dict.data.get("routes", NO_FIELD)
	t.is_true("data: маршруты в payload непусты (иначе ассерт выше вырожден)",
		typeof(dict_routes) == TYPE_ARRAY and not (dict_routes as Array).is_empty())
	# У JSON-пути строгого равенства канону НЕТ и быть не может: числа в `data` приходят
	# float (`3.0`), и `Dictionary ==` на `3.0` против `3` — ложь. Его сторона сверяется
	# с каноном через канонический вид в `_compare_payload` выше; здесь сравнение формы
	# записи выдавало бы три провала о float, а не о расхождении путей.
	t.eq("data: title_key доехал", String(by_dict.data["title_key"]), "mission.small.title")
	t.eq("data: тексты доехали разделом", by_dict.data["texts"], texts)

	# --- 6. Сериализация не теряет данные и не портит типы ----------------------------
	# JSON отдаёт числа float, а ядро обязано получить ИМЕННО `TYPE_INT`: `int` и `float`
	# равны по значению (`1 == 1.0`), поэтому сравнение `data` этого не ловит.
	#
	# Честная граница блока (пробы ревью P5/P5b, находка M1): он НЕ является защитой от
	# снятого `to_int` в загрузчике. Приведение float→int делает типизированный параметр
	# `Mission.add_*`, поэтому ОДИНОЧНЫЕ мутации блок не краснят: и снятый `to_int` при
	# целом типе параметра, и снятый тип `int` при живом `to_int` оставляют кейс зелёным
	# (обе пробы: `probe: tests: 168, failed: 0`, код 0). Фальсификатор, который блок
	# действительно краснит, — СОСТАВНОЙ: одновременное снятие `to_int` в загрузчике И
	# типа `int` у параметра `add_*` — только тогда значение доезжает до модели как float,
	# и блок краснеет 18 НАЗВАННЫМИ ассертами («JSON: шаги ребра остались целым», «JSON: шум
	# ребра остался целым», «JSON: ребро N — steps/noise целое» по каждому ребру,
	# «код ↔ JSON: рёбра целиком», «словарь ↔ JSON: рёбра целиком»).
	#
	# Чтобы блок не был вырожденным, ниже проверена его ПОСЫЛКА: вход JSON-пути приносит
	# именно `TYPE_FLOAT`. Без неё «после круга получилось TYPE_INT» было бы истинно по
	# построению (если бы разбор отдавал int, проверка ничего не проверяла бы).
	#
	# Чтение по индексу и по ключу идёт через `_at`/`_has` (N2): прямое `edges[3]`,
	# `["it4"]`, `[0]` на сломанном входе роняло `run()` рантаймом, кейс предъявлял ноль
	# ассертов, набор писал `LOAD FAIL` (проба до правки: 621 из 900), и ни одна проверка
	# ниже не выполнялась. Теперь пропажа места НАЗВАНА провалом, а не абортом.
	var json_edge3 = _at(_at(json_parsed, "edges", []), 3, {})
	var json_node_it4 = _at(_at(json_parsed, "nodes", {}), "it4", {})
	var json_patrol0 = _at(_at(json_parsed, "patrols", []), 0, {})
	t.is_true("JSON (вход): ребро 3, помещение it4 и патруль 0 на месте",
		_has(json_edge3, "steps") and _has(json_edge3, "noise")
		and _has(json_node_it4, "floor") and _has(json_patrol0, "period"))
	t.is_true("JSON: вход приносит steps как float (посылка блока о TYPE_INT)",
		typeof(_at(json_edge3, "steps")) == TYPE_FLOAT)
	t.is_true("JSON: вход приносит noise как float (посылка блока о TYPE_INT)",
		typeof(_at(json_edge3, "noise")) == TYPE_FLOAT)
	t.is_true("JSON: вход приносит floor как float (посылка блока о TYPE_INT)",
		typeof(_at(json_node_it4, "floor")) == TYPE_FLOAT)
	t.is_true("JSON: вход приносит period как float (посылка блока о TYPE_INT)",
		typeof(_at(json_patrol0, "period")) == TYPE_FLOAT)
	var model_edges: Array = by_json.edges
	var model_nodes: Dictionary = by_json.nodes
	var model_patrols: Array = by_json.patrols
	var model_edge3 = _at(model_edges, 3, {})
	var model_node_it4 = _at(model_nodes, "it4", {})
	var model_patrol0 = _at(model_patrols, 0, {})
	t.is_true("JSON: ребро 3, помещение it4 и патруль 0 на месте в модели",
		_has(model_edge3, "steps") and _has(model_edge3, "noise")
		and _has(model_node_it4, "floor") and _has(model_patrol0, "period"))
	t.is_true("JSON: шаги ребра остались целым", typeof(_at(model_edge3, "steps")) == TYPE_INT)
	t.is_true("JSON: шум ребра остался целым", typeof(_at(model_edge3, "noise")) == TYPE_INT)
	t.is_true("JSON: этаж помещения остался целым", typeof(_at(model_node_it4, "floor")) == TYPE_INT)
	t.is_true("JSON: период патруля остался целым", typeof(_at(model_patrol0, "period")) == TYPE_INT)
	for i in model_edges.size():
		t.is_true("JSON: ребро %d — steps целое" % i,
			typeof(_at(model_edges[i], "steps")) == TYPE_INT)
		t.is_true("JSON: ребро %d — noise целое" % i,
			typeof(_at(model_edges[i], "noise")) == TYPE_INT)
	for node_id in model_nodes:
		t.is_true("JSON: помещение %s — floor целое" % node_id,
			typeof(_at(model_nodes[node_id], "floor")) == TYPE_INT)

	# --- 7. ПЛАН: вторая половина третьей точки входа ---------------------------------
	# Канонический план: маршрут через запертую дверь (иначе окно не откроется ни разу),
	# явный запасной выход и груз — каждое из этих полей обязано доехать до `Plan`.
	var plan_data := {
		"route": ["dock", "hall", "office2", "vault"],
		"exit_node": "dock",
		"exit_backup_node": "archive0",
		"cargo_heavy": true,
		"agents": [
			{"id": "kira", "role": "tactician", "understanding": 3},
			{"id": "echo", "role": "comms", "understanding": 2},
		],
	}
	var plan_dict = Loader.load_plan(plan_data)
	# Путь «код» для плана — `Plan`, собранный полями вручную: план не «загружается» из
	# файла, его строит фаза планирования. Сверка ловит потерю поля на пути загрузки
	# (забытый `cargo_heavy` или срезанный состав) и заодно держит план непустым: на двух
	# пустых планах сравнение «совпало» ничего не доказывало бы.
	var plan_code := Plan.new()
	plan_code.route = ["dock", "hall", "office2", "vault"]
	plan_code.exit_node = "dock"
	plan_code.exit_backup_node = "archive0"
	plan_code.cargo_heavy = true
	plan_code.agents = plan_data["agents"].duplicate(true)
	t.eq("план: путь «код» совпадает со словарём", _plan_of(plan_code), _plan_of(plan_dict))
	t.is_true("план: маршрут непуст", not plan_dict.route.is_empty())

	# Три правила плана, одинаковые на всех путях: явный `[]` — значение («бойцов нет»),
	# мусор в поле — поле игнорируется (остаётся умолчание `Plan`), дубль `id` —
	# остаётся ПЕРВАЯ запись. Плана эти правила касаются отдельно от миссии: у плана нет
	# валидатора, и «мусор в поле» здесь молчаливое решение, а не отказ.
	var plan_cases := [
		["явный пустой состав", {"agents": []}],
		["дубль id", {"agents": [
			{"id": "kira", "role": "tactician", "understanding": 3},
			{"id": "kira", "role": "comms", "understanding": 5},
		]}],
		["мусор вместо состава", {"agents": "не массив"}],
		["мусор в маршруте", {"route": ["dock", {"hall": true}, 7, "vault"]}],
		["мусор в выходах", {"exit_node": ["dock"], "exit_backup_node": {"a": 1}}],
		["мусор в грузе", {"cargo_heavy": "да"}],
	]
	for case in plan_cases:
		var label: String = case[0]
		var payload: Dictionary = case[1]
		var from_dict = Loader.load_plan(payload)
		var from_json = Loader.load_plan(JSON.parse_string(JSON.stringify(payload)))
		# Сверяются ВСЕ поля плана, включая размер и содержимое состава: JSON-путь обязан
		# повторить решения словаря, а не только «собраться без падения».
		t.eq("план (%s): JSON = словарь" % label, _plan_of(from_json), _plan_of(from_dict))
	# Три правила по отдельности: сравнение двух путей выше не заметило бы, что оба пути
	# одинаково НЕВЕРНЫ (например, оба подставляют боевой состав вместо явного `[]`).
	t.eq("план: явный [] — ровно пустой состав (не умолчание)",
		Loader.load_plan({"agents": []}).agents, [])
	t.eq("план: дубль id — осталась первая запись",
		Loader.load_plan({"agents": [
			{"id": "kira", "role": "tactician", "understanding": 3},
			{"id": "kira", "role": "comms", "understanding": 5},
		]}).agents, [{"id": "kira", "role": "tactician", "understanding": 3}])
	t.eq("план: мусор вместо состава — умолчание `Plan` (не пустота)",
		_ids(Loader.load_plan({"agents": "не массив"}).agents, "id"), ["echo", "kira"])
	t.eq("план: по умолчанию состав — умолчание `Plan`",
		_ids(Loader.load_plan({}).agents, "id"), _ids(Plan.new().agents, "id"))

	# --- 8. ОТПЕЧАТОК ПРОГОНА: тот же вход — тот же исход -----------------------------
	# Главное утверждение задачи: один и тот же сценарий приказов и один и тот же seed
	# дают ОДИН отпечаток на всех трёх путях.
	#
	# Сценарии выбраны так, чтобы бросок кубика был ВИДЕН, — это исправление после пробы
	# ревью. Прежняя редакция сверяла три пути на `["breach", "silence"]`, а этот прогон
	# ПОБИТОВО равен `["breach"]`: окно у запертой двери одно, второй элемент сценария не
	# потребляется вовсе (`order_silenced = 0`), и seed 4/5/7 дают один и тот же digest.
	# Главный инвариант доказывался там, где `rng` не вызывается ни разу.
	#
	# Что выбрано теперь:
	#   "breach"  — приказ: дверь открывается ценой варианта, кубик не бросается;
	#   "silence" — молчание у запертой двери: `_resolve_silence` бросает `rng.randf()`,
	#               и исход зависит от seed (17 шагов/шум 41 против 19/36).
	# Невырожденность набора закреплена проверками 8б/8в: сценарии обязаны быть РАЗНЫМИ
	# прогонами, а seed — РАЗНЫМИ исходами. Без них набор через полгода снова выродится
	# в одно испытание, и никто этого не заметит.
	var breach_script := ["breach"]
	var silence_script := ["silence"]
	var scenarios := [breach_script, silence_script]
	var seeds := [4, 5]
	## Отчёты по ключу «сценарий|seed» — из них берутся проверки невырожденности.
	var runs: Dictionary = {}
	for script in scenarios:
		for seed in seeds:
			# Один и тот же вызов трёх путей — ради ОДНОГО отпечатка. `by_dict`/`by_json`
			# переиспользуются на всех кругах: миссия иммутабельна (открытые двери живут
			# в `Sim`, это закреплено `test_harness.gd`). Здесь это ещё и условие честности:
			# пересборка модели на каждом круге маскировала бы расхождение путей.
			var by_code_report: Dictionary = Harness.run_scenario(
				by_code, Loader.load_plan(plan_data), script, {"seed": seed})
			var by_dict_report: Dictionary = Harness.run_scenario(
				by_dict, Loader.load_plan(plan_data), script, {"seed": seed})
			var by_json_report: Dictionary = Harness.run_scenario(
				by_json, Loader.load_plan(plan_data), script, {"seed": seed})
			var label := "%s (seed %d)" % [str(script), seed]
			t.eq("отпечаток %s: код и словарь" % label,
				by_code_report["digest"], by_dict_report["digest"])
			t.eq("отпечаток %s: словарь и JSON" % label,
				by_dict_report["digest"], by_json_report["digest"])
			# Сценарий действительно выполнился до конца: «три пути совпали» на отчёте
			# `invalid_mission` доказывало бы только то, что все три входа одинаково негодны.
			t.eq("прогон %s: миссия принята" % label,
				String(by_dict_report["outcome"]) != "invalid_mission", true)
			# Запертая дверь — то место, ради которого окно и существует: без неё в прогоне
			# не выполнялась бы часть данных контента.
			#
			# Чтение поля — под охраной (N2): у фикстуры без ребра `edge(...)` возвращает
			# `{}`, и прямое `["locked"]` роняло `run()` рантаймом — кейс предъявлял НОЛЬ
			# ассертов, набор писал `LOAD FAIL`. Пропажа поля теперь НАЗВАНА провалом.
			var door: Dictionary = by_code.edge("e_office_vault")
			t.is_true("прогон %s: у ребра запертой двери есть поле locked" % label,
				_has(door, "locked"))
			t.is_true("прогон %s: дверь была заперта на старте" % label,
				bool(_at(door, "locked", false)))
			# Повтор того же входа — тот же отпечаток (детерминизм), и это НЕ тот же вызов,
			# что выше: модель собирается заново из словаря.
			t.eq("прогон %s: повтор совпал" % label, by_dict_report["digest"],
				Harness.run_scenario(Loader.load_mission(_canonical(), texts)["mission"],
					Loader.load_plan(plan_data), script, {"seed": seed})["digest"])
			runs["%s|%d" % [str(script), seed]] = by_dict_report

	# Чего здесь СОЗНАТЕЛЬНО нет: ассерта «отпечаток непуст». Он не может покраснеть —
	# `Harness.digest` склеивает одиннадцать полей по фиксированному списку даже у пустого
	# отчёта, поэтому пустую строку не возвращает никогда, и сравнение выродилось бы в
	# «равны два непустых». Невырожденность самого сравнения стерегут 8б и 8в: они требуют,
	# чтобы отпечаток РАЗЛИЧАЛ сценарий и seed.

	# 8б. Выбранные seed обязаны давать РАЗНЫЕ исходы, иначе «все три пути совпали» —
	# это один прогон, повторённый дважды. Проверка стоит на сценарии `["silence"]`:
	# это единственный вход, где кубик импровизации (D7) действительно бросается.
	# Сверяется РАЗНЫЙ ИСХОД, а не только разные строки отпечатка: два одинаковых прогона
	# с разными строками ничего не доказывали бы про seed.
	#
	# Обращение к `runs` идёт через `get` с умолчанием: если сценарий `["silence"]`
	# выпадет из `scenarios`, кейс обязан ПОКРАСНЕТЬ, а не упасть на обращении к
	# отсутствующему ключу (та самая «индексация без охраны размера» из чек-листа §4).
	var silence_4: Dictionary = runs.get("%s|4" % str(silence_script), {})
	var silence_5: Dictionary = runs.get("%s|5" % str(silence_script), {})
	t.is_true("сценарий %s (seed 4) сверен всеми тремя путями" % str(silence_script),
		not silence_4.is_empty())
	t.is_true("сценарий %s (seed 5) сверен всеми тремя путями" % str(silence_script),
		not silence_5.is_empty())
	t.is_true("сценарий %s: seed 4 и seed 5 дают разные отпечатки" % str(silence_script),
		String(silence_4.get("digest", "прогона нет"))
		!= String(silence_5.get("digest", "прогона нет")))
	t.is_true("сценарий %s: seed 4 — другой шум, чем seed 5" % str(silence_script),
		int(silence_4.get("noise", 0)) != int(silence_5.get("noise", 0)))

	# 8в. Выбранные сценарии обязаны быть РАЗНЫМИ прогонами. Это сторож вырождения:
	# `["breach", "silence"]` выглядел «двумя сценариями», а был одним прогоном, потому что
	# окно одно и второй элемент сценария не потребляется. Такой набор доказывает главное
	# утверждение на одном испытании, и без пробы это не видно.
	for seed in seeds:
		var breach_key := "%s|%d" % [str(breach_script), seed]
		var silence_key := "%s|%d" % [str(silence_script), seed]
		t.is_true("сценарий %s (seed %d) сверен всеми тремя путями" % [str(breach_script), seed],
			runs.has(breach_key))
		t.is_true("сценарий %s (seed %d) сверен всеми тремя путями" % [str(silence_script), seed],
			runs.has(silence_key))
		var breach_run: Dictionary = runs.get(breach_key, {})
		var silence_run: Dictionary = runs.get(silence_key, {})
		t.is_true("сценарии %s и %s (seed %d) — разные прогоны"
			% [str(breach_script), str(silence_script), seed],
			String(breach_run.get("digest", "прогона нет"))
			!= String(silence_run.get("digest", "прогона нет")))

	# Состав плана виден в отпечатке: боец с Пониманием 1 меняет исход найма (D9/D31),
	# значит «план совпал» — утверждение про отчёт, который план действительно читает,
	# а не про поле, до отчёта не доехавшее.
	var plan_weaker := Loader.load_plan({
		"route": plan_data["route"],
		"exit_node": plan_data["exit_node"],
		"agents": [{"id": "kira", "role": "tactician", "understanding": 1}],
	})
	t.is_true("отпечаток зависит от состава плана",
		Harness.run_scenario(by_dict, Loader.load_plan(plan_data), silence_script, {"seed": 5})["digest"]
		!= Harness.run_scenario(by_dict, plan_weaker, silence_script, {"seed": 5})["digest"])
	# Маршрут виден в отпечатке — иначе «план совпал» ничего не говорило бы про маршрут.
	var plan_other_route := Loader.load_plan({
		"route": ["dock", "archive0"],
		"exit_node": "dock",
		"agents": plan_data["agents"],
	})
	t.is_true("отпечаток зависит от маршрута плана",
		Harness.run_scenario(by_dict, Loader.load_plan(plan_data), ["breach"], {"seed": 5})["digest"]
		!= Harness.run_scenario(by_dict, plan_other_route, ["breach"], {"seed": 5})["digest"])

	return t.results


## Множества id раздела — тот же приём, что в `test_content_loader.gd`: сверка состава
## не зависит от порядка записей.
func _ids(items: Array, field: String) -> Array:
	var out: Array = []
	for item in items:
		out.append(String(item[field]))
	out.sort()
	return out

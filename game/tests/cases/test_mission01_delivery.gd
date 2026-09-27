extends RefCounted
## Постоянный кейс на РЕАЛЬНОЙ поставке миссии 01: `game/content/mission-01.json`
## и `game/content/texts.ru.json` читаются с диска и прогоняются через конвейер целиком.
##
## Зачем отдельный кейс от `test_content_validator.gd` и `test_content_loader.gd`.
## Те проверяют ПРАВИЛА на синтетической миссии: каждая проверка ломает одно место и
## смотрит на один диагноз. Здесь проверяется другое — что боевой артефакт уровня (тот,
## который читают прогоны и README) проходит конвейер без единой проблемы. Прежний опыт
## этапа: поставка из 49 проблем дожила до приёмки именно потому, что наш валидатор на ней
## не прогонялся ни разу, а самопроверка генератора кодировала его же неверную схему.
## Этот кейс делает такое положение невозможным: испорченный артефакт краснит набор.
##
## Числа разделов (28/33/11/203/18) — ФАКТ ЭТОЙ ПОСТАВКИ, а не инвариант движка: у другой
## миссии они другие, и «28 помещений» требованием схемы не является. Смысл проверки —
## «собранное не пустышка»: если загрузчик молча отдаст огрызок, число это назовёт.
## Меняет уровень автор — вместе с числами здесь; покрасневший кейс это и скажет.
##
## 203 ключа текстов и 18 заявок — не «числа вообще», а след решения владельца: 44 ключа
## качеств молчания (`window.<id>.silence.<quality>`) добавились к 123, а заявка
## `reveal_operation_silence` переехала в исход `bad` окна `w_echo_reads` (D41: в `safe`,
## ветке «связиста нет», Эхо в группе нет), оставаясь в счёте (17 → 18). Из них 36 — подписи схемы: 28 помещений (`room.`), 7 этажей (`floor.`) и комплекс (`facility.`); они выводятся из данных, и `UNUSED_OK_PREFIXES` их не покрывает намеренно.
##
## ПОРЯДОК ПРОВЕРОК НЕ СЛУЧАЕН. Всё, что судит о ФАЙЛЕ, стоит до раннего выхода по
## несобранной миссии; всё, что судит о МОДЕЛИ, — после сборки. Если поставить проверку
## формы молчания после выхода, она окажется недостижимой: испортить форму, не задев
## валидатор, нельзя, а значит единственным упавшим ассертом она не станет никогда —
## ровно та форма «выглядит проверенным, не будучи им», против которой стоит §4
## `docs/agents/constraints.md`. Проверено пробой P1 (см. отчёт): она называет этот ассерт.
##
## Значения из файла приводятся `str(...)`, а не `String(...)`: конструктор `String` на
## не-строке — недопустимый вызов, он обрывает `run()` и уносит ВСЕ ассерты кейса вместе
## с уже собранным диагнозом (F1 ревью 2). Кейс, теряющий ассерты из-за рантайм-сбоя,
## не диагностирует ничего. То же правило — `validator.gd:_option_signature`.

const Assert := preload("res://tests/assert.gd")
const Problems := preload("res://content/problems.gd")
const Validator := preload("res://content/validator.gd")
const Loader := preload("res://content/loader.gd")
const Mission := preload("res://sim/mission.gd")
const Harness := preload("res://sim/harness.gd")

## Пути от корня проекта: `res://` — это `game/`, канонический артефакт живёт в `content/`.
const MISSION_PATH := "res://content/mission-01.json"
const TEXTS_PATH := "res://content/texts.ru.json"

## Факт поставки (см. шапку файла), а не инвариант движка.
const DELIVERY_NODES := 28
const DELIVERY_EDGES := 33
const DELIVERY_WINDOWS := 13
const DELIVERY_TEXTS := 209
const DELIVERY_PROPOSALS := 18
## Этажи поставки: подвал, 1–5 и кровля. Тоже факт уровня (`levels/mission-01.md` §3),
## а не инвариант движка: у другой миссии этажей меньше или больше.
const DELIVERY_FLOORS := 7
## Шаг сетки координат. Помещения стоят в узлах с шагом 4, коробка помещения рисуется 3×3,
## поэтому «не наезжают» = расстояние Чебышёва между любыми двумя помещениями одного этажа
## не меньше шага: между коробками остаётся минимум 1.
const GRID_STEP := 4

## Исходы молчания — тот же список, что у валидатора (`validator.gd:SILENCE_QUALITIES`).
## Здесь он продублирован осознанно: кейс обязан назвать пропавший исход по имени, даже
## если валидатор однажды перестанет это делать. Имена совпадают со схемой §4.5.
const SILENCE_QUALITIES := ["good", "neutral", "bad", "safe"]


## Чтение JSON с диска. Возвращает {"data": Variant, "problems": Array[String]}:
## проблемы чтения и разбора — словами, чтобы кейс не падал раньше своих ассертов.
func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"data": null, "problems": ["%s не открыт (код %d)" % [path, FileAccess.get_open_error()]]}
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		return {"data": null, "problems": ["%s не разобран как JSON: %s (строка %d)"
			% [path, json.get_error_message(), json.get_error_line()]]}
	return {"data": json.data, "problems": []}


## Список проблем одной строкой — для имени ассерта: провал обязан назвать причину,
## а не «список непуст». Формат строки задаёт `Problems.brief`, чтобы он не разошёлся
## с остальным конвейером.
func _brief(problems: Array) -> String:
	var parts: Array = []
	for p in problems:
		parts.append(Problems.brief(p))
	return "; ".join(parts) if not parts.is_empty() else "(проблем нет)"


## Список строк одной строкой — для имени ассерта с перечислением нарушителей.
func _join(items: Array) -> String:
	return ", ".join(items) if not items.is_empty() else "(нарушителей нет)"


## Окна файла или пустой список, если раздел не массив: падать кейс не имеет права,
## а о форме раздела уже сказал валидатор.
func _windows_of(data: Dictionary) -> Array:
	var raw = data.get("windows", null)
	return raw if typeof(raw) == TYPE_ARRAY else []


## Открывает ли эффект указанное ребро. `unlock` — сам или внутри `fallback` заявки
## движку: ядро применяет `fallback`, когда предложение отклонено (§7), и дверь тогда
## открывается. Логика повторяет `validator.gd:_opens_edge` намеренно: кейс спрашивает
## то же самое про ДАННЫЕ, а не про мнение валидатора, — и потому краснеет независимо.
func _opens_edge(effect, edge: String) -> bool:
	if typeof(effect) != TYPE_DICTIONARY:
		return false
	var type := str(effect.get("type", ""))
	if type == "unlock":
		return str(effect.get("edge", "")) == edge
	if type != "engine_proposal":
		return false
	var fallback = effect.get("fallback", null)
	if typeof(fallback) == TYPE_DICTIONARY:
		return _opens_edge(fallback, edge)
	if typeof(fallback) == TYPE_ARRAY:
		for item in (fallback as Array):
			if _opens_edge(item, edge):
				return true
	return false


## Список эффектов одного исхода молчания. Не массив (форма испорчена) — пустой список:
## об этом уже сказал ассерт формы, а падать кейс не имеет права.
func _effects(raw) -> Array:
	return raw if typeof(raw) == TYPE_ARRAY else []


## Все id заявок движку в порядке обхода: эффекты вариантов, исходов молчания и вложенные
## `fallback`. Обход идёт по массивам, а не по словарям, — порядок фиксирован.
func _collect_proposal_ids(effects: Array, out: Array) -> void:
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		if str(effect.get("type", "")) != "engine_proposal":
			continue
		out.append(str(effect.get("id", "")))
		var fallback = effect.get("fallback", null)
		if typeof(fallback) == TYPE_DICTIONARY:
			_collect_proposal_ids([fallback], out)
		elif typeof(fallback) == TYPE_ARRAY:
			_collect_proposal_ids(fallback, out)


## Координаты узла как целые: `Vector2i(x, y)` или `null`, если форма не та. Числа из JSON
## приходят `float`, поэтому «целое» проверяется через `Loader.to_int` — тем же правилом,
## что и в загрузчике, а не второй его копией. Кейс не падает на кривом поле: `null`
## означает «координаты нет», и это называет ассерт, а не рантайм.
func _pos_of(data: Dictionary, node_id: String):
	var nodes = data.get("nodes", null)
	if typeof(nodes) != TYPE_DICTIONARY:
		return null
	var node = (nodes as Dictionary).get(node_id, null)
	if typeof(node) != TYPE_DICTIONARY:
		return null
	var pos = (node as Dictionary).get("pos", null)
	if typeof(pos) != TYPE_DICTIONARY:
		return null
	var x: Variant = Loader.to_int((pos as Dictionary).get("x", null))
	var y: Variant = Loader.to_int((pos as Dictionary).get("y", null))
	if x == null or y == null:
		return null
	return Vector2i(int(x), int(y))


## Номер этажа узла строкой или пустая строка, если он не читается. Кейс не имеет права
## падать рантаймом на испорченном поле: тогда он потерял бы ВСЕ свои ассерты вместе
## с уже собранным диагнозом (F1 ревью 2), а об испорченном поле уже сказал валидатор.
func _floor_of(node) -> String:
	if typeof(node) != TYPE_DICTIONARY:
		return ""
	var value: Variant = Loader.to_int((node as Dictionary).get("floor", null))
	if value == null:
		return ""
	return str(int(value))


## Узлы рёбер заданного вида: их x и множество этажей. Возвращает
## `{"x": Array[int], "floors": Array[String]}` — x уникальны и отсортированы, этажи тоже.
## Так одна вертикальная связь обязана дать ОДИН x (вертикаль на стопке этажных схем)
## и свой набор этажей, а связь, «размазанная» по двум колонкам, назовётся провалом.
func _column_of(data: Dictionary, kind: String) -> Dictionary:
	var xs: Array = []
	var floors: Array = []
	var nodes = data.get("nodes", null)
	var edges_raw = data.get("edges", null)
	if typeof(nodes) != TYPE_DICTIONARY or typeof(edges_raw) != TYPE_ARRAY:
		return {"x": xs, "floors": floors}
	var node_map: Dictionary = nodes
	for e in (edges_raw as Array):
		if typeof(e) != TYPE_DICTIONARY or str((e as Dictionary).get("kind", "")) != kind:
			continue
		for side in ["a", "b"]:
			var node_id := str((e as Dictionary).get(side, ""))
			if not node_map.has(node_id):
				continue
			var point = _pos_of(data, node_id)
			if point == null:
				continue
			var p: Vector2i = point
			if not xs.has(p.x):
				xs.append(p.x)
			var floor_no := _floor_of(node_map[node_id])
			if floor_no != "" and not floors.has(floor_no):
				floors.append(floor_no)
	xs.sort()
	floors.sort()
	return {"x": xs, "floors": floors}


## Копия данных миссии БЕЗ полей презентации: координаты помещений, их подписи, этажи и
## название комплекса. Второй вход пробы «координаты не влияют на симуляцию»; копия
## делается `duplicate(true)`, поэтому читаемые из файла данные проба не трогает.
func _without_presentation(data: Dictionary) -> Dictionary:
	var out: Dictionary = data.duplicate(true)
	out.erase("floors")
	out.erase("facility_key")
	for node_id in (out["nodes"] as Dictionary):
		var node = (out["nodes"] as Dictionary)[node_id]
		if typeof(node) == TYPE_DICTIONARY:
			(node as Dictionary).erase("pos")
			(node as Dictionary).erase("name_key")
	return out


func run() -> Array:
	var t := Assert.new()

	# 1. Оба файла читаются и разбираются. Провал называет путь: «файл не открылся» без
	# адреса не объясняет ничего.
	var mission_read := _read_json(MISSION_PATH)
	var texts_read := _read_json(TEXTS_PATH)
	for problem in mission_read["problems"]:
		t.is_true("%s (канонический артефакт читается из %s)" % [String(problem), MISSION_PATH], false)
	for problem in texts_read["problems"]:
		t.is_true("%s (канонический артефакт читается из %s)" % [String(problem), TEXTS_PATH], false)
	if mission_read["data"] == null or texts_read["data"] == null:
		return t.results

	# 2. Корни — словари: «файл разобрался как JSON» и «файл описывает миссию» разные вещи.
	var data = mission_read["data"]
	var texts = texts_read["data"]
	t.is_true("данные поставки — словарь, тексты — словарь",
		typeof(data) == TYPE_DICTIONARY and typeof(texts) == TYPE_DICTIONARY)
	if typeof(data) != TYPE_DICTIONARY or typeof(texts) != TYPE_DICTIONARY:
		return t.results

	# 3. Главное: поставка проходит валидатор без единой проблемы — и проходит С ТЕКСТАМИ.
	# Диагноз печатается списком (`Problems.brief`), а не словом «список непуст»: иначе
	# провал не называет, что именно чинить.
	var problems: Array = Validator.validate(data, texts)
	t.eq("поставка без проблем валидатора: %s" % _brief(problems), problems, [])

	# 3а. Обязательные системные ключи (04-texts.md §4 и §3.1–3.2) есть в поставке.
	# Ассерт дублирует часть работы валидатора намеренно: он называет ПРОПАВШИЙ КЛЮЧ,
	# а не «список проблем непуст», и потому краснеет ровно на том ключе, который унесли.
	#
	# Список берётся у валидатора; независимый эталон тех же 32 ключей — в
	# `test_content_validator.gd` (§14), там же доказано, что каждый из них получает ровно
	# ОДИН диагноз: 31 ключ — обязательным перечнем, название миссии — сверкой `title_key`
	# (номер миссии в конвейерной константе дал бы ложный диагноз следующей миссии).
	# Здесь проверяется ДРУГАЯ половина: список валидатора не длиннее поставки.
	var required_gaps: Array = []
	for key in Validator.REQUIRED_TEXT_KEYS:
		if not (texts as Dictionary).has(String(key)):
			required_gaps.append(String(key))
	t.is_true("список обязательных ключей непуст (ключей: %d)"
		% Validator.REQUIRED_TEXT_KEYS.size(), not Validator.REQUIRED_TEXT_KEYS.is_empty())
	t.eq("обязательные системные ключи есть в поставке: %s" % _join(required_gaps),
		required_gaps, [])

	# 3б. ПОЛЯ ПРЕЗЕНТАЦИИ в поставке (`design-presentation-data.md` §8): экран операции
	# рисует схему этажа, и рисовать её нечем, если у помещений нет координат и подписей.
	# Проверяется ФАКТ поставки, а не форма схемы (форму держат кейсы 15 валидатора и 16
	# загрузчика): `pos` и `name_key` у КАЖДОГО помещения, текст к каждой подписи.
	# Нарушители собираются списком: провал обязан назвать помещение, а не «что-то не так».
	## Раздел читается с охраной: `nodes` может быть испорчен, и тогда `data["nodes"]`
	## уронил бы кейс рантаймом. Пустой корпус называет отдельный ассерт ниже.
	var nodes_raw = data.get("nodes", null)
	var node_map: Dictionary = nodes_raw if typeof(nodes_raw) == TYPE_DICTIONARY else {}
	t.is_true("корпус помещений непуст (узлов: %d)" % node_map.size(), not node_map.is_empty())
	var missing_pos: Array = []
	var missing_name: Array = []
	var caption_without_text: Array = []
	for node_id in node_map:
		var id := str(node_id)
		if _pos_of(data, id) == null:
			missing_pos.append(id)
		var node = node_map[node_id]
		var name_key := ""
		if typeof(node) == TYPE_DICTIONARY and (node as Dictionary).has("name_key"):
			name_key = str((node as Dictionary)["name_key"])
		if name_key == "":
			missing_name.append(id)
		elif not (texts as Dictionary).has(name_key):
			caption_without_text.append("%s → %s" % [id, name_key])
	t.eq("у каждого помещения есть координаты (нет pos: %s)" % _join(missing_pos),
		missing_pos, [])
	t.eq("у каждого помещения есть подпись (нет name_key: %s)" % _join(missing_name),
		missing_name, [])
	t.eq("текст есть у каждой подписи помещения (нет текста: %s)" % _join(caption_without_text),
		caption_without_text, [])

	# 3в. Этажи и комплекс. Запись этажа обязана нести `name_key`, и текст к нему обязан
	# быть: подпись этажа приходит на экран ключом, а не строкой в данных.
	var floors_raw = data.get("floors", null)
	var floors: Dictionary = floors_raw if typeof(floors_raw) == TYPE_DICTIONARY else {}
	var floor_gaps: Array = []
	for floor_no in floors:
		var entry = floors[floor_no]
		if typeof(entry) != TYPE_DICTIONARY or not (entry as Dictionary).has("name_key"):
			floor_gaps.append("%s: нет name_key" % str(floor_no))
			continue
		var floor_key := str((entry as Dictionary)["name_key"])
		if not (texts as Dictionary).has(floor_key):
			floor_gaps.append("%s → %s: нет текста" % [str(floor_no), floor_key])
	t.eq("поставка: этажей %d" % DELIVERY_FLOORS, floors.size(), DELIVERY_FLOORS)
	t.eq("у каждого этажа есть подпись и текст к ней: %s" % _join(floor_gaps), floor_gaps, [])

	## Каждый этаж, на котором стоят помещения, обязан иметь запись: иначе на схеме этого
	## этажа не будет подписи. Ожидание выводится из ДАННЫХ (номер этажа → подпись),
	## поэтому пропавшая запись называется номером, а не «этажей стало меньше».
	var uncaptioned_floors: Array = []
	for node_id in node_map:
		var floor_no := _floor_of(node_map[node_id])
		if floor_no == "":
			continue
		if not floors.has(floor_no) and not uncaptioned_floors.has(floor_no):
			uncaptioned_floors.append(floor_no)
	t.eq("на каждый этаж с помещениями есть запись в floors (нет: %s)" % _join(uncaptioned_floors),
		uncaptioned_floors, [])

	var facility_raw = data.get("facility_key", null)
	var facility_key := String(facility_raw) if typeof(facility_raw) == TYPE_STRING else ""
	t.is_true("название комплекса задано ключом строкой (получено: %s)" % str(facility_raw),
		typeof(facility_raw) == TYPE_STRING)
	t.is_true("текст названия комплекса есть в поставке (ключ: «%s»)" % facility_key,
		facility_key != "" and (texts as Dictionary).has(facility_key))

	# 3г. СЕТКА КООРДИНАТ: помещения одного этажа не наезжают. Проверяются ВСЕ пары своего
	# этажа, а не соседи по списку, и расстояние берётся Чебышёва: на шаге 4 и коробке 3×3
	# это ровно «между двумя помещениями остаётся зазор». Счётчик пар рядом — защита от
	# вырождения: «нарушителей нет» на пустом обходе неотличимо от «ничего не проверено».
	var by_floor: Dictionary = {}
	for node_id in node_map:
		var floor_no := _floor_of(node_map[node_id])
		if floor_no == "":
			continue
		var bucket: Array = by_floor.get(floor_no, [])
		var point = _pos_of(data, str(node_id))
		if point != null:
			bucket.append({"id": str(node_id), "p": point})
		by_floor[floor_no] = bucket
	var overlaps: Array = []
	var pairs_checked := 0
	for floor_no in by_floor:
		var items: Array = by_floor[floor_no]
		for i in items.size():
			for j in range(i + 1, items.size()):
				pairs_checked += 1
				var a: Vector2i = items[i]["p"]
				var b: Vector2i = items[j]["p"]
				var gap: int = max(absi(a.x - b.x), absi(a.y - b.y))
				if gap < GRID_STEP:
					overlaps.append("%s и %s на этаже %s: расстояние %d"
						% [items[i]["id"], items[j]["id"], str(floor_no), gap])
	t.is_true("пар помещений одного этажа проверено: %d" % pairs_checked, pairs_checked > 0)
	t.eq("помещения одного этажа не наезжают (шаг сетки %d): %s" % [GRID_STEP, _join(overlaps)],
		overlaps, [])

	# 3д. ТРИ ВЕРТИКАЛЬНЫЕ СВЯЗИ читаются как ТРИ РАЗНЫХ пути (`levels/mission-01.md` §4):
	# лестница (ЛК), пассажирский лифт (Л1) и грузовой лифт (Л2). Связи берутся из РЁБЕР по
	# виду (`kind`) — то, что видит ядро, — а не из имён помещений: каждая связь обязана
	# стоять ОДНОЙ вертикалью (один x на всех её этажах), и три вертикали обязаны стоять
	# на РАЗНЫХ x. Набор этажей у каждой свой: ЛК ходит всюду, включая подвал; Л1 только
	# 1↔5; Л2 — док ↔ 1…4 ↔ подвал. Это и есть «три пути», а не три имени одной шахты.
	var columns: Dictionary = {}
	for kind in ["stairs", "lift_main", "lift_freight"]:
		columns[kind] = _column_of(data, kind)
		var column_x: Array = (columns[kind] as Dictionary)["x"]
		t.eq("связь «%s» — одна вертикаль (x: %s)" % [kind, str(column_x)], column_x.size(), 1)
	var used_x: Array = []
	for kind in ["stairs", "lift_main", "lift_freight"]:
		var column_x: Array = (columns[kind] as Dictionary)["x"]
		if column_x.size() == 1 and not used_x.has(column_x[0]):
			used_x.append(column_x[0])
	t.eq("три связи стоят на трёх разных x: %s" % str(used_x), used_x.size(), 3)
	t.eq("ЛК: этажи связи", (columns["stairs"] as Dictionary)["floors"],
		["-1", "1", "2", "3", "4", "5"])
	t.eq("Л1: этажи связи", (columns["lift_main"] as Dictionary)["floors"], ["1", "5"])
	t.eq("Л2: этажи связи", (columns["lift_freight"] as Dictionary)["floors"], ["-1", "1", "4"])

	var windows := _windows_of(data)

	# 4. Форма молчания: у каждого окна четыре исхода, и каждый — МАССИВ эффектов.
	# Одиночный объект здесь — ошибка формы (§4.5), и валидатор её называет; ассерт
	# повторяет её на языке кейса. Стоит ДО раннего выхода по несобранной миссии —
	# иначе он был бы недостижим (см. шапку файла).
	var shape: Array = []
	for w in windows:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var wid := str(w.get("id", "?"))
		var silence = w.get("silence", null)
		if typeof(silence) != TYPE_DICTIONARY:
			shape.append("%s: молчание не словарь" % wid)
			continue
		for quality in SILENCE_QUALITIES:
			if not (silence as Dictionary).has(quality):
				shape.append("%s: нет исхода %s" % [wid, quality])
			elif typeof(silence[quality]) != TYPE_ARRAY:
				shape.append("%s.%s: не массив эффектов" % [wid, quality])
	t.eq("у каждого окна молчание из четырёх исходов-массивов: %s" % _join(shape), shape, [])

	# 4а. Ключ текста по качеству есть у КАЖДОГО окна, и каждый указывает на существующий
	# текст. Проверка парная: ключ без текста движок молча заменит базовой строкой, а окно
	# без ключа качества так же молча уедет на базовую — и оба раза игрок увидит не того,
	# кто решил. Счётчик окон держит обход от вырождения: «все на месте» на пустом обходе
	# неотличимо от «ничего не проверено».
	var quality_gaps: Array = []
	var quality_windows := 0
	for w in windows:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var silence = w.get("silence", null)
		if typeof(silence) != TYPE_DICTIONARY:
			continue
		quality_windows += 1
		var wid := str(w.get("id", "?"))
		for quality in SILENCE_QUALITIES:
			var field := "%s_key" % quality
			if not (silence as Dictionary).has(field):
				quality_gaps.append("%s: нет %s" % [wid, field])
				continue
			var raw_key = (silence as Dictionary)[field]
			## Не-строка — диагноз, а не сбой: `String(5)` обрывает `run()`, и кейс теряет
			## все ассерты вместе с уже собранным `WRONG_TYPE` от валидатора (F1 ревью 2).
			if typeof(raw_key) != TYPE_STRING:
				quality_gaps.append("%s.%s: ключ не строка (%s)" % [wid, field, type_string(typeof(raw_key))])
				continue
			var key := String(raw_key)
			if key == "":
				quality_gaps.append("%s.%s: ключ пустой" % [wid, field])
			elif not (texts as Dictionary).has(key):
				quality_gaps.append("%s.%s → нет текста «%s»" % [wid, field, key])
	t.eq("окон, у которых проверены ключи качеств", quality_windows, DELIVERY_WINDOWS)
	t.eq("у каждого окна все четыре ключа качеств и текст к каждому: %s" % _join(quality_gaps),
		quality_gaps, [])

	# 4б. Базовый текст молчания (`silence.text_key`) — запасной путь формы (`architecture.md`
	# §2.2): читается, только когда качественного ключа нет, и потому обязан быть верен при
	# ЛЮБОМ качестве. При `safe` решает тактик, при `good`/`neutral`/`bad` — связист (D7, D41),
	# поэтому имя решающего в базовой строке ложно в одном из исходов; у `w_stuck_lift` решать
	# некому вовсе. Ассерт держит это правило на всех окнах поставки: он краснеет, если
	# базовую строку вернут к прежней («Кира вскрывает дверь сама…») или потеряют её текст.
	# Счётчик окон рядом — защита от вырождения: «нарушителей нет» на пустом обходе неотличимо
	# от «ничего не проверено».
	var base_named: Array = []
	var base_windows := 0
	for w in windows:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var silence = w.get("silence", null)
		if typeof(silence) != TYPE_DICTIONARY:
			continue
		base_windows += 1
		var wid := str(w.get("id", "?"))
		var base_key := str((silence as Dictionary).get("text_key", ""))
		var base_text = (texts as Dictionary).get(base_key, "")
		if typeof(base_text) != TYPE_STRING or base_text == "":
			base_named.append("%s: нет текста «%s»" % [wid, base_key])
			continue
		var base_str: String = base_text
		for decider in ["Кира", "Эхо"]:
			if base_str.contains(decider):
				base_named.append("%s: базовый текст называет %s — «%s»" % [wid, decider, base_str])
	t.eq("окон, у которых прочитан базовый текст молчания", base_windows, DELIVERY_WINDOWS)
	t.eq("базовый текст молчания верен при любом качестве и не называет решающего: %s"
		% _join(base_named), base_named, [])

	# 4в. РЕШАЮЩИЙ В КАЧЕСТВЕННОМ ТЕКСТЕ. `safe` выпадает только без живого связиста, и
	# решает в нём тактик (D7, D41), поэтому строка `safe` обязана называть Киру — как
	# базовая строка обязана НЕ называть никого (4б). Проверяются ОБЕ половины правила: и
	# «назван связист» (ложь о решающем), и «не назван тактик». До этого ассерта строку не
	# держало ничто: ключ качества проверялся только на НАЛИЧИЕ текста (4а), и подмена имени
	# в нём не краснила ничего. Провал называет окно и сам текст, счётчик окон — сторож
	# вырождения.
	#
	# Исключение одно, и оно ПРОВЕРЯЕТСЯ, а не подразумевается: у `w_stuck_lift` решать
	# некому вовсе (все четыре исхода — «по инструкции»), и в его `safe` нет ни Кира, ни Эхо.
	# Без этой половины ассерт «не называет связиста» проходил бы и на строке «Никто ничего
	# не делает».
	var safe_comms: Array = []
	var safe_nameless: Array = []
	var safe_stuck_nameless := false
	var safe_windows := 0
	for w in windows:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var silence = w.get("silence", null)
		if typeof(silence) != TYPE_DICTIONARY:
			continue
		safe_windows += 1
		var wid := str(w.get("id", "?"))
		var raw_safe = (silence as Dictionary).get("safe_key", "")
		if typeof(raw_safe) != TYPE_STRING or String(raw_safe) == "":
			safe_comms.append("%s: нет ключа текста safe" % wid)
			continue
		var safe_text = (texts as Dictionary).get(String(raw_safe), "")
		if typeof(safe_text) != TYPE_STRING or String(safe_text) == "":
			safe_comms.append("%s: нет текста «%s»" % [wid, String(raw_safe)])
			continue
		var safe_str := String(safe_text)
		if safe_str.contains("Эхо"):
			safe_comms.append("%s: текст safe называет связиста — «%s»" % [wid, safe_str])
		if safe_str.contains("Кира"):
			continue
		if wid == "w_stuck_lift":
			safe_stuck_nameless = not safe_str.contains("Эхо")
			continue
		safe_nameless.append("%s: текст safe не называет тактика — «%s»" % [wid, safe_str])
	t.eq("окон, у которых прочитан текст safe", safe_windows, DELIVERY_WINDOWS)
	t.eq("текст safe не называет связиста: %s" % _join(safe_comms), safe_comms, [])
	t.eq("текст safe называет тактика (Кира) — во всех окнах, кроме w_stuck_lift: %s"
		% _join(safe_nameless), safe_nameless, [])
	t.is_true("исключение не выдумано: в `safe` окна w_stuck_lift не назван никто",
		safe_stuck_nameless)

	# 5. Окно у двери: `unlock` стоит во ВСЕХ четырёх исходах молчания (D37/D38 —
	# «молчание не проваливает миссию»). Валидатор требует лишь ОДИН открывающий исход
	# (`UNWINNABLE_EDGE` — про тупик), поэтому три из четырёх он пропустит: этот ассерт
	# и есть то, что держит требование брифа целиком. Проба P3b — изъятие одного
	# `unlock` — краснит только его.
	var uncovered: Array = []
	for w in windows:
		if typeof(w) != TYPE_DICTIONARY or str(w.get("kind", "")) != "locked_edge":
			continue
		var wid := str(w.get("id", "?"))
		var trigger = w.get("trigger", null)
		var edge := str((trigger as Dictionary).get("edge", "")) if typeof(trigger) == TYPE_DICTIONARY else ""
		var silence = w.get("silence", null)
		if typeof(silence) != TYPE_DICTIONARY:
			continue
		for quality in SILENCE_QUALITIES:
			var opens := false
			for effect in _effects((silence as Dictionary).get(quality, null)):
				if _opens_edge(effect, edge):
					opens = true
			if not opens:
				uncovered.append("%s.%s не открывает «%s»" % [wid, quality, edge])
	t.eq("все четыре исхода окна у двери открывают своё ребро (D37/D38): %s" % _join(uncovered),
		uncovered, [])

	# 6. id заявок движку уникальны (§7): одинаковый id у разных заявок сделал бы их
	# неразличимыми в отчёте о том, что просит движок. Валидатор этого не проверяет
	# вовсе, поэтому проверка живёт здесь. Число найденных заявок — факт поставки; оно
	# же держит обход от вырождения (пустой обход не «все id уникальны», а «ничего не
	# найдено» и краснеет по числу).
	var proposals: Array = []
	for w in windows:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var options: Array = w["options"] if typeof(w.get("options", null)) == TYPE_ARRAY else []
		for option in options:
			if typeof(option) == TYPE_DICTIONARY:
				_collect_proposal_ids(_effects(option.get("effects", null)), proposals)
		var silence = w.get("silence", null)
		if typeof(silence) == TYPE_DICTIONARY:
			for quality in SILENCE_QUALITIES:
				_collect_proposal_ids(_effects((silence as Dictionary).get(quality, null)), proposals)
	t.eq("поставка: заявок движку %d" % DELIVERY_PROPOSALS, proposals.size(), DELIVERY_PROPOSALS)
	var duplicates: Array = []
	var seen: Dictionary = {}
	for pid in proposals:
		if seen.has(pid):
			if not duplicates.has(pid):
				duplicates.append(pid)
		else:
			seen[pid] = true
	t.eq("id заявок движку уникальны: %s" % _join(duplicates), duplicates, [])

	# 6а. Стык данных и состава: исход `safe` при штатном составе не выпадает ни разу
	# (D41; сам факт держит отдельный ассерт в `test_windows_data.gd`), поэтому заявка,
	# положенная ТОЛЬКО в `safe`, на штатном составе не играется. Убирать её не за что:
	# формат §4.5 определяет `safe` как «обход, дольше, но предсказуемо», и обход
	# принадлежит именно ему — это задел на составы без связиста (D41 п. 3). Но мёртвая
	# ветка обязана быть НАЗВАНА, иначе следующий автор будет искать сцену, которой в
	# прогоне нет. Ассерт краснеет и когда заявку вынесут из `safe`, и когда в `safe`
	# появится новая заявка, которой там быть не должно; ожидание непустое, поэтому
	# вырожденный обход его тоже краснит.
	var by_quality: Dictionary = {}
	var elsewhere: Dictionary = {}
	for w in windows:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var silence = w.get("silence", null)
		if typeof(silence) != TYPE_DICTIONARY:
			continue
		for quality in SILENCE_QUALITIES:
			var ids: Array = []
			_collect_proposal_ids(_effects((silence as Dictionary).get(quality, null)), ids)
			var bucket: Array = by_quality.get(quality, [])
			for pid in ids:
				if not bucket.has(pid):
					bucket.append(pid)
				if quality != "safe":
					elsewhere[pid] = true
			by_quality[quality] = bucket
	var safe_only: Array = []
	for pid in by_quality.get("safe", []):
		if not elsewhere.has(pid):
			safe_only.append(pid)
	safe_only.sort()
	t.eq("заявки, лежащие только в недостижимом исходе safe: %s" % _join(safe_only),
		safe_only, ["detour_kitchen_silence", "detour_office_silence"])

	# 7. «Форма проходит» без сборки ничего не стоит: из данных обязана собираться миссия.
	# Последний ассерт, после которого кейс ещё может судить о данных, но не о модели.
	var loaded := Loader.load_mission(data, texts)
	var loaded_problems: Array = loaded["problems"]
	t.is_true("миссия из поставки собрана: %s" % _brief(loaded_problems), loaded["mission"] != null)
	if loaded["mission"] == null:
		return t.results
	var mission = loaded["mission"]

	# 8. Собранное — не пустышка. Числа — факт поставки (см. шапку), но они же ловят
	# молчаливый огрызок: загрузчик, потерявший раздел, назовётся здесь.
	t.eq("поставка: помещений %d" % DELIVERY_NODES, mission.nodes.size(), DELIVERY_NODES)
	t.eq("поставка: рёбер %d" % DELIVERY_EDGES, mission.edges.size(), DELIVERY_EDGES)
	t.eq("поставка: окон %d" % DELIVERY_WINDOWS, (mission.data["windows"] as Array).size(), DELIVERY_WINDOWS)
	t.eq("поставка: ключей текстов %d" % DELIVERY_TEXTS, (texts as Dictionary).size(), DELIVERY_TEXTS)

	# 9. Разделы доехали до модели, а не остались в файле: окна, тексты и цель сверяются
	# с данными напрямую. «Валидатор доволен, а в игре ничего нет» — расхождение, которое
	# иначе не видно. Данные эти ассерты не ловят (валидатор строже), их держат пробы со
	# сломанным загрузчиком — P11, P12, P13 в отчёте.
	t.eq("поставка: окна доехали до модели", (mission.data["windows"] as Array).size(),
		(data["windows"] as Array).size())
	t.eq("поставка: тексты доехали до модели", mission.data["texts"], texts)
	t.eq("поставка: цель доехала до модели", mission.objective, str(data["objective"]))

	# 10. `Mission.validate()` на собранной модели — вторая, независимая от валидатора
	# проверка согласованности графа. Её пустой ответ держится пробой P6 со сломанным
	# загрузчиком: данными её покраснить нельзя, потому что валидатор строже на тех же
	# полях и до сборки миссия просто не доходит.
	var model_problems: Array = mission.validate()
	t.eq("собранная модель без проблем Mission.validate: %s"
		% ("; ".join(model_problems) if not model_problems.is_empty() else "(проблем нет)"),
		model_problems, [])

	# 10а. ГЕОМЕТРИЯ ЦЕЛИ — проверяемое утверждение документа (`scales.md` §10.1, предложение 1).
	# Прежняя фраза «`exit_node` обязан быть смежен цели (у `archive0` это только `hall0`)»
	# была ЛОЖНОЙ, и правка задачи 9 исправила её в теле: рёбер у цели два, а «только `hall0`»
	# относится к другому утверждению — «со стороны выхода к цели ведёт только `hall0`».
	# Проверяемая половина исправленной фразы такая: соседей у цели РОВНО два — `hall0` и
	# `it_open4`, и `hall0` — тот выход, на котором снят замер (`measure_mission01.gd:EXIT_NODE`;
	# маршруты `A_2floor` и `C_roof` входят в цель именно через него). Непроверяемую половину
	# («сторона выхода») ассерт за собой не берёт: уровня этого не хранят — выход выбирает
	# замысел, и проба других выходов живёт в инструменте замера (раздел 4г).
	var goal_id := str(data["objective"])
	t.eq("цель поставки — archive0: кейс про геометрию именно этой цели", goal_id, "archive0")
	var goal_neighbours: Array = []
	for e in (data["edges"] as Array):
		if String(e["a"]) == goal_id:
			goal_neighbours.append(String(e["b"]))
		elif String(e["b"]) == goal_id:
			goal_neighbours.append(String(e["a"]))
	goal_neighbours.sort()
	t.eq("у цели archive0 соседей ровно два — hall0 и it_open4 (а не «только hall0»)",
		goal_neighbours, ["hall0", "it_open4"])
	t.is_true("выход матрицы замера (hall0) смежен цели: правило 1 отхода к нему применимо",
		goal_neighbours.has("hall0"))

	# 11. КООРДИНАТЫ НЕ ВЛИЯЮТ НА СИМУЛЯЦИЮ. Прогон миссии с полями презентации и прогон
	# той же миссии с ВЫРЕЗАННЫМИ полями обязаны дать один и тот же `harness.digest`:
	# координаты — данные показа, ядро их не читает (в `Mission.nodes` им и попасть некуда —
	# загрузчик кладёт туда `floor` и `tags`, кейс 16 загрузчика). Оба входа идут через
	# валидатор и загрузчик с `texts = null` (тексты в прогон не входят, и вырезанные
	# подписи не дают ложного `DANGLING_TEXT`), поэтому различаются они РОВНО полями
	# презентации. Рядом — проба на невырожденность сравнения: смысловая правка данных
	# (шум первого ребра маршрута) обязана отпечаток ИЗМЕНИТЬ.
	#
	# Мутационная проба ассерта «один и тот же harness.digest» — в отчёте задачи 10:
	# правка `loader.gd`, после которой обработка узла зависит от наличия `pos` (одно
	# место), краснит его: вырезанный вход перестаёт быть той же миссией.
	var run_plan := Loader.load_plan({
		"route": ["main_entry1", "reception1", "hall1", "stair1", "stair2", "hall2",
			"kitchen2", "hall2", "term2", "hall2", "stair2", "stair1", "hall0", "archive0"],
		"exit_node": "hall0",
		"agents": [{"id": "kira", "role": "tactician", "understanding": 3},
			{"id": "echo", "role": "comms", "understanding": 3}],
	})
	var shown_mission = Loader.load_mission(data, null)["mission"]
	var plain_mission = Loader.load_mission(_without_presentation(data), null)["mission"]
	t.is_true("миссия с координатами собрана", shown_mission != null)
	t.is_true("миссия без координат собрана", plain_mission != null)
	if shown_mission == null or plain_mission == null:
		return t.results
	var with_pos: Dictionary = Harness.run_scenario(shown_mission, run_plan, [], {"seed": 5})
	var without_pos: Dictionary = Harness.run_scenario(plain_mission, run_plan, [], {"seed": 5})
	t.is_true("прогон по поставке состоялся (исход: %s)" % str(with_pos["outcome"]),
		str(with_pos["outcome"]) != "" and str(with_pos["outcome"]) != "invalid_mission")
	t.eq("координаты не влияют на симуляцию: один и тот же harness.digest",
		String(without_pos["digest"]), String(with_pos["digest"]))

	var loud_data := _without_presentation(data)
	(loud_data["edges"] as Array)[0]["noise"] = int((loud_data["edges"] as Array)[0]["noise"]) + 5
	var loud_mission = Loader.load_mission(loud_data, null)["mission"]
	t.is_true("миссия со смысловой правкой собрана", loud_mission != null)
	if loud_mission != null:
		var loud_run: Dictionary = Harness.run_scenario(loud_mission, run_plan, [], {"seed": 5})
		t.is_true("смысловая правка данных меняет отпечаток (сравнение не вырождено)",
			String(loud_run["digest"]) != String(with_pos["digest"]))

	return t.results

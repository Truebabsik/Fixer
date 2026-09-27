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
## Числа разделов (28/33/11/167/18) — ФАКТ ЭТОЙ ПОСТАВКИ, а не инвариант движка: у другой
## миссии они другие, и «28 помещений» требованием схемы не является. Смысл проверки —
## «собранное не пустышка»: если загрузчик молча отдаст огрызок, число это назовёт.
## Меняет уровень автор — вместе с числами здесь; покрасневший кейс это и скажет.
##
## 167 ключей текстов и 18 заявок — не «числа вообще», а след решения владельца: 44 ключа
## качеств молчания (`window.<id>.silence.<quality>`) добавились к 123, а заявка
## `reveal_operation_silence` переехала в исход `bad` окна `w_echo_reads` (D41: в `safe`,
## ветке «связиста нет», Эхо в группе нет), оставаясь в счёте (17 → 18).
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

## Пути от корня проекта: `res://` — это `game/`, канонический артефакт живёт в `content/`.
const MISSION_PATH := "res://content/mission-01.json"
const TEXTS_PATH := "res://content/texts.ru.json"

## Факт поставки (см. шапку файла), а не инвариант движка.
const DELIVERY_NODES := 28
const DELIVERY_EDGES := 33
const DELIVERY_WINDOWS := 11
const DELIVERY_TEXTS := 167
const DELIVERY_PROPOSALS := 18

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
	# Список берётся у валидатора; независимый эталон тех же 32 ключей и доказательство,
	# что список валидатора не короче эталона, — в `test_content_validator.gd` (§14).
	# Здесь проверяется ДРУГАЯ половина: список валидатора не длиннее поставки.
	var required_gaps: Array = []
	for key in Validator.REQUIRED_TEXT_KEYS:
		if not (texts as Dictionary).has(String(key)):
			required_gaps.append(String(key))
	t.is_true("список обязательных ключей непуст (ключей: %d)"
		% Validator.REQUIRED_TEXT_KEYS.size(), not Validator.REQUIRED_TEXT_KEYS.is_empty())
	t.eq("обязательные системные ключи есть в поставке: %s" % _join(required_gaps),
		required_gaps, [])

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

	return t.results

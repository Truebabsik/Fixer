extends RefCounted
## Самопроверка скелета постановки: `docs/handoff/2026-09-26-mission-content/`.
##
## Зачем отдельный кейс. Скелет — стартовая точка для внешней сессии генератора контента,
## и `README.md` пакета обещает, что он проходит НАШ валидатор. Обещание уже один раз
## оказалось ложным: скелет давал 4 проблемы (разрыв маршрута патруля `floor3 → it4` и
## одиночные объекты вместо массивов в `silence`). Слово в README этого не стережёт —
## схема меняется, скелет тихо расходится с ней, а внешняя сессия стартует с неверного
## образца. Здесь обещание становится ПРОВЕРЯЕМЫМ: файл читается с диска, разбирается,
## прогоняется через `content/validator.gd` и `content/loader.gd`.
##
## Файл лежит ВНЕ `res://` (это документация, а не проект), поэтому путь строится от корня
## проекта: `res://` → `game/`, и на уровень выше — `docs/`. Проверено прогоном:
## `FileAccess` такой путь открывает (см. отчёт). В собранной игре (pck) документации нет,
## но кейс и не для неё: он гоняется из исходников, как и весь остальной набор.

const Assert := preload("res://tests/assert.gd")
const Problems := preload("res://content/problems.gd")
const Validator := preload("res://content/validator.gd")
const Loader := preload("res://content/loader.gd")

## Путь к скелету ОТ КОРНЯ ПРОЕКТА. Именно относительный: при переезде файла провал
## назовёт прочитанный путь целиком, и искать не придётся «где-то в docs».
const SKELETON_RELATIVE := "../docs/handoff/2026-09-26-mission-content/example-mission.skeleton.json"

## Тексты к ключам скелета — ВСЕ, что он использует, и ничего лишнего.
##
## Зачем фикстура. У `Validator.validate` второй аргумент обязателен, и сверка ключей
## идёт только тогда, когда тексты переданы словарём (`null` — явный отказ от сверки,
## см. `validator.gd`). Без фикстуры пункты 22–23 `02-format.md` §3 (все `*_key` есть
## в текстах; лишних ключей нет) на скелете НЕ проверялись бы, а `README.md` пакета
## обещает ровно это: положительный ассерт «проблем нет» ничего не говорил бы про ключи.
## Проверка была бы вырожденной: скелет мог разойтись со схемой по ключам и остаться
## «прошедшим». Держат её два отрицательных контроля в кейсе 2a.
##
## Цена названа прямо: это вторая копия списка ключей, и новый ключ в скелете требует
## строки здесь (иначе кейс краснеет на MISSING_TEXT — то есть расхождение видно, а не
## проглочено). Вывести фикстуру из скелета нельзя: тогда она повторила бы данные и не
## поймала бы ни удалённый ключ, ни лишний.
##
## ФИКСТУРА ТЕКСТОВ дополняется обязательными системными ключами (`_fixture_texts`):
## сверка текстов-словарём требует и их (04-texts.md §4), а скелет — образец формы
## миссии, и системных текстов в нём нет вовсе. Независимый эталон перечня и
## доказательство, что список валидатора не короче эталона, — в `test_content_validator.gd`
## (§14); третьей копии здесь нет намеренно. Этот кейс проверяет другую половину:
## что список валидатора не длиннее фикстуры.
const SKELETON_TEXTS := {
	"mission.01.title": "Операция «Тихий архив»",
	"window.w_bio_door.text": "Биометрическая дверь на четвёртый.",
	"window.w_bio_door.breach": "Выбить дверь.",
	"window.w_bio_door.pick": "Вскрыть замок.",
	"window.w_bio_door.cut_power": "Обесточить датчик.",
	"window.w_bio_door.silence": "Кира обходит дверь.",
	"window.w_echo_reads.text": "Эхо читает архив.",
	"window.w_echo_reads.stop": "Остановить Эхо.",
	"window.w_echo_reads.let_read": "Дать дочитать.",
	"window.w_echo_reads.silence": "Кира молчит.",
	"intel.hack.patrol_ok": "Обход на третьем — штатный.",
	"intel.hack.it4_door_closed": "Дверь на четвёртый заперта.",
	"intel.agents.patrol_false": "Подброшенное расписание обхода.",
	"intel.agents.it4": "На четвёртом один охранник.",
	"intel.drone.roof": "Крыша пуста.",
	"ap.ap_term5.text": "Терминал на пятом.",
	"ap.ap_term5.copy_data": "Скопировать данные.",
	"ap.ap_term5.take_money": "Взять деньги.",
	"ap.ap_term5.leave": "Уйти.",
}


## Скелет пакета постановки: абсолютный путь и разобранные данные.
## Возвращает {"path": String, "data": Variant, "problems": Array[String]} — проблемы
## чтения и разбора словами, чтобы кейс не падал раньше собственных ассертов.
func _read_skeleton() -> Dictionary:
	var absolute: String = ProjectSettings.globalize_path("res://").path_join(SKELETON_RELATIVE).simplify_path()
	var file := FileAccess.open(absolute, FileAccess.READ)
	if file == null:
		return {"path": absolute, "data": null, "problems": ["скелет не открыт (код %d)" % FileAccess.get_open_error()]}
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		return {"path": absolute, "data": null, "problems": [
			"скелет не разобран как JSON: %s (строка %d)" % [json.get_error_message(), json.get_error_line()]]}
	return {"path": absolute, "data": json.data, "problems": []}


## Список проблем одной строкой — для имени ассерта: провал обязан назвать причину,
## а не «список непуст». Формат строки задаёт `Problems.brief`, чтобы он не разошёлся
## с остальным конвейером.
func _brief(problems: Array) -> String:
	var parts: Array = []
	for p in problems:
		parts.append(Problems.brief(p))
	return "; ".join(parts) if not parts.is_empty() else "(проблем нет)"


## Тексты, которые кейс передаёт валидатору и загрузчику: ключи скелета ПЛЮС обязательные
## системные (04-texts.md §4). Скелет — образец ФОРМЫ миссии, и системных текстов он не
## несёт; но сверка текстов-словарём требует их наличия, а обещание README («скелет
## проходит наш валидатор») обязано остаться правдой. Список берётся у валидатора, эталон
## его перечня — в кейсе валидатора (§14): так расхождение этих двух списков краснит
## ассерт с именем ключа, а не молчит.
func _fixture_texts() -> Dictionary:
	var out := SKELETON_TEXTS.duplicate()
	for key in Validator.REQUIRED_TEXT_KEYS:
		out[String(key)] = "%s: системный текст" % String(key)
	return out


## Коды проблем — чтобы «список непуст» не проходило вместо «диагноз ровно тот».
func _codes_of(problems: Array) -> Array:
	var out: Array = []
	for p in problems:
		out.append(String(p["code"]))
	return out


## Называет ли ДАННЫЕ этот ключ. Список берётся у валидатора (`_collect_text_keys`):
## вопрос здесь — «ссылаются ли данные на ключ», а не «есть ли он в фикстуре».
func _key_in(entries: Array, key: String) -> bool:
	for entry in entries:
		if String(entry["key"]) == key:
			return true
	return false


func run() -> Array:
	var t := Assert.new()
	var skeleton := _read_skeleton()
	var absolute := String(skeleton["path"])

	# 1. Файл читается и разбирается. Оба ассерта называют ПУТЬ: скелет — договор с внешней
	# сессией, и «файл не открылся» без адреса не объясняет ничего.
	#
	# Про переезд проекта сказано ПРЯМО в имени ассерта: путь считается от корня репозитория
	# (`<корень>/game/` + `../docs/handoff/...`), и если `game/` перенесли, упавший кейс —
	# это устаревший путь, а не дефект конвейера. Провал остаётся жёстким: молчаливый
	# пропуск был бы хуже, потому что «кейс не выполнился» неотличимо от «всё хорошо».
	for problem in skeleton["problems"]:
		t.is_true("%s: %s (путь считается от корня репозитория: <корень>/game/ + %s; при переносе game/ путь надо обновить)"
			% [String(problem), absolute, SKELETON_RELATIVE], false)
	if skeleton["data"] == null:
		return t.results

	# 2. Главное обещание README: скелет проходит наш валидатор без единой проблемы —
	# и проходит С ТЕКСТАМИ. Сверка ключей идёт только при переданном словаре, поэтому
	# фикстура обязательна, а её непустота — отдельный ассерт.
	var data = skeleton["data"]
	var fixture_texts := _fixture_texts()
	t.is_true("фикстура текстов непуста (ключей: %d)" % fixture_texts.size(),
		not fixture_texts.is_empty())
	var problems: Array = Validator.validate(data, fixture_texts)
	t.eq("скелет без проблем валидатора: %s" % _brief(problems), problems, [])

	# 2a. ПОЛОЖИТЕЛЬНЫЙ ассерт выше САМ ПО СЕБЕ вырожден: «проблем нет» верно и тогда,
	# когда сверка ключей не выполнена вовсе. Держат его два ОТРИЦАТЕЛЬНЫХ контроля ниже;
	# оба краснеют, если сверку отключить, а второй — ещё и если фикстура разошлась со
	# скелетом. Проба «подменить `_check_texts` пустышкой» краснит первый из них.
	#
	# Контроль первый: пустой словарь — это НЕ «пропустить сверку», а осмысленное «текстов
	# нет» (отказ — это `null`). Тогда отсутствующими обязаны оказаться ВСЕ ключи, на
	# которые ссылаются данные скелета, ПЛЮС обязательные системные ключи, которых данные
	# не называют вовсе. Число берётся у самого валидатора (`_collect_text_keys`), а не
	# вписано константой: вписанное разошлось бы со скелетом при первом же новом окне, и
	# проверка начала бы врать. Приватность здесь по соглашению (подчёркивание), как и у
	# `Loader._items` в кейсе загрузчика.
	var data_text_keys: Array = Validator._collect_text_keys(data)
	t.is_true("у скелета есть ключи текстов (найдено: %d)" % data_text_keys.size(),
		data_text_keys.size() > 0)
	var expected_missing: Array = []
	for _i in data_text_keys.size():
		expected_missing.append(Problems.MISSING_TEXT)
	## Ключ, лежащий И в данных, И в обязательном списке (`mission.01.title`), назван здесь
	## ОДИН раз — как `MISSING_TEXT` на своём поле: `_check_required_texts` второго диагноза
	## ему не выписывает.
	for key in Validator.REQUIRED_TEXT_KEYS:
		if not _key_in(data_text_keys, String(key)):
			expected_missing.append(Problems.MISSING_REQUIRED_TEXT)
	var without_texts: Array = Validator.validate(data, {})
	t.eq("пустой словарь текстов — диагноз на каждый отсутствующий ключ",
		_codes_of(without_texts), expected_missing)

	# Контроль второй: фикстура ИСПОРЧЕНА НАОБОРОТ — из неё убран ОДИН ключ, и валидатор
	# обязан назвать ровно этот ключ и ровно этот путь. Именно так проверка перестаёт быть
	# вырожденной: она краснеет, если сверка «ключ из данных есть в текстах» сломана,
	# и краснеет, если фикстура перестала совпадать со скелетом.
	var gapped_texts := fixture_texts.duplicate()
	gapped_texts.erase("window.w_bio_door.text")
	var gap_problems: Array = Validator.validate(data, gapped_texts)
	t.eq("удалён один ключ фикстуры — ровно MISSING_TEXT",
		_codes_of(gap_problems), [Problems.MISSING_TEXT])
	# Путь сверяется по ФОРМЕ, а не дословно: `windows[0]` верен сегодняшнему порядку окон,
	# но кейс не должен краснеть от того, что скелет переставил окна местами. Диагноз
	# «MISSING_TEXT на поле текстового ключа» от перестановки не меняется.
	var gap_path := "(проблем нет)"
	if not gap_problems.is_empty():
		gap_path = String((gap_problems[0] as Dictionary).get("path", ""))
	t.is_true("удалён один ключ фикстуры — путь на поле *_key (%s)" % gap_path,
		gap_path.begins_with("windows[") and gap_path.ends_with(".text_key"))

	# 2b. Обратное направление: лишний ключ в текстах — DANGLING_TEXT. Без ассерта
	# «расхождение со схемой уронит прогон» (README пакета) держалось бы одной стороной.
	# Здесь же видно и то, что `null` из сверки не выпадает незаметно: словарь передаётся
	# явно, и лишний ключ в нём назван.
	var extra_texts := fixture_texts.duplicate()
	extra_texts["window.которого.нет"] = "Лишний."
	t.is_true("лишний ключ текстов — DANGLING_TEXT",
		Problems.has(Validator.validate(data, extra_texts), Problems.DANGLING_TEXT))
	t.is_true("лишний ключ текстов — ровно один диагноз",
		_codes_of(Validator.validate(data, extra_texts)).size() == 1)

	# 3. «Форма проходит» без сборки ничего не стоит: из скелета обязана собираться миссия.
	var loaded := Loader.load_mission(data, fixture_texts)
	var loaded_problems: Array = loaded["problems"]
	t.is_true("миссия из скелета собрана: %s" % _brief(loaded_problems), loaded["mission"] != null)
	if loaded["mission"] == null:
		return t.results
	var mission = loaded["mission"]

	# 4. Собранное — не пустышка: скелет показывает структуру целиком, а не огрызок.
	# Точные числа (17/20/2) не фиксируем: скелет имеет право расти, а проверяем мы
	# форму и проходимость, а не конкретный уровень.
	t.is_true("скелет: помещений больше одного", mission.nodes.size() > 1)
	t.is_true("скелет: рёбер больше одного", mission.edges.size() > 1)
	t.is_true("скелет: окна доехали до модели", (mission.data["windows"] as Array).size() > 0)
	t.eq("скелет: objective доехал", mission.objective, String(data["objective"]))

	# 5. Тексты доехали до модели тем же путём: `Mission` носит их в payload, и «ключ
	# проверен, а текста в игре нет» — расхождение, которое иначе не видно.
	t.eq("скелет: тексты доехали до модели", (mission.data["texts"] as Dictionary), fixture_texts)

	return t.results

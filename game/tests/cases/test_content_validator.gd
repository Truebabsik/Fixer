extends RefCounted
## Самопроверка валидатора контента. Один кейс на код проблемы: так видно, что
## каждая проверка ловит ровно свой дефект, а не «что-то не то».
##
## Основа — корректная миссия, в которой каждый тест ломает ровно одно место:
## иначе непонятно, какая именно проверка сработала.

const Assert := preload("res://tests/assert.gd")
const Problems := preload("res://content/problems.gd")
const Validator := preload("res://content/validator.gd")
## Ядро нужно ради ОДНОГО вопроса — списка исполняемых видов эффектов (`Sim.EFFECT_TYPES`):
## форма обязана спрашивать его у применятеля, а не держать свою копию (M6 ревью 01–04).
const Sim := preload("res://sim/sim.gd")

## ЭТАЛОН видов эффектов — независимая копия, как `REQUIRED_TEXTS` ниже. Форма СПРАШИВАЕТ
## список у ядра (`Sim.EFFECT_TYPES`), и эталон держит обе стороны сразу: пропажу вида из
## ядра (тогда форма отвергла бы честный эффект) и лишний вид в форме. Сверка «список формы
## против списка формы» была бы тавтологией и не покраснела бы никогда.
## `noop` стоит в эталоне осознанно: это пустой эффект, который ядро не обрабатывает, и так
## и заявлено — именно его расхождение и открыло M6.
const EFFECT_KINDS := ["unlock", "noise", "delay", "noop", "engine_proposal", "money", "trace", "mark"]

## ЭТАЛОН обязательных системных ключей — независимая копия перечня из постановки
## (`docs/handoff/2026-09-26-mission-content/04-texts.md` §4 плюс блоки §3.1–3.2).
## Список намеренно НЕ берётся из `Validator.REQUIRED_TEXT_KEYS`: эталон, производный от
## проверяемого, не поймал бы ни одного ключа, выпавшего из списка валидатора
## (`docs/agents/review-checklist.md` §2 — «ассерт, который не может покраснеть»).
## Держатся они вместе кейсом 14, но НЕ поэлементно: 31 ключ эталона ловит обязательный
## перечень, а `mission.01.title` — сверка данных (`title_key`), потому что номер миссии в
## конвейерной константе давал ложный диагноз СЛЕДУЮЩЕЙ миссии (`review-03` §7.5). Цикл
## 14г снимает каждый ключ эталона по одному и требует ровно ОДИН диагноз про него — этим
## покрыты обе половины; положительный ассерт на полном наборе держит список валидатора от
## лишних требований.
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


## Корректная миссия: вход, коридор, цель за запертой дверью, патруль, сенсор, окно,
## объявленный нормативный маршрут.
## Числа и топология минимальны: тест про валидатор, а не про баланс.
##
## Маршрут (`routes`) здесь ОБЯЗАТЕЛЕН: раздел обязателен у формы, и без него фикстура
## перестала бы быть корректной миссией — с неё начались бы все проверки ниже.
## Второй вариант окна несёт эффекты-счётчики и метку (`money`/`trace`/`mark`) — так
## положительный ассерт держит и их приём формой: прежде они жили в разделе
## `access_points`, которого в форме больше нет.
func _good() -> Dictionary:
	return {
		"id": "t_mission",
		"title_key": "mission.01.title",
		"nodes": {
			"entry": {"floor": 1, "tags": ["entry"]},
			"hall": {"floor": 1, "tags": []},
			"vault": {"floor": 1, "tags": ["shielded"]},
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
				{"id": "take_money", "text_key": "window.w_door.money", "complexity": 2,
					"cost": {"noise": 0, "delay": 2},
					"effects": [{"type": "money", "value": 10}, {"type": "trace", "value": 3},
						{"type": "mark", "id": "copy_taken"}]},
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
		"routes": [{"id": "main", "entry": "entry", "exit": "entry",
			"route": ["entry", "hall", "vault", "hall", "entry"]}],
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
		"window.w_door.money": "Снять деньги со счёта.",
		"window.w_door.silence": "Кира обходит.",
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


## Копия корректной миссии с одним подменённым эффектом во ВТОРОМ варианте окна.
##
## Второй вариант (`take_money`) несёт счётчики и метку — тот самый набор эффектов, который
## в форме заменил раздел точек доступа. Хелпер берёт его, а не первый: первый занят
## `unlock`, и подмена эффекта там задела бы правило «unlock у окна не про дверь», то есть
## проверялся бы не тот дефект, который назван в имени ассерта.
##
## Копия делается `duplicate(true)`: кейс не имеет права портить фикстуру, из которой
## строятся все остальные входы файла.
func _with_effect(base: Dictionary, effect: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	((out["windows"] as Array)[0] as Dictionary)["options"][1]["effects"] = [effect]
	return out


## Копия корректной миссии, у которой ЕДИНСТВЕННОЕ окно переведено в «боковой» вид
## (`node_entered` или `guard_in_sensor`) с заданным триггером.
##
## Зачем хелпер. У корректной фикстуры окно висит на ЗАПЕРТОЙ двери, и его эффекты —
## `unlock` того же ребра. Как только окно становится боковым, тот же `unlock` превращается
## в честный диагноз «открывать нечего» (правило одно на все места окна), и он заглушил бы
## тот диагноз, ради которого вход построен. Поэтому эффекты бокового окна приводятся к
## «ничего не открывает»: так у входа остаётся РОВНО ОДИН дефект — тот, что назван в имени
## ассерта. Молчание правится вместе с вариантом: у окна не про дверь `unlock` в любом
## исходе — тот же дефект.
##
## Копия делается `duplicate(true)`: кейс не имеет права портить фикстуру, из которой
## строятся все остальные входы файла.
func _as_side_window(base: Dictionary, kind: String, trigger: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	var w: Dictionary = (out["windows"] as Array)[0]
	w["kind"] = kind
	w["trigger"] = trigger
	for option in (w["options"] as Array):
		(option as Dictionary)["effects"] = [{"type": "noop"}]
	for quality in ["good", "neutral", "bad", "safe"]:
		(w["silence"] as Dictionary)[quality] = [{"type": "noop"}]
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


## Коды проблем РОВНО на пути. Отдельно от `_codes_at`: у раздела `routes` два правила
## пишут на ОДИН путь («повтор id» и «ровно один маршрут на вход»), и префиксная сверка
## вернула бы два кода там, где кейс называет один дефект. Ожидание — точный список кодов
## ровно на этом пути.
func _codes_exactly_at(problems: Array, path: String) -> Array:
	var out: Array = []
	for p in problems:
		if String(p["path"]) == path:
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
			"windows", "intel", "routes"]:
		var m := _good()
		m.erase(field)
		t.is_true("нет %s — MISSING_FIELD" % field, Problems.has(Validator.validate(m, null), Problems.MISSING_FIELD))

	# Предмет здесь — «пустой раздел допустим», а не тексты, поэтому вторым аргументом идёт
	# `null` (явный отказ от сверки). Рукописную фикстуру `_texts_for` сюда передать нельзя:
	# опустошённый раздел уносит с собой свои `*_key`, и фикстура стала бы висячей —
	# кейс краснел бы на DANGLING_TEXT про фикстуру, а не про пустой раздел. Обратное
	# направление (ключ данных без текста и текст без ключа) держит кейс 12.
	for section in ["patrols", "sensors", "windows", "intel"]:
		var empty_section := _good()
		empty_section[section] = []
		t.is_true("пустой %s допустим" % section, Validator.validate(empty_section, null).is_empty())

	var blank_title := _good()
	blank_title["title_key"] = ""
	t.is_true("пустой title_key — BAD_VALUE", Problems.has(Validator.validate(blank_title, null), Problems.BAD_VALUE))

	# C1. Неверный тип необязательного раздела: валидатор обязан назвать болезнь,
	# иначе загрузчик пойдёт циклом по словарю и упадёт внутри цикла.
	for section in ["patrols", "sensors", "windows", "intel"]:
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

	# 3а. РЕШЕНИЕ ПО ДРОБНЫМ ЧИСЛАМ: целое, записанное с точкой, ПРИНИМАЕТСЯ — и это
	# осознанный отказ от строгости, а не недосмотр (см. отчёт 12, раздел D). Причина
	# измерена, а не предположена: разбор JSON отдаёт ВСЕ числа дробными (кейс 3
	# `test_three_paths.gd`), поэтому поставка, прочитанная с диска, состоит из `float`
	# целиком, и строгая проверка объявила бы `WRONG_TYPE` на каждом числе честного
	# уровня (`mission-01.json`) — ложное срабатывание дороже пропуска. Дробное значение
	# при этом по-прежнему отвергается: `1.5` выше.
	#
	# Ассерт держит решение от молчаливого ужесточения: сними терпимость к `TYPE_FLOAT`
	# в `_expect_int`/`_int_or` — и он покраснеет (проба P-D в отчёте).
	var int_as_float := _good()
	int_as_float["patrols"][0]["period"] = 4.0
	t.is_true("целое с точкой (4.0) принимается: JSON не хранит целых иначе",
		Validator.validate(int_as_float, null).is_empty())

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

	# I6б. ЗАМЫКАНИЕ маршрута патруля. Ядро ведёт охранника ПО КРУГУ: индекс растёт по
	# модулю длины списка (`sim/sim.gd:_advance_guards` — `(patrol_index + 1) % size`),
	# поэтому после последней точки идёт первая, и замыкающая пара — такое же ребро
	# маршрута, как соседние. Прежде замыкание не проверялось вовсе: маршрут из трёх
	# помещений без ребра «последнее → первое» считался валидным, и уровень проходил
	# форму с разрывом в цикле (находка 1 отчёта 11, §5.3). В `_good()` есть только рёбра
	# `entry–hall` и `hall–vault`: пары `vault–entry` в графе нет.
	var open_route := _good()
	open_route["patrols"][0]["route"] = ["entry", "hall", "vault"]
	var open_route_problems: Array = Validator.validate(open_route, null)
	t.eq("разомкнутый маршрут патруля — PATROL_ROUTE_OPEN на patrols[0].route",
		_codes_at(open_route_problems, "patrols[0].route"), [Problems.PATROL_ROUTE_OPEN])
	## Диагноз ровно один: соседние пары соединены, и разрыв замыкания не порождает
	## второго сообщения (в том числе тем же кодом, что у соседних пар) — иначе автор
	## искал бы ещё один разрыв маршрута.
	t.eq("разомкнутый маршрут патруля — одна проблема на маршрут",
		_codes(open_route_problems), [Problems.PATROL_ROUTE_OPEN])
	## Сообщение называет ОБЕ точки замыкающей пары — последнюю и первую: по ним автор
	## и находит пару, которой не хватает ребра.
	t.is_true("разомкнутый маршрут — названы последняя и первая точки",
		_message_at(open_route_problems, "patrols[0].route").contains("vault")
		and _message_at(open_route_problems, "patrols[0].route").contains("entry"))

	# Вторая половина правила: тот же маршрут с добавленным замыкающим ребром проходит.
	var closed_route := _good()
	closed_route["edges"].append({"id": "e_vault_entry", "a": "vault", "b": "entry",
		"kind": "corridor", "steps": 1, "noise": 0})
	closed_route["patrols"][0]["route"] = ["entry", "hall", "vault"]
	t.eq("замкнутый маршрут из трёх точек — на маршруте проблем нет",
		_codes_at(Validator.validate(closed_route, null), "patrols[0].route"), [])

	# Маршрут, возвращающийся в первую точку (`a, b, a`), разрыва НЕ содержит: «переход»
	# из точки в неё же ребром не является (петли запрещены), а ядро проходит его как
	# стояние на месте. Без этой половины наивная проверка замыкания требовала бы
	# несуществующего ребра `entry–entry` и краснила честный уровень.
	var there_and_back := _good()
	there_and_back["patrols"][0]["route"] = ["entry", "hall", "entry"]
	t.eq("маршрут «туда и обратно» — не разрыв замыкания",
		_codes_at(Validator.validate(there_and_back, null), "patrols[0].route"), [])

	# I6б-2. Маршрут из ДВУХ точек: соседняя пара и замыкающая — ОДНА И ТА ЖЕ, и второго
	# диагноза на один дефект быть не должно. Здесь эта пара не соединена ребром
	# (`vault–entry` в графе нет: есть только `entry–hall` и `hall–vault`), поэтому разрыв
	# называет `BAD_VALUE` на соседней паре, а `PATROL_ROUTE_OPEN` не выписывается.
	#
	# Сверяется ВЕСЬ список диагнозов маршрута, а не «PATROL_ROUTE_OPEN нет»: отсутствие
	# кода верно и тогда, когда замыкание не проверяется вовсе, — а пара «ровно один
	# `BAD_VALUE`» доказывает, что маршрут разобран и разрыв назван.
	#
	# Проба на НЕСУЩУЮ половину защиты (снят `route_judgeable` из условия замыкания в
	# `validator.gd:_check_patrols`) краснит этот ассерт вторым диагнозом. Условие
	# `size >= 3` пробой НЕ краснеет и держаться ассертом не может: на двухточечном
	# маршруте `_connected` спрашивают про ту же пару, что и выше (ответ «соединены» —
	# иначе разрыв уже назван и `route_judgeable` снят), поэтому замена `size >= 3` на
	# `size >= 1` не меняет НИ ОДНОГО ответа валидатора — это проверено перебором
	# маршрутов всех размеров (раздел D отчёта 15). Так защита и названа в коде.
	var two_point_gap := _good()
	two_point_gap["patrols"][0]["route"] = ["vault", "entry"]
	t.eq("маршрут из двух точек с разрывом — ровно BAD_VALUE о соседней паре, замыкание не судится",
		_codes_at(Validator.validate(two_point_gap, null), "patrols[0].route"), [Problems.BAD_VALUE])

	# I6в. ГРАНИЦА нового правила: замыкание судится только тогда, когда о маршруте можно
	# судить — все узлы существуют и все соседние пары соединены. Здесь у трёхточечного
	# маршрута один узел не существует: `BAD_REF` на нём уже назвал корень, и соседняя пара
	# с ним — тот же корень, а не второй разрыв. До правки сюда добавлялся третий диагноз,
	# `PATROL_ROUTE_OPEN` про замыкающую пару `нет_такого → entry` (находка Minor 3 ревью 4:
	# три диагноза на одну опечатку). Ассерт называет ВЕСЬ список диагнозов маршрута, а не
	# «PATROL_ROUTE_OPEN нет»: отсутствие кода верно и тогда, когда правило выключено вовсе,
	# а пара `BAD_REF` + `BAD_VALUE` доказывает, что маршрут действительно разобран.
	var bad_ref_route := _good()
	bad_ref_route["patrols"][0]["route"] = ["entry", "hall", "нет_такого"]
	var bad_ref_route_problems: Array = Validator.validate(bad_ref_route, null)
	t.eq("опечатка в узле маршрута — только BAD_REF и BAD_VALUE, замыкание не судится",
		_codes_at(bad_ref_route_problems, "patrols[0].route"),
		[Problems.BAD_REF, Problems.BAD_VALUE])

	# I6в-2. Вторая половина того же условия, которую первый ассерт НЕ держит: узел маршрута
	# не существует, но рёбра его «соединяют» — опечатка в id живёт и в маршруте, и в рёбрах
	# (автор переименовал помещение в двух местах, а в `nodes` — нет). Формально все соседние
	# пары соединены, и судить о замыкании можно было бы; но помещения, вокруг которого
	# строится цикл, в файле нет, и корень уже назван `BAD_REF`. Проба A2 (снят флаг на узле)
	# краснит ровно этот ассерт: без узлового флага выходит ещё и `PATROL_ROUTE_OPEN`.
	var ghost_route := _good()
	ghost_route["edges"].append({"id": "e_hall_ghost", "a": "hall", "b": "нет_такого",
		"kind": "corridor", "steps": 1, "noise": 0})
	ghost_route["patrols"][0]["route"] = ["entry", "hall", "нет_такого"]
	t.eq("узел маршрута не существует, хотя рёбра его «соединяют» — замыкание не судится",
		_codes_at(Validator.validate(ghost_route, null), "patrols[0].route"),
		[Problems.BAD_REF])

	# I6г. Сломанный РАЗДЕЛ `edges` (не массив): о рёбрах нечего спросить, и каждая
	# соседняя пара названа `BAD_VALUE`. Замыкание при этом не судится НИ НА ОДНОМ патруле:
	# до правки каждый патруль получал ещё и `PATROL_ROUTE_OPEN` про пару, о которой уже
	# сказано (находка Minor 3 ревью 4, проба C4). Два патруля в фикстуре — чтобы «не выдан
	# ни на одном» не проходило на единственном патруле по случайности.
	var broken_edges := _good()
	broken_edges["patrols"].append({"id": "guard_2", "route": ["entry", "hall", "vault"], "period": 4})
	broken_edges["patrols"][0]["route"] = ["entry", "hall", "vault"]
	broken_edges["edges"] = {}
	var broken_edges_problems: Array = Validator.validate(broken_edges, null)
	t.is_false("раздел edges не массив — PATROL_ROUTE_OPEN не выдан ни на одном патруле",
		Problems.has(broken_edges_problems, Problems.PATROL_ROUTE_OPEN))
	t.eq("раздел edges не массив — разрывы пар первого патруля названы по одному на пару",
		_codes_at(broken_edges_problems, "patrols[0].route"),
		[Problems.BAD_VALUE, Problems.BAD_VALUE])
	t.eq("раздел edges не массив — разрывы пар второго патруля названы так же",
		_codes_at(broken_edges_problems, "patrols[1].route"),
		[Problems.BAD_VALUE, Problems.BAD_VALUE])

	# I6д. Сломанный РАЗДЕЛ `nodes`: о существовании узлов маршрута судить нечем — ссылки
	# `BAD_REF` здесь не выписываются намеренно (иначе пустой раздел дал бы по диагнозу на
	# каждый узел каждого патруля). Раз маршрут называет помещения, которых в файле нет,
	# разрыв замыкания — не отдельный дефект, и `PATROL_ROUTE_OPEN` не выдаётся. Заодно
	# видно число следствий пустого раздела: ровно одно.
	var no_nodes := _good()
	no_nodes["nodes"] = {}
	no_nodes["patrols"][0]["route"] = ["entry", "hall", "vault"]
	var no_nodes_problems: Array = Validator.validate(no_nodes, null)
	t.is_false("раздел nodes пуст — PATROL_ROUTE_OPEN не выдан",
		Problems.has(no_nodes_problems, Problems.PATROL_ROUTE_OPEN))
	t.eq("раздел nodes пуст — о маршруте не сказано ничего",
		_codes_at(no_nodes_problems, "patrols[0].route"), [])
	t.eq("раздел nodes пуст — диагноз один, и он про сам раздел",
		_codes(no_nodes_problems), [Problems.EMPTY_SECTION])

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

	## Вход маршрута — ссылка на помещение, и она проверяется как любая другая: опечатка
	## в имени входа обязана называться `BAD_REF` на своём поле, а не «вход не обслужен»
	## (второго следствия на одну опечатку не выписываем).
	var bad_point := _good()
	bad_point["routes"][0]["entry"] = "нет_такого"
	t.is_true("вход маршрута в пустоту — BAD_REF",
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
	reverse_cut["routes"] = []
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
		_codes_at(Validator.validate(twin_options, null), "windows.w_door.options[2]"), [Problems.DUPLICATE_ID])

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

	# I1б. ПРАВИЛО «unlock у окна не про дверь» РАБОТАЕТ ВО ВСЕХ МЕСТАХ ОКНА, где бывают
	# эффекты, а не только в молчании: `unlock` снимает блокировку с РЕБРА, и у окна
	# `node_entered` / `guard_in_sensor` открывать нечего — ядро эффект применит
	# (`sim/sim.gd:_apply_effect` → `_unlock`), а сцены у двери не будет. Прежде проверка
	# жила только в `_check_silence`, и `unlock` в ВАРИАНТЕ проходил молча (находка 2
	# отчёта 11, §5.3). Перебираются ОБА не-дверных триггера: «группа вошла» и «охранник в зоне» —
	# разные значения одного правила, и «прошло на первом» второго не доказывает.
	for non_door in [{"type": "node_entered", "node": "vault"},
			{"type": "guard_in_sensor", "sensor": "s_hall"}]:
		var window_kind := String(non_door["type"])
		var unlock_option := _good()
		unlock_option["windows"][0]["kind"] = window_kind
		unlock_option["windows"][0]["trigger"] = non_door
		## Молчание приводится к «не открывает ничего»: предмет кейса — ВАРИАНТ, и лишние
		## диагнозы молчания сделали бы список проблем нечитаемым.
		for quality in ["good", "neutral", "bad", "safe"]:
			unlock_option["windows"][0]["silence"][quality] = [{"type": "delay", "value": 3}]
		var option_problems: Array = Validator.validate(unlock_option, null)
		t.eq("unlock в варианте окна «%s» — BAD_VALUE на поле эффектов" % window_kind,
			_codes_at(option_problems, "windows.w_door.options[0].effects"), [Problems.BAD_VALUE])
		## Ровно одна проблема: у одного дефекта одно следствие — `UNWINNABLE_EDGE` окну не
		## про дверь не выписывается вовсе, а форма эффекта верна.
		t.eq("unlock в варианте окна «%s» — ровно одна проблема" % window_kind,
			_codes(option_problems), [Problems.BAD_VALUE])

	# …и в молчании тот же код на своём пути: прежняя половина правила не сломана, а оба
	# места окна называет ОДИН хелпер (`_check_unlock_needs_door`).
	var unlock_silence_path := _good()
	unlock_silence_path["windows"][0]["kind"] = "node_entered"
	unlock_silence_path["windows"][0]["trigger"] = {"type": "node_entered", "node": "vault"}
	unlock_silence_path["windows"][0]["options"][0]["effects"] = [{"type": "delay", "value": 1}]
	t.eq("unlock в молчании окна не про дверь — BAD_VALUE на исходе",
		_codes_at(Validator.validate(unlock_silence_path, null), "windows.w_door.silence.good"),
		[Problems.BAD_VALUE])

	# …и на уровень глубже: `fallback` заявки движку открывает ребро тем же `unlock`, и у
	# окна не про дверь открывать так же нечего. Читаются ОБЕ формы `fallback` (§7) —
	# одиночный эффект и массив: «прошло на первой» вторую не доказывает, а приводит их
	# к списку одно место (`_as_effect_list`, как у `_check_fallback`).
	for nested in [{"type": "unlock", "edge": "e_hall_vault"},
			[{"type": "unlock", "edge": "e_hall_vault"}]]:
		var unlock_fallback := _good()
		unlock_fallback["windows"][0]["kind"] = "node_entered"
		unlock_fallback["windows"][0]["trigger"] = {"type": "node_entered", "node": "vault"}
		unlock_fallback["windows"][0]["options"][0]["effects"] = [{
			"type": "engine_proposal", "id": "hold_door", "want": "дверь открыта",
			"needs": "таймер возврата", "fallback": nested,
		}]
		for quality in ["good", "neutral", "bad", "safe"]:
			unlock_fallback["windows"][0]["silence"][quality] = [{"type": "delay", "value": 3}]
		t.eq("unlock в fallback (%s) окна не про дверь — BAD_VALUE на поле fallback"
			% ("массив" if typeof(nested) == TYPE_ARRAY else "одиночный эффект"),
			_codes_at(Validator.validate(unlock_fallback, null),
				"windows.w_door.options[0].effects[0].fallback"), [Problems.BAD_VALUE])

	# Испорченный триггер: корень уже назван на `trigger.type`, и об эффектах варианта не
	# судим — второго следствия одному дефекту не выписываем (шапка валидатора).
	var broken_trigger_options := _good()
	broken_trigger_options["windows"][0]["trigger"] = {"type": "магия"}
	t.eq("испорченный триггер — эффекты варианта не судятся вторым диагнозом",
		_codes_at(Validator.validate(broken_trigger_options, null),
			"windows.w_door.options[0].effects"), [])

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

	# 10. НОРМАТИВНЫЕ МАРШРУТЫ (проверки формы v3). Прежде этот номер занимали точки доступа
	# (`access_points`), которых в форме больше НЕТ: раздел, который ядро не исполняет вовсе,
	# не имеет права приниматься (иначе уровень обещает механику, которой нет), а действие у
	# терминала выражается вариантом окна. Здесь — обратная сторона той же правки: у уровня
	# появился ОБЯЗАТЕЛЬНЫЙ раздел маршрутов, и каждое его правило держится своим ассертом.
	#
	# Правила маршрутов называются РАЗНЫМИ кодами по той же причине, что и три диагноза
	# «окно невозможно»: правки у автора разные (дописать вход, сменить конец, соединить
	# пару, провести маршрут через цель), и общий код заставлял бы угадывать причину.

	## Положительная половина: у корректной миссии маршрут ОДИН на единственный вход, он
	## начинается и кончается входом и проходит через цель. Ассерт держит и сам факт
	## «проверка не краснит честные данные»: без него все отрицательные ниже могли бы
	## проходить на правиле, которое краснит вообще всё.
	t.eq("объявленный маршрут на единственный вход проходит",
		Validator.validate(_good(), _texts_for(_good())), [])

	## Диагноз «вход не обслужен» — на пустом разделе. Ассерт НЕ вырожден: проба «снять
	## проверку покрытия» краснит ровно его, а «пустой routes допустим» — не проходит.
	var no_routes := _good()
	no_routes["routes"] = []
	t.eq("нет маршрута для входа — ROUTES_PER_ENTRY на разделе",
		_codes_at(Validator.validate(no_routes, null), "routes"), [Problems.ROUTES_PER_ENTRY])
	t.is_true("нет маршрута для входа — сообщение называет вход",
		_message_at(Validator.validate(no_routes, null), "routes").contains("entry"))

	## И обратная половина того же решения: `routes` — ОБЯЗАТЕЛЬНЫЙ раздел, поэтому
	## «пустой массив» здесь НЕ «нормальная миссия без маршрутов», а дефект. Ассерт держит
	## именно это от молчаливого возврата раздела в необязательные.
	var empty_routes := _good()
	empty_routes["routes"] = []
	t.is_true("пустой routes — не «нет маршрутов», а ROUTES_PER_ENTRY",
		Problems.has(Validator.validate(empty_routes, null), Problems.ROUTES_PER_ENTRY))

	## Вторая половина того же правила: маршрутов у входа БОЛЬШЕ одного. Это тот же код, но
	## другая правка (убрать лишний маршрут), и сообщение обязано называть её СЛОВАМИ.
	var twin_routes := _good()
	twin_routes["routes"].append({"id": "second", "entry": "entry", "exit": "entry",
		"route": ["entry", "hall", "vault", "hall", "entry"]})
	t.eq("два маршрута у одного входа — ROUTES_PER_ENTRY на разделе",
		_codes_at(Validator.validate(twin_routes, null), "routes"), [Problems.ROUTES_PER_ENTRY])
	t.is_true("два маршрута у одного входа — сообщение говорит «больше одного»",
		_message_at(Validator.validate(twin_routes, null), "routes").contains("больше одного"))

	## `entry`/`exit` — узлы С ТЕГОМ entry, а не просто существующие помещения: в MVP
	## выходом служит один из входов («уходишь тем путём, каким вошёл»). Узел `vault`
	## существует, и `BAD_REF` на нём не выписывается — дефект в другом, и код свой.
	for side in ["entry", "exit"]:
		var not_entry := _good()
		not_entry["routes"][0][side] = "vault"
		t.eq("%s маршрута без тега entry — ROUTE_END_NOT_ENTRY на своём поле" % side,
			_codes_at(Validator.validate(not_entry, null), "routes[0].%s" % side),
			[Problems.ROUTE_END_NOT_ENTRY])
	var exit_not_entry := _good()
	exit_not_entry["routes"][0]["exit"] = "vault"
	var exit_not_entry_problems: Array = Validator.validate(exit_not_entry, null)
	t.is_true("конец маршрута без тега entry — сообщение называет роль и узел",
		_message_at(exit_not_entry_problems, "routes[0].exit").contains("выход")
		and _message_at(exit_not_entry_problems, "routes[0].exit").contains("vault"))

	## M5 ревью 01–04: ОДНА правка автора (сменить `exit`) даёт ДВА диагноза — и оба
	## уместны. Решение: парный диагноз не гасится, потому что это ДВА РАЗНЫХ ФАКТА о
	## данных, а не следствие одного: «объявленный выход — помещение без тега entry»
	## (правится поле `exit`) и «список кончается не на объявленном выходе» (правится
	## список). Каждый из них бывает БЕЗ второго — обе половины проверены рядом: здесь
	## (переехали и поле, и список) и ниже (`wrong_tail`: поле верное, список устарел).
	## От каскада, который валидатор ГАСИТ (нечитаемый `route` — тогда «соседние пары» и
	## «цель на маршруте» не судятся вовсе), это отличается тем, что оба факта читаемы и
	## оба верны; свернув их в один, валидатор заставил бы автора угадывать, какое из двух
	## расхождений он видит. Ассерт держит ИМЕННО ПАРУ и оба её пути: выпадение любой из
	## половин — провал с названным списком.
	t.eq("exit без тега entry при устаревшем списке — два диагноза, каждый на своём пути (M5)",
		_paths(exit_not_entry_problems), ["routes[0].exit", "routes[0].route"])
	t.eq("…и коды у них разные: ROUTE_END_NOT_ENTRY на поле, BAD_VALUE на списке",
		_codes(exit_not_entry_problems),
		[Problems.ROUTE_END_NOT_ENTRY, Problems.BAD_VALUE])
	var moved_both := _good()
	moved_both["routes"][0]["exit"] = "vault"
	moved_both["routes"][0]["route"] = ["entry", "hall", "vault", "hall", "vault"]
	t.eq("выход не вход, а список своему выходу верен — только ROUTE_END_NOT_ENTRY",
		_codes(Validator.validate(moved_both, null)), [Problems.ROUTE_END_NOT_ENTRY])

	## Концы СПИСКА обязаны совпасть с объявленными `entry`/`exit`: иначе норматив считается
	## не по тому прохождению, которое объявлено. Обе половины проверяются отдельно —
	## «начало» и «конец» это два разных поля, и одно правило их не покрывает.
	var swapped := _good()
	swapped["routes"][0]["route"] = ["hall", "entry", "hall", "vault", "hall", "entry"]
	t.eq("список начинается не с объявленного входа — BAD_VALUE на route",
		_codes_at(Validator.validate(swapped, null), "routes[0].route"), [Problems.BAD_VALUE])
	var wrong_tail := _good()
	wrong_tail["routes"][0]["route"] = ["entry", "hall", "vault", "hall"]
	## Вторая половина пары M5 (см. выше): поле `exit` верное, устарел список — и диагноз
	## выписывается ОДИН, без `ROUTE_END_NOT_ENTRY`. Тем и доказано, что пара выше — не
	## каскад: каждый факт живёт без второго.
	t.eq("список кончается не на объявленном выходе — BAD_VALUE на route",
		_codes_at(Validator.validate(wrong_tail, null), "routes[0].route"), [Problems.BAD_VALUE])
	t.eq("список кончается не на объявленном выходе — и только он, без диагноза про вход",
		_codes(Validator.validate(wrong_tail, null)), [Problems.BAD_VALUE])

	## Пустой список помещений: `route[0]` не существует вовсе, и сравнивать концы не с чем.
	## Это не падение валидатора, а названный дефект: ассерт держит ЗАЩИТУ от `route[0]`
	## на пустом массиве (без неё движок печатает `Invalid access of index '0'` и прогон
	## остаётся зелёным — ровно тот класс, что закрыт у патрулей).
	var empty_route := _good()
	empty_route["routes"][0]["route"] = []
	var empty_route_problems: Array = Validator.validate(empty_route, null)
	t.eq("пустой маршрут — BAD_VALUE на route, а не падение",
		_codes_at(empty_route_problems, "routes[0].route"), [Problems.BAD_VALUE])
	t.is_true("пустой маршрут — сообщение называет, чем обязаны быть концы",
		_message_at(empty_route_problems, "routes[0].route").contains("route[0]"))

	## Соседние точки обязаны быть соединены ребром: маршрут — прохождение ПО ГРАФУ, и
	## разрыв означает, что объявленный проход невыполним, а норматив посчитан по
	## несуществующему пути. Диагноз выписывается на КАЖДУЮ разорванную пару, и пара
	## называется обеими точками: сообщение о паре, которой автор не писал, отправляло бы
	## его чинить несуществующий разрыв.
	var broken_pass := _good()
	broken_pass["routes"][0]["route"] = ["entry", "vault", "entry"]
	var broken_pass_problems: Array = Validator.validate(broken_pass, null)
	t.eq("разрыв нормативного маршрута — по диагнозу на разорванную пару",
		_codes_at(broken_pass_problems, "routes[0].route"),
		[Problems.BAD_VALUE, Problems.BAD_VALUE])
	t.is_true("разрыв маршрута — сообщение называет ОБЕ точки пары",
		_message_at(broken_pass_problems, "routes[0].route").contains("«entry»")
		and _message_at(broken_pass_problems, "routes[0].route").contains("«vault»"))
	t.is_true("разрыв маршрута — проблема НЕ выписана входам и цели",
		not Problems.has(broken_pass_problems, Problems.WINDOW_ON_ENTRY_NODE))

	## Цель обязана лежать на маршруте: норматив «окон за прохождение» считается по проходам,
	## которые ВЕДУТ к цели. Маршрут при этом полностью корректен по рёбрам и концам — и
	## именно поэтому у него свой код: правка «провести маршрут через цель».
	var off_route := _good()
	off_route["routes"][0]["route"] = ["entry", "hall", "entry"]
	t.eq("цель не лежит на маршруте — OBJECTIVE_OFF_ROUTE на разделе",
		_codes_at(Validator.validate(off_route, null), "routes"), [Problems.OBJECTIVE_OFF_ROUTE])
	t.is_true("цель не на маршруте — сообщение называет цель и маршрут",
		_message_at(Validator.validate(off_route, null), "routes").contains("vault")
		and _message_at(Validator.validate(off_route, null), "routes").contains("main"))

	## id маршрута повторяется — тот же `DUPLICATE_ID`, что у остальных разделов: инструмент
	## приёмки печатает маршруты по id, и два одинаковых имени в отчёте неразличимы.
	##
	## Двойник берётся ПОЛНОЙ копией, но ОБЪЯВЛЕННЫЕ КОНЦЫ у него свои (`vault`), и список
	## помещений им соответствует. Так повтор имени остаётся ЕДИНСТВЕННЫМ дефектом: копия с
	## тем же входом задела бы ещё и «ровно один маршрут на вход» — и ассерт проверял бы не
	## то, что называет. Проверка идёт РОВНО по пути раздела (`_codes_exactly_at`), потому
	## что оба правила пишут на один путь, и это здесь названо прямо.
	var dup_route := _good()
	var twin_route: Dictionary = (_good()["routes"][0] as Dictionary).duplicate(true)
	twin_route["entry"] = "vault"
	twin_route["exit"] = "vault"
	twin_route["route"] = ["vault", "hall", "entry", "hall", "vault"]
	dup_route["routes"].append(twin_route)
	t.eq("повтор id маршрута — DUPLICATE_ID на разделе",
		_codes_exactly_at(Validator.validate(dup_route, null), "routes"), [Problems.DUPLICATE_ID])

	## Неизвестное поле маршрута: опечатка в имени («path» вместо «route») обязана называться,
	## а не выглядеть как «маршрута нет».
	var unknown_route_key := _good()
	unknown_route_key["routes"][0]["path"] = ["entry", "hall"]
	t.eq("неизвестное поле маршрута — UNKNOWN_KEY на своём пути",
		_codes_at(Validator.validate(unknown_route_key, null), "routes[0].path"),
		[Problems.UNKNOWN_KEY])

	# 10а. ТРИ ДИАГНОЗА «ОКНО НЕВОЗМОЖНО». Каждый — про окно, описанное в данных, которое
	# не сработает НИ ПРИ КАКОМ прохождении. Прогон такое окно ловит только если
	# построенный маршрут вообще доходит до его якоря, а форма обязана не пускать дефект
	# в работу: приёмка v2 нашла два таких окна прогоном именно потому, что статически
	# их не называл никто. Три ассерта ниже держат три РАЗНЫХ кода — по одному на диагноз.

	## (1) `guard_in_sensor`, чью зону не посещает НИ ОДИН патруль. Все описанные в ошибке
	## вещи существуют и ДОСТИЖИМЫ: помещение `o1` стоит в графе и соединено с холлом,
	## сенсор `s_far` на него ссылается. Корень ровно один — патруль в зону не заходит, и
	## контакта там не бывает никогда: сенсорные контакты ядро выдаёт ТОЛЬКО охране.
	## Достижимость здесь несущая: сделай `o1` отрезанным — и к диагнозу добавился бы
	## третий («якорь недостижим»), то есть ассерт проверял бы два дефекта вместо одного.
	var unvisited := _good()
	unvisited["nodes"]["o1"] = {"floor": 1, "tags": []}
	unvisited["edges"].append({"id": "e_hall_o1", "a": "hall", "b": "o1",
		"kind": "corridor", "steps": 1, "noise": 0})
	unvisited["sensors"].append({"id": "s_far", "nodes": ["o1"]})
	unvisited["windows"][0] = _as_side_window(unvisited, "guard_in_sensor",
		{"type": "guard_in_sensor", "sensor": "s_far"})["windows"][0]
	var unvisited_problems: Array = Validator.validate(unvisited, null)
	t.eq("сенсор без патруля — WINDOW_ON_UNVISITED_SENSOR на поле сенсора",
		_codes_at(unvisited_problems, "windows.w_door.trigger.sensor"),
		[Problems.WINDOW_ON_UNVISITED_SENSOR])
	t.is_true("сенсор без патруля — сообщение называет сенсор и его зону",
		_message_at(unvisited_problems, "windows.w_door.trigger.sensor").contains("s_far")
		and _message_at(unvisited_problems, "windows.w_door.trigger.sensor").contains("o1"))
	t.is_true("сенсор без патруля — диагноз ровно один (якорь достижим, окно боковое)",
		unvisited_problems.size() == 1)

	## Положительный контроль к нему: тот же сенсор, но патруль через его зону — чисто.
	## Без этой половины правило могло бы краснить любой сенсор, и предыдущий ассерт этого
	## не заметил бы. Окно приводится к «боковому» виду (`_as_side_window`): у окна не про
	## дверь `unlock` открывать нечего, и лишние диагнозы сделали бы контроль нечитаемым.
	var visited := _as_side_window(_good(), "guard_in_sensor", {"type": "guard_in_sensor", "sensor": "s_hall"})
	visited["patrols"][0]["route"] = ["hall", "entry"]
	t.eq("патруль через зону сенсора — окно живо",
		Validator.validate(visited, _texts_for(visited)), [])

	## Зона из НЕСКОЛЬКИХ помещений: патруль в одном из них оживляет окно (считается
	## ОБЪЕДИНЕНИЕ маршрутов, а не «все помещения»). Второе помещение зоны стоит в графе,
	## и патруль ходит именно через него — ровно тот случай, ради которого объединение
	## и берётся: первое помещение зоны охрана не посещает вовсе.
	var zone := _good()
	zone["nodes"]["o2"] = {"floor": 1, "tags": []}
	zone["edges"].append({"id": "e_hall_o2", "a": "hall", "b": "o2", "kind": "corridor", "steps": 1, "noise": 0})
	zone["sensors"].append({"id": "s_pair", "nodes": ["o2"]})
	zone["windows"][0] = _as_side_window(zone, "guard_in_sensor",
		{"type": "guard_in_sensor", "sensor": "s_pair"})["windows"][0]
	zone["patrols"].append({"id": "guard_2", "route": ["o2", "hall"], "period": 4})
	var zone_problems: Array = Validator.validate(zone, null)
	t.is_false("патруль во втором помещении зоны оживляет окно",
		Problems.has(zone_problems, Problems.WINDOW_ON_UNVISITED_SENSOR))
	t.eq("зона, посещаемая патрулём, — других диагнозов нет",
		zone_problems, [])

	## (2) `node_entered` на помещении с тегом `entry`: группа там СТАРТУЕТ, и события
	## `agent_moved` в этот узел на входе не бывает. Сцена входа ставится на первое
	## помещение ВНУТРИ — так сделано для главного входа и НЕ было сделано для дока.
	var on_entry := _as_side_window(_good(), "node_entered", {"type": "node_entered", "node": "entry"})
	t.eq("окно входа на самом входе — WINDOW_ON_ENTRY_NODE на поле узла",
		_codes_at(Validator.validate(on_entry, null), "windows.w_door.trigger.node"),
		[Problems.WINDOW_ON_ENTRY_NODE])
	t.is_true("окно входа на входе — сообщение называет узел и причину",
		_message_at(Validator.validate(on_entry, null), "windows.w_door.trigger.node").contains("entry")
		and _message_at(Validator.validate(on_entry, null), "windows.w_door.trigger.node").contains("стартует"))

	## Положительный контроль: то же окно, но на первом помещении ВНУТРИ — чисто.
	var inside := _as_side_window(_good(), "node_entered", {"type": "node_entered", "node": "hall"})
	t.eq("окно входа на первом помещении внутри — живо",
		Validator.validate(inside, _texts_for(inside)), [])

	## (3) Якорь окна недостижим от объявленных входов по рёбрам. Проверяются ДВА ВИДА
	## якоря (помещение и ребро), потому что «достижим» — это свойство ГРАФА, и вывод «оба
	## конца достижимы, значит и ребро» здесь был бы догадкой. Якорь помещается в
	## отрезанный компонент: ребро `e_hall_vault` соединяет `hall` и `vault`, и до них от
	## входа `entry` пути нет (ребро `e_entry_hall` из графа убрано).
	##
	## Маршрут при этом остаётся ОБЪЯВЛЕННЫМ и корректным по концам — иначе к диагнозу
	## «якорь недостижим» добавился бы «вход не обслужен», и ассерт проверял бы два
	## дефекта вместо одного.
	for anchor in [{"type": "node_entered", "node": "vault"}, {"type": "locked_edge", "edge": "e_hall_vault"}]:
		var unreachable := _as_side_window(_good(), String(anchor["type"]), anchor)
		unreachable["edges"] = [{"id": "e_hall_vault", "a": "hall", "b": "vault",
			"kind": "door", "steps": 1, "noise": 0, "locked": true}]
		unreachable["sensors"] = []
		unreachable["patrols"] = []
		unreachable["routes"][0]["route"] = ["entry", "hall", "entry"]
		var unreachable_problems: Array = Validator.validate(unreachable, null)
		t.eq("якорь окна «%s» отрезан от входов — WINDOW_ON_UNREACHABLE_NODE" % String(anchor["type"]),
			_codes_at(unreachable_problems, "windows.w_door.trigger"),
			[Problems.WINDOW_ON_UNREACHABLE_NODE])

	## I2: окно `guard_in_sensor` НЕДОСТИЖИМОСТЬЮ ОТ ВХОДОВ НЕ СУДИТСЯ, и это проверяется
	## ЗАКОННЫМ уровнем. Актёр этого окна — ОХРАНА: она стартует на своём маршруте
	## (`sim.gd:setup` ставит её в `route[0]`) и приходит в зону не от входа. Крыло,
	## отрезанное от входов, но со своим патрулём и сенсором, — рабочий уровень: проба
	## ревью показала, что окно там срабатывает на первом шаге, а прежняя форма выписывала
	## ему `WINDOW_ON_UNREACHABLE_NODE` и отвергала уровень зря.
	##
	## Половины две, и обе несущие: (1) зона отрезана от входов, патруль по ней ходит —
	## диагнозов нет вовсе; (2) тот же патруль снят с зоны — диагноз есть, но СВОЙ
	## (`WINDOW_ON_UNVISITED_SENSOR`). Вместе они показывают и «мёртвый сенсор ловится»,
	## и «недостижимость к охраннику не применяется».
	var wing := _good()
	wing["nodes"]["wing1"] = {"floor": 1, "tags": []}
	wing["nodes"]["wing2"] = {"floor": 1, "tags": []}
	## Крыло соединено само с собой и НЕ соединено с `entry`: от входов до него не дойти.
	wing["edges"].append({"id": "e_wing1_wing2", "a": "wing1", "b": "wing2",
		"kind": "corridor", "steps": 1, "noise": 0})
	wing["patrols"][0]["route"] = ["wing1", "wing2"]
	wing["sensors"].append({"id": "s_wing", "nodes": ["wing2"]})
	wing["windows"][0] = _as_side_window(wing, "guard_in_sensor",
		{"type": "guard_in_sensor", "sensor": "s_wing"})["windows"][0]
	t.eq("крыло отрезано от входов, но патруль в зоне — окно охраны живо, диагнозов нет",
		Validator.validate(wing, null), [])
	## Вторая половина: патруль ушёл из зоны — и назван ровно один диагноз, про сенсор.
	wing["patrols"][0]["route"] = ["hall", "entry"]
	var wing_dead_problems: Array = Validator.validate(wing, null)
	t.eq("патруль вне зоны отрезанного крыла — WINDOW_ON_UNVISITED_SENSOR на поле сенсора",
		_codes_at(wing_dead_problems, "windows.w_door.trigger.sensor"),
		[Problems.WINDOW_ON_UNVISITED_SENSOR])
	t.is_true("мёртвый сенсор в отрезанном крыле — WINDOW_ON_UNREACHABLE_NODE не выписан",
		not Problems.has(wing_dead_problems, Problems.WINDOW_ON_UNREACHABLE_NODE))

	# 10б. ТЕГ `shielded` (экранированное помещение) — известен форме и не диагноз.
	# Проверяется ОБЕ половины: тег принят, и он не ломает остальные проверки узла.
	# Перечня допустимых тегов у формы НЕТ намеренно (тег читает ядро по имени): закрытый
	# список отверг бы честный новый тег и требовал бы правки валидатора ради данных.
	var shielded := _good()
	shielded["nodes"]["hall"]["tags"] = ["shielded"]
	t.eq("тег shielded принимается и миссия остаётся валидной",
		Validator.validate(shielded, _texts_for(shielded)), [])
	t.is_false("тег shielded — не неизвестный ключ",
		Problems.has(Validator.validate(shielded, null), Problems.UNKNOWN_KEY))
	var bad_tags := _good()
	bad_tags["nodes"]["hall"]["tags"] = ["shielded", 5]
	t.eq("не-строка в тегах — WRONG_TYPE на своём элементе",
		_codes_at(Validator.validate(bad_tags, null), "nodes.hall.tags[1]"), [Problems.WRONG_TYPE])

	# 10в. ЭФФЕКТЫ-СЧЁТЧИКИ И МЕТКА. Форма обязана их ПРИНИМАТЬ и проверять типы полей:
	# эффект, который «принят, но не понят», — это ровно тот класс, из-за которого раздел
	# точек доступа ушёл из формы. `money`/`trace` несут `value`, `mark` — строковый `id`.
	#
	# M6: СПИСОК видов эффектов — СПРОШЕННЫЙ у ядра, а не своя копия. Сверка идёт с эталоном
	# (`EFFECT_KINDS`) с обеих сторон, поэтому ловит и пропажу вида из ядра, и лишний вид
	# в форме. Без первой половины вторая ничего не доказывала бы: обе стороны сравнения
	# были бы одним и тем же списком формы.
	t.eq("виды эффектов у ядра — эталон: ни один не пропал и ни один не появился лишним",
		Sim.EFFECT_TYPES, EFFECT_KINDS)
	t.eq("форма берёт виды эффектов у ядра, а не держит свою копию",
		Validator.EFFECT_TYPES, EFFECT_KINDS)
	for broken_effect in [{"type": "money"}, {"type": "trace"},
			{"type": "money", "value": "много"}, {"type": "trace", "value": -1},
			{"type": "mark"}, {"type": "mark", "id": 5}]:
		var broken_window := _good()
		broken_window["windows"][0]["options"][1]["effects"] = [broken_effect]
		var effect_problems: Array = Validator.validate(broken_window, null)
		t.is_true("испорченный эффект %s назван на своём поле" % str(broken_effect),
			not _codes_at(effect_problems, "windows.w_door.options[1].effects").is_empty())
	t.eq("деньги без value — MISSING_FIELD на своём пути",
		_codes_at(Validator.validate(_with_effect(_good(), {"type": "money"}), null),
			"windows.w_door.options[1].effects[0].value"), [Problems.MISSING_FIELD])
	t.eq("метка без id — MISSING_FIELD на своём пути",
		_codes_at(Validator.validate(_with_effect(_good(), {"type": "mark"}), null),
			"windows.w_door.options[1].effects[0].id"), [Problems.MISSING_FIELD])
	t.eq("метка с числовым id — WRONG_TYPE на своём пути",
		_codes_at(Validator.validate(_with_effect(_good(), {"type": "mark", "id": 5}), null),
			"windows.w_door.options[1].effects[0].id"), [Problems.WRONG_TYPE])

	# 10г. ПРИЗРАК ОБЯЗАН РАСХОДИТЬСЯ С РЕАЛЬНОСТЬЮ ПО ОБОИМ ПРИЗНАКАМ (D48). Сцена «призрак
	# разошёлся» — единственный индикатор тревоги в игре, и предусматривается она ДАННЫМИ:
	# маршрутом и периодом. Отличий два, и КАЖДОЕ обязательно: совпавший маршрут исчезает
	# через такт, а совпавший период виден только по времени. Поэтому диагноз выписывается на
	# ЛЮБОЕ совпадение, и проверяются ВСЕ ТРИ случая — копия, тот же маршрут, тот же период.
	# Прежняя редакция держала обратное («совпал ровно один — расхождение есть») и была слабее
	# решения; канонический контент проходил именно этой слабостью (C1 ревью 01–04).
	#
	# Настоящий патруль фикстуры — `guard_1`, маршрут `["hall", "entry"]`, период 4.
	var ghost := _good()
	ghost["intel"] = [{"channel": "hack", "observed_at": 0, "entries": [
		{"kind": "patrol", "id": "guard_1", "route": ["hall", "entry"], "period": 4,
			"age_hours": 8, "false": false}]}]
	var ghost_problems: Array = Validator.validate(ghost, null)
	t.eq("призрак дословно равен реальному патрулю — GHOST_SAME_AS_REAL на пункте",
		_codes_at(ghost_problems, "intel[0].entries[0]"), [Problems.GHOST_SAME_AS_REAL])
	t.is_true("призрак равен реальности — сообщение называет патруль, оба совпадения и период",
		_message_at(ghost_problems, "intel[0].entries[0]").contains("guard_1")
		and _message_at(ghost_problems, "intel[0].entries[0]").contains("и маршрут, и период")
		and _message_at(ghost_problems, "intel[0].entries[0]").contains("период 4"))

	## Тот же МАРШРУТ, другой период: путь призрака совпал с реальным и исчезнет через такт.
	var same_route := _good()
	same_route["intel"] = [{"channel": "hack", "observed_at": 0, "entries": [
		{"kind": "patrol", "id": "guard_1", "route": ["hall", "entry"], "period": 5,
			"age_hours": 8, "false": false}]}]
	var same_route_problems: Array = Validator.validate(same_route, null)
	t.eq("тот же маршрут при другом периоде — GHOST_SAME_AS_REAL на пункте",
		_codes_at(same_route_problems, "intel[0].entries[0]"), [Problems.GHOST_SAME_AS_REAL])
	t.is_true("совпал маршрут — сообщение называет именно маршрут",
		_message_at(same_route_problems, "intel[0].entries[0]").contains("маршрут совпал"))

	## Другой маршрут, ТОТ ЖЕ период: расхождение видно только по времени, и его тоже нет.
	var same_period := _good()
	same_period["intel"] = [{"channel": "hack", "observed_at": 0, "entries": [
		{"kind": "patrol", "id": "guard_1", "route": ["entry", "hall"], "period": 4,
			"age_hours": 8, "false": false}]}]
	var same_period_problems: Array = Validator.validate(same_period, null)
	t.eq("тот же период при другом маршруте — GHOST_SAME_AS_REAL на пункте",
		_codes_at(same_period_problems, "intel[0].entries[0]"), [Problems.GHOST_SAME_AS_REAL])
	t.is_true("совпал период — сообщение называет именно период",
		_message_at(same_period_problems, "intel[0].entries[0]").contains("период совпал"))

	## Оба признака разные — расхождение полное, и диагноза нет. Положительный контроль:
	## без него три ассерта выше держали бы «правило краснит всякий пункт разведки».
	var both_differ := _good()
	both_differ["intel"] = [{"channel": "hack", "observed_at": 0, "entries": [
		{"kind": "patrol", "id": "guard_1", "route": ["entry", "hall"], "period": 5,
			"age_hours": 8, "false": false}]}]
	t.is_false("другой маршрут И другой период — расхождения достаточно, диагноза нет",
		Problems.has(Validator.validate(both_differ, null), Problems.GHOST_SAME_AS_REAL))

	## Несуществующий патруль — `BAD_REF`, и НЕ `GHOST_SAME_AS_REAL`: сравнивать не с чем,
	## и второго следствия на одну опечатку не выписываем.
	var ghost_missing := _good()
	ghost_missing["intel"] = [{"channel": "hack", "observed_at": 0, "entries": [
		{"kind": "patrol", "id": "guard_нет", "route": ["hall", "entry"], "period": 4,
			"age_hours": 8, "false": false}]}]
	var ghost_missing_problems: Array = Validator.validate(ghost_missing, null)
	t.is_true("призрак ссылается на несуществующий патруль — BAD_REF",
		Problems.has(ghost_missing_problems, Problems.BAD_REF))
	t.is_false("несуществующий патруль — GHOST_SAME_AS_REAL не выписан",
		Problems.has(ghost_missing_problems, Problems.GHOST_SAME_AS_REAL))
	# P8. Тип в MISSING_FIELD — по ФАКТУ поля, а не общий «String». Прежнее отсутствие
	# `effects` (массив), `cost` (словарь) и `complexity` (число) обещало строку: тесты
	# сверяли код и путь, поэтому ложь в сообщении не ловилась (класс M3). Корпус нормы имён
	# типов (кейс 13) собирается из этих же входов: пропажа любого из них оставила бы норму
	# без части корпуса — а она проверяет КАЖДОЕ сообщение `MISSING_FIELD`/`WRONG_TYPE`.
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

	## Тип в сообщении берётся ПО ФАКТУ поля и у второго варианта окна: `complexity` —
	## целое, `effects` — массив, `cost` — словарь. Прежде эта половина держалась на
	## действиях точки доступа, которых в форме больше нет; проверка переехала на вариант
	## окна, а не пропала — иначе норма имён типов осталась бы без части своего корпуса.
	var no_option_complexity := _good()
	no_option_complexity["windows"][0]["options"][1].erase("complexity")
	t.is_true("нет options[].complexity — обещано целое",
		_message_at(Validator.validate(no_option_complexity, null),
			"windows.w_door.options[1].complexity").contains("целое"))

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
	#
	# Период здесь отличается от реального (`5` против `4`) НАМЕРЕННО: с D48 совпадение
	# ЛЮБОГО признака — свой диагноз (`GHOST_SAME_AS_REAL`), и при совпавшем периоде этот
	# вход краснел бы вторым следствием, а проверяется на нём ровно одно — что несуществующее
	# помещение в маршруте призрака диагноза НЕ даёт.
	var ghost_route_unknown_node := _good()
	ghost_route_unknown_node["intel"] = [{"channel": "hack", "observed_at": 0,
		"entries": [{"kind": "patrol", "id": "guard_1", "route": ["hall", "этаж_которого_нет"],
			"period": 5, "age_hours": 8, "false": false}]}]
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

	# 11а. КАНАЛ ОБЯЗАН БЫТЬ ИЗ ПЕРЕЧНЯ. Значение `channel` адресует блок данных каналу на
	# экране и ключам пояснений `intel.<канал>.<пометка>`; опечатка («agentss») проходила
	# молча, и данные приезжали, не попав ни в один канал (находка 3 отчёта 11, §5.3). Перечень —
	# `docs/spr/channels.md` §2: дрон, агентура, взлом. Имена каналов здесь написаны
	# ЛИТЕРАЛАМИ, а не взяты у валидатора: эталон, производный от проверяемого, не поймал бы
	# ни одного канала, выпавшего из списка (`review-checklist.md` §2).
	for channel in ["drone", "agents", "hack"]:
		var known_channel := _good()
		known_channel["intel"] = [{"channel": channel, "observed_at": 0,
			"entries": [{"kind": "sensor", "nodes": ["hall"], "age_hours": 6,
				"false": channel == "agents"}]}]
		t.eq("канал «%s» из перечня проходит" % channel,
			Validator.validate(known_channel, null), [])

	var unknown_channel := _good()
	unknown_channel["intel"][0]["channel"] = "agentss"
	var unknown_channel_problems: Array = Validator.validate(unknown_channel, null)
	t.eq("неизвестный канал — BAD_VALUE на своём поле",
		_codes_at(unknown_channel_problems, "intel[0].channel"), [Problems.BAD_VALUE])
	## Ровно одна проблема: ложь считается только у ИЗВЕСТНОГО канала агентуры, и на
	## «agentss» без подброшенных пунктов второго диагноза (`INTEL_LIE_COUNT`) не выписано.
	t.eq("неизвестный канал — ровно BAD_VALUE, без INTEL_LIE_COUNT",
		_codes(unknown_channel_problems), [Problems.BAD_VALUE])
	t.is_true("неизвестный канал назван в сообщении",
		_message_at(unknown_channel_problems, "intel[0].channel").contains("agentss"))

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
	# Ключ, лежащий в данных (`mission.01.title` через `title_key`), назван здесь ОДИН раз —
	# как `MISSING_TEXT` на своём поле: обязательный перечень его не дублирует
	# (`validator.gd:_check_required_texts` пропускает ключи, на которые сослались данные), и
	# кейс 14 держит это отдельными ассертами (14в и 14ж).
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

	# 12a-8. Соседние точки маршрута патруля соединены ребром: движок путь не ищет, узлы
	# берутся из списка по индексу (`sim/sim.gd:_advance_guards`), и разрыв означает, что
	# патруль оказывается в помещении, которого не проходит. `entry → vault` ребра не
	# имеет: есть только `entry → hall` и `hall → vault`.
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
	for broken in [no_effects_field, no_option_cost, no_option_complexity,
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
	# Обе стороны держатся вместе циклом 14г, но разными правилами: 31 ключ эталона —
	# обязательным перечнем (`MISSING_REQUIRED_TEXT`), `mission.01.title` — сверкой данных
	# (`MISSING_TEXT` на `title_key`), потому что конвейерная константа не знает номера
	# миссии (14ж). Положительный ассерт на полном наборе держит перечень от ЛИШНИХ
	# требований: лишний обязательный ключ сделал бы его красным.
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

	# 14в. НАЗВАНИЕ МИССИИ: ОДИН КЛЮЧ — ОДИН ДИАГНОЗ, и путь на поле данных. `mission.01.title`
	# лежит в данных (`title_key`) и потому второго правила не требует: пропажу называет
	# сверка данных — `MISSING_TEXT` на своём поле, — а обязательный перечень его не
	# дублирует (в нём этого ключа нет вовсе, см. 14ж). Два диагноза отправляли бы автора
	# искать вторую причину, которой нет. Ровно один — и он там, где ключ и живёт.
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

	# 14д. ПУСТЫЕ ТЕКСТЫ. Это исходная цель правила («сдача без системных текстов
	# неполна»), и проверяется она здесь на ключе БЕЗ поля в данных: иначе «проблема есть»
	# объяснялось бы сверкой данных, а не обязательным перечнем.
	var empty_texts_problems: Array = Validator.validate(_good(), {})
	t.eq("пустые тексты: обязательный ключ без поля в данных назван MISSING_REQUIRED_TEXT",
		_codes_at(empty_texts_problems, "texts.log.silence"), [Problems.MISSING_REQUIRED_TEXT])

	# 14е. УРЕЗАН ЦЕЛЫЙ БЛОК. Регресс этой проверки — не «пусто», а «усохло»: снятие всего
	# блока `voice.` обязано назвать КАЖДЫЙ обязательный ключ блока своим диагнозом. Так
	# правило не вырождается в «в текстах есть хоть что-то»: положительное «блок непуст»
	# прошло бы и на одном уцелевшем ключе.
	var no_voice := _texts_for(_good())
	var voice_keys: Array = []
	for key in REQUIRED_TEXTS:
		if String(key).begins_with("voice."):
			no_voice.erase(key)
			voice_keys.append(String(key))
	t.eq("корпус кейса непуст: в эталоне есть блок voice.", voice_keys.size(), 3)
	var no_voice_problems: Array = Validator.validate(_good(), no_voice)
	t.eq("урезан весь блок voice. — диагноз на КАЖДЫЙ ключ блока",
		_codes(no_voice_problems),
		[Problems.MISSING_REQUIRED_TEXT, Problems.MISSING_REQUIRED_TEXT, Problems.MISSING_REQUIRED_TEXT])
	t.eq("урезан весь блок voice. — названы именно ключи блока",
		_paths(no_voice_problems), ["texts.voice.kira.ack", "texts.voice.kira.command", "texts.voice.echo.joke"])

	# 14ж. ПЕРЕЧЕНЬ НЕ ЗНАЕТ НОМЕРА МИССИИ. Это правка находки `review-03` §7.5: прежний
	# первый элемент `mission.01.title` был ключом ОДНОЙ миссии, и миссия с
	# `title_key = mission.02.title` получала ЛОЖНЫЙ диагноз на ключ чужой миссии. Название
	# держит сверка данных, поэтому проверяются ОБЕ половины: с полным набором текстов
	# проблем нет, а без своего названия — ровно один диагноз, на поле данных и про СВОЙ
	# ключ. Первый ассерт краснеет, если в перечень вернут ключ с номером миссии; второй —
	# если сверку данных отключат, приняв «проблем нет» за доказательство.
	var second := _good()
	second["title_key"] = "mission.02.title"
	var second_texts := _texts_for(_good())
	second_texts.erase("mission.01.title")
	second_texts["mission.02.title"] = "ВТОРАЯ МИССИЯ"
	t.eq("миссия 02 с полными текстами проходит без проблем: перечень не привязан к номеру миссии",
		Validator.validate(second, second_texts), [])
	var second_no_title := _texts_for(_good())
	second_no_title.erase("mission.01.title")
	var second_problems: Array = Validator.validate(second, second_no_title)
	t.eq("миссия 02 без своего названия — ровно MISSING_TEXT, чужой ключ не назван",
		_codes(second_problems), [Problems.MISSING_TEXT])
	t.eq("миссия 02 без своего названия — путь на поле данных",
		_paths(second_problems), ["title_key"])
	t.is_true("миссия 02 без своего названия — сообщение называет СВОЙ ключ",
		_message_at(second_problems, "title_key").contains("mission.02.title"))

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
	#
	# Ассерт фиксирует ВСЮ картину, а не только путь `floors` (находка Minor 4 ревью 4:
	# прежняя проверка закрепляла половину). Не-словарь в `floors` оставляет без ссылки
	# КАЖДУЮ подпись этажа: ключи не собираются (`_walk_text_keys` ходит по словарю), и
	# каждая подпись получает `DANGLING_TEXT` на своём ключе. Это то же следствие одного
	# дефекта, что у испорченного поля-ключа (§15 спецификации: «висячий ключ исчезнет
	# сам»), и оно НЕ гасится — ровно так же, как у `name_key`/`trace_key` (см. 15е, 15ж).
	# Поэтому ожидание здесь посчитано руками (1 + по одной подписи на этаж), а не взято
	# у валидатора: иначе ассерт не поймал бы ни потерю диагноза, ни лишний.
	for bad_floors in [[], "этажи", 7]:
		var floors_not_dict := _good_presented()
		floors_not_dict["floors"] = bad_floors
		var floors_not_dict_problems: Array = Validator.validate(floors_not_dict, _presentation_texts())
		t.eq("floors = %s — WRONG_TYPE на своём пути" % str(bad_floors),
			_codes_at(floors_not_dict_problems, "floors"),
			[Problems.WRONG_TYPE])
		t.eq("floors = %s — каждая подпись этажа осталась без ссылки" % str(bad_floors),
			_codes_at(floors_not_dict_problems, "texts.floor."),
			[Problems.DANGLING_TEXT, Problems.DANGLING_TEXT])
		t.eq("floors = %s — диагнозов ровно 1 + по одному на подпись этажа" % str(bad_floors),
			floors_not_dict_problems.size(), 3)

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

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
## чтобы список не разошёлся с ядром (соглашение проекта: только const preload).
const Mission := preload("res://sim/mission.gd")
## Виды рёбер, перекрываемых тревогой, живут в `sim/response.gd` — по той же причине,
## что и `Mission` выше: валидатор их не перечисляет, а спрашивает ядро
## (`Response.blockable_kind`). Второй список здесь разошёлся бы с ядром молча, и окно
## у ребра, которое закрывает тревога, получало бы `WINDOW_ON_OPEN_EDGE` — диагноз
## «сцены не будет» на сцене, которая есть.
const Response := preload("res://sim/response.gd")
## Применятель эффектов живёт в ядре — у него же спрашивается и СПИСОК видов эффектов
## (`Sim.EFFECT_TYPES`, см. `EFFECT_TYPES` ниже). Свой перечень тут уже расходился
## с ядром: `noop` форма принимала, а ядро его не называло вовсе.
const Sim := preload("res://sim/sim.gd")

## `floors` и `facility_key` — поля ФОРМЫ ПРЕЗЕНТАЦИИ: экран операции рисует схему этажа
## с подписями помещений, а взять их неоткуда (что нужно уровню, чтобы его можно было
## нарисовать, — `01-format.md` §12).
## Оба НЕобязательны: уровень без координат, подписей и этажей обязан оставаться валидным
## и грузиться — это условие приёмки формы, а не пожелание.
## `routes` — раздел НОРМАТИВНЫХ маршрутов уровня (форма v3): замысел прохождения данными,
## а не словами в отчёте. `access_points` из списка УБРАН (форма v3): ядро этот раздел не
## исполняет вовсе, и форма не имеет права его принимать — иначе уровень обещает механику,
## которой нет. Действие у терминала выражается вариантом окна (`money`/`trace`/`mark`).
const ROOT_KEYS := ["id", "title_key", "nodes", "edges", "patrols", "sensors",
	"objective", "windows", "intel", "routes", "floors", "facility_key", "note"]
## `pos` и `name_key` — та же форма презентации на узле: координаты помещения на схеме
## этажа и ключ подписи (`room.<node_id>`, значение — в текстах). Оба необязательны.
const NODE_KEYS := ["floor", "tags", "pos", "name_key", "note"]
## Разрешённые поля координаты: обе оси и `note` (`01-format.md` §2 разрешает его
## в записи `pos`). Список закрыт намеренно: опечатка в имени оси обязана назваться
## `UNKNOWN_KEY`, а не выглядеть как «координаты нет».
const POS_KEYS := ["x", "y", "note"]
## Разрешённые поля записи этажа (`floors.<номер>`): `name_key` внутри обязателен.
const FLOOR_KEYS := ["name_key", "note"]
const EDGE_KEYS := ["id", "a", "b", "kind", "steps", "noise", "locked", "note"]
const PATROL_KEYS := ["id", "route", "period", "note"]
const SENSOR_KEYS := ["id", "nodes", "note"]
const WINDOW_KEYS := ["id", "kind", "trigger", "text_key", "options", "silence", "note"]
const OPTION_KEYS := ["id", "text_key", "complexity", "cost", "effects", "note"]
const COST_KEYS := ["noise", "delay", "note"]
## Разрешённые поля `silence` списком здесь НЕ стоят: их собирает `_silence_keys()`
## из `SILENCE_QUALITIES`. Ключи качеств (`good_key`, …) обязаны появляться вместе с
## новым качеством, и второй список тех же имён разошёлся бы с первым молча — тем
## самым дефектом, против которого стоят `TRIGGER_TYPES`/`WINDOW_KINDS`.
const TRIGGER_KEYS := ["type", "edge", "node", "sensor", "note"]
const EFFECT_KEYS := ["type", "edge", "value", "id", "want", "needs", "fallback", "note"]
const INTEL_KEYS := ["channel", "observed_at", "entries", "note"]
const INTEL_ENTRY_KEYS := ["kind", "id", "route", "period", "nodes", "node", "count",
	"age_hours", "false", "note_key", "note"]
## Разрешённые поля нормативного маршрута уровня: `id`, вход, выход, список помещений.
## Список закрыт: раздел читает инструмент приёмки и человек, и опечатка в имени
## поля («path» вместо «route») обязана назваться `UNKNOWN_KEY`, а не выглядеть как
## «маршрута нет».
const ROUTE_KEYS := ["id", "entry", "exit", "route", "note"]

## Разделы-массивы: обязательны на корне (см. `01-format.md` §1), но пустой массив —
## нормальная миссия. «Ключа нет» и «ключ есть, но не массив» — разные болезни.
##
## Держать в согласии с `Mission.DATA_ARRAY_SECTIONS` (`sim/mission.gd`): там перечислено,
## какие разделы модель миссии вообще принимает в `data`. Списки НЕ совпадают дословно —
## здесь все семь корневых массивов файла (`edges`, `patrols`, `sensors` ядру в `data` не
## едут, они у него в жёстком API), — но новая секция обязана появиться в обоих.
## `routes` стоит здесь, а не среди необязательных полей НЕ случайно: раздел обязателен
## (форма v3), и «маршрутов нет» — не «уровень без маршрутов», а дефект: норматив «окон за
## прохождение» иначе нечем измерить.
const ARRAY_SECTIONS := ["edges", "patrols", "sensors", "windows", "intel", "routes"]
## Обязательные корневые поля, кроме разделов: id миссии и ключ её названия.
const REQUIRED_ROOT_STRINGS := ["id", "title_key"]
## Вид окна и тип триггера — ОДИН список: `kind` обязан совпадать с `trigger.type`
## (`01-format.md` §5.1), и третий вид, добавленный в один список, обязан появиться в обоих.
## Две отдельные константы с одинаковым содержимым разошлись бы молча — тем самым дефектом,
## против которого стоит сверка `kind` ↔ `trigger.type`. Имена оставлены оба: в месте
## проверки окна читается «вид окна», в месте триггера — «тип триггера».
const TRIGGER_TYPES := ["locked_edge", "node_entered", "guard_in_sensor"]
const WINDOW_KINDS := TRIGGER_TYPES
## Виды эффектов, известные ядру. Список СПРАШИВАЕТСЯ у применятеля (`Sim.EFFECT_TYPES`),
## а не переписывается здесь: вторая копия разошлась бы с ядром молча, и форма принимала бы
## эффект, которого никто не исполняет (так уже было с `noop`). Всё остальное — только через
## `engine_proposal`. `money`/`trace` — счётчики, `mark` — именованная метка: «Итоги» фазы планирования
## читают именно их, а ось «копия против оригинала» выражается выбором игрока (меткой), а не
## перевозкой носителей. Требования к полям у каждого свои и разобраны в `_check_effects`.
const EFFECT_TYPES := Sim.EFFECT_TYPES
const POINT_KINDS := ["terminal", "door_panel", "camera", "climate"]
const INTEL_KINDS := ["patrol", "sensor", "guard_count", "door_state"]
## Каналы разведки: единственный подброшенный пункт живёт у агентуры (см. ниже), и это имя
## объявлено ОТДЕЛЬНО — чтобы «agents» не оказалось двумя литералами в одном файле: канал
## переименуется в одном месте, и список с правилом лжи не разъедутся молча.
const INTEL_LIE_CHANNEL := "agents"
## Каналы разведки, известные форме, — ровно три и дословно: дрон (`drone`), агентура
## (`agents`), взлом (`hack`). Список закрыт: канал адресует данные на экране и в текстах
## (`intel.<канал>.<пометка>`), поэтому опечатка («agentss») уносит весь блок из своего
## канала молча — данные приехали, а на экран не попали.
##
## Живёт здесь, рядом с `INTEL_KINDS`, потому что спросить его сегодня некому: разведку не
## читает НИ ОДНА строка ядра (ядро строит «призраков» охраны из позиций патрулей на старте,
## а не из `intel`), и второго перечня каналов в коде нет. Место, где он должен жить дальше, —
## модель миссии (`sim/mission.gd`, рядом с `EDGE_KINDS`) или презентация, когда разведка
## понадобится им: тогда валидатор будет спрашивать список оттуда, как спрашивает
## `Mission.EDGE_KINDS` и `Response.blockable_kind`, а не держать у себя. Перенос — правка
## ядра, а перенос — отдельная правка ядра, не формы.
const INTEL_CHANNELS := ["drone", INTEL_LIE_CHANNEL, "hack"]
const SILENCE_QUALITIES := ["good", "neutral", "bad", "safe"]

## Свои агенты заняты движком: под этими id в patrols нельзя.
const RESERVED_AGENT_IDS := ["kira", "echo"]

## ОБЯЗАТЕЛЬНЫЕ текстовые ключи: тексты СИСТЕМЫ, а не окна. Дословный список этих 31
## ключа — `01-format.md` §11.1; что лежит в каждом блоке — `03-texts.md` §3.
## У `log.silence`, `outcome.caught` или `results.summary` нет поля в данных
## миссии, на которое указывал бы `*_key`, поэтому обычная сверка (`_walk_text_keys` →
## `_check_texts`) их не видит вовсе: поставка без них оставалась бы «чистой», а игра — без
## строки «КОМАНДУЕТ» и без итогов.
##
## Перечень НЕ привязан к номеру миссии. Прежний первый элемент, `mission.01.title`, был
## ключом ОДНОЙ миссии и на миссии с другим `title_key` выписывал ЛОЖНЫЙ
## `MISSING_REQUIRED_TEXT` (проверено пробой). Держать его здесь нечем и
## незачем: название миссии — обычное поле данных (`title_key`), а его отсутствие называет
## сверка данных — `MISSING_TEXT` на своём поле и ровно один диагноз, при ЛЮБОМ номере
## миссии (см. `_check_required_texts`; тот же вывод назван получателю — `01-format.md`
## §11.1 и `03-texts.md` §3). Поэтому из перечня убран ровно этот
## ключ, а остальные взяты дословно и НЕ расширяются: окна, голоса и финальные раскрытия
## остаются автору уровня (`03-texts.md` §4 — ключи, выводимые из данных; блоки «Голоса»
## и «Финал» — §3 того же файла), и требовать их здесь значило бы
## зашить одну миссию в конвейер. `team.market.intro` стоит рядом с обязательными потому, что
## он того же класса: биржа команды (`03-texts.md` §3, блок «Команда (наём)») — экран системы,
## а не окно миссии.
##
## Проверка идёт ТОЛЬКО при переданных текстах-словаре: `null` — осознанный отказ от сверки
## (контракт `validate`), пустой словарь — «текстов нет», и тогда отсутствуют все
## обязательные ключи тоже.
const REQUIRED_TEXT_KEYS := [
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

## Ключи вне данных, которых валидатор НЕ требует, но и не считает висячими, даже если ни
## одно окно на них не ссылается. `intel.` здесь потому, что пояснения к разведке
## адресуются по каналу и пометке (`intel.hack.patrol_false`), а не по id
## конкретного пункта: собрать такие ключи из данных нельзя, и без префикса они получали
## ложный DANGLING_TEXT (`01-format.md` §9 — данные разведки, §11.2 — служебные семейства).
##
## Это список ТЕРПИМОГО, а не проверяемого: он отвечает на вопрос «висячий ли ключ», и
## наличие ключа под этими префиксами никто не обещает. Обязательность несут ровно
## `REQUIRED_TEXT_KEYS` выше — там же сказано, почему.
##
## Прежний долг, записанный здесь («обязательные группы `log.*`, `voice.*`, `final.*`,
## `outcome.*`, `results.*` не проверяются: текстов ноль, и такая проверка давала бы только
## ложные срабатывания»), ЗАКРЫТ: тексты поставки есть (все 32 ключа перечня постановки на
## месте — 31 держит `REQUIRED_TEXT_KEYS`, название миссии — сверка `title_key`; число
## ключей поставки держит кейс доставки), и пропажа обязательного ключа — реальный дефект
## контента, который обязан называться. Проверка живёт в
## `_check_required_texts`, код проблемы — `MISSING_REQUIRED_TEXT`.
const UNUSED_OK_PREFIXES := ["mission.", "negotiation.", "team.", "log.", "voice.",
	"final.", "outcome.", "results.", "intel."]


## problems = validate(mission_dict, texts).
##
## `texts` ОБЯЗАТЕЛЕН и значения по умолчанию не имеет намеренно. Прежний
## `texts: Dictionary = {}` делал забывание невидимым: `validate(data)` на данных
## с двумя десятками ключей возвращал «проблем нет», ничего не сверив, — тот же
## молчаливый пропуск, что и `--check-only`, печатавший `Parse Error` с кодом 0.
## Теперь `validate(data)` не компилируется, а выбор виден в каждой строке вызова:
##
##   `texts == null`      — сверка НЕ выполняется; это явный отказ вызывающего,
##                          написанный в коде (не «забыл», а «здесь тексты не про это»);
##   `texts` — словарь    — сверка выполняется. Пустой словарь тоже: «текстов нет» —
##                          осмысленное утверждение, и тогда отсутствующими окажутся
##                          ВСЕ ключи, на которые ссылаются данные, и все обязательные
##                          системные ключи (`REQUIRED_TEXT_KEYS`);
##   иное                 — ТРЕТЬЕ состояние: строка, число, логическое, массив и любой
##                          другой не-словарь. Сверку вести нечем, и это ОШИБКА вызова,
##                          а не «текстов нет»: она называется `WRONG_TYPE` с путём
##                          `(тексты)`, и сверка не выполняется. Раньше вызов с чужим
##                          вторым аргументом выглядел успешным: `load_mission(data,
##                          "мусор-строка")` отдавал `problems = 0` и СОБРАННУЮ миссию,
##                          а движок печатал в stderr `Nonexistent function 'has' in base
##                          'String'` и обрывал `_check_texts` на первой же строке —
##                          stderr вердиктом не является. Триггер правдоподобен:
##                          у `load_text(json_text: String, texts)` рядом оказываются два
##                          строковых параметра, и подставить текст вместо словаря текстов
##                          — естественная описка.
##
## Тип у `texts` не указан ровно потому, что `null` — законное значение: аннотация
## `Dictionary` отвергла бы его на входе. Обратная сторона названа прямо: без аннотации
## компилятор ловит ЗАБЫВАНИЕ аргумента, но не подстановку НЕ ТОГО, — поэтому третье
## состояние проверяется явно, а не оставляется на движок. Нового кода проблемы «тексты
## не переданы» нет: сам факт обязательности аргумента и есть защита.
static func validate(data, texts) -> Array:
	if typeof(data) != TYPE_DICTIONARY:
		return [Problems.wrong_type("(корень)", TYPE_DICTIONARY, typeof(data))]
	var problems: Array = []

	_check_root_keys(data, problems)
	_check_sections(data, problems)
	_check_notes(data, "", problems)
	_check_floors(data, problems)
	var nodes := _check_nodes(data, problems)
	_check_edges(data, nodes, problems)
	_check_patrols(data, nodes, problems)
	_check_sensors(data, nodes, problems)
	_check_objective(data, nodes, problems)
	var entries := _entry_nodes(nodes)
	var known_edges := _known_edges(data)
	var known_sensors := _known_ids(data, "sensors")
	var known_patrols := _known_ids(data, "patrols")
	## `entries` (узлы с тегом `entry`) нужны сразу нескольким проверкам: нормативным
	## маршрутам (форма v3 — ровно один маршрут на вход), достижимости цели, обоим диагнозам
	## «окно невозможно» про вход и недостижимый якорь ГРУППОВОГО окна (`node_entered`,
	## `locked_edge`; у `guard_in_sensor` актёр — охрана, см. `_window_anchors`). Считается
	## ОДИН раз: второй обход `nodes` разошёлся бы с первым молча.
	_check_routes(data, nodes, entries, problems)
	_check_reachability(data, nodes, known_edges, entries, problems)
	_check_windows(data, known_edges, known_sensors, _known_ids_from(nodes), entries,
		_patrolled_nodes(data), problems)
	_check_window_reachability(data, known_edges, _known_ids_from(nodes),
		entries, problems)
	## `_patrol_data` — маршрут и период КАЖДОГО патруля: по ним решается, расходится ли
	## с реальностью подброшенное расписание (`GHOST_SAME_AS_REAL`).
	_check_intel(data, known_patrols, _patrol_data(data), problems)
	## Третье состояние второго аргумента (см. контракт `validate` выше). Проверка стоит
	## здесь, а не в `_check_texts`, потому что это форма АРГУМЕНТА, как и `(корень)` выше:
	## `_check_texts` отвечает на вопрос «что в текстах против данных», и внутрь него
	## не-словарь попадать не должен. Молча пропустить нельзя: именно так вызов с чужим
	## вторым аргументом выглядел успешным, отдавая собранную миссию.
	if texts != null and typeof(texts) != TYPE_DICTIONARY:
		problems.append(Problems.wrong_type("(тексты)", TYPE_DICTIONARY, typeof(texts)))
	else:
		_check_texts(data, texts, problems)
	return problems


## Обязательные поля корня и типы разделов-массивов. Отдельно от `_check_root_keys`,
## потому что это РАЗНЫЕ вопросы: «поля нет» и «поле есть, но не той формы».
static func _check_sections(data: Dictionary, problems: Array) -> void:
	for name in REQUIRED_ROOT_STRINGS:
		if not data.has(name):
			problems.append(Problems.missing_field(name, TYPE_STRING))
		else:
			var value := _string_or(data[name], name, problems)
			if value == "" and typeof(data[name]) == TYPE_STRING:
				problems.append(Problems.bad_value(name, "поле не может быть пустым"))
	for name in ARRAY_SECTIONS:
		if not data.has(name):
			problems.append(Problems.missing_field(name, TYPE_ARRAY))
			continue
		if typeof(data[name]) != TYPE_ARRAY:
			problems.append(Problems.wrong_type(name, TYPE_ARRAY, typeof(data[name])))


## `note` разрешён в любом объекте, но только строкой (`01-format.md` §0, правила записи;
## в корне и у `pos` он назван отдельно — §1 и §2). Обход всего
## словаря: так новое поле с `note` не останется без проверки.
static func _check_notes(value, path: String, problems: Array) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		for key in value:
			var child_path := "%s.%s" % [path, String(key)] if path != "" else String(key)
			if String(key) == "note" and typeof(value[key]) != TYPE_STRING:
				problems.append(Problems.wrong_type(child_path, TYPE_STRING, typeof(value[key])))
			else:
				_check_notes(value[key], child_path, problems)
	elif typeof(value) == TYPE_ARRAY:
		var arr: Array = value
		for i in arr.size():
			_check_notes(arr[i], "%s[%d]" % [path, i], problems)


## Множество id помещений — тот же вид, что `_known_ids` для разделов-массивов.
static func _known_ids_from(items: Dictionary) -> Dictionary:
	var out := {}
	for key in items:
		out[String(key)] = true
	return out


## id раздела → САМА запись, а не `true`. Ссылочные проверки спрашивают только `has`, и
## для них разницы нет; но «окно не сработает: зону сенсора не посещает ни один патруль»
## обязано назвать САМИ помещения зоны — а взять их можно только из записи сенсора.
## Второй сборки того же словаря «id → запись» здесь не заводим: она разошлась бы с первой
## молча (тем же дефектом, против которого стоят `TRIGGER_TYPES`/`WINDOW_KINDS`).
static func _known_ids(data: Dictionary, section: String) -> Dictionary:
	var out := {}
	if not data.has(section) or typeof(data[section]) != TYPE_ARRAY:
		return out
	for item in data[section]:
		if typeof(item) == TYPE_DICTIONARY and item.has("id"):
			out[String(item["id"])] = item
	return out


## Помещения зоны сенсора по его id — для сообщения о мёртвом сенсоре. Пустой список у
## несуществующего сенсора и у испорченного поля `nodes`: о них уже сказано своим диагнозом
## (`BAD_REF`, `WRONG_TYPE`), и падать на них валидатор не имеет права.
static func _sensor_nodes(sensor: String, known_sensors: Dictionary) -> Array:
	var out: Array = []
	if not known_sensors.has(sensor):
		return out
	var record = known_sensors[sensor]
	if typeof(record) != TYPE_DICTIONARY:
		return out
	var nodes = (record as Dictionary).get("nodes", null)
	if typeof(nodes) != TYPE_ARRAY:
		return out
	for node in (nodes as Array):
		if typeof(node) == TYPE_STRING:
			out.append(String(node))
	return out


## id ребра → сведения о ребре, нужные проверкам окон: `locked` КАК ЕСТЬ, `kind`
## строкой и ОБА КОНЦА. Не приведённый к `bool` `locked` и не `true`.
##
## Проверкам окон нужны ПЯТЬ ответов про одно и то же ребро: существует ли ссылка (`has`),
## заперто ли оно (`true`), «поле испорчено — судить нельзя» (не-bool), «перекрывается
## ли оно тревогой» (`kind`) и ДОСТИЖИМЫ ЛИ ЕГО КОНЦЫ — якорь окна у ребра это ребро
## целиком, и без `a`/`b` в записи «якорь недостижим» у окна у двери не проверялся бы
## вовсе (проверено пробой: диагноз не выдавался ни на одном входе). Читать концы из
## самого файла вторым обходом (`data["edges"]`) значило бы держать два ответа на один
## вопрос в двух местах — ровно тот класс, против которого стоят `TRIGGER_TYPES` и
## `Response.blockable_kind`.
##
## Приведение `locked` здесь и было бы дефектом: `bool("да")` —
## не существующий конструктор (рантайм-сбой движка), `bool(1)` — тихая истина, то есть
## мусор превращался бы в уверенное «заперто». `kind` берётся через `str`, а не `String`:
## значение приходит из данных и может быть словарём, а конструктор `String` на нём падает
## рантаймом.
## Для ссылочных проверок (`_check_ref_key`, `_check_effects`) словарь ведёт себя как
## прежний: ключи — существующие id.
static func _known_edges(data: Dictionary) -> Dictionary:
	var out := {}
	if not data.has("edges") or typeof(data["edges"]) != TYPE_ARRAY:
		return out
	for e in (data["edges"] as Array):
		if typeof(e) == TYPE_DICTIONARY and e.has("id"):
			out[String(e["id"])] = {
				"locked": e.get("locked", false),
				"kind": str(e.get("kind", "")),
				"a": str(e.get("a", "")),
				"b": str(e.get("b", "")),
			}
	return out


# --- структура ----------------------------------------------------------------

static func _check_root_keys(data: Dictionary, problems: Array) -> void:
	for key in data:
		if not ROOT_KEYS.has(String(key)):
			problems.append(Problems.unknown_key(String(key), String(key)))
	for required in [["nodes", TYPE_DICTIONARY], ["objective", TYPE_STRING]]:
		var name: String = required[0]
		if not data.has(name):
			problems.append(Problems.missing_field(name, required[1]))
		else:
			_expect_type(data[name], required[1], name, problems)
	## `facility_key` — НЕобязательное корневое поле (ключ названия комплекса). Тип
	## проверяется по факту поля, как у остальных текстовых ключей (`_check_text_key`): без
	## этой проверки испорченное поле молча выпадает из сбора текстовых ключей
	## (`_walk_text_keys` берёт только строки), и текст, на который оно ссылалось,
	## объявляется висячим — автор получает `DANGLING_TEXT` про текст, которого не терял,
	## не видя кривого поля.
	if data.has("facility_key"):
		_string_or(data["facility_key"], "facility_key", problems)


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
			problems.append(Problems.wrong_type(path, TYPE_DICTIONARY, typeof(node)))
			continue
		_check_keys(node, NODE_KEYS, path, problems)
		if not node.has("floor"):
			problems.append(Problems.missing_field("%s.floor" % path, TYPE_INT))
		else:
			_expect_int(node["floor"], "%s.floor" % path, problems)
		## Теги узла — свободный список строк, и перечня допустимых имён у формы НЕТ
		## намеренно: тег читает ядро по имени, а не по списку. `entry` — вход группы,
		## `shielded` — экранированное помещение, где глохнет голос; остальные
		## (`stair`, `lift_main`, `terminal`, `server`, …) — подписи для презентации.
		## Поэтому проверяется ФОРМА (массив строк), а не значение: закрытый перечень
		## отверг бы честный новый тег и заставил бы править валидатор ради данных.
		if node.has("tags"):
			_check_string_array(node["tags"], "%s.tags" % path, problems)
		## Поля презентации — по факту наличия, как `name_key` ниже: `pos` НЕобязателен, но
		## если он есть, то обе оси обязательны и целые; `name_key` — ключ подписи, и его
		## тип проверяется тем же способом, что у остальных текстовых ключей.
		if node.has("pos"):
			_check_pos(node["pos"], "%s.pos" % path, problems)
		_check_text_key(node, "name_key", path, problems)
		nodes[String(node_id)] = node
	return nodes


## Координаты помещения на схеме этажа: `{"x": <целое>, "y": <целое>}`.
##
## Проверка идёт по ФАКТУ поля (`pos` необязателен), и внутри — по обеим осям сразу:
## `{"x": 5}` без `y` — это не «координата наполовину», а неполная форма, и назвать её
## обязан `MISSING_FIELD` на своей оси. Отрицательные значения законны: схема этажа
## может быть разложена и в отрицательную сторону, поэтому `BAD_VALUE` здесь не бывает.
static func _check_pos(raw, path: String, problems: Array) -> void:
	if typeof(raw) != TYPE_DICTIONARY:
		problems.append(Problems.wrong_type(path, TYPE_DICTIONARY, typeof(raw)))
		return
	var pos: Dictionary = raw
	_check_keys(pos, POS_KEYS, path, problems)
	for axis in ["x", "y"]:
		var axis_path := "%s.%s" % [path, axis]
		if not pos.has(axis):
			problems.append(Problems.missing_field(axis_path, TYPE_INT))
			continue
		_int_or(pos[axis], axis_path, problems)


## `floors` — НЕобязательный корневой раздел: словарь «номер этажа → запись с подписью»
## (`{"-1": {"name_key": "floor.-1"}, ...}`). Ключ — номер этажа СТРОКОЙ: в JSON ключи
## объектов строковые, и `-1` для подвала допустим.
##
## Это словарь, а не седьмой раздел-массив: `ARRAY_SECTIONS` перечисляет корневые
## МАССИВЫ файла, и попадание `floors` туда сделало бы раздел обязательным — уровень без
## координат перестал бы грузиться. Отсутствие `floors` не даёт ни одной проблемы;
## `floors: []` (массив вместо словаря) — `WRONG_TYPE` на своём пути.
##
## Сверка номеров этажей с `nodes[].floor` здесь НЕ ведётся: `floors` — подписи для
## показа, и запись этажа, на котором помещений нет, дефектом не является (сказано
## прямо и получателю — `01-format.md` §1.1).
static func _check_floors(data: Dictionary, problems: Array) -> void:
	if not data.has("floors"):
		return
	var raw = data["floors"]
	if typeof(raw) != TYPE_DICTIONARY:
		problems.append(Problems.wrong_type("floors", TYPE_DICTIONARY, typeof(raw)))
		return
	var floors: Dictionary = raw
	for key in floors:
		var path := "floors.%s" % String(key)
		var entry = floors[key]
		if typeof(entry) != TYPE_DICTIONARY:
			problems.append(Problems.wrong_type(path, TYPE_DICTIONARY, typeof(entry)))
			continue
		_check_keys(entry, FLOOR_KEYS, path, problems)
		if not entry.has("name_key"):
			problems.append(Problems.missing_field("%s.name_key" % path, TYPE_STRING))
		else:
			_string_or(entry["name_key"], "%s.name_key" % path, problems)


static func _check_edges(data: Dictionary, nodes: Dictionary, problems: Array) -> void:
	if not data.has("edges") or typeof(data["edges"]) != TYPE_ARRAY:
		return
	var seen: Array = []
	## Неупорядоченная пара помещений → id первого ребра между ними. Второе ребро
	## станет невидимым: `edge_between` вернёт первое (`01-format.md` §3, «Запрещено»).
	var pairs: Dictionary = {}
	for i in (data["edges"] as Array).size():
		var e = data["edges"][i]
		var path := "edges[%d]" % i
		if typeof(e) != TYPE_DICTIONARY:
			problems.append(Problems.wrong_type(path, TYPE_DICTIONARY, typeof(e)))
			continue
		_check_keys(e, EDGE_KEYS, path, problems)
		for required in ["id", "a", "b", "kind", "steps", "noise"]:
			if not e.has(required):
				problems.append(Problems.missing_field("%s.%s" % [path, required],
					TYPE_INT if required in ["steps", "noise"] else TYPE_STRING))
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
		elif a != "" and b != "":
			var pair := "%s|%s" % ([a, b] if a < b else [b, a])
			if pairs.has(pair):
				problems.append(Problems.bad_value(path,
					"второе ребро между «%s» и «%s»: «%s» останется невидимым, движок вернёт «%s»"
					% [a, b, eid if eid != "" else path, String(pairs[pair])]))
			else:
				pairs[pair] = eid if eid != "" else path
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
			problems.append(Problems.wrong_type("%s.locked" % path, TYPE_BOOL, typeof(e["locked"])))


static func _check_patrols(data: Dictionary, nodes: Dictionary, problems: Array) -> void:
	if not data.has("patrols") or typeof(data["patrols"]) != TYPE_ARRAY:
		return
	var seen: Array = []
	for i in (data["patrols"] as Array).size():
		var p = data["patrols"][i]
		var path := "patrols[%d]" % i
		if typeof(p) != TYPE_DICTIONARY:
			problems.append(Problems.wrong_type(path, TYPE_DICTIONARY, typeof(p)))
			continue
		_check_keys(p, PATROL_KEYS, path, problems)
		if not p.has("id"):
			problems.append(Problems.missing_field("%s.id" % path, TYPE_STRING))
		var pid := _string_or(p.get("id", ""), "%s.id" % path, problems)
		if pid != "":
			if RESERVED_AGENT_IDS.has(pid):
				problems.append(Problems.reserved_id("patrols", pid))
			elif seen.has(pid):
				problems.append(Problems.duplicate_id("patrols", pid))
			else:
				seen.append(pid)
		if not p.has("route"):
			problems.append(Problems.missing_field("%s.route" % path, TYPE_ARRAY))
		else:
			var route: Variant = _string_array_or(p["route"], "%s.route" % path, problems)
			if route != null:
				if (route as Array).size() < 2:
					problems.append(Problems.bad_value("%s.route" % path, "маршрут патруля короче двух точек"))
				## «О маршруте можно судить»: каждый его узел существует, и каждая соседняя
				## пара соединена ребром. Пока это не так, корень разрыва уже назван своим
				## диагнозом (`BAD_REF` на узле, `BAD_VALUE` на паре или на всём разделе
				## `edges`), и замыкание НЕ судится: иначе одна опечатка в узле из трёх
				## точек давала три диагноза на один дефект, а не-массив в `edges` —
				## `PATROL_ROUTE_OPEN` на каждом патруле (принцип
				## шапки файла «одна ошибка — одно следствие», `01-format.md` §15).
				## Пустой словарь `nodes` — тот же случай: раздела нет, о существовании
				## узлов судить нечем, и о замыкании тоже.
				var nodes_known := not nodes.is_empty()
				var route_judgeable := nodes_known
				for n in route:
					if nodes_known and not nodes.has(String(n)):
						problems.append(Problems.bad_ref("%s.route" % path, "нет помещения «%s»" % String(n)))
						route_judgeable = false
				## Движок путь не ищет: охранник идёт по СПИСКУ, узлы берутся по индексу
				## и увеличиваются по модулю длины списка, и разрыв означает, что патруль
				## оказывается в помещении, которого не проходит. Соседние точки обязаны
				## быть соединены ребром (`01-format.md` §4.1).
				var size := (route as Array).size()
				for k in max(0, size - 1):
					if not _connected(String(route[k]), String(route[k + 1]), data):
						problems.append(Problems.bad_value("%s.route" % path,
							"разрыв маршрута: «%s» и «%s» не соединены ребром"
							% [String(route[k]), String(route[k + 1])]))
						route_judgeable = false
				## ЗАМЫКАНИЕ маршрута: индекс растёт по модулю длины списка, поэтому
				## после последней точки идёт первая, и замыкающая пара — такое же ребро
				## маршрута, как соседние. Прежде она не проверялась вовсе, и маршрут из
				## трёх помещений без ребра «последнее → первое» считался валидным:
				## уровень проходил форму с разрывом в цикле.
				##
				## Две пары сюда не попадают, и обе — не разрыв:
				##  * маршрут из ДВУХ точек: соседняя пара и замыкающая — одна и та же,
				##    о ней уже сказано выше; второй диагноз на один дефект запрещён.
				##    `size >= 3` здесь — ЗАЩИТА В ГЛУБИНУ, а не несущий порог для двух
				##    точек: на двухточечном маршруте `_connected` спрашивают про ту же
				##    пару, что и выше (ответ «соединены» — иначе разрыв уже назван и снят
				##    `route_judgeable`), поэтому замена `size >= 3` на `size >= 1` не
				##    меняет НИ ОДНОГО ответа валидатора — проверено перебором маршрутов
				##    всех размеров, включая пустой. Держать этот порог ассертом поэтому
				##    нельзя, и он не держится. Несущая половина той же пары —
				##    `route_judgeable` ниже: сними её, и двухточечный разрыв получит
				##    второй диагноз (`PATROL_ROUTE_OPEN`) вдобавок к названному соседнему;
				##    держит это ассерт «маршрут из двух точек с разрывом».
				##    Сам порог при этом СНЯТЬ НЕЛЬЗЯ: без него пустой маршрут роняет
				##    `route[0]` — движок печатает `SCRIPT ERROR: Invalid access of
				##    index '0'`, а вердикт остаётся зелёным.
				##  * маршрут, возвращающийся в первую точку (`a, b, a`): «переход» из
				##    точки в неё же ребром не является (петли запрещены), а ядро такой
				##    шаг проходит как стояние на месте — замыкать нечего. Половина
				##    несущая: сними `String(route[0]) != String(route[size - 1])` — и
				##    честный маршрут «туда и обратно» получит диагноз о несуществующем
				##    ребре `a → a`; держит это ассерт «маршрут «туда и обратно»».
				##
				## Последнее условие — `route_judgeable` (см. выше): на маршруте, где уже
				## назван разрыв пары или несуществующий узел, замыкание не судится, и
				## `PATROL_ROUTE_OPEN` не выдаётся. Здоровый маршрут с ОДНИМ разрывом в
				## замыкающей паре при этом по-прежнему получает ровно один диагноз: все
				## узлы на месте, все соседние пары соединены — судить есть о чём.
				if route_judgeable and size >= 3 and String(route[0]) != String(route[size - 1]) \
						and not _connected(String(route[size - 1]), String(route[0]), data):
					problems.append(Problems.patrol_route_open("%s.route" % path,
						String(route[size - 1]), String(route[0])))
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
			problems.append(Problems.wrong_type(path, TYPE_DICTIONARY, typeof(s)))
			continue
		_check_keys(s, SENSOR_KEYS, path, problems)
		if not s.has("id"):
			problems.append(Problems.missing_field("%s.id" % path, TYPE_STRING))
		var sid := _string_or(s.get("id", ""), "%s.id" % path, problems)
		if sid != "":
			if seen.has(sid):
				problems.append(Problems.duplicate_id("sensors", sid))
			else:
				seen.append(sid)
		if not s.has("nodes"):
			problems.append(Problems.missing_field("%s.nodes" % path, TYPE_ARRAY))
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

## Два правила постановки: «вход → цель» (п. 14) и обратный путь «цель → вход» (п. 15).
## Обратный путь проверяется ЯВНО, обходом от цели, а не выводом «граф неориентированный,
## значит то же самое»: правило не должно зависеть от того, что рёбра сегодня проходимы
## в обе стороны.
##
## Обе проверки РАБОТАЮТ и обе могут сообщить: при недостижимости прямого пути выдаётся
## сообщение на каждый вход, и вдобавок срабатывает обратный обход (ни от цели, ни к цели
## пути нет). Два сообщения на один разрыв — осознанно: это разные диагнозы, «от входа
## до цели не дойти» и «от цели не вернуться к входу», и контент может чинить их разными
## правками. При равенстве путей (обычный случай) обе проверки молчат.
##
## Третье правило — про РЕБРО, а не про помещение: якорь окна с триггером `locked_edge`
## обязан быть достижим от входов. Прежде оно проверялось только для помещений, и окно
## у ребра в отрезанной части графа проходило форму молча. Строка ребра читается из
## `known_edges` (того же словаря, что у окон): второй его сборки здесь не заводим, иначе
## «ребро есть» в двух местах могло бы значить разное.
##
## `entries` приходит аргументом, а не считается здесь: список входов уже построен
## вызывающим, и второй обход `nodes` разошёлся бы с первым молча.
static func _check_reachability(data: Dictionary, nodes: Dictionary, known_edges: Dictionary,
		entries: Array, problems: Array) -> void:
	if nodes.is_empty() or not data.has("edges") or typeof(data["edges"]) != TYPE_ARRAY:
		return
	if not data.has("objective") or typeof(data["objective"]) != TYPE_STRING:
		return
	var objective := String(data["objective"])
	if not nodes.has(objective):
		return
	if entries.is_empty():
		problems.append(Problems.unreachable("nodes", "нет ни одного помещения с тегом entry — группу некуда ставить"))
		return
	for entry in entries:
		if not _reaches(entry, objective, data["edges"]):
			problems.append(Problems.unreachable("objective",
				"от входа «%s» до цели «%s» нет пути" % [entry, objective]))
	## Обратный путь: от цели обязан быть достижим хотя бы один вход.
	var has_reverse := false
	for entry in entries:
		if _reaches(objective, entry, data["edges"]):
			has_reverse = true
			break
	if not has_reverse:
		problems.append(Problems.unreachable("objective",
			"от цели «%s» не дойти ни до одного входа: %s" % [objective, ", ".join(entries)]))


## Достижимые от входов помещения ОДНИМ обходом. Отвечает на вопрос «можно ли вообще
## попасть в это помещение от какого-нибудь входа», а не «каким путём»: путь — замысел
## уровня, и он объявлен разделом `routes`, а не выводится валидатором.
##
## Словарь-множество (а не список) потому, что спрашивают его по каждому якорю окна:
## поиск по списку на каждом окне — та же работа, только медленнее и незаметнее.
static func _reachable_from_entries(entries: Array, edges: Array) -> Dictionary:
	var seen: Dictionary = {}
	var queue: Array = []
	for entry in entries:
		var id := String(entry)
		if not seen.has(id):
			seen[id] = true
			queue.append(id)
	while not queue.is_empty():
		var current := String(queue.pop_front())
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
	return seen


## Помещения, через которые ходит хотя бы один патруль: ОБЪЕДИНЕНИЕ маршрутов. По этому
## множеству решается, бывает ли охрана в зоне сенсора вообще.
##
## Именно объединение, а не «маршрут одного патруля»: ядро выдаёт `sensor_contact`, когда
## ЛЮБОЙ охранник входит в зону, и второй патруль через ту же зону окно оживляет. Множество
## узлов, а не список, — по той же причине, что и у `_reachable_from_entries`: спрашивают
## его на каждом окне с сенсором.
static func _patrolled_nodes(data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if not data.has("patrols") or typeof(data["patrols"]) != TYPE_ARRAY:
		return out
	for p in (data["patrols"] as Array):
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var route = p.get("route", null)
		if typeof(route) != TYPE_ARRAY:
			continue
		for node in (route as Array):
			if typeof(node) == TYPE_STRING:
				out[String(node)] = true
	return out


## Маршрут и период КАЖДОГО патруля по id: по ним проверяется, расходится ли с реальностью
## подброшенное расписание (`GHOST_SAME_AS_REAL`). Форма полей здесь не судится —
## её уже назвали `_check_patrols`; словарь отвечает только на вопрос «а как на самом деле».
static func _patrol_data(data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if not data.has("patrols") or typeof(data["patrols"]) != TYPE_ARRAY:
		return out
	for p in (data["patrols"] as Array):
		if typeof(p) != TYPE_DICTIONARY or not p.has("id"):
			continue
		out[String(p["id"])] = {
			"route": p.get("route", []),
			"period": p.get("period", null),
		}
	return out


static func _entry_nodes(nodes: Dictionary) -> Array:
	var out: Array = []
	for node_id in nodes:
		var tags = nodes[node_id].get("tags", [])
		if typeof(tags) == TYPE_ARRAY and (tags as Array).has("entry"):
			out.append(String(node_id))
	return out


# --- нормативные маршруты -----------------------------------------------------

## `routes` — ОБЯЗАТЕЛЬНЫЙ раздел: «ровно один маршрут на каждый узел с тегом entry».
## Прежде норматив «8–9 срабатывающих окон за прохождение» нечем было измерить: маршрутов
## в данных не было, приёмка строила свои (BFS от входа к цели), и спор «9/9/8 против 5/6/7»
## не имел арбитра. Теперь замысел прохождения объявлен ДАННЫМИ, а BFS остаётся тем, чем и
## должен быть, — способом показать, что каждое окно вообще способно сработать.
##
## Проверок здесь шесть, и каждая называет СВОЁ: раздела нет; он не массив; записей про
## вход не ровно одна; `entry`/`exit` — не вход; `route[0]`/`route[-1]` не совпали с
## `entry`/`exit`; соседние точки маршрута не соединены ребром; цель не лежит на маршруте.
## Разные правки у автора — разные диагнозы (принцип шапки файла).
##
## Каскад гасится там, где он был бы вторым следствием одной ошибки: покрытие входов
## считается только по маршрутам, у которых список помещений ЧИТАЕТСЯ (массив строк), а
## «цель на маршруте» и «соседние пары» — только по тем, у которых он непуст. Иначе
## `route: "не массив"` давал бы ещё и «вход не обслужен», и «цель не на маршруте» —
## три диагноза на одну опечатку в типе.
##
## `entries` — узлы с тегом `entry` (считаны вызывающим). Пустой список сюда доходит
## свободно: «нет ни одного входа» уже названо `_check_reachability` кодом `UNREACHABLE`,
## и второго диагноза про то же мы не выписываем.
static func _check_routes(data: Dictionary, nodes: Dictionary, entries: Array, problems: Array) -> void:
	if not data.has("routes") or typeof(data["routes"]) != TYPE_ARRAY:
		return
	var duplicates := _duplicate_ids(data["routes"])
	if not duplicates.is_empty():
		problems.append(Problems.duplicate_id("routes", String(duplicates[0])))
	## Цель считается ОДИН раз: она не зависит от маршрута, а спрашивают её в цикле.
	## Нечитаемое поле даёт пустую строку — о нём уже сказано своим диагнозом, и второго
	## следствия («цель не на маршруте») на испорченное поле мы не выписываем.
	var objective := _objective_of(data)
	var starts: Dictionary = {}
	for i in (data["routes"] as Array).size():
		var entry_def = data["routes"][i]
		var path := "routes[%d]" % i
		if typeof(entry_def) != TYPE_DICTIONARY:
			problems.append(Problems.wrong_type(path, TYPE_DICTIONARY, typeof(entry_def)))
			continue
		var route_def: Dictionary = entry_def
		_check_keys(route_def, ROUTE_KEYS, path, problems)
		var label := _string_or(route_def.get("id", ""), "%s.id" % path, problems)
		if label == "":
			## Имени у маршрута нет — называть его дальше нечем, остаётся индекс.
			## Прежний `Path` структуры не меняется, и это тот же приём, что у окна без id.
			label = path
		var entry_node := _string_or(route_def.get("entry", ""), "%s.entry" % path, problems)
		var exit_node := _string_or(route_def.get("exit", ""), "%s.exit" % path, problems)
		## Вход и выход — узлы с тегом `entry`: в MVP выходом служит один из
		## входов («уходишь тем путём, каким вошёл»). Отдельного выхода уровень не объявляет,
		## и молчаливое расширение формы здесь недопустимо.
		##
		## Ссылка проверяется по СПИСКУ входов, а не по `nodes`: узел, существующий без тега
		## `entry`, — такой же дефект, как несуществующий, и сообщение обязано назвать
		## причину. Имена `nodes` и `entries` тут различаются: первое — «такого помещения
		## нет», второе — «оно есть, но это не вход».
		if entry_node != "" and not nodes.is_empty() and not nodes.has(entry_node):
			problems.append(Problems.bad_ref("%s.entry" % path, "нет помещения «%s»" % entry_node))
		elif entry_node != "" and not entries.is_empty() and not entries.has(entry_node):
			problems.append(Problems.route_end_not_entry("%s.entry" % path, entry_node, "вход"))
		if exit_node != "" and not nodes.is_empty() and not nodes.has(exit_node):
			problems.append(Problems.bad_ref("%s.exit" % path, "нет помещения «%s»" % exit_node))
		elif exit_node != "" and not entries.is_empty() and not entries.has(exit_node):
			problems.append(Problems.route_end_not_entry("%s.exit" % path, exit_node, "выход"))
		## Покрытие входов — ТОЛЬКО по маршрутам с честным `entry`: у маршрута без входа
		## корень уже назван, и второй диагноз («этот вход не обслужен») был бы следствием.
		if entry_node != "" and entries.has(entry_node):
			starts[entry_node] = int(starts.get(entry_node, 0)) + 1
		if not route_def.has("route"):
			problems.append(Problems.missing_field("%s.route" % path, TYPE_ARRAY))
			continue
		var list: Variant = _string_array_or(route_def["route"], "%s.route" % path, problems)
		if list == null:
			continue
		var route: Array = list
		if route.is_empty():
			problems.append(Problems.bad_value("%s.route" % path,
				"маршрут пуст: `route[0]` обязан быть входом, а `route[-1]` — выходом"))
			continue
		## Концы списка обязаны совпасть с объявленными `entry`/`exit`: иначе маршрут —
		## не тот, что объявлен, и норматив считается не по тому прохождению.
		if entry_node != "" and String(route[0]) != entry_node:
			problems.append(Problems.bad_value("%s.route" % path,
				"маршрут начинается с «%s», а объявленный вход — «%s»" % [String(route[0]), entry_node]))
		var last := route.size() - 1
		if exit_node != "" and String(route[last]) != exit_node:
			problems.append(Problems.bad_value("%s.route" % path,
				"маршрут кончается на «%s», а объявленный выход — «%s»" % [String(route[last]), exit_node]))
		## Соседние точки обязаны быть соединены ребром: маршрут — это прохождение по
		## РЁБРАМ графа. Разрыв означает, что объявленный проход невыполним, и норматив
		## посчитан по несуществующему пути.
		var size := route.size()
		for k in max(0, size - 1):
			if not _connected(String(route[k]), String(route[k + 1]), data):
				problems.append(Problems.bad_value("%s.route" % path,
					"разрыв маршрута: «%s» и «%s» не соединены ребром"
					% [String(route[k]), String(route[k + 1])]))
		## Цель обязана лежать на маршруте: норматив «окон за прохождение» считается по
		## проходам, которые к цели ВЕДУТ.
		if objective != "" and not route.has(objective):
			problems.append(Problems.objective_off_route(label, objective))
	## Ровно один маршрут на вход — и каждый вход обслужен ровно раз. Считается
	## по полю `entry` (счёт `starts[entry_node]` выше — там же, где проверено, что
	## `entry` действительно вход), а не по числу записей: запись с чужим `entry` вход
	## не обслуживает, и объявить два маршрута с одним входом нельзя — «ровно один».
	if entries.is_empty():
		return
	var missing: Array = []
	var repeated: Array = []
	for entry_node in entries:
		var count := int(starts.get(String(entry_node), 0))
		if count == 0:
			missing.append(String(entry_node))
		elif count > 1:
			repeated.append("%s (%d)" % [String(entry_node), count])
	if not missing.is_empty():
		problems.append(Problems.routes_per_entry("routes", "нет маршрута для входа: %s" % ", ".join(missing)))
	if not repeated.is_empty():
		problems.append(Problems.routes_per_entry("routes", "больше одного маршрута у входа: %s" % ", ".join(repeated)))


## Цель миссии строкой или пустая строка, если поле не читается: о нечитаемом поле уже
## сказано (`WRONG_TYPE`/`MISSING_FIELD` в `_check_root_keys`/`_check_objective`), а
## валидатор падать не имеет права.
static func _objective_of(data: Dictionary) -> String:
	if not data.has("objective") or typeof(data["objective"]) != TYPE_STRING:
		return ""
	return String(data["objective"])


## Список помещений одной строкой — для СООБЩЕНИЙ (маршрут призрака, названный в диагнозе).
## Это не путь в файле: путь у проблемы свой, а здесь автору нужно узнать, С ЧЕМ совпало
## подброшенное расписание. Значения приводятся `str`, а не `String(...)`: конструктор
## `String` на Variant падает рантаймом, а сюда попадает что угодно из данных.
static func _route_text(route) -> String:
	if typeof(route) != TYPE_ARRAY:
		return str(route)
	var parts: Array = []
	for item in (route as Array):
		parts.append(str(item))
	return " → ".join(parts)


## Повторяющиеся id внутри раздела-массива. Возвращает список повторов в порядке
## появления — или пустой. Отдельная функция на один вызывающий (`_check_routes`):
## правило «id уникален» есть и у других разделов, но там оно записано на месте, в цикле,
## где id уже разбирается по типу; сюда вынесена только та проверка, чей раздел читается
## целиком и заранее. Общей функции «для всех разделов» здесь нет — это был бы второй
## проход по данным и второе место, где про id сказано разное.
static func _duplicate_ids(section) -> Array:
	var out: Array = []
	if typeof(section) != TYPE_ARRAY:
		return out
	var seen: Dictionary = {}
	for item in (section as Array):
		if typeof(item) != TYPE_DICTIONARY or not item.has("id"):
			continue
		var id := str(item["id"])
		if seen.has(id):
			if not out.has(id):
				out.append(id)
		else:
			seen[id] = true
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

## Есть ли ребро между парой помещений. Соседние точки маршрута патруля обязаны быть
## соединены: движок ведёт охранника по списку и путь не ищет (`01-format.md` §4.1).
static func _connected(a: String, b: String, data: Dictionary) -> bool:
	if a == "" or b == "" or not data.has("edges") or typeof(data["edges"]) != TYPE_ARRAY:
		return false
	for e in (data["edges"] as Array):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var ea := String(e.get("a", ""))
		var eb := String(e.get("b", ""))
		if (ea == a and eb == b) or (ea == b and eb == a):
			return true
	return false


static func _check_windows(data: Dictionary, known_edges: Dictionary, known_sensors: Dictionary,
		known_nodes: Dictionary, entries: Array, patrolled: Dictionary, problems: Array) -> void:
	if not data.has("windows") or typeof(data["windows"]) != TYPE_ARRAY:
		return
	var seen: Array = []
	for i in (data["windows"] as Array).size():
		var w = data["windows"][i]
		var index_path := "windows[%d]" % i
		if typeof(w) != TYPE_DICTIONARY:
			problems.append(Problems.wrong_type(index_path, TYPE_DICTIONARY, typeof(w)))
			continue
		## Путь окна — ПО ID, а не по индексу в массиве: так он читаемее и совпадает
		## с путями вариантов, молчания и триггера (`windows.w_door.options[0]`).
		## У окна без id (или с нестроковым id) назвать его больше нечем — остаётся индекс:
		## id в этом поле может оказаться числом, массивом или отсутствовать вовсе, а путь
		## обязан быть строкой и указывать хоть куда-то. Индексный путь здесь — не выбор,
		## а единственное, что остаётся; по нему автор находит окно в массиве файла. Тогда
		## `wid` дальше несёт `index_path` целиком (`windows[0]`), и пути полей выходят
		## `windows[0].kind`, `windows[0].options[0]` — то есть без имени окна.
		var wid := _string_or(w.get("id", ""), "%s.id" % index_path, problems)
		if wid == "":
			problems.append(Problems.missing_field("%s.id" % index_path, TYPE_STRING))
			wid = index_path
		elif seen.has(wid):
			problems.append(Problems.duplicate_id("windows", wid))
		else:
			seen.append(wid)
		var path := index_path if wid == index_path else "windows.%s" % wid
		_check_keys(w, WINDOW_KEYS, path, problems)
		if not w.has("text_key"):
			problems.append(Problems.missing_field("%s.text_key" % path, TYPE_STRING))
		_check_text_key(w, "text_key", path, problems)
		var kind := ""
		if not w.has("kind"):
			problems.append(Problems.missing_field("%s.kind" % path, TYPE_STRING))
		else:
			kind = _string_or(w["kind"], "%s.kind" % path, problems)
			if kind != "" and not WINDOW_KINDS.has(kind):
				problems.append(Problems.bad_value("%s.kind" % path,
					"неизвестный вид окна «%s», допустимы: %s" % [kind, ", ".join(WINDOW_KINDS)]))
		var trigger := _check_trigger(w, wid, known_edges, known_sensors, known_nodes, entries,
			patrolled, problems)
		var trigger_type := String(trigger["type"])
		## `kind` обязан совпадать с `trigger.type`. Сам по себе `kind` вид окна не задаёт:
		## рантайм-форму ядро собирает из `trigger.type`, а `kind`
		## лишь повторяет его для читателя (`01-format.md` §5.1). Расхождение — поле-обманка: автор думает, что
		## выбрал вид окна, а ядро открыло другое. Сверяем и говорим прямо.
		##
		## Сверка идёт только для ИЗВЕСТНОГО вида: у «магии» диагноз уже есть
		## («неизвестный вид окна»), и второе сообщение по тому же полю было бы вторым
		## следствием одной ошибки.
		if WINDOW_KINDS.has(kind) and trigger_type != "" and kind != trigger_type:
			problems.append(Problems.bad_value("%s.kind" % path,
				"вид окна «%s» не совпадает с триггером «%s»: рантайм-вид ядро строит из trigger.type, kind на него не влияет" % [kind, trigger_type]))
		_check_options(w, wid, trigger_type, known_edges, problems)
		_check_silence(w, wid, trigger_type, String(trigger["edge"]), known_edges, problems)


## ЯКОРЬ ОКНА ГРУППЫ ОБЯЗАН БЫТЬ ДОСТИЖИМ ОТ ВХОДОВ.
##
## Правило проверяет то, чего не видит ни одна проверка выше: окно можно поставить в части
## графа, куда группа не попадёт НИКОГДА. Прогон такое окно ловит только если построенный
## маршрут через его якорь вообще доходит до цели, а форма обязана не пускать дефект в
## работу — приёмка нашла это прогоном именно потому, что статически не называл никто.
##
## Правило СУДИТ ТОЛЬКО ОКНА ГРУППЫ — те, чей актёр приходит в якорь от входа:
##  * `node_entered` — помещение: группа обязана уметь в него войти;
##  * `locked_edge` — ребро: это отдельная проверка, а не вывод из «оба конца достижимы».
##    Ребро между двумя недостижимыми помещениями недостижимо, даже если граф связен
##    «где-то ещё», и обратное тоже верно — вывод из помещений здесь был бы догадкой.
##
## Окно `guard_in_sensor` сюда НЕ попадает, и это не пропуск. Его актёр — ОХРАНА, а охрана
## СТАРТУЕТ на своём маршруте (`sim.gd:setup` ставит её в `patrols[].route[0]`) и ходит по
## нему, не приходя от входов вовсе: крыло, отрезанное от входов, но со своим патрулём и
## сенсором, — законный уровень, и окно там срабатывает с первого шага. Недостижимость
## «от входов» к этому актёру неприменима; про сенсор, которого не касается НИ ОДИН патруль,
## говорит своё правило — `WINDOW_ON_UNVISITED_SENSOR` (`_check_trigger`). Прежняя редакция
## считала якорями зоны сенсора и отвергала такой уровень зря.
##
## Обход один на все окна (множество достижимых помещений считается ОДИН раз), но диагноз
## выписывается НА ОКНО: автору нужно окно, а не список помещений.
##
## Что сюда НЕ доходит:
##  * испорченный или неизвестный триггер — корень назван (`WRONG_TYPE`, `BAD_VALUE`);
##  * ссылка на несуществующий узел/ребро — корень назван (`BAD_REF`);
##  * миссия без рёбер или без входов — о входах говорит `_check_reachability`
##    (`UNREACHABLE`), и «якорь недостижим» было бы вторым следствием того же.
static func _check_window_reachability(data: Dictionary, known_edges: Dictionary,
		known_nodes: Dictionary, entries: Array, problems: Array) -> void:
	if not data.has("windows") or typeof(data["windows"]) != TYPE_ARRAY:
		return
	if entries.is_empty() or not data.has("edges") or typeof(data["edges"]) != TYPE_ARRAY:
		return
	var reachable := _reachable_from_entries(entries, data["edges"])
	for i in (data["windows"] as Array).size():
		var w = data["windows"][i]
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var wid := str(w.get("id", ""))
		if wid == "":
			wid = "windows[%d]" % i
		for anchor in _window_anchors(w, known_edges, known_nodes):
			if reachable.has(String(anchor["node"])):
				continue
			## Одно окно — один диагноз: у окна у ребра недостижимых концов может быть
			## два, но правка у автора одна (соединить якорь с графом).
			problems.append(Problems.window_on_unreachable_node(wid, String(anchor["what"])))
			break


## Якоря окна ГРУППЫ: список `{"node", "what"}`, где `node` — помещение графа, от которого
## зависит срабатывание, а `what` — словами, чем этот якорь является в окне (для сообщения).
##
## Пустой список — «судить не о чем»: триггера нет или он не той формы, ссылка не строка,
## объекта нет в миссии. Все эти случаи уже названы своими диагнозами, и второго следствия
## на них не выписываем. Рёбра разворачиваются в ОБА конца: ребро существует между двумя
## помещениями, и недостижим любой из них — окно не сработает.
##
## `guard_in_sensor` возвращает пустой список ВСЕГДА: актёр этого окна — охрана, и её
## приход в зону от входов не зависит (см. шапку `_check_window_reachability`). Молчание
## здесь не «проверка не сработала», а «этому актёру данное правило не адресовано»:
## о мёртвом сенсоре говорит `WINDOW_ON_UNVISITED_SENSOR`.
static func _window_anchors(w: Dictionary, known_edges: Dictionary,
		known_nodes: Dictionary) -> Array:
	var out: Array = []
	var trigger = w.get("trigger", null)
	if typeof(trigger) != TYPE_DICTIONARY:
		return out
	var trigger_dict: Dictionary = trigger
	if typeof(trigger_dict.get("type", null)) != TYPE_STRING:
		return out
	var type := String(trigger_dict["type"])
	match type:
		"node_entered":
			var node = trigger_dict.get("node", null)
			if typeof(node) == TYPE_STRING and known_nodes.has(String(node)):
				out.append({"node": String(node), "what": "помещение «%s»" % String(node)})
		"guard_in_sensor":
			## Актёр этого окна — охрана, и её приход в зону от входов не зависит: якоря
			## группы у него нет вовсе (шапка `_window_anchors`).
			return out
		"locked_edge":
			var edge = trigger_dict.get("edge", null)
			if typeof(edge) != TYPE_STRING or not known_edges.has(String(edge)):
				return out
			var record = known_edges[String(edge)]
			if typeof(record) == TYPE_DICTIONARY:
				## `a`/`b` читаются из записи ребра: второй сборки «id → концы» не заводим.
				for side in ["a", "b"]:
					var end = (record as Dictionary).get(side, null)
					if typeof(end) == TYPE_STRING and known_nodes.has(String(end)):
						out.append({"node": String(end), "what": "ребро «%s»" % String(edge)})
	return out


## Разбор триггера. Возвращает его вид и ребро (пустая строка, если ребра нет):
## вид нужен проверке молчания, ребро — проверке выполнимости окна у двери.
##
## Здесь же живут два диагноза «окно невозможно» — оба про АКТЁРА сцены, и оба видны только на
## триггере:
##  * `node_entered` на помещении с тегом `entry` — группа там стартует, события входа
##    не бывает (`WINDOW_ON_ENTRY_NODE`). Список входов приходит аргументом: второй его
##    сборки здесь не заводим.
##  * `guard_in_sensor`, чью зону не посещает НИ ОДИН патруль
##    (`WINDOW_ON_UNVISITED_SENSOR`) — сцена про человека на таком сенсоре не играется
##    никогда, потому что контакты сенсоров ядро выдаёт только охране.
##
## Оба судятся только по ЦЕЛОМУ триггеру: у испорченного `type`/`sensor`/`node` корень уже
## назван (`WRONG_TYPE`, `BAD_REF`), и второе следствие на ту же ошибку не выписываем
## (шапка файла). Неизвестный сенсор в `known_sensors` не значится — о нём говорит
## `_check_ref_key`, и «зона не посещается» про него было бы второй правдой о том же.
static func _check_trigger(w: Dictionary, wid: String, known_edges: Dictionary,
		known_sensors: Dictionary, known_nodes: Dictionary, entries: Array,
		patrolled: Dictionary, problems: Array) -> Dictionary:
	if not w.has("trigger"):
		problems.append(Problems.missing_field("windows.%s.trigger" % wid, TYPE_DICTIONARY))
		return {"type": "", "edge": ""}
	var trigger = w["trigger"]
	var path := "windows.%s.trigger" % wid
	if typeof(trigger) != TYPE_DICTIONARY:
		problems.append(Problems.wrong_type(path, TYPE_DICTIONARY, typeof(trigger)))
		return {"type": "", "edge": ""}
	_check_keys(trigger, TRIGGER_KEYS, path, problems)
	if not trigger.has("type"):
		problems.append(Problems.missing_field("%s.type" % path, TYPE_STRING))
		return {"type": "", "edge": ""}
	var type := _string_or(trigger["type"], "%s.type" % path, problems)
	if type == "":
		return {"type": "", "edge": ""}
	if not TRIGGER_TYPES.has(type):
		problems.append(Problems.bad_value("%s.type" % path,
			"неизвестный триггер «%s», допустимы: %s" % [type, ", ".join(TRIGGER_TYPES)]))
		return {"type": "", "edge": ""}
	var edge := ""
	match type:
		"locked_edge":
			_check_ref_key(trigger, "edge", "ребра", path, known_edges, problems)
			if typeof(trigger.get("edge", null)) == TYPE_STRING:
				edge = String(trigger["edge"])
		"node_entered":
			_check_ref_key(trigger, "node", "помещения", path, known_nodes, problems)
			var node := String(trigger.get("node", "")) if typeof(trigger.get("node", null)) == TYPE_STRING else ""
			if node != "" and entries.has(node):
				problems.append(Problems.window_on_entry_node(wid, node))
		"guard_in_sensor":
			_check_ref_key(trigger, "sensor", "сенсора", path, known_sensors, problems)
			## «Зону не посещает ни один патруль» — вопрос про ОБЪЕДИНЕНИЕ маршрутов:
			## второй патруль через ту же зону окно оживляет.
			##
			## Пустое множество патрулей сюда не попадает как «мёртвый сенсор»: у миссии
			## без патрулей корень в другом (их просто нет), и диагноз на каждое окно с
			## сенсором был бы следствием пустого раздела, а не дефектом окна. Об этом
			## прямо говорит положительный кейс «миссия без патрулей валидна».
			var sensor := String(trigger.get("sensor", "")) if typeof(trigger.get("sensor", null)) == TYPE_STRING else ""
			if sensor != "" and known_sensors.has(sensor) and not patrolled.is_empty():
				var visited := false
				var zones: Array = []
				for node in _sensor_nodes(sensor, known_sensors):
					zones.append(node)
					if patrolled.has(node):
						visited = true
				if not visited:
					problems.append(Problems.window_on_unvisited_sensor(wid, sensor, ", ".join(zones)))
	return {"type": type, "edge": edge}


## Поле обязательно, и по возможности ссылается на существующий объект.
static func _check_ref_key(obj: Dictionary, key: String, what: String, path: String,
		known: Dictionary, problems: Array) -> void:
	if not obj.has(key):
		problems.append(Problems.missing_field("%s.%s" % [path, key], TYPE_STRING))
		return
	var value := _string_or(obj[key], "%s.%s" % [path, key], problems)
	if value != "" and not known.is_empty() and not known.has(value):
		problems.append(Problems.bad_ref("%s.%s" % [path, key], "нет %s «%s»" % [what, value]))


static func _check_options(w: Dictionary, wid: String, trigger_type: String,
		known_edges: Dictionary, problems: Array) -> void:
	if not w.has("options"):
		problems.append(Problems.missing_field("windows.%s.options" % wid, TYPE_ARRAY))
		return
	if typeof(w["options"]) != TYPE_ARRAY:
		problems.append(Problems.wrong_type("windows.%s.options" % wid, TYPE_ARRAY, typeof(w["options"])))
		return
	var options: Array = w["options"]
	if options.is_empty():
		problems.append(Problems.empty_section("windows.%s.options" % wid))
		return
	var seen: Array = []
	## Сочетание цены и эффектов → id первого варианта с таким сочетанием (п. 20).
	var by_effect: Dictionary = {}
	for i in options.size():
		var o = options[i]
		var path := "windows.%s.options[%d]" % [wid, i]
		if typeof(o) != TYPE_DICTIONARY:
			problems.append(Problems.wrong_type(path, TYPE_DICTIONARY, typeof(o)))
			continue
		_check_keys(o, OPTION_KEYS, path, problems)
		## Ожидаемый тип в сообщении — по факту поля: `cost` словарь, `effects` массив,
		## `complexity` число. Прежний общий «String» отправлял автора искать строку там,
		## где схема её не обещала.
		for required in [["id", TYPE_STRING], ["text_key", TYPE_STRING], ["complexity", TYPE_INT],
				["cost", TYPE_DICTIONARY], ["effects", TYPE_ARRAY]]:
			if not o.has(String(required[0])):
				problems.append(Problems.missing_field("%s.%s" % [path, String(required[0])],
					required[1]))
		_check_text_key(o, "text_key", path, problems)
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
		var cost_ok := false
		if o.has("cost"):
			var cost = o["cost"]
			var cost_path := "%s.cost" % path
			if typeof(cost) != TYPE_DICTIONARY:
				problems.append(Problems.wrong_type(cost_path, TYPE_DICTIONARY, typeof(cost)))
			else:
				_check_keys(cost, COST_KEYS, cost_path, problems)
				cost_ok = true
				for field in ["noise", "delay"]:
					if not cost.has(field):
						problems.append(Problems.missing_field("%s.%s" % [cost_path, field], TYPE_INT))
						cost_ok = false
						continue
					var v: Variant = _int_or(cost[field], "%s.%s" % [cost_path, field], problems)
					if v == null:
						cost_ok = false
					elif int(v) < 0:
						problems.append(Problems.bad_value("%s.%s" % [cost_path, field],
							"цена не может быть отрицательной"))
		if o.has("effects"):
			_check_effects(o["effects"], "%s.effects" % path, known_edges, problems)
			_check_unlock_needs_door(o["effects"], "%s.effects" % path, trigger_type, problems)
		## Дубль варианта — два приказа с одинаковой ценой и одинаковыми последствиями:
		## выбор между ними ничего не меняет. Порядок эффектов значим (импульс, шум,
		## задержка — разный ход), поэтому сравнивается последовательность целиком.
		var signature := _option_signature(o, cost_ok)
		if signature == "":
			continue
		if by_effect.has(signature):
			problems.append(Problems.make(Problems.DUPLICATE_ID, path,
				"вариант совпал с «%s» по цене и эффектам" % String(by_effect[signature])))
		else:
			by_effect[signature] = oid if oid != "" else path


## Подпись варианта: цена плюс эффекты в порядке объявления. Пустая строка — подпись
## неполна (цена или эффекты не той формы), сравнивать нечего: об этом уже сказано.
## Значения приводятся `str`, а не `String(...)`: конструктор String на Variant падает
## рантаймом («Invalid call 'String' constructor»), и подпись молча ломала прогон.
static func _option_signature(o: Dictionary, cost_ok: bool) -> String:
	if not cost_ok or not o.has("effects") or typeof(o["effects"]) != TYPE_ARRAY:
		return ""
	var cost: Dictionary = o["cost"]
	var parts: Array = ["noise=%d" % int(cost["noise"]), "delay=%d" % int(cost["delay"])]
	for i in (o["effects"] as Array).size():
		var e = o["effects"][i]
		if typeof(e) != TYPE_DICTIONARY or not e.has("type"):
			return ""
		parts.append("%d:type=%s" % [i, str(e["type"])])
		for field in ["edge", "value", "id"]:
			if e.has(field):
				parts.append("%s=%s" % [field, str(e[field])])
	return "|".join(parts)


## Окно, которое ждёт не запертой двери, открывать нечего: `unlock` снимает блокировку с
## РЕБРА, а `node_entered` и `guard_in_sensor` срабатывают не на ребре. Ядро такой эффект
## применит (снимает блокировку по id ребра и о триггере не спрашивает), и автор будет считать, что поставил
## сцену с открытием двери, а открывать нечего (`01-format.md` §5.5).
##
## Правило ОДНО на все места окна, где бывают эффекты: варианты (`options[].effects`) и
## четыре исхода молчания. Прежняя проверка жила только в молчании, и `unlock` в варианте
## окна «группа вошла в помещение» проходил молча.
##
## `path` — путь ПОЛЯ с эффектами, а не элемента списка: диагноз адресует место, где эффект
## объявлен, и совпадает с прежним диагнозом молчания. Форму списка и его элементов уже
## назвал `_check_effects` (`WRONG_TYPE` на не-массив и на не-словарь внутри): разбирать
## нечего, и второго следствия одному дефекту не выписываем (шапка файла). Испорченный
## триггер (`trigger_type == ""`) сюда тоже не доходит: о нём сказано на `trigger.type`.
##
## Заглядывает и в `fallback` заявки движку: это ТО ЖЕ место окна на уровень глубже, и
## `unlock` там открывает ровно то же, чего у окна нет. Читается `fallback` обеими
## формами (`01-format.md` §7) через `_as_effect_list` — тем же приведением, что у `_check_fallback`.
## Мусор и пустой `fallback` не разбираются: их форма уже названа, и второго следствия
## одному дефекту не выписываем.
##
## Правило зовётся ТОЛЬКО из окон и только у окна не про дверь: «открывать нечего» —
## утверждение про то, чего ждёт ЭТО окно. Общим разбором всех списков эффектов оно быть
## не может: `unlock` законен у двери (`locked_edge`), и общий разбор покраснил бы честный
## контент. Точки доступа (`access_points[].actions[].effects`) сюда не попадают вовсе —
## раздела в форме больше нет, а действие у терминала выражается вариантом окна.
static func _check_unlock_needs_door(raw, path: String, trigger_type: String, problems: Array) -> void:
	if trigger_type == "" or trigger_type == "locked_edge":
		return
	if typeof(raw) != TYPE_ARRAY:
		return
	var effects: Array = raw
	for i in effects.size():
		var effect = effects[i]
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		## `str`, а не `String`: значение приходит из данных и может быть словарём —
		## конструктор `String` на таком значении падает рантаймом.
		var type := str(effect.get("type", ""))
		if type == "unlock":
			problems.append(Problems.bad_value(path,
				"unlock у окна с триггером «%s»: открывать нечего" % trigger_type))
		elif type == "engine_proposal":
			_check_unlock_needs_door(_as_effect_list(effect.get("fallback", null)),
				"%s[%d].fallback" % [path, i], trigger_type, problems)


## Разрешённые поля `silence` (`01-format.md` §6 плюс ключи качеств): базовый ключ
## текста, ключ качества на каждый исход, сами эффекты исхода, заметка.
##
## Ключи качеств (`good_key`, …) — НЕобязательные поля: без них читается базовый
## `text_key`, поэтому они проверяются по типу, а
## не на присутствие (`01-format.md` §6.2). Собираются они здесь, а не переписываются константой рядом:
## третье качество, добавленное в `SILENCE_QUALITIES`, обязано приехать и сюда.
static func _silence_keys() -> Array:
	var out: Array = ["text_key"]
	for quality in SILENCE_QUALITIES:
		out.append("%s_key" % quality)
	for quality in SILENCE_QUALITIES:
		out.append(quality)
	out.append("note")
	return out


static func _check_silence(w: Dictionary, wid: String, trigger_type: String, trigger_edge: String,
		known_edges: Dictionary, problems: Array) -> void:
	var path := "windows.%s.silence" % wid
	if not w.has("silence"):
		problems.append(Problems.missing_silence(wid))
		return
	var silence = w["silence"]
	if typeof(silence) != TYPE_DICTIONARY:
		problems.append(Problems.wrong_type(path, TYPE_DICTIONARY, typeof(silence)))
		return
	_check_keys(silence, _silence_keys(), path, problems)
	if not silence.has("text_key"):
		problems.append(Problems.missing_field("%s.text_key" % path, TYPE_STRING))
	_check_text_key(silence, "text_key", path, problems)
	for quality in SILENCE_QUALITIES:
		_check_text_key(silence, "%s_key" % quality, path, problems)
	var complete := true
	for quality in SILENCE_QUALITIES:
		if not silence.has(quality):
			complete = false
	if not complete:
		problems.append(Problems.missing_silence(wid))
	## `form_ok` — «о молчании можно судить»: все четыре исхода на месте, и каждый из них
	## массив. Если форма неполна, корень уже назван (`MISSING_SILENCE`), и второй диагноз
	## про выполнимость был бы вторым следствием одной ошибки (см. шапку файла).
	var form_ok := complete
	var unlocks_edge := false
	for quality in SILENCE_QUALITIES:
		if not silence.has(quality):
			continue
		var q_path := "%s.%s" % [path, quality]
		_check_effects(silence[quality], q_path, known_edges, problems)
		## Правило «открывать нечего» — то же, что у вариантов: ОДИН хелпер на оба места
		## окна, где бывают эффекты, и один код проблемы (`_check_unlock_needs_door`).
		_check_unlock_needs_door(silence[quality], q_path, trigger_type, problems)
		## Разбор эффектов идёт только у массива: одиночный объект — уже названная болезнь
		## формы (`_check_effects` → `WRONG_TYPE`, `01-format.md` §6). Единый разбор обоих
		## форматов есть только у `fallback` (`01-format.md` §7) — там его и делает `_check_fallback`.
		if typeof(silence[quality]) != TYPE_ARRAY:
			form_ok = false
			continue
		for effect in (silence[quality] as Array):
			## Не словарь — форма элемента уже названа (`WRONG_TYPE` в `_check_effects`),
			## разбирать нечего, и о выполнимости судить не по чему.
			if typeof(effect) != TYPE_DICTIONARY:
				form_ok = false
				continue
			## Зачёт выполнимости: `unlock` на нужное ребро — сам или внутри fallback.
			if trigger_edge != "" and _opens_edge(effect, trigger_edge):
				unlocks_edge = true
	## Выполнимость окна у двери. Окно срабатывает один раз за миссию (`01-format.md` §5.2),
	## а приказ может быть и не отдан: если ни один исход молчания не открывает ИМЕННО
	## это ребро, группа остаётся перед запертой дверью навсегда. Варианты в зачёт не
	## идут — молчание не должно означать провал. Достаточно одного исхода из четырёх:
	## валидатор ловит невыполнимость, а не отступление от просьбы положить `unlock`
	## во ВСЕ четыре исхода (`01-format.md` §8: требование формы — минимум, наша
	## просьба — все четыре).
	##
	## Правило смотрит на РЕБРО, а не на имя триггера, и судит только о существующем
	## ребре с ЧЕСТНЫМ `locked`:
	##  * ребра нет (`BAD_REF` уже сказан) — судить не о чем, второго следствия не будет;
	##  * `locked` не bool (`WRONG_TYPE` уже сказан в `_check_edges`) — о запертости судить
	##    не по чему, и второго следствия одному дефекту не выписываем;
	##  * ребро не запираемо — окно не сработает ни разу, и это отдельный диагноз
	##    (`WINDOW_ON_OPEN_EDGE`), а не невыполнимость;
	##  * форма молчания неполна или неверна — корень назван (`MISSING_SILENCE`,
	##    `WRONG_TYPE`), и о выполнимости судить рано.
	##
	## «ЗАПИРАЕМО» = заперто замком ИЛИ перекрывается тревогой (`_blocked_by_alarm`).
	## Окно ★27 поставки висит на ребре `e_freight_4_0` (`lift_freight`), которое закрывает
	## тревога, а не замок: сцена у такого ребра срабатывает так же, как у двери, и ядро
	## снимает обе блокировки одним `unlock`.
	if trigger_type == "locked_edge" and known_edges.has(trigger_edge):
		var edge: Dictionary = known_edges[trigger_edge]
		var locked = edge["locked"]
		if typeof(locked) == TYPE_BOOL:
			if not bool(locked) and not _blocked_by_alarm(edge):
				problems.append(Problems.window_on_open_edge(wid, trigger_edge))
			elif form_ok and not unlocks_edge:
				problems.append(Problems.unwinnable_edge(wid, trigger_edge))


## Перекрывается ли ребро тревогой по своему ВИДУ. Список видов — в ядре
## (`sim/response.gd:BLOCKED_KINDS`): второй список здесь разошёлся бы с ядром молча —
## тот же класс дефекта, что `TRIGGER_TYPES`/`WINDOW_KINDS`, только через границу
## «контент ↔ ядро», и заметить его было бы нечем (валидатор и прогон смотрели бы
## на разные списки).
##
## Вопрос именно «может ли тревога вообще перекрыть этот вид», а не «перекрыто ли оно
## сейчас»: у валидатора нет и не должно быть состояния прогона — тревоги в файле нет.
static func _blocked_by_alarm(edge: Dictionary) -> bool:
	return Response.blockable_kind(String(edge.get("kind", "")))


## Открывает ли эффект `unlock` указанное ребро. Считается и `fallback` предложения
## движку: ядро применяет fallback, и если `unlock` стоит там — дверь откроется.
##
## Аргумент без типа намеренно: `fallback` бывает и списком, и одиночным объектом, и
## элементом списка может оказаться что угодно. Не словарь — не открывает ничего:
## форма такого элемента уже названа `WRONG_TYPE`, а падать валидатор не имеет права.
static func _opens_edge(effect, edge: String) -> bool:
	if typeof(effect) != TYPE_DICTIONARY:
		return false
	if str(effect.get("type", "")) == "unlock":
		return str(effect.get("edge", "")) == edge
	if str(effect.get("type", "")) != "engine_proposal":
		return false
	for fallback_effect in _as_effect_list(effect.get("fallback", null)):
		if _opens_edge(fallback_effect, edge):
			return true
	return false


static func _check_effects(raw, path: String, known_edges: Dictionary, problems: Array) -> void:
	if typeof(raw) != TYPE_ARRAY:
		problems.append(Problems.wrong_type(path, TYPE_ARRAY, typeof(raw)))
		return
	var effects: Array = raw
	for i in effects.size():
		var e = effects[i]
		var e_path := "%s[%d]" % [path, i]
		if typeof(e) != TYPE_DICTIONARY:
			problems.append(Problems.wrong_type(e_path, TYPE_DICTIONARY, typeof(e)))
			continue
		_check_keys(e, EFFECT_KEYS, e_path, problems)
		if not e.has("type"):
			problems.append(Problems.missing_field("%s.type" % e_path, TYPE_STRING))
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
					problems.append(Problems.missing_field("%s.edge" % e_path, TYPE_STRING))
				else:
					var edge := _string_or(e["edge"], "%s.edge" % e_path, problems)
					if edge != "" and not known_edges.is_empty() and not known_edges.has(edge):
						problems.append(Problems.bad_ref("%s.edge" % e_path, "нет ребра «%s»" % edge))
			"noise", "delay", "money", "trace":
				if not e.has("value"):
					problems.append(Problems.missing_field("%s.value" % e_path, TYPE_INT))
				else:
					var v: Variant = _int_or(e["value"], "%s.value" % e_path, problems)
					if v != null and int(v) < 0:
						problems.append(Problems.bad_value("%s.value" % e_path, "значение не может быть отрицательным"))
			"mark":
				## Метка называется СТРОКОЙ, а не числом: `marks` в результате прогона —
				## `Array[String]`, отсортированный по алфавиту (детерминизм отпечатка), и
				## число здесь сделало бы выбор в окне неразличимым в «Итогах».
				if not e.has("id"):
					problems.append(Problems.missing_field("%s.id" % e_path, TYPE_STRING))
				else:
					_string_or(e["id"], "%s.id" % e_path, problems)
			"engine_proposal":
				## `id`, `want`, `needs` — строки, `fallback` — одиночный эффект ИЛИ массив
				## (`01-format.md` §7) и он обязателен: без него окно останется без эффекта. Раньше в слот
				## ожидаемого ТИПА подставлялась целая фраза, и автор читал «ожидался без
				## fallback окно останется без эффекта».
				for required in [["id", TYPE_STRING], ["want", TYPE_STRING], ["needs", TYPE_STRING],
						["fallback", "словарь эффекта или массив эффектов"]]:
					if not e.has(String(required[0])):
						problems.append(Problems.missing_field("%s.%s" % [e_path, String(required[0])],
							required[1]))
				## `fallback` — эффект из словаря эффектов (`01-format.md` §5.5), который сработает, если предложение
				## отклонят. Он обязан быть разобран по тем же правилам: иначе
				## `unlock` в fallback открывал бы несуществующее ребро.
				if e.has("fallback"):
					_check_fallback(e["fallback"], "%s.fallback" % e_path, known_edges, problems)


## `fallback` у `engine_proposal` — одиночный эффект ИЛИ массив, форматы равнозначны
## (`01-format.md` §7). Приводим к массиву: `_check_effects` знает только массивы.
##
## Пустой массив — не «не тот тип»: тип как раз верный, пусто СОДЕРЖИМОЕ, и сказать надо
## это. Прежнее сообщение («ожидался словарь эффекта, получен Array») врало: автор шёл
## менять тип там, где тип правильный, а `fallback` был просто пустым.
static func _check_fallback(raw, path: String, known_edges: Dictionary, problems: Array) -> void:
	if typeof(raw) == TYPE_ARRAY and (raw as Array).is_empty():
		problems.append(Problems.bad_value(path,
			"пустой массив эффектов: у заявки движку обязателен `fallback` — если предложение отклонят, окно останется без эффекта"))
		return
	var list := _as_effect_list(raw)
	if list.is_empty():
		problems.append(Problems.wrong_type(path, "словарь эффекта или массив эффектов",
			typeof(raw)))
		return
	_check_effects(list, path, known_edges, problems)


## Приведение к списку эффектов. Терпимость к одиночному объекту — РОВНО там, где её
## разрешает схема: `fallback` у `engine_proposal` (`01-format.md` §7: «`fallback` — один
## эффект объектом ИЛИ массив эффектов; форматы равнозначны»). В `silence.<quality>`
## и `options[].effects` одиночный объект — ошибка формы: `_check_effects` выдаёт на него
## `WRONG_TYPE`, и дальше он не разбирается. Здесь только нормализация; сама проверка формы
## живёт в `_check_effects`.
static func _as_effect_list(raw) -> Array:
	if typeof(raw) == TYPE_ARRAY:
		return raw
	if typeof(raw) == TYPE_DICTIONARY:
		return [raw]
	return []


# --- разведка -----------------------------------------------------------------

## `_check_intel` судит разведку по трём правилам: форма блока и пунктов, ровно один
## подброшенный пункт у агентуры (`INTEL_LIE_COUNT`) и **расхождение призрака с
## реальностью** (`GHOST_SAME_AS_REAL`).
##
## Почему расхождение — правило формы, а не пожелание: сцена «призрак разошёлся» —
## единственный индикатор тревоги в игре (так задан уровень), и предусматривается
## она ДАННЫМИ — маршрутом и периодом. Призрак, совпавший с реальным патрулём **по любому
## из двух признаков**, расходится неполно: совпавший маршрут исчезает через такт, а
## совпавший период виден только по времени. «Честный, но устаревший» пункт
## выражается возрастом данных (`age_hours`), а не копией расписания.
static func _check_intel(data: Dictionary, known_patrols: Dictionary, patrols: Dictionary,
		problems: Array) -> void:
	if not data.has("intel") or typeof(data["intel"]) != TYPE_ARRAY:
		return
	for i in (data["intel"] as Array).size():
		var block = data["intel"][i]
		var path := "intel[%d]" % i
		if typeof(block) != TYPE_DICTIONARY:
			problems.append(Problems.wrong_type(path, TYPE_DICTIONARY, typeof(block)))
			continue
		_check_keys(block, INTEL_KEYS, path, problems)
		if not block.has("channel"):
			problems.append(Problems.missing_field("%s.channel" % path, TYPE_STRING))
			continue
		var channel := _string_or(block["channel"], "%s.channel" % path, problems)
		## Значение канала обязано быть из перечня: опечатка («agentss») проходила молча, и
		## блок разведки не попадал ни в один канал на экране (`01-format.md` §9).
		##
		## Правило лжи ниже судится только по ИЗВЕСТНОМУ каналу: у «магии» корень уже назван,
		## и второе следствие на ту же ошибку (`INTEL_LIE_COUNT` про агентуру, которой в файле
		## нет) было бы вторым диагнозом одному дефекту (шапка файла).
		if channel != "" and not INTEL_CHANNELS.has(channel):
			problems.append(Problems.bad_value("%s.channel" % path,
				"неизвестный канал «%s», допустимы: %s" % [channel, ", ".join(INTEL_CHANNELS)]))
		if block.has("observed_at"):
			var observed: Variant = _int_or(block["observed_at"], "%s.observed_at" % path, problems)
			if observed != null and int(observed) < 0:
				problems.append(Problems.bad_value("%s.observed_at" % path,
					"снимок не может быть сделан на отрицательном шаге"))
		if not block.has("entries") or typeof(block["entries"]) != TYPE_ARRAY:
			problems.append(Problems.missing_field("%s.entries" % path, TYPE_ARRAY))
			continue
		var lies := 0
		## Ложь считается только по честным пометкам `false`: у мусора в поле диагноз уже
		## есть (`WRONG_TYPE`), и `INTEL_LIE_COUNT` по тому же полю был бы вторым следствием.
		var lies_known := true
		var entries: Array = block["entries"]
		for j in entries.size():
			var entry = entries[j]
			var e_path := "%s.entries[%d]" % [path, j]
			if typeof(entry) != TYPE_DICTIONARY:
				problems.append(Problems.wrong_type(e_path, TYPE_DICTIONARY, typeof(entry)))
				continue
			_check_keys(entry, INTEL_ENTRY_KEYS, e_path, problems)
			if not entry.has("kind"):
				problems.append(Problems.missing_field("%s.kind" % e_path, TYPE_STRING))
				continue
			var kind := _string_or(entry["kind"], "%s.kind" % e_path, problems)
			if not INTEL_KINDS.has(kind):
				problems.append(Problems.bad_value("%s.kind" % e_path,
					"неизвестный вид данных «%s», допустимы: %s" % [kind, ", ".join(INTEL_KINDS)]))
			## Возраст данных — источник расхождения призрака с реальностью (`01-format.md` §9),
			## поэтому он обязателен и не может быть отрицательным: «свежее, чем сейчас» —
			## не данные, а ошибка.
			if not entry.has("age_hours"):
				problems.append(Problems.missing_field("%s.age_hours" % e_path, TYPE_INT))
			else:
				var age: Variant = _int_or(entry["age_hours"], "%s.age_hours" % e_path, problems)
				if age != null and int(age) < 0:
					problems.append(Problems.bad_value("%s.age_hours" % e_path,
						"возраст данных не может быть отрицательным"))
			## Данные разведки ссылаются на патруль по id: ссылка обязана существовать,
			## иначе призрак на карте будет указывать в никуда.
			if kind == "patrol" and entry.has("id"):
				var patrol_id := _string_or(entry["id"], "%s.id" % e_path, problems)
				if patrol_id != "" and not known_patrols.is_empty() and not known_patrols.has(patrol_id):
					problems.append(Problems.bad_ref("%s.id" % e_path, "нет патруля «%s»" % patrol_id))
				## ПРИЗРАК ОБЯЗАН РАСХОДИТЬСЯ. Правило смотрит на СУЩЕСТВУЮЩИЙ патруль
				## (о несуществующем сказано `BAD_REF`) и только на пункт вида `patrol`:
				## у `sensor`/`guard_count`/`door_state` расписания нет вовсе.
				##
				## Сравниваются ОБА признака, и КАЖДЫЙ обязан отличаться: «период без
				## маршрута даёт расхождение, которое игрок увидит только по времени, а
				## маршрут без периода — расхождение, которое исчезнет через такт». Значит,
				## «совпал ровно один» — ТАКОЙ ЖЕ дефект, как дословная копия, и диагноз
				## выписывается на любое совпадение. Прежнее чтение («совпал один —
				## расхождение есть») было слабее решения, и именно этой слабостью проходил
				## канонический контент: у трёх его пунктов маршрут совпадал с реальным, а
				## отличался только период.
				##
				## Форма полей здесь не судится: не-массив `route` или нечисло `period` уже
				## названы ниже (`WRONG_TYPE`), и призрак сравнивался бы с реальностью по
				## мусору. Поэтому сравнение идёт только по ЧИТАЕМЫМ полям, а `_int_or`
				## спрашивается с пустым списком проблем: это ЗОНД «число ли это», а не
				## проверка — диагноз за нечисло выписывается ровно один раз, ниже.
				var ghost_route = entry.get("route", null)
				var ghost_period: Variant = _int_or(entry.get("period", null), "", [])
				if patrol_id != "" and patrols.has(patrol_id) \
						and typeof(ghost_route) == TYPE_ARRAY and ghost_period != null:
					var real: Dictionary = patrols[patrol_id]
					var real_route = real.get("route", [])
					var real_period: Variant = _int_or(real.get("period", null), "", [])
					if typeof(real_route) == TYPE_ARRAY and real_period != null:
						var same_route := (ghost_route as Array) == (real_route as Array)
						var same_period := int(ghost_period) == int(real_period)
						if same_route or same_period:
							problems.append(Problems.ghost_same_as_real(e_path, patrol_id,
								_ghost_sameness(same_route, same_period, real_route, int(real_period))))
			## Поля разведки, объявленные схемой (`01-format.md` §9), проверяются ПО ТИПУ: маршрут призрака —
			## список помещений, период и счётчик — целые, состав сенсора — список, `false` —
			## булево. Раньше эти поля не проверялись вовсе: `"route": "floor3"` и
			## `"false": "да"` проходили молча.
			##
			## Ссылки ВНУТРИ маршрута с графом НЕ сверяются: призрак обязан врать, и в скелете
			## подброшенное расписание называет помещение, которого в миссии нет или которое есть,
			## но не на том этаже. Ложь здесь — часть замысла уровня, а не дефект ссылки
			## (`01-format.md` §9: «маршрут призрака с графом не сверяется»).
			if entry.has("route"):
				_string_array_or(entry["route"], "%s.route" % e_path, problems)
			if entry.has("period"):
				_int_or(entry["period"], "%s.period" % e_path, problems)
			if entry.has("nodes"):
				_string_array_or(entry["nodes"], "%s.nodes" % e_path, problems)
			if entry.has("node"):
				_string_or(entry["node"], "%s.node" % e_path, problems)
			if entry.has("count"):
				_int_or(entry["count"], "%s.count" % e_path, problems)
			if entry.has("note_key"):
				_string_or(entry["note_key"], "%s.note_key" % e_path, problems)
			## Пометка лжи. Не-bool — диагноз `WRONG_TYPE`, и счёт лож после него не считается:
			## иначе на одну ошибку выходило бы два следствия (`WRONG_TYPE` и
			## `INTEL_LIE_COUNT`), а автор искал бы недостающую ложь вместо кривого поля.
			if entry.has("false"):
				if typeof(entry["false"]) != TYPE_BOOL:
					lies_known = false
					problems.append(Problems.wrong_type("%s.false" % e_path, TYPE_BOOL,
						typeof(entry["false"])))
				elif bool(entry["false"]):
					lies += 1
		## Ложь агентуры — часть замысла уровня, а не бросок: ровно один подброшенный пункт
		## у канала `agents` (`01-format.md` §9).
		## Считается только там, где все пометки `false` — честные bool.
		if channel == INTEL_LIE_CHANNEL and lies_known and lies != 1:
			problems.append(Problems.intel_lie_count(channel, lies))


## Что именно у призрака совпало с реальностью — словами, для диагноза `GHOST_SAME_AS_REAL`.
##
## Отличий два (маршрут и период), и совпасть может любое из них по отдельности:
## «маршрут тот же» и «период тот же» — разные дефекты с разной правкой у автора (развести
## путь и развести ритм). Сообщение обязано назвать тот, который и надо править, — иначе
## автор слышит «призрак равен реальности» про пункт, где равен только период, и не знает,
## что менять. Реальный патруль называется целиком: с ним и сравнивают.
static func _ghost_sameness(same_route: bool, same_period: bool, real_route, real_period: int) -> String:
	var what := "дословная копия: и маршрут, и период"
	if same_route and not same_period:
		what = "маршрут совпал с реальным (отличается только период)"
	elif same_period and not same_route:
		what = "период совпал с реальным (отличается только маршрут)"
	return "%s; реальный патруль — маршрут %s, период %d" % [what, _route_text(real_route), real_period]


# --- тексты -------------------------------------------------------------------

## Собирает все ключи, на которые ссылаются данные, сверяет с текстами, ищет висячие
## и спрашивает про обязательные системные ключи (`REQUIRED_TEXT_KEYS`).
##
## `texts == null` — сверки нет вовсе: ни `MISSING_TEXT`, ни `MISSING_REQUIRED_TEXT`,
## ни `DANGLING_TEXT`. Это НЕ «пустые тексты»: пустой словарь — осмысленное «текстов нет»,
## и тогда каждый ключ данных получает `MISSING_TEXT` (а обязательные системные —
## `MISSING_REQUIRED_TEXT`). Разница между `null` и `{}` видна в каждой строке вызова и
## закреплена ассертами: `null` — сверки нет, `{}` — «текстов нет».
##
## Сюда приходят только `null` или словарь: третье состояние называет `validate`, и до
## сверки оно не доходит. Проверка формы аргумента живёт в ОДНОМ месте (`validate`),
## а не дублируется здесь: второй такой же `typeof` разошёлся бы с первым молча.
static func _check_texts(data: Dictionary, texts, problems: Array) -> void:
	if texts == null:
		return
	var used := _collect_text_keys(data)
	for entry in used:
		if not texts.has(String(entry["key"])):
			problems.append(Problems.missing_text(String(entry["path"]), String(entry["key"])))
	_check_required_texts(texts, used, problems)
	for key in texts:
		if _is_key_used(used, String(key)):
			continue
		if _is_unused_ok(String(key)):
			continue
		problems.append(Problems.dangling_text(String(key)))


## Отсутствие обязательного системного ключа (см. `REQUIRED_TEXT_KEYS`) — третий вопрос
## сверки текстов, рядом с «ключ данных есть в текстах» и «чужих ключей нет».
##
## Ключ, на который ССЫЛАЮТСЯ данные, здесь второй раз НЕ называется: общая сверка уже
## выписала ему `MISSING_TEXT` на его поле (`title_key` → ключ названия миссии), а «одна
## ошибка — одно следствие» — правило шапки файла. Так держится и название миссии: в
## обязательном перечне его нет (номер миссии в конвейерной константе давал ложный диагноз
## следующей миссии), а диагноз приходит от сверки данных и ровно один — на
## `title_key`, где ключ и живёт. Половина правила «данные называют ключ, а его в текстах
## нет» от этого не слабеет: она идёт по КАЖДОМУ ключу данных, включая название миссии.
##
## У системного ключа без поля в данных пути нет вовсе: `MISSING_TEXT` с чужим путём
## (`windows[3].text_key` у `log.silence`) был бы ложью. Такой ключ называет
## `MISSING_REQUIRED_TEXT` с путём в пространстве ИМЁН ТЕКСТОВ (`texts.log.silence`) —
## там же, где живёт `DANGLING_TEXT`.
static func _check_required_texts(texts: Dictionary, used: Array, problems: Array) -> void:
	for key in REQUIRED_TEXT_KEYS:
		if texts.has(key):
			continue
		if _is_key_used(used, key):
			continue
		problems.append(Problems.missing_required_text(key))


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
		problems.append(Problems.wrong_type(path, expected, typeof(value)))


## Число: целое значение. Дробное — WRONG_TYPE, а не BAD_VALUE: JSON в Godot отдаёт
## float, и «1.5 шага» — это ошибка формы, а не диапазона.
static func _expect_int(value, path: String, problems: Array) -> void:
	if typeof(value) == TYPE_INT:
		return
	if typeof(value) == TYPE_FLOAT and is_equal_approx(value, floor(value)):
		return
	problems.append(Problems.wrong_type(path, TYPE_INT, typeof(value)))


## Возвращает int или null, если значение не число нужной формы.
static func _int_or(value, path: String, problems: Array):
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_FLOAT and is_equal_approx(value, floor(value)):
		return int(value)
	problems.append(Problems.wrong_type(path, TYPE_INT, typeof(value)))
	return null


static func _string_or(value, path: String, problems: Array) -> String:
	if typeof(value) != TYPE_STRING:
		problems.append(Problems.wrong_type(path, TYPE_STRING, typeof(value)))
		return ""
	return String(value)


## Поле, которое является КЛЮЧОМ ТЕКСТА, обязано быть строкой — не только
## присутствовать. Причина отдельная от общей типизации: без этой проверки
## испорченное поле молча выпадает из сбора текстовых ключей (`_walk_text_keys`
## берёт только строки), текст, на который поле ссылалось, остаётся без ссылки и
## объявляется висячим — и автор получает `DANGLING_TEXT` про текст, которого не
## терял, не видя, какое поле испорчено.
##
## `WRONG_TYPE` при этом ДОБАВЛЯЕТСЯ к тому диагнозу, а не заменяет его: поле
## действительно оставило свой текст без ссылки, и оба следствия верны. Так же ведёт
## себя испорченный `name_key` помещения и `facility_key`; каскад здесь не гасится —
## гашение было бы отдельным правилом «одна ошибка — одно следствие», и оба диагноза
## закреплены ассертами.
static func _check_text_key(obj: Dictionary, key: String, path: String, problems: Array) -> void:
	if obj.has(key):
		_string_or(obj[key], "%s.%s" % [path, key], problems)


static func _check_string_array(value, path: String, problems: Array) -> void:
	if typeof(value) != TYPE_ARRAY:
		problems.append(Problems.wrong_type(path, TYPE_ARRAY, typeof(value)))
		return
	for i in (value as Array).size():
		if typeof(value[i]) != TYPE_STRING:
			problems.append(Problems.wrong_type("%s[%d]" % [path, i], TYPE_STRING, typeof(value[i])))


## Массив строк или null, если это не массив (проблема уже добавлена).
static func _string_array_or(value, path: String, problems: Array):
	if typeof(value) != TYPE_ARRAY:
		problems.append(Problems.wrong_type(path, TYPE_ARRAY, typeof(value)))
		return null
	for i in (value as Array).size():
		if typeof(value[i]) != TYPE_STRING:
			problems.append(Problems.wrong_type("%s[%d]" % [path, i], TYPE_STRING, typeof(value[i])))
			return null
	return value

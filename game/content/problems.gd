extends RefCounted
## Проблема контента: код, путь и сообщение. Одна форма на весь конвейер.
##
## Зачем коды. Прежний валидатор (`sim/mission.gd:validate`) отдаёт русские строки, и
## вызывающий не может отличить «нет помещения» от «неизвестный вид ребра», не разбирая
## текст. Конвейеру нужна машинная причина: тесты и отчёт прогона смотрят на код,
## человек читает сообщение.
##
## Путь указывает место в файле контента, а не в рантайме: `nodes.hall.floor`,
## `windows.w_door.options[0].id`. По нему автор находит ошибку, не читая загрузчик.
## Путь объекта — по его id, где id есть; индекс (`windows[2]`) остаётся только у объекта,
## у которого id нет или он не строка: тогда назвать его больше нечем.
##
## Модуль ничего не печатает и ничего не проверяет — только строит проблемы.
## Проверки живут в `content/validator.gd`.

# --- структурные: файл не той формы ---
const MISSING_FIELD := "MISSING_FIELD"     ## обязательного поля нет
const WRONG_TYPE := "WRONG_TYPE"           ## поле есть, но другого типа
const UNKNOWN_KEY := "UNKNOWN_KEY"         ## поле, которого схема не знает
const EMPTY_SECTION := "EMPTY_SECTION"     ## раздел обязателен и не может быть пустым
const BAD_JSON := "BAD_JSON"               ## строка не разбирается как JSON

# --- значения: форма верна, значение бессмысленно ---
const DUPLICATE_ID := "DUPLICATE_ID"       ## id повторяется внутри своего раздела
const RESERVED_ID := "RESERVED_ID"         ## id занят движком (свои агенты, D-решение)
const BAD_VALUE := "BAD_VALUE"             ## значение вне допустимого (диапазон, перечисление)
const BAD_REF := "BAD_REF"                 ## ссылка на несуществующий объект
const UNREACHABLE := "UNREACHABLE"         ## до цели нельзя дойти по рёбрам

# --- правила уровня: форма и значения верны, нарушен закон игры ---
const MISSING_SILENCE := "MISSING_SILENCE" ## у окна нет молчания (запрещено, D23)
const SILENCE_AS_OPTION := "SILENCE_AS_OPTION" ## «молчать» подсунуто обычным вариантом
const UNWINNABLE_EDGE := "UNWINNABLE_EDGE" ## окно оставляет группу перед запертой дверью навсегда
const WINDOW_ON_OPEN_EDGE := "WINDOW_ON_OPEN_EDGE" ## окно привязано к ребру, которое не заперто: не сработает никогда
const MISSING_TEXT := "MISSING_TEXT"       ## ключ текста не найден в текстах
const MISSING_REQUIRED_TEXT := "MISSING_REQUIRED_TEXT" ## обязательного системного ключа нет в текстах
const DANGLING_TEXT := "DANGLING_TEXT"     ## ключ текста нигде не используется
const INTEL_LIE_COUNT := "INTEL_LIE_COUNT" ## подброшенных пунктов не ровно один


static func make(code: String, path: String, message: String) -> Dictionary:
	return {"code": code, "path": path, "message": message}


## Имя типа для сообщений — по-русски и из ОДНОГО места: `TYPE_*` → слово, готовая строка
## пропускается как есть (ею описывают ожидание там, где схема разрешает не один тип,
## например `fallback`, §7). Незнакомый `TYPE_*` отдаётся через `type_string` — честный
## откат вместо молчания.
##
## Норма словаря: `строка`, `массив`, `целое`, `логическое`, `дробное`, `словарь`, `ничто`.
## Рамки сообщений безличные («ожидалось: …»): словарь смешанного рода, и любое
## согласование («ожидался …») ломалось бы на половине слов.
##
## Рамка — часть контракта, а не оформление: на неё опираются ассерты кейсов (они сверяют
## обе половины — ожидаемый и фактический тип). Менять формулировку значит менять и их.
static func type_name(expected) -> String:
	if typeof(expected) == TYPE_STRING:
		return String(expected)
	var names := {
		TYPE_NIL: "ничто",
		TYPE_BOOL: "логическое",
		TYPE_INT: "целое",
		TYPE_FLOAT: "дробное",
		TYPE_STRING: "строка",
		TYPE_STRING_NAME: "строка",
		TYPE_ARRAY: "массив",
		TYPE_DICTIONARY: "словарь",
	}
	var type := int(expected)
	return String(names.get(type, type_string(type)))


## `expected` — `TYPE_*` (см. `type_name`) или готовое описание словами.
static func missing_field(path: String, expected) -> Dictionary:
	return make(MISSING_FIELD, path, "нет обязательного поля (ожидалось: %s)" % type_name(expected))


## `expected` — `TYPE_*` или описание словами; `actual` — `typeof(значение)`, а не
## `type_string(...)`: отображение имени живёт в `type_name`, а не размазано по вызовам.
static func wrong_type(path: String, expected, actual: int) -> Dictionary:
	return make(WRONG_TYPE, path, "ожидалось: %s, получено: %s" % [type_name(expected), type_name(actual)])


static func unknown_key(path: String, key: String) -> Dictionary:
	return make(UNKNOWN_KEY, path, "схема не знает поля «%s»" % key)


## Строка и причина сбоя разбора: `error` — код `Error` от `JSON.parse()`,
## `error_line` — 1-based номер строки (0, если движок его не знает).
static func bad_json(error: int, error_line: int, error_message: String) -> Dictionary:
	var where := "строка %d" % error_line if error_line > 0 else "(место неизвестно)"
	return make(BAD_JSON, "(корень)", "не разбирается как JSON: %s — %s" % [error_message, where])


static func empty_section(section: String) -> Dictionary:
	return make(EMPTY_SECTION, section, "раздел «%s» не может быть пустым" % section)


static func duplicate_id(section: String, id: String) -> Dictionary:
	return make(DUPLICATE_ID, section, "id «%s» повторяется в разделе «%s»" % [id, section])


## Отдельно от `duplicate_id`: повтора нет, id просто занят движком. Прежнее сообщение
## «повторяется в разделе patrols» отправляло автора искать несуществующий дубль.
static func reserved_id(section: String, id: String) -> Dictionary:
	return make(RESERVED_ID, section, "id «%s» зарезервирован движком, в разделе «%s» его быть не может" % [id, section])


static func bad_value(path: String, why: String) -> Dictionary:
	return make(BAD_VALUE, path, why)


static func bad_ref(path: String, why: String) -> Dictionary:
	return make(BAD_REF, path, why)


static func unreachable(path: String, why: String) -> Dictionary:
	return make(UNREACHABLE, path, why)


static func missing_silence(window_id: String) -> Dictionary:
	return make(MISSING_SILENCE, "windows.%s" % window_id,
		"у окна нет молчания — а оно обязано быть у каждого (D23)")


static func silence_as_option(window_id: String) -> Dictionary:
	return make(SILENCE_AS_OPTION, "windows.%s.options" % window_id,
		"«молчать» подсунуто обычным вариантом: молчание встроено в форму окна и приказа не тратит")


## Окно у запертой двери срабатывает один раз (02-format.md §4.2). Если ни один исход
## молчания не открывает это ребро, молчание оставляет группу перед дверью навсегда —
## тупик, а «ничто не является стеной, всё является ценой» (06-borders.md §4, D20).
static func unwinnable_edge(window_id: String, edge: String) -> Dictionary:
	return make(UNWINNABLE_EDGE, "windows.%s.silence" % window_id,
		"ни один исход молчания не открывает ребро «%s»: окно сработает один раз, и группа останется перед дверью навсегда" % edge)


## Окно с триггером `locked_edge` держится за ребро, которое никто не запирал — ни замком,
## ни тревогой (виды рёбер, перекрываемых тревогой, знает ядро: `Response.blockable_kind`,
## `sim/response.gd`). Такое окно не откроется ни разу: ждать нечего. Это дефект контента,
## а не формальность — автор считает, что поставил сцену у двери, а сцены не будет.
## Отдельный код, а не `BAD_VALUE`: причина у дефекта своя, и автору нужно её название.
##
## «Не заперто» и «не запираемо» — разные вещи: ребро, перекрытое тревогой, дефектом НЕ
## является. Поэтому сообщение называет ОБЕ причины, по которым окно могло бы сработать:
## иначе автор идёт запирать ребро, которое и так запирается тревогой.
static func window_on_open_edge(window_id: String, edge: String) -> Dictionary:
	return make(WINDOW_ON_OPEN_EDGE, "windows.%s.trigger.edge" % window_id,
		"окно ждёт запертое ребро «%s», а оно не запирается ни замком, ни тревогой: окно не сработает никогда" % edge)


static func missing_text(path: String, key: String) -> Dictionary:
	return make(MISSING_TEXT, path, "ключа «%s» нет в текстах" % key)


## Обязательный СИСТЕМНЫЙ ключ (`validator.gd:REQUIRED_TEXT_KEYS`, 04-texts.md §4): у такого
## ключа НЕТ поля `*_key` в данных миссии, поэтому общая сверка его не видит и `MISSING_TEXT`
## ему не выписывает — и пропажа ключа раньше не называлась ничем.
##
## Отдельный код, а не `MISSING_TEXT`, потому что у проблемы другое МЕСТО: поля контента,
## которое можно было бы назвать, у системного ключа не существует, и путь вида
## `windows[3].text_key` был бы ложью — автор пошёл бы искать несуществующее поле. Путь
## здесь в пространстве ИМЁН ТЕКСТОВ (`texts.<ключ>`), как у `dangling_text`: там этот
## ключ и обязан появиться.
##
## Исключение названо прямо: если данные ВСЁ ЖЕ ссылаются на ключ из обязательного списка
## (`title_key` → `mission.01.title`), диагноз выписывает общая сверка — `MISSING_TEXT` на
## поле данных, и ровно один на ключ (`validator.gd:_check_required_texts`).
static func missing_required_text(key: String) -> Dictionary:
	return make(MISSING_REQUIRED_TEXT, "texts.%s" % key,
		"обязательного ключа «%s» нет в текстах: он относится к системе, а не к окну, и из данных миссии не выводится" % key)


static func dangling_text(key: String) -> Dictionary:
	return make(DANGLING_TEXT, "texts.%s" % key, "ключ «%s» нигде не используется" % key)


static func intel_lie_count(channel: String, count: int) -> Dictionary:
	return make(INTEL_LIE_COUNT, "intel.%s" % channel,
		"подброшенных пунктов %d, а у агентуры обязан быть ровно один" % count)


## Есть ли среди проблем такая-то. Этим спрашивают тесты (и любой вызывающий, которому
## важен один диагноз, а не весь список): валидатор отвечает не «болезнь уже названа»,
## а тем, что каскадные проверки пропускаются по испорченному полю.
static func has(problems: Array, code: String) -> bool:
	for p in problems:
		if String(p["code"]) == code:
			return true
	return false


## Сводка для сообщений: «BAD_REF nodes.hall» — коротко и однозначно. Единственный
## потребитель — кейс скелета постановки (`tests/cases/test_handoff_skeleton.gd`): список
## проблем печатается в имени ассерта, чтобы провал называл причину, а не «список непуст».
static func brief(p: Dictionary) -> String:
	return "%s %s" % [String(p["code"]), String(p["path"])]

extends RefCounted
## Проблема контента: код, путь и сообщение. Одна форма на весь конвейер.
##
## Зачем коды. Прежний валидатор (`sim/mission.gd:validate`) отдаёт русские строки, и
## вызывающий не может отличить «нет помещения» от «неизвестный вид ребра», не разбирая
## текст. Конвейеру нужна машинная причина: тесты и отчёт прогона смотрят на код,
## человек читает сообщение.
##
## Путь указывает место в файле контента, а не в рантайме: `nodes.hall.floor`,
## `windows[2].options[0].id`. По нему автор находит ошибку, не читая загрузчик.
##
## Модуль ничего не печатает и ничего не проверяет — только строит проблемы.
## Проверки живут в `content/validator.gd`.

# --- структурные: файл не той формы ---
const MISSING_FIELD := "MISSING_FIELD"     ## обязательного поля нет
const WRONG_TYPE := "WRONG_TYPE"           ## поле есть, но другого типа
const UNKNOWN_KEY := "UNKNOWN_KEY"         ## поле, которого схема не знает
const EMPTY_SECTION := "EMPTY_SECTION"     ## раздел обязателен и не может быть пустым

# --- значения: форма верна, значение бессмысленно ---
const DUPLICATE_ID := "DUPLICATE_ID"       ## id повторяется внутри своего раздела
const BAD_VALUE := "BAD_VALUE"             ## значение вне допустимого (диапазон, перечисление)
const BAD_REF := "BAD_REF"                 ## ссылка на несуществующий объект
const UNREACHABLE := "UNREACHABLE"         ## до цели нельзя дойти по рёбрам

# --- правила уровня: форма и значения верны, нарушен закон игры ---
const MISSING_SILENCE := "MISSING_SILENCE" ## у окна нет молчания (запрещено, D23)
const SILENCE_AS_OPTION := "SILENCE_AS_OPTION" ## «молчать» подсунуто обычным вариантом
const MISSING_TEXT := "MISSING_TEXT"       ## ключ текста не найден в текстах
const DANGLING_TEXT := "DANGLING_TEXT"     ## ключ текста нигде не используется
const INTEL_LIE_COUNT := "INTEL_LIE_COUNT" ## подброшенных пунктов не ровно один


static func make(code: String, path: String, message: String) -> Dictionary:
	return {"code": code, "path": path, "message": message}


static func missing_field(path: String, expected_type: String) -> Dictionary:
	return make(MISSING_FIELD, path, "нет обязательного поля (ожидался %s)" % expected_type)


static func wrong_type(path: String, expected_type: String, actual_type: String) -> Dictionary:
	return make(WRONG_TYPE, path, "ожидался %s, получен %s" % [expected_type, actual_type])


static func unknown_key(path: String, key: String) -> Dictionary:
	return make(UNKNOWN_KEY, path, "схема не знает поля «%s»" % key)


static func empty_section(section: String) -> Dictionary:
	return make(EMPTY_SECTION, section, "раздел «%s» не может быть пустым" % section)


static func duplicate_id(section: String, id: String) -> Dictionary:
	return make(DUPLICATE_ID, section, "id «%s» повторяется в разделе «%s»" % [id, section])


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


static func missing_text(path: String, key: String) -> Dictionary:
	return make(MISSING_TEXT, path, "ключа «%s» нет в текстах" % key)


static func dangling_text(key: String) -> Dictionary:
	return make(DANGLING_TEXT, "texts.%s" % key, "ключ «%s» нигде не используется" % key)


static func intel_lie_count(channel: String, count: int) -> Dictionary:
	return make(INTEL_LIE_COUNT, "intel.%s" % channel,
		"подброшенных пунктов %d, а у агентуры обязан быть ровно один" % count)


## Есть ли среди проблем такая-то. Валидатор спрашивает этим, чтобы не повторять
## одну и ту же болезнь по десять раз для одного объекта.
static func has(problems: Array, code: String) -> bool:
	for p in problems:
		if String(p["code"]) == code:
			return true
	return false


## Сводка для сообщений: «BAD_REF nodes.hall» — коротко и однозначно.
static func brief(p: Dictionary) -> String:
	return "%s %s" % [String(p["code"]), String(p["path"])]

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
const RESERVED_ID := "RESERVED_ID"         ## id занят движком (свои агенты: kira, echo)
const BAD_VALUE := "BAD_VALUE"             ## значение вне допустимого (диапазон, перечисление)
const BAD_REF := "BAD_REF"                 ## ссылка на несуществующий объект
const UNREACHABLE := "UNREACHABLE"         ## до цели нельзя дойти по рёбрам
const PATROL_ROUTE_OPEN := "PATROL_ROUTE_OPEN" ## маршрут патруля не замкнут: последняя точка не соединена с первой

# --- правила уровня: форма и значения верны, нарушен закон игры ---
const MISSING_SILENCE := "MISSING_SILENCE" ## у окна нет молчания: оно обязательно у каждого окна
const SILENCE_AS_OPTION := "SILENCE_AS_OPTION" ## «молчать» подсунуто обычным вариантом
const UNWINNABLE_EDGE := "UNWINNABLE_EDGE" ## окно оставляет группу перед запертой дверью навсегда
const WINDOW_ON_OPEN_EDGE := "WINDOW_ON_OPEN_EDGE" ## окно привязано к ребру, которое не заперто: не сработает никогда
const MISSING_TEXT := "MISSING_TEXT"       ## ключ текста не найден в текстах
const MISSING_REQUIRED_TEXT := "MISSING_REQUIRED_TEXT" ## обязательного системного ключа нет в текстах
const DANGLING_TEXT := "DANGLING_TEXT"     ## ключ текста нигде не используется
const INTEL_LIE_COUNT := "INTEL_LIE_COUNT" ## подброшенных пунктов не ровно один

# --- «окно невозможно»: описанное в данных окно, которое не сработает никогда ---
## Три разных дефекта данных — три разных кода. Разные они потому, что и ЧИНЯТ их по-разному:
## сенсор надо провести патрулём (или расширить зону), окно — переставить на первое
## помещение внутри, якорь — соединить с входом. Один общий код «окно невозможно» заставлял
## бы автора угадывать причину по тексту сообщения.
const WINDOW_ON_UNVISITED_SENSOR := "WINDOW_ON_UNVISITED_SENSOR" ## зону сенсора не посещает ни один патруль
const WINDOW_ON_ENTRY_NODE := "WINDOW_ON_ENTRY_NODE" ## окно входа стоит на самом входе: события входа там не бывает
const WINDOW_ON_UNREACHABLE_NODE := "WINDOW_ON_UNREACHABLE_NODE" ## якорь окна недостижим от входов по рёбрам

# --- нормативные маршруты уровня ---
const ROUTES_PER_ENTRY := "ROUTES_PER_ENTRY" ## на вход не ровно один нормативный маршрут
const ROUTE_END_NOT_ENTRY := "ROUTE_END_NOT_ENTRY" ## `entry`/`exit` маршрута — не узел с тегом entry
const OBJECTIVE_OFF_ROUTE := "OBJECTIVE_OFF_ROUTE" ## цель не лежит на объявленном маршруте

# --- разведка: расхождение призрака с реальностью ---
const GHOST_SAME_AS_REAL := "GHOST_SAME_AS_REAL" ## подброшенное расписание дословно равно реальному патрулю


static func make(code: String, path: String, message: String) -> Dictionary:
	return {"code": code, "path": path, "message": message}


## Имя типа для сообщений — по-русски и из ОДНОГО места: `TYPE_*` → слово, готовая строка
## пропускается как есть (ею описывают ожидание там, где схема разрешает не один тип,
## например `fallback`, — `01-format.md` §7). Незнакомый `TYPE_*` отдаётся через `type_string` — честный
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


## Маршрут патруля — ЦИКЛ: ядро ведёт охранника по списку и берёт узлы по модулю длины
## списка, поэтому после последней точки идёт первая. Разрыв в
## замыкающей паре означает то же, что разрыв между соседними, — охранник оказывается в
## помещении, которого не проходит, — но говорит о нём СВОЙ код.
##
## Отдельный код, а не `BAD_VALUE` соседних пар, потому что правок у автора две разные:
## «вставить пропущенную точку в середину» и «замкнуть маршрут». По коду это видно в
## отчёте приёмки, не разбирая текст сообщения. Имя называет ОБЕ точки — последнюю и
## первую: по ним автор и находит замыкающую пару.
static func patrol_route_open(path: String, last: String, first: String) -> Dictionary:
	return make(PATROL_ROUTE_OPEN, path,
		"маршрут не замкнут: «%s» и «%s» не соединены ребром, а охранник идёт по кругу" % [last, first])


## Молчание — часть ФОРМЫ окна, а не один из вариантов: оно есть у каждого окна и приказа
## не тратит. Сообщение говорит это прямо: получателю данных незачем знать внутренние
## номера наших решений, ему нужно знать, что чинить.
static func missing_silence(window_id: String) -> Dictionary:
	return make(MISSING_SILENCE, "windows.%s" % window_id,
		"у окна нет молчания — а оно обязано быть у каждого: молчание встроено в форму окна и приказа не тратит")


static func silence_as_option(window_id: String) -> Dictionary:
	return make(SILENCE_AS_OPTION, "windows.%s.options" % window_id,
		"«молчать» подсунуто обычным вариантом: молчание встроено в форму окна и приказа не тратит")


## Окно у запертой двери срабатывает один раз за миссию. Если ни один исход молчания не
## открывает это ребро, молчание оставляет группу перед дверью навсегда — тупик, а тупиков
## уровень содержать не должен: «ничто не является стеной, всё является ценой» (05-borders.md §4).
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


## Обязательный СИСТЕМНЫЙ ключ (`validator.gd:REQUIRED_TEXT_KEYS`, дословный перечень —
## `01-format.md` §11.1): у такого
## ключа НЕТ поля `*_key` в данных миссии, поэтому общая сверка его не видит и `MISSING_TEXT`
## ему не выписывает — и пропажа ключа раньше не называлась ничем.
##
## Отдельный код, а не `MISSING_TEXT`, потому что у проблемы другое МЕСТО: поля контента,
## которое можно было бы назвать, у системного ключа не существует, и путь вида
## `windows[3].text_key` был бы ложью — автор пошёл бы искать несуществующее поле. Путь
## здесь в пространстве ИМЁН ТЕКСТОВ (`texts.<ключ>`), как у `dangling_text`: там этот
## ключ и обязан появиться.
##
## Исключение названо прямо: ключ, на который ссылаются ДАННЫЕ, сюда не попадает вовсе —
## `validator.gd:_check_required_texts` пропускает его, и диагноз выписывает общая сверка:
## `MISSING_TEXT` на поле данных, ровно один на ключ. Так держится и название миссии: поле в
## данных у него есть (`title_key`), поэтому в обязательном перечне его нет (номер миссии в
## конвейерной константе давал ложный диагноз СЛЕДУЮЩЕЙ миссии), а пропажа
## его текста называется как пропажа любого ключа данных.
static func missing_required_text(key: String) -> Dictionary:
	return make(MISSING_REQUIRED_TEXT, "texts.%s" % key,
		"обязательного ключа «%s» нет в текстах: он относится к системе, а не к окну, и из данных миссии не выводится" % key)


static func dangling_text(key: String) -> Dictionary:
	return make(DANGLING_TEXT, "texts.%s" % key, "ключ «%s» нигде не используется" % key)


static func intel_lie_count(channel: String, count: int) -> Dictionary:
	return make(INTEL_LIE_COUNT, "intel.%s" % channel,
		"подброшенных пунктов %d, а у агентуры обязан быть ровно один" % count)


## Три фабрики «окно невозможно». Общее у них одно: окно описано в данных и не
## сработает НИ ПРИ КАКОМ прохождении — это ошибка данных, а не «редкая сцена». Прогон
## ловит такое окно только если построенный маршрут вообще доходит до его якоря, а форма
## обязана не пускать дефект в работу: приёмка нашла `w_guard4` и `w_dock_courier`
## именно прогоном, потому что статически их не называл никто.
##
## Путь у каждого свой: у сенсора — сам триггер (там назван sensor), у входа и якоря —
## поле, которое надо править. Это то место, где автор читает диагноз.

## Зона сенсора не пересекается с объединением маршрутов патрулей. Обоснование в ядре:
## событие `sensor_contact` возникает ТОЛЬКО у охраны (`sim.gd:_update_visibility` обходит
## `guards`), а `_actor_in_sensor` спрашивает именно его. Значит, сцена про человека
## (`guard_in_sensor` — только про саму охрану) на такой зоне не играется никогда.
static func window_on_unvisited_sensor(window_id: String, sensor: String, zones: String) -> Dictionary:
	return make(WINDOW_ON_UNVISITED_SENSOR, "windows.%s.trigger.sensor" % window_id,
		"зону сенсора «%s» (%s) не посещает ни один патруль: события охраны там не бывает, и окно не сработает никогда"
		% [sensor, zones])


## Окно с триггером `node_entered` стоит на помещении с тегом `entry`: группа там
## СТАРТУЕТ, и события `agent_moved` в этот узел на входе не бывает. Сцена входа ставится
## на первое помещение ВНУТРИ (так сделано для главного входа: `w_reception` на `lobby1`).
## Окно «на возврате» тоже не считается: к возврату в док миссия обычно завершена.
static func window_on_entry_node(window_id: String, node: String) -> Dictionary:
	return make(WINDOW_ON_ENTRY_NODE, "windows.%s.trigger.node" % window_id,
		"окно входа стоит на самом входе «%s»: группа там стартует, и события входа не бывает — сцену надо ставить на первое помещение внутри"
		% node)


## Якорь окна ГРУППЫ недостижим от объявленных входов по рёбрам. `what` — ГОТОВАЯ фраза про
## якорь («помещение «x»», «ребро «e»»): у двух якорей разный род и разное число, и
## согласование прилагательного с именем якоря ломалось бы на одном из двух. Фразу собирает
## вызывающий (он знает вид якоря), рамку держит одна фабрика.
##
## Окна `guard_in_sensor` сюда не попадают: их актёр — охрана, она стартует на своём маршруте
## и в зону от входов не приходит.
static func window_on_unreachable_node(window_id: String, what: String) -> Dictionary:
	return make(WINDOW_ON_UNREACHABLE_NODE, "windows.%s.trigger" % window_id,
		"%s окна недостижим(а) от объявленных входов по рёбрам: окно не сработает ни при каком прохождении"
		% what)


## На вход не ровно один нормативный маршрут. Без этого правила норматив
## «окон за прохождение» снова становится предметом переговоров: «исполнитель не объявил»
## и «исполнитель объявил неудобный» неразличимы, а спор 9/9/8 против 5/6/7 остаётся
## без арбитра. `why` называет, ЧЕГО не хватает — маршрута или лишнего маршрута, и у какого входа.
static func routes_per_entry(path: String, why: String) -> Dictionary:
	return make(ROUTES_PER_ENTRY, path,
		"на каждый вход обязан быть ровно один нормативный маршрут: %s" % why)


## `entry`/`exit` маршрута — узел, существующий, но БЕЗ тега `entry`. Отдельно от `BAD_REF`:
## правка другая — либо тег на узле, либо имя в маршруте. В MVP выходом служит один из
## входов («уходишь тем путём, каким вошёл»), поэтому `exit` проверяется тем же правилом.
static func route_end_not_entry(path: String, node: String, role: String) -> Dictionary:
	return make(ROUTE_END_NOT_ENTRY, path,
		"%s маршрута «%s» — не вход: у помещения нет тега entry, а выходом в MVP служит один из входов" % [role, node])


## Цель не лежит на объявленном маршруте: такой проход к цели не ведёт, и норматив «окон
## за прохождение» считался бы по дороге, которой в замысле уровня нет.
static func objective_off_route(route_id: String, objective: String) -> Dictionary:
	return make(OBJECTIVE_OFF_ROUTE, "routes",
		"цель «%s» не лежит на маршруте «%s»: проход к цели не ведёт" % [objective, route_id])


## Призрак не расходится с реальным патрулём по ОБОИМ признакам: совпал маршрут, период
## или и то и другое — что именно, называет `why` (его собирает `validator.gd:_ghost_sameness`).
##
## Сцена «призрак разошёлся с реальностью» — ЕДИНСТВЕННЫЙ индикатор тревоги в игре
## (отдельной шкалы нет, индикатор тревоги — призраки), и
## предусматривается она данными: маршрутом и периодом призрака против реальных. Совпавший
## признак не расходится: маршрут без периода исчезает через такт, а период без маршрута
## виден только по времени.
##
## Требуются ОБА отличия, а не хотя бы одно. Сообщение поэтому не говорит «дословно
## равно» на всякий случай: у «совпал только период» правка у автора другая.
static func ghost_same_as_real(path: String, patrol_id: String, why: String) -> Dictionary:
	return make(GHOST_SAME_AS_REAL, path,
		"призрак «%s» не расходится с реальным патрулём по обоим признакам: %s (маршрут И период обязаны отличаться)" % [patrol_id, why])


## Есть ли среди проблем такая-то. Этим спрашивают тесты (и любой вызывающий, которому
## важен один диагноз, а не весь список): валидатор отвечает не «болезнь уже названа»,
## а тем, что каскадные проверки пропускаются по испорченному полю.
static func has(problems: Array, code: String) -> bool:
	for p in problems:
		if String(p["code"]) == code:
			return true
	return false


## Сводка для сообщений: «BAD_REF nodes.hall» — коротко и однозначно. Держится ради имён
## ассертов: список проблем печатается в имени, чтобы провал называл причину, а не «список
## непуст».
static func brief(p: Dictionary) -> String:
	return "%s %s" % [String(p["code"]), String(p["path"])]

extends RefCounted
## Самопроверка формата проблем контента и типизированного payload миссии.
##
## Зачем коды, а не только текст. Прежний валидатор (`mission.gd:validate`) отдаёт
## русские строки, и вызывающий не может отличить «нет помещения» от «неизвестный вид
## ребра», не разбирая текст. Контент-конвейер должен возвращать причину машинно:
## тесты и отчёт прогона смотрят на код, человек читает сообщение.

const Assert := preload("res://tests/assert.gd")
const Problems := preload("res://content/problems.gd")
const Mission := preload("res://sim/mission.gd")


func run() -> Array:
	var t := Assert.new()

	# 1. Фабрики заполняют код, путь и сообщение — все три поля непусты.
	# Ожидаемый и фактический типы передаются как `TYPE_*`: имена раскрывает одна
	# `Problems.type_name`, норма — русские слова.
	var missing: Dictionary = Problems.missing_field("nodes.hall.floor", TYPE_INT)
	t.eq("пропущенное поле: код", String(missing["code"]), "MISSING_FIELD")
	t.eq("пропущенное поле: путь", String(missing["path"]), "nodes.hall.floor")
	t.is_true("пропущенное поле: сообщение непусто", String(missing["message"]) != "")
	t.is_true("пропущенное поле: тип назван по-русски",
		String(missing["message"]).contains("целое"))

	var wrong: Dictionary = Problems.wrong_type("edges[2].steps", TYPE_INT, TYPE_STRING)
	t.eq("неверный тип: код", String(wrong["code"]), "WRONG_TYPE")
	t.eq("неверный тип: путь", String(wrong["path"]), "edges[2].steps")
	# Сверяются ОБЕ половины, и каждая — в СВОЁМ слоте. Прежние два `contains` держали
	# только «слово есть в сообщении»: перестановка аргументов в `wrong_type`
	# («ожидалось: строка, получено: целое») оставляла оба ассерта зелёными — слова
	# на месте, роли перепутаны, автор читает совет наоборот.
	var wrong_message := String(wrong["message"])
	t.is_true("неверный тип: ожидаемый тип назван в своём слоте",
		wrong_message.contains("ожидалось: целое"))
	t.is_true("неверный тип: фактический тип назван в своём слоте",
		wrong_message.contains("получено: строка"))
	# «Проходит как есть» — это обо ВСЁМ описании, а не о его первом слове: проба,
	# обрезающая описание до «словарь эффекта», прежний ассерт не краснила.
	t.is_true("неверный тип: описательное ожидание проходит как есть",
		String(Problems.wrong_type("x", "словарь эффекта или массив эффектов", TYPE_ARRAY)["message"])
			.contains("словарь эффекта или массив эффектов"))

	var unknown: Dictionary = Problems.unknown_key("windows[0].option", "option")
	t.eq("неизвестный ключ: код", String(unknown["code"]), "UNKNOWN_KEY")
	t.eq("неизвестный ключ: путь", String(unknown["path"]), "windows[0].option")

	var dup: Dictionary = Problems.duplicate_id("nodes", "hall")
	t.eq("дубль id: код", String(dup["code"]), "DUPLICATE_ID")
	t.eq("дубль id: путь — раздел", String(dup["path"]), "nodes")

	var bad: Dictionary = Problems.bad_value("edges[1].noise", "noise не может быть отрицательным")
	t.eq("неверное значение: код", String(bad["code"]), "BAD_VALUE")
	t.eq("неверное значение: путь", String(bad["path"]), "edges[1].noise")

	var ref: Dictionary = Problems.bad_ref("sensors[0].nodes[1]", "нет помещения ghost")
	t.eq("битая ссылка: код", String(ref["code"]), "BAD_REF")
	t.is_true("битая ссылка: путь назван", String(ref["path"]) != "")

	# Зарезервированный id — не повтор: у проблемы свой код, иначе автор ищет дубль.
	var reserved: Dictionary = Problems.reserved_id("patrols", "kira")
	t.eq("занятый id: код", String(reserved["code"]), "RESERVED_ID")
	t.is_true("занятый id: код не про дубль", String(reserved["code"]) != Problems.DUPLICATE_ID)
	t.is_true("занятый id: «зарезервирован» в сообщении",
		String(reserved["message"]).contains("зарезервирован"))

	# Битый JSON несёт и причину, и строку: без них автор ищет запятую глазами.
	var bad_json: Dictionary = Problems.bad_json(43, 3, "Expected '}'")
	t.eq("битый JSON: код", String(bad_json["code"]), "BAD_JSON")
	t.is_true("битый JSON: строка названа", String(bad_json["message"]).contains("строка 3"))
	t.is_true("битый JSON: причина названа", String(bad_json["message"]).contains("Expected '}'"))

	var no_line: Dictionary = Problems.bad_json(1, 0, "Parse error")
	t.is_true("битый JSON без строки: место помечено",
		String(no_line["message"]).contains("место неизвестно"))

	# Окно у двери, которое не открывает эту дверь: свой код, не BAD_VALUE.
	var unwinnable: Dictionary = Problems.unwinnable_edge("w_door", "e_hall_vault")
	t.eq("невыполнимое окно: код", String(unwinnable["code"]), "UNWINNABLE_EDGE")
	t.is_true("невыполнимое окно: ребро названо",
		String(unwinnable["message"]).contains("e_hall_vault"))

	# Окно на НЕзапертом ребре — соседний, но другой диагноз: группа пройдёт свободно,
	# а окно не сработает ни разу. Код отдельный, чтобы автор не искал невыполнимость.
	var open_edge: Dictionary = Problems.window_on_open_edge("w_door", "e_hall_vault")
	t.eq("окно на незапертом ребре: код", String(open_edge["code"]), "WINDOW_ON_OPEN_EDGE")
	t.is_true("окно на незапертом ребре: код не про невыполнимость",
		String(open_edge["code"]) != Problems.UNWINNABLE_EDGE)
	t.eq("окно на незапертом ребре: путь — триггер",
		String(open_edge["path"]), "windows.w_door.trigger.edge")
	t.is_true("окно на незапертом ребре: ребро названо",
		String(open_edge["message"]).contains("e_hall_vault"))
	# «Не заперто» и «не запираемо» — разные вещи: ребро, перекрытое тревогой, дефектом
	# НЕ является (`Response.blockable_kind`), и сообщение обязано называть обе причины,
	# иначе автор идёт запирать ребро, которое и так запирается тревогой.
	t.is_true("окно на незапираемом ребре: названы обе причины — «ни замком, ни тревогой»",
		String(open_edge["message"]).contains("ни замком, ни тревогой"))

	# Разомкнутый маршрут патруля: ядро ведёт охранника ПО КРУГУ
	# (`sim.gd:_advance_guards` — индекс по модулю длины), поэтому замыкающая пара — такое
	# же ребро маршрута, как соседние. Код свой, а не `BAD_VALUE` соседних пар: правок у
	# автора две разные — «вставить точку в середину» и «замкнуть маршрут», — и по коду
	# это видно в отчёте приёмки, не разбирая текст. Обе точки замыкания названы.
	var open_route: Dictionary = Problems.patrol_route_open("patrols[0].route", "vault", "entry")
	t.eq("разомкнутый маршрут: код", String(open_route["code"]), "PATROL_ROUTE_OPEN")
	t.is_true("разомкнутый маршрут: код не про разрыв соседних пар",
		String(open_route["code"]) != Problems.BAD_VALUE)
	t.eq("разомкнутый маршрут: путь — маршрут патруля", String(open_route["path"]),
		"patrols[0].route")
	t.is_true("разомкнутый маршрут: названы обе точки замыкания — последняя и первая",
		String(open_route["message"]).contains("vault")
		and String(open_route["message"]).contains("entry"))

	# Обязательный СИСТЕМНЫЙ текстовый ключ — свой код, а не `MISSING_TEXT`: у него НЕТ
	# поля в данных миссии, на которое тот указывал бы, поэтому путь у проблемы другой —
	# в пространстве имён ТЕКСТОВ (`texts.<ключ>`), там же, где у `DANGLING_TEXT`. Путь
	# вида `windows[3].text_key` отправил бы автора искать несуществующее поле.
	var required: Dictionary = Problems.missing_required_text("log.silence")
	t.eq("нет обязательного системного текста: код", String(required["code"]),
		"MISSING_REQUIRED_TEXT")
	t.is_true("нет обязательного системного текста: код не про ключ данных",
		String(required["code"]) != Problems.MISSING_TEXT)
	t.eq("нет обязательного системного текста: путь в пространстве текстов",
		String(required["path"]), "texts.log.silence")
	t.is_true("нет обязательного системного текста: ключ назван",
		String(required["message"]).contains("log.silence"))
	t.is_true("нет обязательного системного текста: причина названа",
		String(required["message"]).contains("систем"))

	# 2. `has` ищет по коду — этим валидатор будет отвечать «эта болезнь уже названа».
	var list := [missing, wrong]
	t.is_true("has находит код", Problems.has(list, "WRONG_TYPE"))
	t.is_false("has не выдумывает код", Problems.has(list, "BAD_REF"))

	# 3. payload миссии: типизированные разделы доезжают до данных без потерь.
	# Mission остаётся единственной моделью миссии — второго представления не заводим.
	var m := Mission.new()
	m.set_data({
		"windows": [{"id": "w_a", "trigger": {"type": "locked_edge", "edge": "e_x"}}],
		"intel": [{"channel": "hack", "entries": []}],
		"access_points": [{"id": "ap_a", "node": "hall"}],
	})
	t.is_true("payload: окна доехали", m.data["windows"].size() == 1)
	t.eq("payload: id окна", String(m.data["windows"][0]["id"]), "w_a")
	t.is_true("payload: разведка доехала", m.data["intel"].size() == 1)
	t.is_true("payload: точки доступа доехали", m.data["access_points"].size() == 1)

	# 4. Миссия без payload остаётся рабочей: фикстура собирается прежним API,
	# и разделы новых данных просто пусты.
	var plain := Mission.new()
	t.is_true("без payload: окна пусты", plain.data["windows"].is_empty())
	t.is_true("без payload: разведка пуста", plain.data["intel"].is_empty())
	t.is_true("без payload: точки доступа пусты", plain.data["access_points"].is_empty())

	return t.results

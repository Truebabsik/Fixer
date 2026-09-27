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
	var missing: Dictionary = Problems.missing_field("nodes.hall.floor", "int")
	t.eq("пропущенное поле: код", String(missing["code"]), "MISSING_FIELD")
	t.eq("пропущенное поле: путь", String(missing["path"]), "nodes.hall.floor")
	t.is_true("пропущенное поле: сообщение непусто", String(missing["message"]) != "")

	var wrong: Dictionary = Problems.wrong_type("edges[2].steps", "int", "String")
	t.eq("неверный тип: код", String(wrong["code"]), "WRONG_TYPE")
	t.eq("неверный тип: путь", String(wrong["path"]), "edges[2].steps")
	t.is_true("неверный тип: тип назван в сообщении", String(wrong["message"]).contains("int"))

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

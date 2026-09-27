extends RefCounted
## Сборка результатов прогона. Список кейсов и правила их приёма живут здесь в одном
## экземпляре, а не копией в каждом раннере: иначе «зелёный» и «красный» входы
## расходятся в том, что именно они проверяют, и красный перестаёт что-либо доказывать.
##
## Модуль не печатает: печать остаётся за раннером, чтобы один и тот же сбор годился
## и для обычного прогона, и для самопроверки красного пути.

const VERDICT := preload("res://tests/verdict.gd")

## Список кейсов явный: никакого сканирования каталогов, порядок фиксирован,
## поэтому прогон воспроизводим.
const CASES := [
	"res://tests/cases/test_runner.gd",
	"res://tests/cases/test_verdict.gd",
	"res://tests/cases/test_scales.gd",
	"res://tests/cases/test_radio.gd",
	"res://tests/cases/test_understanding.gd",
	"res://tests/cases/test_mission.gd",
	"res://tests/cases/test_movement.gd",
	"res://tests/cases/test_visibility.gd",
	"res://tests/cases/test_windows.gd",
	"res://tests/cases/test_response.gd",
	"res://tests/cases/test_casualties.gd",
	"res://tests/cases/test_harness.gd",
]

## Типы, которые run() не имеет права вернуть. Сравниваем с typeof() вручную,
## чтобы не тянуть в тесты глобальные имена движка.
const FAILED_TYPES := [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_OBJECT]


## Прогоняет cases, печатает провалы, возвращает вердикт из verdict.gd.
## broken_channel прокидывается в приговор: этим кодом раннер сообщит, что сломан
## приговор, а не что упал набор.
static func run(cases: Array, expect_failures: bool, broken_channel := VERDICT.EXIT_FAILED) -> Dictionary:
	var results: Array = []
	var load_failures := 0
	for path in cases:
		var problem: String = _collect(path, results)
		if problem == "load":
			print("LOAD FAIL  %s" % path)
			load_failures += 1
		elif problem == "empty":
			print("LOAD FAIL  %s: кейс не предъявил ни одного ассерта" % path)
			load_failures += 1
	_print_failures(results)
	var verdict := VERDICT.evaluate(results, expect_failures, load_failures, broken_channel)
	print(VERDICT.summary(verdict))
	return verdict


## Разбирает один кейс. Возвращает "" если кейс принят, иначе причину отказа:
## "load" (не загрузился / без run() / вернул не то) или "empty" (ноль ассертов).
static func _collect(path: String, results: Array) -> String:
	var case_script: GDScript = load(path)
	if case_script == null:
		return "load"
	if not case_script.can_instantiate():
		return "load"
	var case_obj = case_script.new()
	if not case_obj.has_method("run"):
		return "load"
	var produced = case_obj.run()
	if typeof(produced) in FAILED_TYPES:
		return "load"
	## Кейс, не предъявивший ни одного ассерта, — провал: пустой Array от
	## абортированной run() неотличим от честного «ноль ассертов».
	if produced.size() == 0:
		return "empty"
	## Помечаем каждый результат источником: строка FAIL печатается по общему списку,
	## а имя файла кейса — единственное, что позволяет найти провал.
	var source := path.get_file()
	for r in produced:
		r["case"] = source
	results.append_array(produced)
	return ""


static func _print_failures(results: Array) -> void:
	for r in results:
		if not bool(r["ok"]):
			print("FAIL  %s :: %s" % [str(r.get("case", "")), str(r["name"])])
			print("      ожидалось: %s" % str(r["expected"]))
			print("      получено:  %s" % str(r["actual"]))

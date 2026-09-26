extends SceneTree
## Раннер ядра. Вердикт — код возврата процесса: 0 зелёный, 1 есть провалы.
## Список кейсов явный: никакого сканирования каталогов, порядок фиксирован,
## поэтому прогон воспроизводим.
##
## Сторож вердикта: GDScript при рантайм-сбое прерывает _initialize() (а не процесс),
## поэтому без сторожа прогон может закончиться нулём или повиснуть. Сторож превращает
## «аборт до вердикта» в код 1 и гарантирует завершение.

const CASES := [
	"res://tests/cases/test_runner.gd",
]

## Типы, которые run() не имеет права вернуть. Сравниваем с typeof() вручную,
## чтобы не тянуть в тесты глобальные имена движка.
const FAILED_TYPES := [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_OBJECT]

var _verdict_reached := false


func _initialize() -> void:
	var total := 0
	var failed := 0
	for path in CASES:
		var case_script: GDScript = load(path)
		if case_script == null:
			print("LOAD FAIL  %s" % path)
			failed += 1
			continue
		if not case_script.can_instantiate():
			print("LOAD FAIL  %s" % path)
			failed += 1
			continue
		var case_obj = case_script.new()
		if not case_obj.has_method("run"):
			print("LOAD FAIL  %s" % path)
			failed += 1
			continue
		var results = case_obj.run()
		if typeof(results) in FAILED_TYPES:
			print("LOAD FAIL  %s" % path)
			failed += 1
			continue
		for r in results:
			total += 1
			if not bool(r["ok"]):
				failed += 1
				print("FAIL  %s :: %s" % [path.get_file(), str(r["name"])])
				print("      ожидалось: %s" % str(r["expected"]))
				print("      получено:  %s" % str(r["actual"]))
	print("tests: %d, failed: %d" % [total, failed])
	_verdict_reached = true
	quit(1 if failed > 0 else 0)


## Сторож: если _initialize() прервался до вердикта, quit() не вызван и процесс
## иначе повис бы (главный цикл сам не завершается). Флаг гарантирует, что на
## нормальном прогоне сторож не вмешивается.
func _process(_delta: float) -> bool:
	if _verdict_reached:
		return false
	print("LOAD FAIL  вердикт не выставлен: _initialize() прервался до quit()")
	quit(1)
	return true

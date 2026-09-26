extends SceneTree
## НАРОЧНО КРАСНЫЙ раннер. Его единственная задача — вернуть НЕНУЛЕВОЙ код.
##
## Зачем отдельная точка входа. Сторож нормального раннера («кейс без ассертов —
## провал», `_process`-сторож, `quit(1)` при провале) проверялся руками один раз
## и ничем не охраняется: зашитый `quit(0)` в `tests/run.gd` оставил бы все
## будущие прогоны зелёными, и заметить это было бы нечем. Этот раннер запускает
## заведомо падающий кейс, поэтому обязан завершиться кодом 1. Если он вернёт 0 —
## сломан приговор, а не кейс.
##
## Команды — в docs/architecture.md §8.
##
## Здесь НЕТ `_process`-сторожа намеренно: нормальный раннер и его сторож — часть
## проверяемой системы, и второй их экземпляр ничего не доказывает. Сторож
## проверяется тем, что падение доказывает провал.

const CASES := [
	"res://tests/red_path.gd",
]

## Типы, которые run() не имеет права вернуть. Сравниваем с typeof() вручную,
## как и в обычном раннере, чтобы не тянуть в тесты глобальные имена движка.
const FAILED_TYPES := [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_OBJECT]


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
		if results.size() == 0:
			print("LOAD FAIL  %s: кейс не предъявил ни одного ассерта" % path)
			failed += 1
			continue
		for r in results:
			total += 1
			if not bool(r["ok"]):
				failed += 1
				print("FAIL  %s :: %s" % [path.get_file(), str(r["name"])])
				print("      ожидалось: %s" % str(r["expected"]))
				print("      получено:  %s" % str(r["actual"]))
	## Кейс обязан упасть: ноль провалов здесь — это ошибка красного пути.
	if failed == 0:
		print("RED PATH BROKEN: нарочно падающий кейс не упал")
		quit(1)
		return
	print("red-path: tests: %d, failed: %d (ожидаем failed > 0)" % [total, failed])
	quit(1)

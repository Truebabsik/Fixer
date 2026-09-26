extends SceneTree
## Раннер ядра. Вердикт — код возврата процесса: 0 зелёный, 1 есть провалы.
## Список кейсов явный: никакого сканирования каталогов, порядок фиксирован,
## поэтому прогон воспроизводим.

const CASES := [
	"res://tests/cases/test_runner.gd",
]


func _initialize() -> void:
	var total := 0
	var failed := 0
	for path in CASES:
		var case_script: GDScript = load(path)
		if case_script == null:
			print("LOAD FAIL  %s" % path)
			failed += 1
			continue
		var case_obj = case_script.new()
		var results: Array = case_obj.run()
		for r in results:
			total += 1
			if not bool(r["ok"]):
				failed += 1
				print("FAIL  %s :: %s" % [path.get_file(), str(r["name"])])
				print("      ожидалось: %s" % str(r["expected"]))
				print("      получено:  %s" % str(r["actual"]))
	print("tests: %d, failed: %d" % [total, failed])
	quit(1 if failed > 0 else 0)

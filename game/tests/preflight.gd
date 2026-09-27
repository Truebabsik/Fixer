extends SceneTree
## Ворота разбора: грузят каждый скрипт конвейера и называют те, что не разобрались.
##
## Зачем отдельный вход, а не `--check-only --script res://tests/run.gd`.
## `--check-only` разбирает только названный скрипт и то, что он тянет статическими
## `preload`. Кейсы и модули конвейера попадают в прогон динамически (`load(path)` в
## tests/suite.gd), поэтому документированная команда разбора их не видит: синтаксическая
## ошибка в `game/content/validator.gd` дала по ней код 0 при полностью нерабочем прогоне.
## Здесь путь каждого скрипта назван явно, порядок зафиксирован, а вердикт — код возврата
## процесса: `load()` вернул null или `can_instantiate()` сказал «нет» — провал.
##
## Сторож вердикта: GDScript при рантайм-сбое прерывает _initialize() (а не процесс),
## поэтому без сторожа прогон может закончиться нулём или повиснуть. Сторож превращает
## «аборт до вердикта» в код 1 и гарантирует завершение.

const Suite := preload("res://tests/suite.gd")

## Порядок — от листьев к зависимым: сломанный модуль роняет и тех, кто тянет его через
## `preload`, поэтому первый же LOAD FAIL обязан называть причину, а не следствие.
## Список явный, без сканирования каталогов: рядом со скриптами лежат `.uid`-файлы, и
## сканирование по расширению — единственная защита от них; состав ворот должен быть
## виден глазами и не меняться от появления файла в каталоге.
##
## Раннеров (`tests/run.gd`, `tests/run_red.gd`) в списке нет намеренно: движок разбирает
## названный `--script` сам, поэтому ошибка в них ловится их же командой гейта — проверено
## прогоном (код 1 и у разбора, и у прогона сломанного `run.gd`).
const MODULES := [
	# sim/ — листья: ни от кого не зависят
	"res://sim/agent.gd",
	"res://sim/mission.gd",
	"res://sim/plan.gd",
	"res://sim/radio.gd",
	"res://sim/response.gd",
	"res://sim/scales.gd",
	"res://sim/understanding.gd",
	"res://sim/window.gd",
	# sim/ — зависимые: идут после своих листьев
	"res://sim/sim.gd",
	"res://sim/harness.gd",
	# content/ — тоже от листьев к зависимым
	"res://content/problems.gd",
	"res://content/validator.gd",
	"res://content/loader.gd",
]

var _verdict_reached := false


func _initialize() -> void:
	var scripts: Array = MODULES.duplicate()
	## Кейсы берутся из suite.gd, а не копией: копия разошлась бы при добавлении кейса,
	## и ворота молча перестали бы его разбирать.
	scripts.append_array(Suite.CASES)
	var failed := 0
	for path in scripts:
		if not _parses(path):
			print("LOAD FAIL  %s" % path)
			failed += 1
	print("preflight: scripts: %d, failed: %d" % [scripts.size(), failed])
	_verdict_reached = true
	quit(1 if failed > 0 else 0)


## Разбирается ли скрипт: загрузка и возможность создать экземпляр. Ошибка разбора внутри
## `load()` уже напечатана движком (`Parse Error` с именем файла) — здесь важно назвать
## путь в том же формате, что у раннера, чтобы провал читался одинаково на обоих входах.
static func _parses(path: String) -> bool:
	var script = load(path)
	if script == null:
		return false
	return script.can_instantiate()


## Сторож: если _initialize() прервался до вердикта, quit() не вызван и процесс иначе
## повис бы (главный цикл сам не завершается). Флаг гарантирует, что на нормальном
## прогоне сторож не вмешивается.
func _process(_delta: float) -> bool:
	if _verdict_reached:
		return false
	print("LOAD FAIL  вердикт не выставлен: _initialize() прервался до quit()")
	quit(1)
	return true

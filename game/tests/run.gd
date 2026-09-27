extends SceneTree
## Раннер ядра. Вердикт — код возврата процесса: 0 зелёный, 1 провал, 2 приговор сломан.
## Список кейсов и правила их приёма — в tests/suite.gd, приговор — в tests/verdict.gd.
## Оба раннера (этот и run_red.gd) пользуются ими, поэтому «зелёный» и «красный» пути
## не могут разойтись в трактовке.
##
## Сторож вердикта: GDScript при рантайм-сбое прерывает _initialize() (а не процесс),
## поэтому без сторожа прогон может закончиться нулём или повиснуть. Сторож превращает
## «аборт до вердикта» в код 1 и гарантирует завершение.

const Suite := preload("res://tests/suite.gd")
const Verdict := preload("res://tests/verdict.gd")

var _verdict_reached := false


func _initialize() -> void:
	var verdict := Suite.run(Suite.CASES, false, Verdict.EXIT_FAILED)
	_verdict_reached = true
	quit(int(verdict["exit_code"]))


## Сторож: если _initialize() прервался до вердикта, quit() не вызван и процесс
## иначе повис бы (главный цикл сам не завершается). Флаг гарантирует, что на
## нормальном прогоне сторож не вмешивается.
func _process(_delta: float) -> bool:
	if _verdict_reached:
		return false
	print("LOAD FAIL  вердикт не выставлен: _initialize() прервался до quit()")
	quit(1)
	return true

extends RefCounted
## Приговор прогона: сколько ассертов, сколько провалов и каким кодом завершиться.
## Общий для обоих входов — tests/run.gd (зелёный путь) и tests/run_red.gd (красный).
##
## Зачем общий модуль. Раньше приговор жил в двух копиях, и красная копия была
## отдельным раннером с жёстко зашитым quit(1): она не могла заметить, что нарочно
## падающий кейс перестал падать, и потому ничего не защищала. Теперь решение о коде
## возврата принимается в одном месте и покрыто юнит-тестом
## (tests/cases/test_verdict.gd), который входит в обычный прогон.
##
## Красный путь возвращает 0, если нарочная ошибка НЕ зафиксирована: это значит, что
## сломан не приговор, а сам красный кейс. Раньше в этой ситуации возвращался 1, и
## заметить поломку было нечем.
##
## Модуль намеренно ничего не печатает: печать остаётся за раннером, а приговор —
## чистая функция от собранных результатов.

const MODE_GREEN := "green"
const MODE_RED := "red"

## Коды возврата. Различаем «набор упал» и «сломан сам приговор»: это разные болезни,
## и разный код позволяет вызывающему скрипту понять, что именно случилось.
const EXIT_OK := 0
const EXIT_FAILED := 1
const EXIT_BROKEN := 2

## Метка строки для случая «приговор не работает» — отдельная от "LOAD FAIL",
## чтобы при разборе прогона было видно, что сломан приговор, а не кейс.
const BROKEN_MARK := "BROKEN"

## Имя модуля сборки задано строкой намеренно: preload tests/suite.gd из этого модуля
## создал бы цикл (suite.gd уже зависит от verdict.gd).
const GREEN_SUITE_SCRIPT := "res://tests/suite.gd"


## results — список словарей вида {"ok": bool, "name": String}; порядок важен только
## для счётчика. load_failures — сколько кейсов не доехало до прогона (не загрузились,
## не имели run(), вернули не то). expect_failures: false — зелёный путь (провалов быть
## не должно), true — красный (провал обязан быть зафиксирован).
## broken_channel — каким кодом сообщать «сломан приговор» на зелёном пути. Красный
## раннер передаёт EXIT_BROKEN, чтобы его самопроверка не путалась с падением набора.
static func evaluate(results: Array, expect_failures: bool, load_failures := 0, broken_channel := EXIT_FAILED) -> Dictionary:
	var total := results.size()
	var failed := int(load_failures)
	for r in results:
		if not bool(r["ok"]):
			failed += 1
	var mode := MODE_RED if expect_failures else MODE_GREEN
	## «Ожидание нарушено» — только про красный путь: он существует ради того, чтобы
	## провал был зафиксирован. Пустой зелёный прогон — отдельная болезнь (total == 0).
	var violated := expect_failures and failed == 0
	var exit_code := EXIT_OK
	if expect_failures:
		## Красный путь: провал должен быть. Нет провала — ошибка не зафиксирована.
		exit_code = EXIT_OK if failed > 0 else EXIT_BROKEN
	else:
		if failed > 0:
			exit_code = broken_channel
		elif total == 0:
			## Кейс не предъявил ни одного ассерта: пустой список неотличим от аборта прогона.
			exit_code = broken_channel
	return {
		"mode": mode,
		"total": total,
		"failed": failed,
		"load_failures": int(load_failures),
		"expect_failures": expect_failures,
		"expectation_violated": violated,
		"exit_code": exit_code,
	}


## Самопроверка защиты приговора — запускается КРАСНЫМ раннером.
##
## Одной проверки мало, и это выяснилось прогоном, а не рассуждением. Если сломать
## tests/suite.gd (например, приговор в нём зашить нулём), то «зелёный набор проходит»
## перестаёт что-либо доказывать: проверка идёт через тот же сломанный модуль. Поэтому
## здесь две независимые проверки:
##
##   1. Нарочно падающий список, поданный НАПРЯМУЮ в evaluate, обязан дать провал.
##      Это не зависит от suite.gd — только от приговора.
##   2. Зелёный набор, прогнанный обычным путём, обязан пройти. Это ловит поломку
##      в самом раннере (зашитый quit(0) в run.gd).
##
## Возвращает {"ok": bool, "problems": Array[String]}. Печатает вызывающий раннер.
static func verify() -> Dictionary:
	var problems: Array = []

	var failing := [{"ok": false, "name": "нарочно неверный"}]
	var direct := evaluate(failing, false, 0)
	if int(direct["failed"]) != 1 or int(direct["exit_code"]) != EXIT_FAILED:
		problems.append("приговор не увидел провал: failed=%d, exit_code=%d (ждали 1 и 1)" \
			% [int(direct["failed"]), int(direct["exit_code"])])

	var passing := [{"ok": true, "name": "верный"}]
	var clean := evaluate(passing, false, 0)
	if int(clean["exit_code"]) != EXIT_OK:
		problems.append("приговор забраковал чистый список: exit_code=%d (ждали 0)" \
			% int(clean["exit_code"]))

	var suite_script: GDScript = load(GREEN_SUITE_SCRIPT)
	if suite_script == null:
		problems.append("не загрузился %s" % GREEN_SUITE_SCRIPT)
	else:
		var green: Dictionary = suite_script.run(suite_script.CASES, false, EXIT_BROKEN)
		if int(green["exit_code"]) != EXIT_OK:
			problems.append("зелёный набор не проходит при запуске из красного пути (код %d)" \
				% int(green["exit_code"]))

	return {"ok": problems.is_empty(), "problems": problems}


## Человекочитаемая строка приговора для печати раннером.
static func summary(v: Dictionary) -> String:
	if bool(v["expect_failures"]):
		return "red-path: tests: %d, failed: %d (ожидаем failed > 0)" % [int(v["total"]), int(v["failed"])]
	return "tests: %d, failed: %d" % [int(v["total"]), int(v["failed"])]

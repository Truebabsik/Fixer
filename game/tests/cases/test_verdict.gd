extends RefCounted
## Самопроверка приговора. Раннеры (run.gd и run_red.gd) только собирают результаты
## кейсов, а решение «какой код возврата» принимает один общий модуль — иначе
## «зелёный» и «красный» пути расходятся в трактовке, и защищать нечего.
##
## Главное свойство, которого не было у прежней копии раннера: красный путь,
## в котором нарочная ошибка НЕ зафиксирована, обязан вернуть 0. Прежний run_red.gd
## возвращал 1 всегда и потому про поломку красного кейса молчал.

const Assert := preload("res://tests/assert.gd")
const Verdict := preload("res://tests/verdict.gd")

const GREEN := false
const RED := true


func run() -> Array:
	var t := Assert.new()

	var ok_list := [{"ok": true, "name": "верный"}, {"ok": true, "name": "тоже верный"}]
	var bad_list := [{"ok": true, "name": "верный"}, {"ok": false, "name": "неверный"}]

	## Зелёный путь: провалов нет — код 0.
	var green := Verdict.evaluate(ok_list, GREEN, 0)
	t.eq("зелёный: код 0", green["exit_code"], 0)
	t.eq("зелёный: провалов нет", green["failed"], 0)
	t.eq("зелёный: ассертов 2", green["total"], 2)
	t.is_false("зелёный: ожидание соблюдено", green["expectation_violated"])

	## Зелёный путь с провалом: код 1, и это не «нарушение ожидания», а обычный провал.
	var green_bad := Verdict.evaluate(bad_list, GREEN, 0)
	t.eq("зелёный с провалом: код 1", green_bad["exit_code"], 1)
	t.eq("зелёный с провалом: провалов 1", green_bad["failed"], 1)
	t.is_false("зелёный с провалом: ожидание соблюдено", green_bad["expectation_violated"])

	## Зелёный путь без единого ассерта: не «зелено», а сломанный прогон.
	var empty := Verdict.evaluate([], GREEN, 0)
	t.eq("пустой список: код 1", empty["exit_code"], Verdict.EXIT_FAILED)
	t.eq("пустой список: ассертов 0", empty["total"], 0)

	## Канал «сломан приговор»: красный раннер проверяет этим кодом, что зелёный набор
	## вообще проходит. Иначе зашитый quit(0) в run.gd не заметил бы никто.
	var green_for_red := Verdict.evaluate(ok_list, GREEN, 0, Verdict.EXIT_BROKEN)
	t.eq("канал красного: проходит — код 0", green_for_red["exit_code"], Verdict.EXIT_OK)
	var green_fail_for_red := Verdict.evaluate(bad_list, GREEN, 0, Verdict.EXIT_BROKEN)
	t.eq("канал красного: упал — код 2", green_fail_for_red["exit_code"], Verdict.EXIT_BROKEN)
	var empty_for_red := Verdict.evaluate([], GREEN, 0, Verdict.EXIT_BROKEN)
	t.eq("канал красного: пусто — код 2", empty_for_red["exit_code"], Verdict.EXIT_BROKEN)

	## Красный путь: провал зафиксирован — код 0.
	var red := Verdict.evaluate(bad_list, RED, 0)
	t.eq("красный с падением: код 0", red["exit_code"], 0)
	t.eq("красный с падением: провалов 1", red["failed"], 1)
	t.is_false("красный с падением: ожидание соблюдено", red["expectation_violated"])

	## Дефект, ради которого модуль и заведён: нарочно падающий кейс не упал.
	var red_broken := Verdict.evaluate(ok_list, RED, 0)
	t.eq("красный без падения: код 2", red_broken["exit_code"], Verdict.EXIT_BROKEN)
	t.is_true("красный без падения: ожидание нарушено", red_broken["expectation_violated"])

	## Красный путь, где помимо провала есть недоехавший кейс: провал есть — код 0.
	var red_short := Verdict.evaluate(bad_list, RED, 1)
	t.eq("красный с недоехавшими: код 0", red_short["exit_code"], 0)
	t.eq("красный с недоехавшими: провалов 2", red_short["failed"], 2)

	return t.results

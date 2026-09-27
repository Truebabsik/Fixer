extends SceneTree
## Приёмочный прогон поставки уровня: форма → геометрия → связность → прогон ядра → критерии.
##
## ЗАЧЕМ. Валидатор контента отвечает на вопрос «верен ли ФАЙЛ» и на вопрос «играется ли
## УРОВЕНЬ» ответить не может: «цель берётся от каждого входа», «окна срабатывают на реальных
## маршрутах», «группа доходит до выхода», «провал достижим» — это утверждения о ПРОГОНЕ ядра.
## Проверять их чтением отчёта исполнителя — повторение ошибки прошлой приёмки (49 проблем
## дожили до неё, потому что наш валидатор на поставке не прогонялся вовсе, а самопроверка
## исполнителя кодировала его же схему). Поэтому здесь: боевые `content/validator.gd`,
## `content/loader.gd` и `sim/harness.gd`, автоматически построенные маршруты и вердикт —
## КОД ВОЗВРАТА.
##
## ЗАПУСК:
##   --headless --path game --script res://tests/accept_delivery.gd -- <mission.json> <texts.json>
##
## КОД ВОЗВРАТА (текст вердиктом не является, stderr — тоже):
##   0 — все обязательные критерии выполнены;
##   1 — есть нарушенные критерии (названы) ЛИБО сломан сам инструмент (см. «ИНСТРУМЕНТ»);
##   2 — вход/сборка не состоялись: аргументы, чтение, разбор JSON, форма корня, сборка миссии.
##
## ПОЧЕМУ АРГУМЕНТЫ, А НЕ `res://content/`. Инструмент принимает ПРОИЗВОЛЬНУЮ пару
## «миссия + тексты»: следующая поставка будет другой, а приёмка — та же процедура. Пути
## приходят снаружи, боевой контент `game/content/` инструмент не читает и не трогает.
##
## ПОЧЕМУ МАРШРУТЫ БЫВАЮТ ДВУХ РОДОВ. Норматив «окон за прохождение» мерится на
## маршрутах, которые уровень ОБЪЯВИЛ САМ (`routes`, D47): замысел прохождения — это
## данные уровня, а не наша догадка о нём. Автоматические BFS-маршруты остаются, но в
## ДРУГОЙ роли: «вход → цель» и «вход → якорь окна → цель» доказывают, что каждое
## объявленное окно вообще СПОСОБНО сработать и что мёртвых окон нет. Числа двух
## выборок печатаются раздельно и подписанно: прочитать норматив не с той строки нельзя.
##
## ПОЧЕМУ ТРИ ПОВЕДЕНИЯ. «Молчание» и «первый вариант» — крайности: игрок не вмешивался
## вовсе и игрок жмёт первое, что видит. Требование задания §3.4 («при разумном плане и
## разумных приказах миссия должна завершаться успехом») этими двумя не покрывается,
## поэтому добавлено третье — «разумные приказы»: детерминированно выбрать вариант,
## снимающий препятствие, при равном эффекте — тишайший, иначе молчать (`order_builder.gd`).
##
## ЧТО ИНСТРУМЕНТ НЕ ПРОВЕРЯЕТ (граница названа, чтобы не читалась как проверенное):
## смысл текстов, «пять обязательных ★ по смыслу», цену заявок движку, баланс (долю
## вмешательства, порог тревоги). Это чтение и дизайнерское решение, а не прогон.

const Validator := preload("res://content/validator.gd")
const Loader := preload("res://content/loader.gd")
const Problems := preload("res://content/problems.gd")
const Plan := preload("res://sim/plan.gd")
## Виды рёбер, перекрываемых тревогой, инструмент берёт У ЯДРА, а не своим списком:
## два списка разошлись бы молча, и «путь, не перекрываемый тревогой» считался бы по
## другому правилу, чем играет ядро.
const Response := preload("res://sim/response.gd")
## Рантайм-вид окна (`locked_edge` → `locked_door`) и составной id берутся у ядра: id
## объявленного окна и id события `window_opened` обязаны считаться ОДНИМ правилом, иначе
## сверка «окно сработало» ищет в журнале имя, которого там нет (проба это и поймала).
const WindowScript := preload("res://sim/window.gd")
## Построение сценария вмешательства — тот же модуль, что у замера (`measure_mission01.gd`):
## «приказы» здесь и там считаются по одному правилу, а не по двум похожим.
const OrderBuilder := preload("res://tests/order_builder.gd")

const EXIT_OK := 0
const EXIT_CRITERIA := 1
const EXIT_BAD_INPUT := 2

## Сиды 1…5 — как в замере v1: матрица сравнима, а детерминизм подтверждается повтором.
const SEEDS := [1, 2, 3, 4, 5]

const BEHAVIOR_SILENCE := "молчание"
const BEHAVIOR_FIRST := "первый вариант"
const BEHAVIOR_REASONABLE := "разумные приказы"
const BEHAVIORS := [BEHAVIOR_SILENCE, BEHAVIOR_FIRST, BEHAVIOR_REASONABLE]

## Геометрия: шаг сетки и размер коробки помещения (report.md §10, `scales.md` §10).
## Помещения стоят в узлах сетки, коробка рисуется 3×3, поэтому «не наезжают» = расстояние
## Чебышёва между любыми двумя помещениями одного этажа не меньше шага.
const GRID_STEP := 4

## Критерии приёмки — имена ДОСЛОВНО из `design.md` §3, порядок печати фиксирован.
## Одно имя добавлено решением D53 (`REASONABLE_ORDERS_SUCCEED`): именно им требование
## задания §3.4 («при разумных приказах миссия завершается успехом») становится
## проверяемым, а без него матрица покрывала бы только две крайности поведения.
const CRITERIA := ["FORM", "GEOMETRY", "ENTRIES_DECLARED", "OBJECTIVE_FROM_EVERY_ENTRY",
	"EXIT_REACHED", "FAILURE_REACHABLE", "TWO_INDEPENDENT_EXITS", "WINDOW_FIRED_AT_LEAST_ONCE",
	"FIRING_RANGE", "REASONABLE_ORDERS_SUCCEED"]
const VERDICT_OK := "выполнен"
const VERDICT_FAIL := "НАРУШЕН"
const VERDICT_SKIP := "не проверялось"

const FIRING_MIN := 5
const FIRING_MAX := 12
const FIRING_TARGET := "8–9"

## Причины отказа приказа, объявленные ядром (`sim.gd:order`: `unknown_option`, `no_orders`,
## `shielded`/`jammed` — одной веткой). Список нужен ровно затем, чтобы вывод НАЗЫВАЛ причину:
## «приказов 0» без причины читается как «игрок молчал», хотя ядро отказывало. Причина,
## которой здесь нет, — расхождение инструмента с ядром, и оно называется вслух
## (`_print_behaviors`): это тот же класс, что снятая сверка двух счётов окон.
const REFUSAL_REASONS := ["shielded", "jammed", "no_orders", "unknown_option"]

## Бюджет перебора простых путей. Перебор ищет ВТОРОЙ путь и останавливается, как только
## нашёл: на разреженном графе уровня это доли миллисекунды. Бюджет стоит на случай графа,
## где путей нет вовсе, а циклов много: тогда перебор прекращается и говорит об этом вслух,
## а не висит.
const PATH_SEARCH_BUDGET := 200000

var _verdict_reached := false
## Нарушения внутренних инвариантов ИНСТРУМЕНТА (не критериев приёмки): расхождение двух
## счётов одного и того же, несошедшийся сценарий, разошедшийся детерминизм. Критерий про
## них молчит, но вердикт обязан быть красным: сломанный инструмент не имеет права
## докладывать «уровень принят».
var _instrument: Array = []
## Вердикты критериев: имя → {fact, requirement, verdict}.
var _criteria: Dictionary = {}


func _initialize() -> void:
	for name in CRITERIA:
		_criteria[name] = {"fact": "—", "requirement": "—", "verdict": VERDICT_SKIP}
	## Результат работы — КОНВЕРТ, а не код возврата. Причина проверена пробой P7: рантайм-сбой
	## внутри `_accept()` прерывает ТОЛЬКО её, а `_initialize()` продолжается — и `quit(code)`
	## получает правдоподобный ноль, уже напечатав `SCRIPT ERROR` (процесс отдал 0). Конверт
	## с обязательным ключом отличим от того, что вернёт прерванная функция (null, пустой
	## словарь, ноль), поэтому «аборт до вердикта» не может выглядеть как зелёный прогон.
	var result = _accept()
	if typeof(result) != TYPE_DICTIONARY or not (result as Dictionary).has("verdict_code"):
		print("АБОРТ  вердикт не выставлен: _accept() прервался, а не дошёл до вердикта (код 1)")
		_verdict_reached = true
		quit(EXIT_CRITERIA)
		return
	_verdict_reached = true
	quit(int((result as Dictionary)["verdict_code"]))


## Вердикт приёмки в конверте (см. `_initialize`): код едет ключом, а не значением функции.
func _verdict(code: int) -> Dictionary:
	return {"verdict_code": code}


## Форма результата стадии. Проба P7 показала, что прерванный вызов возвращает не то, что
## обещала функция, и вызывающий продолжает работу: поэтому каждая стадия, чей результат
## судит вердикт, проверяется ПО ФОРМЕ, а не по «не упало».
func _shaped(value, key: String) -> bool:
	return typeof(value) == TYPE_DICTIONARY and (value as Dictionary).has(key)


## Стадия вернула не то, что обещала: судить нечем, вердикт — «инструмент сломан» (код 1).
func _broken(what: String) -> Dictionary:
	print("АБОРТ  %s: результат стадии не той формы — вызов прервался (код 1)" % what)
	_print_criteria()
	return _verdict(EXIT_CRITERIA)


## Второй сторож: срабатывает, если прервался сам `_initialize()` — тогда `quit()` не вызван
## вовсе, и без сторожа процесс висел бы или отдал ноль. Тот же приём, что в
## `kit/verifier/verify.gd`; вместе с конвертом он закрывает оба способа аборта.
func _process(_delta: float) -> bool:
	if _verdict_reached:
		return false
	print("АБОРТ  вердикт не выставлен: прогон прервался до quit() (код 1)")
	quit(EXIT_CRITERIA)
	return true


## Стадии приёмки. Возвращает КОНВЕРТ `{"verdict_code": …}` (см. `_initialize`), а не код:
## иначе рантайм-сбой внутри превратился бы в «похожий на правду» ноль.
func _accept():
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		print("ИСПОЛЬЗОВАНИЕ: --script res://tests/accept_delivery.gd -- <mission.json> <texts.json>")
		print("передано аргументов после `--`: %d, а нужно ровно два" % args.size())
		return _verdict(EXIT_BAD_INPUT)
	var mission_path := String(args[0])
	var texts_path := String(args[1])

	var mission_read := _read_json(mission_path)
	if not bool(mission_read["ok"]):
		print("НЕ ПРОЧИТАНО  mission: %s" % String(mission_read["error"]))
		return _verdict(EXIT_BAD_INPUT)
	var texts_read := _read_json(texts_path)
	if not bool(texts_read["ok"]):
		print("НЕ ПРОЧИТАНО  texts: %s" % String(texts_read["error"]))
		return _verdict(EXIT_BAD_INPUT)
	var data = mission_read["data"]
	var texts = texts_read["data"]
	if typeof(data) != TYPE_DICTIONARY or typeof(texts) != TYPE_DICTIONARY:
		print("НЕ ТОТ ФОРМАТ  mission: %s, texts: %s — нужны объекты {}" % [
			type_string(typeof(data)), type_string(typeof(texts))])
		return _verdict(EXIT_BAD_INPUT)

	print("=== Приёмка поставки уровня: %s ===" % mission_path)
	print("тексты: %s" % texts_path)
	print("")

	## Граф сырых данных и входы нужны и нормативу (стадия 0), и связности (стадия 3):
	## считаются один раз, до первой стадии, чтобы «маршрута для входа нет» было названо
	## РАНЬШЕ вердикта по форме — иначе норматив просто не с чего взять, а прогон
	## остановился бы на форме и промолчал о том, что мерить нечего.
	var adj := _adjacency(data)
	var entries := _entry_nodes(data)

	# ------------------------------------------------- стадия 0: норматив (D47, D53)
	## Норматив «окон за прохождение» мерится на ОБЪЯВЛЕННЫХ маршрутах, поэтому их
	## пригодность проверяется до всего остального и называется своими словами:
	## у каждого входа обязан быть ровно один объявленный маршрут, и каждая пара его
	## соседей — ребро. Валидатор судит то же самое, но вердикт по форме печатается
	## ПОСЛЕ, а «мерить не на чем» — факт о нормативе, а не о форме.
	print("== 0. Норматив: объявленные в данных маршруты (D47) ==")
	var declared := _declared_routes(data)
	var declared_gaps: Array = _declared_gaps(declared, entries, adj)
	print("  объявленных маршрутов: %d; входов (тег entry): %d" % [declared.size(), entries.size()])
	for r in declared:
		print("  %-16s %s → %s (помещений %d): %s" % [String(r["id"]), String(r["entry"]),
			String(r["exit"]), (r["route"] as Array).size(), " → ".join(_strings(r["route"]))])
	for gap in declared_gaps:
		print("  НАРУШЕНИЕ НОРМАТИВА: %s" % String(gap))
	if declared_gaps.is_empty():
		print("  DECLARED_ROUTES: у каждого входа ровно один объявленный маршрут, пары соседей — рёбра (нарушений 0)")
	else:
		_instrument.append("DECLARED_ROUTES: %s" % "; ".join(declared_gaps))
	print("")

	# ---------------------------------------------------------------- стадия 1: форма
	print("== 1. Форма: боевые content/validator.gd + content/loader.gd ==")
	var problems: Array = Validator.validate(data, texts)
	print("ПРОБЛЕМ: %d" % problems.size())
	var i := 1
	for p in problems:
		print("  %d. [%s] %s — %s" % [i, String(p.get("code", "")), String(p.get("path", "")),
			String(p.get("message", ""))])
		i += 1
	if not problems.is_empty():
		_set_criterion("FORM", "проблем формы: %d (первая: %s)" % [problems.size(),
			Problems.brief(problems[0])], "0 проблем формы, миссия собирается", VERDICT_FAIL)
		print("СОБРАНО: — миссия не собрана (проблем формы %d), дальше судить нечего" % problems.size())
		_print_criteria()
		print("ИТОГ ПРИЁМКИ: уровень не принят — форма не прошла (код 1)")
		return _verdict(EXIT_CRITERIA)

	var loaded := Loader.load_mission(data, texts)
	var loaded_problems: Array = loaded["problems"]
	if loaded["mission"] == null or not loaded_problems.is_empty():
		print("СБОРКА: миссия НЕ собрана, хотя проблем формы нет:")
		for p in loaded_problems:
			print("  [%s] %s — %s" % [String(p.get("code", "")), String(p.get("path", "")),
				String(p.get("message", ""))])
		_set_criterion("FORM", "проблем формы 0, но миссия НЕ собрана", "0 проблем формы, миссия собирается",
			VERDICT_FAIL)
		_print_criteria()
		print("ИТОГ ПРИЁМКИ: вход/сборка не состоялись (код 2)")
		return _verdict(EXIT_BAD_INPUT)
	var mission = loaded["mission"]
	_set_criterion("FORM", "проблем формы 0, миссия собрана", "0 проблем формы, миссия собирается",
		VERDICT_OK)
	print("СОБРАНО: миссия «%s», помещений %d, рёбер %d, патрулей %d, сенсоров %d, окон %d, разведка %d, объявленных маршрутов %d"
		% [mission.id, mission.nodes.size(), mission.edges.size(), mission.patrols.size(),
			mission.sensors.size(), OrderBuilder.windows(mission).size(),
			(mission.data["intel"] as Array).size(), declared.size()])
	print("")

	# ---------------------------------------------------------------- стадия 2: геометрия
	print("== 2. Геометрия схемы: pos, наложения помещений этажа, подписи с текстами ==")
	var geometry := _geometry(data, texts)
	if not _shaped(geometry, "violations"):
		return _broken("стадия 2 (геометрия)")
	for v in geometry["violations"]:
		print("  НАРУШЕНИЕ: %s" % String(v))
	print("  помещений с координатами: %d, пар одного этажа проверено: %d, нарушений: %d" % [
		int(geometry["placed"]), int(geometry["pairs"]), (geometry["violations"] as Array).size()])
	_set_criterion("GEOMETRY", "нарушений: %d; помещений с pos %d, пар этажа %d" % [
		(geometry["violations"] as Array).size(), int(geometry["placed"]), int(geometry["pairs"])],
		"pos у всех помещений, зазор ≥ %d (коробка 3×3), подписи/этажи/комплекс с текстами" % GRID_STEP,
		VERDICT_OK if (geometry["violations"] as Array).is_empty() else VERDICT_FAIL)
	if not (geometry["violations"] as Array).is_empty():
		print("")
		_print_criteria()
		print("ИТОГ ПРИЁМКИ: уровень не принят — карта не собирается (код 1)")
		return _verdict(EXIT_CRITERIA)
	print("")

	# ---------------------------------------------------------------- стадия 3: связность
	print("== 3. Связность и тупики: входы, путь к цели, независимые пути к выходу ==")
	var objective := String(data.get("objective", ""))
	print("перекрываемые тревогой виды рёбер (ядро, sim/response.gd:BLOCKED_KINDS): %s"
		% ", ".join(_strings(Response.BLOCKED_KINDS)))
	print("входы (тег entry): %s (узлов: %d)" % [
		", ".join(entries) if not entries.is_empty() else "(нет)", entries.size()])
	print("цель: %s" % objective)
	print("НАПРАВЛЕНИЕ СВЯЗНОСТИ — ОТ ЦЕЛИ К ВЫХОДУ, а он у объявленного маршрута свой")
	print("(`exit` в данных); автоматические маршруты выходят туда, откуда пришли.")
	_set_criterion("ENTRIES_DECLARED", "узлов с тегом entry: %d" % entries.size(), "не меньше трёх",
		VERDICT_OK if entries.size() >= 3 else VERDICT_FAIL)

	var exits_ok := true
	var exits_facts: Array = []
	for entry in entries:
		var to_goal := _bfs_path(adj, String(entry), objective, true)
		if to_goal.is_empty():
			print("  %s → %s: ПУТИ НЕТ" % [entry, objective])
		else:
			print("  %s → %s: %s (рёбер %d)" % [entry, objective, " → ".join(to_goal),
				(to_goal as Array).size() - 1])
		var plain := _count_paths(adj, objective, String(entry))
		var free_path := _bfs_path(adj, objective, String(entry), false)
		var entry_ok := int(plain["count"]) >= 2 and not free_path.is_empty()
		exits_ok = exits_ok and entry_ok
		exits_facts.append("%s: путей %d%s, без перекрываемых рёбер %s" % [entry,
			int(plain["count"]), " (перебор прерван)" if bool(plain["exhausted"]) else "",
			"есть" if not free_path.is_empty() else "НЕТ"])
		print("    от цели (%s) к выходу (%s): простых путей %d%s; путь без перекрываемых тревогой рёбер: %s"
			% [objective, entry, int(plain["count"]),
				" (перебор прерван по бюджету)" if bool(plain["exhausted"]) else "",
				(" → ".join(free_path)) if not free_path.is_empty() else "НЕТ"])
		if bool(plain["exhausted"]):
			_instrument.append("перебор путей к %s прерван по бюджету %d" % [entry, PATH_SEARCH_BUDGET])
	_set_criterion("TWO_INDEPENDENT_EXITS", "; ".join(exits_facts) if not exits_facts.is_empty() else "входов нет",
		"от цели к выходу ≥ 2 простых путей И есть путь без рёбер видов %s"
			% ", ".join(_strings(Response.BLOCKED_KINDS)),
		VERDICT_OK if exits_ok and not entries.is_empty() else VERDICT_FAIL)
	print("")

	# ---------------------------------------------------------------- стадия 4: маршруты
	print("== 4. Маршруты: ОБЪЯВЛЕННЫЕ в данных (норматив) + автоматические BFS (доказательство) ==")
	var auto := _build_routes(adj, data, entries, objective)
	if not _shaped(auto, "routes"):
		return _broken("стадия 4 (построение маршрутов)")
	for note in auto["notes"]:
		print("  ПРОПУЩЕН: %s" % String(note))
	var routes_norm: Array = declared
	var routes_proof: Array = auto["routes"]
	var routes: Array = []
	routes.append_array(routes_norm)
	routes.append_array(routes_proof)
	print("  НОРМАТИВ — объявленные маршруты: %d; на них считаются окна за прохождение," % routes_norm.size())
	print("  исходы и доля вмешательства (D47/D53).")
	print("  ДОКАЗАТЕЛЬСТВО — автоматические BFS-маршруты: %d уникальных (с повторами-крышками: %d);" % [
		routes_proof.size(), int(auto["built"])])
	print("  они отвечают на другой вопрос: способно ли КАЖДОЕ объявленное окно сработать.")
	print("  в матрице прогонов: %d маршрутов (%d объявленных + %d автоматических)" % [
		routes.size(), routes_norm.size(), routes_proof.size()])
	var adjacency_violations: Array = []
	for r in routes:
		var chain: Array = r["route"]
		for k in range(chain.size() - 1):
			if mission.edge_between(String(chain[k]), String(chain[k + 1])).is_empty():
				adjacency_violations.append("%s: %s → %s" % [r["id"], chain[k], chain[k + 1]])
	if not adjacency_violations.is_empty():
		print("  ВНУТРЕННИЙ ИНВАРИАНТ ROUTE_ADJACENCY НАРУШЕН (пара соседей без ребра):")
		for v in adjacency_violations:
			print("    %s" % String(v))
		_instrument.append("ROUTE_ADJACENCY: пар без ребра %d" % adjacency_violations.size())
	else:
		print("  ROUTE_ADJACENCY: все пары соседей маршрутов ОБЕИХ выборок — рёбра собранной модели (нарушений 0)")
	print("")

	# ---------------------------------------------------------------- стадия 4: прогоны
	print("== 4а. Прогон ядра: маршрут × поведение × сид ==")
	print("поведения: %s; сиды: %s; прогонов: %d" % [
		", ".join(BEHAVIORS), str(SEEDS), routes.size() * BEHAVIORS.size() * SEEDS.size()])
	var rows: Array = []
	for r in routes:
		for behavior in BEHAVIORS:
			for seed in SEEDS:
				var built := _run_route(mission, r, behavior, int(seed))
				if not _shaped(built, "run"):
					return _broken("стадия 4 (прогон %s)" % r["id"])
				var row := _row(mission, r, built, String(behavior), int(seed))
				if not _shaped(row, "outcome"):
					return _broken("стадия 4 (строка %s)" % r["id"])
				rows.append(row)
				if not bool(row["stable"]):
					_instrument.append("%s/%s/seed %d: сценарий не сошёлся" % [
						r["id"], behavior, seed])
				if int(row.get("unknown_option", 0)) > 0:
					_instrument.append("%s/%s/seed %d: unknown_option=%d" % [
						r["id"], behavior, seed, int(row.get("unknown_option", 0))])
				if not bool(row["counters_match"]):
					_instrument.append("%s/%s/seed %d: два счёта окон разошлись (%s против %s)" % [
						r["id"], behavior, seed, str(row["fired"]), str(row["ordered"])])
	print("  прогонов состоялось: %d" % rows.size())
	print("")

	_print_route_table(routes_norm, "5а-1", "НОРМАТИВ: объявленные маршруты (выход — `exit` из данных)")
	_print_route_table(routes_proof, "5а-2", "ДОКАЗАТЕЛЬСТВО: автоматические BFS-маршруты (выход = вход маршрута)")
	_print_window_table(routes_norm, rows, "5б", "НОРМАТИВ: объявленные маршруты")
	_print_window_table(routes_proof, rows, "5в", "ДОКАЗАТЕЛЬСТВО: автоматические BFS-маршруты")
	_print_outcome_matrix(routes_norm, rows, "5г", "НОРМАТИВ: объявленные маршруты")
	_print_outcome_matrix(routes_proof, rows, "5д", "ДОКАЗАТЕЛЬСТВО: автоматические BFS-маршруты")
	var firing := _print_firing_range(routes_norm, rows)
	if not _shaped(firing, "ok"):
		return _broken("стадия 5 (диапазон срабатываний)")
	_print_proof_range(routes_proof, rows)
	var reasonable := _print_behaviors(routes_norm, rows)
	if not _shaped(reasonable, "orders"):
		return _broken("стадия 5 (поведения)")
	var dead := _never_fired(data, rows)
	if typeof(dead) != TYPE_ARRAY:
		return _broken("стадия 5 (неработавшие окна)")
	_print_never_fired(dead, routes_norm, routes_proof, rows)
	var windows_total := _windows_total(data)
	_set_criterion("WINDOW_FIRED_AT_LEAST_ONCE",
		"объявленных окон: %d; сработало %d%s" % [windows_total, windows_total - dead.size(),
			("; ни разу: %s" % _dead_names(dead)) if not dead.is_empty() else ""],
		"каждое объявленное окно срабатывает хотя бы на одном прогоне матрицы (обе выборки)",
		VERDICT_OK if dead.is_empty() and windows_total > 0 else VERDICT_FAIL)
	_set_criterion("FIRING_RANGE", String(firing["fact"]),
		"на КАЖДОМ объявленном маршруте срабатывающих окон за прохождение %d…%d; ни одно прохождение любой выборки не больше %d (ориентир %s печатается отдельно)" % [
			FIRING_MIN, FIRING_MAX, FIRING_MAX, FIRING_TARGET],
		VERDICT_OK if bool(firing["ok"]) else VERDICT_FAIL)
	_set_criterion("REASONABLE_ORDERS_SUCCEED", String(reasonable["fact"]),
		"на КАЖДОМ объявленном маршруте поведение «%s» хотя бы на одном сиде даёт исход extracted (проходимость при разумных приказах, задание на поставку §3.4)" % BEHAVIOR_REASONABLE,
		VERDICT_OK if bool(reasonable["ok"]) else VERDICT_FAIL)

	# ---------------------------------------------------------------- критерии прогона
	var goals := _entries_with(rows, "objective_done")
	var extracted := _entries_with(rows, "extracted")
	_set_criterion("OBJECTIVE_FROM_EVERY_ENTRY", _entries_fact(entries, goals,
		"входов с взятой целью: %d из %d", "цель не взята ни на одном прогоне"), 
		"от КАЖДОГО входа есть прогон, где группа берёт цель (objective_done)",
		VERDICT_OK if goals.size() == entries.size() and not entries.is_empty() else VERDICT_FAIL)
	_set_criterion("EXIT_REACHED", _entries_fact(entries, extracted,
		"входов с исходом extracted: %d из %d", "ни одного extracted"), 
		"на КАЖДОМ входе есть прогон с исходом extracted",
		VERDICT_OK if extracted.size() == entries.size() and not entries.is_empty() else VERDICT_FAIL)
	var caught := 0
	for row in rows:
		if str(row["outcome"]) == "caught":
			caught += 1
	_set_criterion("FAILURE_REACHABLE", "прогонов с исходом caught: %d из %d" % [caught, rows.size()],
		"существует прогон с исходом caught",
		VERDICT_OK if caught > 0 else VERDICT_FAIL)

	# ---------------------------------------------------------------- детерминизм
	var det := _determinism(mission, routes_norm)
	if not _shaped(det, "same"):
		return _broken("стадия 6 (детерминизм)")
	print("== 6. Детерминизм: тот же маршрут + сид + поведение → тот же digest ==")
	print("  %s" % String(det["line"]))
	if not bool(det["same"]):
		_instrument.append("детерминизм: digest повтора разошёлся")
	print("")

	_print_criteria()
	if not _instrument.is_empty():
		print("ИНСТРУМЕНТ: %s" % "; ".join(_instrument))
	var failed: Array = []
	for name in CRITERIA:
		if str((_criteria[name] as Dictionary)["verdict"]) == VERDICT_FAIL:
			failed.append(String(name))
	if failed.is_empty() and _instrument.is_empty():
		print("ИТОГ ПРИЁМКИ: все обязательные критерии выполнены (код 0)")
		return _verdict(EXIT_OK)
	if not failed.is_empty():
		print("ИТОГ ПРИЁМКИ: нарушены критерии: %s (код 1)" % ", ".join(failed))
		return _verdict(EXIT_CRITERIA)
	print("ИТОГ ПРИЁМКИ: критерии выполнены, но инструмент неисправен — вердикт не выносится (код 1)")
	## Ветка возвращает КОНВЕРТ, как и все остальные выходы `_accept()`. Пока здесь стоял
	## голый `int`, он не отличался от «функция прервалась» (`null`), и `_initialize`
	## печатал ложное `АБОРТ  _accept() прервался` о функции, которая дошла до вердикта
	## (M2 ревью 01–04): сообщение отправляло искать аборт, которого не было. Код возврата
	## при этом был верный — врал только текст, и именно поэтому дефект не ловился прогоном.
	return _verdict(EXIT_CRITERIA)


# ---------------------------------------------------------------- критерии и печать

func _set_criterion(name: String, fact: String, requirement: String, verdict: String) -> void:
	_criteria[name] = {"fact": fact, "requirement": requirement, "verdict": verdict}


func _print_criteria() -> void:
	print("== 7. Критерии приёмки: имя — факт — требование — вердикт (имена из design.md §3; `REASONABLE_ORDERS_SUCCEED` добавлен D53) ==")
	for name in CRITERIA:
		var entry: Dictionary = _criteria[name]
		print("  %-27s %s" % [String(name), str(entry["verdict"])])
		print("      факт:        %s" % str(entry["fact"]))
		print("      требование:  %s" % str(entry["requirement"]))
	print("")


## Входы, на которых у матрицы есть прогон с нужным свойством. Два свойства — «цель взята»
## (`objective_done`) и «исход extracted»: «путь существует» и «цель берётся» — разные
## утверждения (design.md §3, `OBJECTIVE_FROM_EVERY_ENTRY`).
func _entries_with(rows: Array, what: String) -> Array:
	var out: Array = []
	for row in rows:
		var hit := bool(row["objective_done"]) if what == "objective_done" \
			else str(row["outcome"]) == "extracted"
		if not hit:
			continue
		if not out.has(String(row["entry"])):
			out.append(String(row["entry"]))
	return out


func _entries_fact(entries: Array, hit: Array, template: String, empty: String) -> String:
	if entries.is_empty():
		return empty
	var missing: Array = []
	for entry in entries:
		if not hit.has(String(entry)):
			missing.append(String(entry))
	return (template % [hit.size(), entries.size()]) + \
		("; без успеха: %s" % ", ".join(missing) if not missing.is_empty() else "")


## Сверка двух независимых счётов одного и того же: окна, открывшиеся по `window_opened`,
## против окон, получивших решение (`order_issued`/`order_silenced`). Расхождение означает,
## что подпись таблицы и её счёт разошлись, — это дефект инструмента, а не данных.


# ---------------------------------------------------------------- чтение входа

func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "data": null,
			"error": "не открыт «%s» (код ошибки %d)" % [path, FileAccess.get_open_error()]}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var error := json.parse(text)
	if error != OK:
		return {"ok": false, "data": null,
			"error": "«%s» не разбирается как JSON: %s (строка %d)"
				% [path, json.get_error_message(), json.get_error_line()]}
	return {"ok": true, "data": json.data, "error": ""}


func _strings(items: Array) -> Array:
	var out: Array = []
	for i in items:
		out.append(str(i))
	return out


# ---------------------------------------------------------------- граф

## Смежность по СЫРЫМ данным файла: словарь «узел → [{to, edge, kind}]», список каждого узла
## отсортирован по id ребра, затем по узлу. Порядок обхода фиксирован: BFS и перебор путей
## обязаны давать один и тот же ответ при каждом прогоне.
func _adjacency(data: Dictionary) -> Dictionary:
	var adj: Dictionary = {}
	var edges = data.get("edges", [])
	if typeof(edges) != TYPE_ARRAY:
		return adj
	for e in (edges as Array):
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var dict: Dictionary = e
		var a := str(dict.get("a", ""))
		var b := str(dict.get("b", ""))
		var eid := str(dict.get("id", ""))
		var kind := str(dict.get("kind", ""))
		if a == "" or b == "":
			continue
		_append_neighbour(adj, a, {"to": b, "edge": eid, "kind": kind})
		_append_neighbour(adj, b, {"to": a, "edge": eid, "kind": kind})
	for node in adj:
		(adj[node] as Array).sort_custom(func(x, y):
			if String(x["edge"]) == String(y["edge"]):
				return String(x["to"]) < String(y["to"])
			return String(x["edge"]) < String(y["edge"]))
	return adj


func _append_neighbour(adj: Dictionary, node: String, step: Dictionary) -> void:
	var bucket: Array = adj.get(node, [])
	bucket.append(step)
	adj[node] = bucket


## Узлы с тегом `entry`, отсортированные по id: порядок печати и построения маршрутов
## не должен зависеть от порядка ключей словаря `nodes`.
func _entry_nodes(data: Dictionary) -> Array:
	var nodes = data.get("nodes", null)
	if typeof(nodes) != TYPE_DICTIONARY:
		return []
	var out: Array = []
	for node_id in (nodes as Dictionary):
		var node = (nodes as Dictionary)[node_id]
		if typeof(node) != TYPE_DICTIONARY:
			continue
		var tags = (node as Dictionary).get("tags", [])
		if typeof(tags) == TYPE_ARRAY and (tags as Array).has("entry"):
			out.append(str(node_id))
	out.sort()
	return out


## Кратчайший путь по числу рёбер. `allow_blocked == false` — по графу БЕЗ рёбер видов,
## перекрываемых тревогой: так проверяется «перекрытие одного пути не отрезает выход».
func _bfs_path(adj: Dictionary, from: String, to: String, allow_blocked: bool) -> Array:
	if from == "" or to == "":
		return []
	if from == to:
		return [from]
	var prev: Dictionary = {from: ""}
	var queue: Array = [from]
	while not queue.is_empty():
		var current := String(queue.pop_front())
		for step in adj.get(current, []):
			if not allow_blocked and Response.BLOCKED_KINDS.has(String(step["kind"])):
				continue
			var nxt := String(step["to"])
			if prev.has(nxt):
				continue
			prev[nxt] = current
			if nxt == to:
				return _restore_path(prev, to)
			queue.append(nxt)
	return []


func _restore_path(prev: Dictionary, to: String) -> Array:
	var out: Array = [to]
	var current := to
	while String(prev[current]) != "":
		current = String(prev[current])
		out.push_front(current)
	return out


## Сколько РАЗНЫХ простых путей ведёт из `from` в `to`, но не больше `cap`: перебор
## останавливается на втором. Считаются именно пути, а не рёбра: у пути к выходу и его
## обходной ветки общее начало (выход из архива один), и «рёберно непересекающихся путей
## нет» было бы ложным диагнозом уровню, который играется.
func _count_paths(adj: Dictionary, from: String, to: String, cap := 2) -> Dictionary:
	if from == "" or to == "":
		return {"count": 0, "exhausted": false}
	if from == to:
		return {"count": 1, "exhausted": false}
	var state := {"found": 0, "budget": PATH_SEARCH_BUDGET, "exhausted": false}
	var visited: Dictionary = {from: true}
	_search_paths(adj, from, to, visited, state, cap)
	return {"count": int(state["found"]), "exhausted": bool(state["exhausted"])}


func _search_paths(adj: Dictionary, current: String, goal: String, visited: Dictionary,
		state: Dictionary, cap: int) -> void:
	if int(state["found"]) >= cap or int(state["budget"]) <= 0:
		if int(state["budget"]) <= 0 and int(state["found"]) < cap:
			state["exhausted"] = true
		return
	if current == goal:
		state["found"] = int(state["found"]) + 1
		return
	for step in adj.get(current, []):
		state["budget"] = int(state["budget"]) - 1
		if int(state["budget"]) <= 0:
			state["exhausted"] = true
			return
		var nxt := String(step["to"])
		if visited.has(nxt):
			continue
		visited[nxt] = true
		_search_paths(adj, nxt, goal, visited, state, cap)
		visited.erase(nxt)
		if int(state["found"]) >= cap:
			return


# ---------------------------------------------------------------- геометрия

## Геометрия схемы операции: координаты, наложения помещений одного этажа, подписи.
## Валидатор судит только ФОРМУ `pos` (обе оси — целые) и пропускает его отсутствие:
## «помещения не наезжают» и «у каждой подписи есть текст» — отдельный вопрос, и его
## задаёт этот раздел.
func _geometry(data: Dictionary, texts) -> Dictionary:
	var violations: Array = []
	var nodes = data.get("nodes", null)
	var node_map: Dictionary = nodes if typeof(nodes) == TYPE_DICTIONARY else {}
	var placed := 0
	var pairs := 0
	var by_floor: Dictionary = {}
	if node_map.is_empty():
		violations.append("nodes: раздел пуст или не словарь — геометрию судить не по чему")
	for node_id in node_map:
		var id := str(node_id)
		var node = node_map[node_id]
		if typeof(node) != TYPE_DICTIONARY:
			violations.append("%s: запись помещения не словарь" % id)
			continue
		var point = _pos_of(node)
		if point == null:
			violations.append("%s: pos нет или оси не целые" % id)
			continue
		placed += 1
		var floor_no := _floor_of(node)
		var bucket: Array = by_floor.get(floor_no, [])
		bucket.append({"id": id, "p": point})
		by_floor[floor_no] = bucket
		var name_key := ""
		if (node as Dictionary).has("name_key"):
			name_key = str((node as Dictionary)["name_key"])
		if name_key == "":
			violations.append("%s: нет name_key — подпись на схеме взять неоткуда" % id)
		elif not _has_text(texts, name_key):
			violations.append("%s: текста «%s» нет в текстах" % [id, name_key])
	var floors = data.get("floors", null)
	var floors_map: Dictionary = floors if typeof(floors) == TYPE_DICTIONARY else {}
	if not (typeof(floors) == TYPE_DICTIONARY):
		violations.append("floors: раздела нет или он не словарь — подписей этажей не будет")
	for floor_key in floors_map:
		var entry = floors_map[floor_key]
		if typeof(entry) != TYPE_DICTIONARY or not (entry as Dictionary).has("name_key"):
			violations.append("floors.%s: нет name_key" % str(floor_key))
			continue
		var floor_name_key := str((entry as Dictionary)["name_key"])
		if not _has_text(texts, floor_name_key):
			violations.append("floors.%s: текста «%s» нет в текстах" % [str(floor_key), floor_name_key])
	for floor_no in by_floor:
		if not floors_map.has(String(floor_no)):
			violations.append("этаж %s: помещения есть, записи в floors нет — подписи этажа не будет"
				% str(floor_no))
	var facility_key := str(data.get("facility_key", ""))
	if facility_key == "":
		violations.append("facility_key: не задан — названия комплекса на схеме не будет")
	elif not _has_text(texts, facility_key):
		violations.append("facility_key: текста «%s» нет в текстах" % facility_key)
	for floor_no in by_floor:
		var items: Array = by_floor[floor_no]
		for i in items.size():
			for j in range(i + 1, items.size()):
				pairs += 1
				var a: Vector2i = items[i]["p"]
				var b: Vector2i = items[j]["p"]
				var gap := maxi(absi(a.x - b.x), absi(a.y - b.y))
				if gap < GRID_STEP:
					violations.append("«%s» и «%s» на этаже %s: расстояние %d < %d (коробка 3×3 на шаге %d)"

						% [items[i]["id"], items[j]["id"], str(floor_no), gap, GRID_STEP, GRID_STEP])
	return {"violations": violations, "placed": placed, "pairs": pairs}


func _pos_of(node) -> Variant:
	if typeof(node) != TYPE_DICTIONARY:
		return null
	var pos = (node as Dictionary).get("pos", null)
	if typeof(pos) != TYPE_DICTIONARY:
		return null
	var x: Variant = Loader.to_int((pos as Dictionary).get("x", null))
	var y: Variant = Loader.to_int((pos as Dictionary).get("y", null))
	if x == null or y == null:
		return null
	return Vector2i(int(x), int(y))


func _floor_of(node) -> String:
	if typeof(node) != TYPE_DICTIONARY:
		return ""
	var value: Variant = Loader.to_int((node as Dictionary).get("floor", null))
	if value == null:
		return ""
	return str(int(value))


## Есть ли текст по ключу. `texts == null` — сверки нет (контракт валидатора): в приёмке
## тексты обязательны, поэтому `null` здесь означает «судить нечем» и назван нарушением.
func _has_text(texts, key: String) -> bool:
	if typeof(texts) != TYPE_DICTIONARY:
		return false
	return (texts as Dictionary).has(key)


# ---------------------------------------------------------------- маршруты

## Маршруты матрицы. Базовые — BFS «вход → цель» на каждый вход; крышечные — «вход → якорь
## окна → цель» на каждое объявленное окно. Якорь берётся у окна: `node` у `node_entered`,
## `edge` у `locked_edge` (маршрут обязан ПРОЙТИ ребро, поэтому строятся обе ориентации),
## `sensor` у `guard_in_sensor` (первое помещение сенсора — порядок объявления).
##
## Одинаковые цепочки схлопываются: разные окна нередко стоят на одном пути, и повторный
## прогон той же цепочки не добавил бы ничего, кроме времени. Имя окна при этом не теряется —
## оно остаётся в списке повторов маршрута.
func _build_routes(adj: Dictionary, data: Dictionary, entries: Array, objective: String) -> Dictionary:
	var routes: Array = []
	var seen: Dictionary = {}
	var notes: Array = []
	var built := 0
	for entry in entries:
		var chain := _bfs_path(adj, String(entry), objective, true)
		built += 1
		if chain.is_empty():
			notes.append("базовый маршрут %s → %s: пути нет" % [entry, objective])
			continue
		_add_route(routes, seen, _make_route("BASE:%s" % entry, String(entry), chain, "базовый", ""))
	var windows = data.get("windows", [])
	if typeof(windows) != TYPE_ARRAY:
		return {"routes": routes, "notes": notes, "built": built}
	for w in (windows as Array):
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var win: Dictionary = w
		var wid := str(win.get("id", ""))
		var trigger = win.get("trigger", null)
		if typeof(trigger) != TYPE_DICTIONARY:
			continue
		var trig: Dictionary = trigger
		var ttype := str(trig.get("type", ""))
		var options: Array = []
		if ttype == "node_entered":
			options.append({"label": "node", "nodes": [str(trig.get("node", ""))]})
		elif ttype == "guard_in_sensor":
			options.append({"label": "sensor", "nodes": _sensor_nodes(data, str(trig.get("sensor", "")))})
		elif ttype == "locked_edge":
			var ends := _edge_ends(data, str(trig.get("edge", "")))
			if ends.size() == 2:
				options.append({"label": "edge", "nodes": ends, "through": true})
		for anchor in options:
			for entry in entries:
				var chains := _anchor_routes(adj, String(entry), objective,
					(anchor as Dictionary)["nodes"], bool((anchor as Dictionary).get("through", false)))
				for item in chains:
					built += 1
					var chain: Array = (item as Dictionary)["chain"]
					var variant := String((item as Dictionary)["variant"])
					_add_route(routes, seen, _make_route("W:%s:%s%s" % [wid, entry, variant],
						String(entry), chain, "крышечный", wid))
	return {"routes": routes, "notes": notes, "built": built}


## Маршруты «вход → якорь → цель». Для ребра-якоря строятся обе ориентации: дверь
## симметрична, и подход с другой стороны — другой прогон. Вариант едет в id маршрута
## (`#1`/`#2`): два маршрута одного окна — РАЗНЫЕ маршруты, и одинаковое имя в матрице
## читалось бы как удвоенная строка одного и того же.
func _anchor_routes(adj: Dictionary, entry: String, objective: String, anchors: Array,
		through: bool) -> Array:
	var out: Array = []
	if anchors.is_empty():
		return out
	if through and anchors.size() == 2:
		for k in 2:
			var x := String(anchors[k])
			var y := String(anchors[1 - k])
			var prefix := _bfs_path(adj, entry, x, true)
			var suffix := _bfs_path(adj, y, objective, true)
			if prefix.is_empty() or suffix.is_empty():
				continue
			var chain: Array = prefix.duplicate()
			chain.append(y)
			for i in range(1, suffix.size()):
				chain.append(String(suffix[i]))
			out.append({"chain": chain, "variant": "#%d" % (k + 1)})
		return out
	var anchor := String(anchors[0])
	var prefix := _bfs_path(adj, entry, anchor, true)
	var suffix := _bfs_path(adj, anchor, objective, true)
	if prefix.is_empty() or suffix.is_empty():
		return out
	var chain: Array = prefix.duplicate()
	for i in range(1, suffix.size()):
		chain.append(String(suffix[i]))
	out.append({"chain": chain, "variant": ""})
	return out


## `exit_node` едет отдельным аргументом: у объявленного маршрута выход задан данными
## (`exit`, D47), и подменять его входом значило бы играть не тот замысел, который объявлен.
func _make_route(id: String, entry: String, chain: Array, kind: String, window_id: String,
		exit_node := "") -> Dictionary:
	return {"id": id, "entry": entry, "exit": exit_node if exit_node != "" else entry, "kind": kind,
		"window": window_id, "route": chain, "aliases": [], "key": "|".join(_strings(chain))}


func _add_route(routes: Array, seen: Dictionary, route: Dictionary) -> void:
	var key := String(route["key"])
	if seen.has(key):
		var existing: Dictionary = routes[int(seen[key])]
		(existing["aliases"] as Array).append(String(route["id"]))
		return
	seen[key] = routes.size()
	routes.append(route)


func _edge_ends(data: Dictionary, edge_id: String) -> Array:
	var edges = data.get("edges", [])
	if typeof(edges) != TYPE_ARRAY:
		return []
	for e in (edges as Array):
		if typeof(e) == TYPE_DICTIONARY and str((e as Dictionary).get("id", "")) == edge_id:
			return [str((e as Dictionary).get("a", "")), str((e as Dictionary).get("b", ""))]
	return []


func _sensor_nodes(data: Dictionary, sensor_id: String) -> Array:
	var sensors = data.get("sensors", [])
	if typeof(sensors) != TYPE_ARRAY:
		return []
	for s in (sensors as Array):
		if typeof(s) != TYPE_DICTIONARY or str((s as Dictionary).get("id", "")) != sensor_id:
			continue
		var raw = (s as Dictionary).get("nodes", [])
		if typeof(raw) == TYPE_ARRAY and not (raw as Array).is_empty():
			return [str((raw as Array)[0])]
	return []


# ---------------------------------------------------------------- объявленные маршруты

## Нормативные маршруты уровня ИЗ ДАННЫХ (`routes`, D47) — та выборка, на которой считается
## норматив «окон за прохождение». Id маршрута получает префикс `DECL:`: без него
## объявленный маршрут `main` и автоматический `BASE:main` читались бы в таблицах как одно
## и то же, а это разные выборки с разными вопросами.
##
## Форму записи здесь НЕ судим (это работа валидатора) — берём то, что есть, и называем
## пропуски в `_declared_gaps`: инструмент обязан сказать «мерить не на чем», а не молча
## померить на меньшем числе маршрутов.
func _declared_routes(data: Dictionary) -> Array:
	var out: Array = []
	var raw = data.get("routes", [])
	if typeof(raw) != TYPE_ARRAY:
		return out
	for r in (raw as Array):
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var route: Dictionary = r
		var chain = route.get("route", [])
		var list: Array = _strings(chain) if typeof(chain) == TYPE_ARRAY else []
		out.append(_make_route("DECL:%s" % str(route.get("id", "")), str(route.get("entry", "")),
			list, "объявленный", "", str(route.get("exit", ""))))
	return out


## Пригоден ли норматив: у каждого входа РОВНО ОДИН объявленный маршрут, объявленный вход
## существует, пары соседей — рёбра. Проверка идёт по СЫРЫМ данным (собранной модели на этой
## стадии ещё нет) и вызывается до вердикта по форме: «мерить не на чем» — факт о нормативе.
func _declared_gaps(declared: Array, entries: Array, adj: Dictionary) -> Array:
	var out: Array = []
	var by_entry: Dictionary = {}
	for r in declared:
		var entry := String(r["entry"])
		var bucket: Array = by_entry.get(entry, [])
		bucket.append(String(r["id"]))
		by_entry[entry] = bucket
		if not entries.has(entry):
			out.append("маршрут «%s» объявлен на узле «%s», а узла с тегом entry «%s» нет"
				% [String(r["id"]), entry, entry])
		var chain: Array = r["route"]
		if chain.is_empty():
			out.append("маршрут «%s» пуст: помещений 0" % String(r["id"]))
			continue
		var first := String(chain[0])
		var last := String(chain[chain.size() - 1])
		if first != entry:
			out.append("маршрут «%s» начинается с «%s», а объявленный вход — «%s»"
				% [String(r["id"]), first, entry])
		if last != String(r["exit"]):
			out.append("маршрут «%s» кончается на «%s», а объявленный выход — «%s»"
				% [String(r["id"]), last, String(r["exit"])])
		for k in range(chain.size() - 1):
			if not _adjacent(adj, String(chain[k]), String(chain[k + 1])):
				out.append("маршрут «%s» разорван: «%s» → «%s» — ребра нет"
					% [String(r["id"]), String(chain[k]), String(chain[k + 1])])
	for entry in entries:
		var ids: Array = by_entry.get(String(entry), [])
		if ids.is_empty():
			out.append("НА ВХОДЕ %s НЕТ ОБЪЯВЛЕННОГО МАРШРУТА" % String(entry))
		elif ids.size() > 1:
			out.append("у входа %s больше одного объявленного маршрута: %s"
				% [String(entry), ", ".join(ids)])
	return out


func _adjacent(adj: Dictionary, a: String, b: String) -> bool:
	for step in adj.get(a, []):
		if String(step["to"]) == b:
			return true
	return false


# ---------------------------------------------------------------- прогоны

func _run_route(mission, route: Dictionary, behavior: String, seed: int) -> Dictionary:
	var plan := Plan.new()
	plan.route = (route["route"] as Array).duplicate()
	plan.exit_node = String(route["exit"])
	plan.exit_backup_node = String(route["exit"])
	var config := {"seed": seed}
	if behavior == BEHAVIOR_SILENCE:
		return {"script": [], "iterations": 1, "stable": true,
			"run": OrderBuilder.run(mission, plan, [], config)}
	if behavior == BEHAVIOR_REASONABLE:
		return OrderBuilder.order_script(mission, plan, seed, OrderBuilder.PICK_REASONABLE, 0)
	return OrderBuilder.order_script(mission, plan, seed, OrderBuilder.PICK_FIRST, 0)


## Строка матрицы. «Сработавшие окна» считаются ДВУМЯ путями — по `window_opened` и по
## решениям окон (`order_issued`/`order_silenced`, тем же `OrderBuilder.window_sequence`,
## что строит сценарий вмешательства): расхождение этих счётов означает дефект инструмента,
## а не данных, и называется вслух (`counters_match`).
func _row(mission, route: Dictionary, built: Dictionary, behavior: String, seed: int) -> Dictionary:
	var run: Dictionary = built["run"]
	var out: Dictionary = run["out"]
	var ev: Array = run["events"]
	var fired: Array = []
	var ordered: Array = []
	var issued := 0
	var silenced := 0
	var opened := 0
	var refused: Dictionary = {}
	var alarm_step := -1
	for e in ev:
		var t := str(e["type"])
		if t == "window_opened":
			opened += 1
			var rid := _window_id_of(e["data"])
			if not fired.has(rid):
				fired.append(rid)
		elif t == "order_issued":
			issued += 1
		elif t == "order_silenced":
			silenced += 1
		elif t == "order_refused":
			var reason := str(e["data"].get("reason", ""))
			refused[reason] = int(refused.get(reason, 0)) + 1
		elif t == "alarm_raised":
			alarm_step = int(e["step"])
	for wid in OrderBuilder.window_sequence(ev):
		if not ordered.has(wid):
			ordered.append(wid)
	var fired_sorted: Array = fired.duplicate()
	fired_sorted.sort()
	var ordered_sorted: Array = ordered.duplicate()
	ordered_sorted.sort()
	return {
		"route": String(route["id"]),
		"entry": String(route["entry"]),
		"kind": String(route["kind"]),
		"window": String(route["window"]),
		"behavior": behavior,
		"seed": seed,
		"outcome": str(out["outcome"]),
		"objective_done": bool(out["objective_done"]),
		"steps": int(out["steps"]),
		"noise": int(out["noise"]),
		"alarm_step": alarm_step,
		"fired": fired,
		"ordered": ordered,
		"counters_match": fired_sorted == ordered_sorted,
		"fired_count": fired.size(),
		## `opened` — сколько окон ОТКРЫЛОСЬ за прогон (события `window_opened`), а не сколько
		## разных окон сработало: доля вмешательства считается у замера как
		## Σ`order_issued` / Σ`window_opened`, и здесь она обязана считаться тем же правилом.
		"opened": opened,
		"issued": issued,
		"silenced": silenced,
		## Отказы ядра по каждой причине ОТДЕЛЬНОЙ строкой словаря и отдельным полем
		## `unknown_reasons`. Причина, которой нет в `REFUSAL_REASONS`, обязана быть
		## напечатана и названа: иначе отказ исчезнувшего вида выглядел бы как «отказов нет».
		"refused": refused.duplicate(),
		"unknown_reasons": _unknown_refusal_reasons(refused),
		"unknown_option": int(refused.get("unknown_option", 0)),
		"stable": bool(built["stable"]),
		"iterations": int(built["iterations"]),
		"digest": str(out["digest"]),
	}


## Причина отказа, которой нет в `REFUSAL_REASONS`: список инструмента обязан следовать за
## ядром, а не за памятью автора. Порядок — по имени, чтобы вывод не зависел от порядка
## словаря (`constraints.md` §1.6): иначе одна и та же матрица печатала бы разные строки.
func _unknown_refusal_reasons(refused: Dictionary) -> Array:
	var out: Array = []
	for reason in refused:
		if not REFUSAL_REASONS.has(String(reason)):
			out.append(String(reason))
	out.sort()
	return out


## Составной id окна из данных события `window_opened` — тот же, что у окна рантайма
## (`view:якорь`): у `locked_edge` это `edge`, у `node_entered` — `node`, у
## `guard_in_sensor` — `sensor` (`sim.gd:_window_event_data`).
func _window_id_of(d: Dictionary) -> String:
	var kind := str(d.get("kind", ""))
	for key in ["edge", "node", "sensor"]:
		if d.has(key):
			return "%s:%s" % [kind, str(d.get(key, ""))]
	return kind


# ---------------------------------------------------------------- таблицы вывода

func _print_route_table(routes: Array, number: String, title: String) -> void:
	print("== %s. %s ==" % [number, title])
	for r in routes:
		var aliases: Array = r["aliases"]
		print("  %-24s %s" % [String(r["id"]), " → ".join(_strings(r["route"]))])
		if not aliases.is_empty():
			print("      те же помещения у маршрутов: %s" % ", ".join(_strings(aliases)))
	print("")


## Таблица «маршрут → окна, которые сработали»: объединение по всем прогонам маршрута
## (3 поведения × 5 сидов), порядок — порядок первого появления окна. В скобках — в скольких
## прогонах маршрута окно сработало: «сработало один раз из пятнадцати» и «сработало всегда» —
## разные факты, и свести их в одну галочку значило бы потерять второй.
##
## Список маршрутов приходит снаружи: строки матрицы содержат ОБЕ выборки, и без списка
## норматив и доказательство слились бы в одну таблицу — ровно то, чего D53 не велит.
func _print_window_table(routes: Array, rows: Array, number: String, title: String) -> void:
	print("== %s. %s: маршрут → сработавшие окна (объединение по прогонам маршрута) ==" % [number, title])
	var order: Array = []
	var by_route: Dictionary = {}
	for r in routes:
		order.append(String(r["id"]))
		by_route[String(r["id"])] = {"order": [], "count": {}, "runs": 0}
	for row in rows:
		var rid := String(row["route"])
		if not by_route.has(rid):
			continue
		var bucket: Dictionary = by_route[rid]
		bucket["runs"] = int(bucket["runs"]) + 1
		for wid in row["fired"]:
			if not (bucket["order"] as Array).has(wid):
				(bucket["order"] as Array).append(wid)
			var counts: Dictionary = bucket["count"]
			counts[wid] = int(counts.get(wid, 0)) + 1
	if order.is_empty():
		print("  (маршрутов этой выборки нет)")
	for rid in order:
		var bucket: Dictionary = by_route[rid]
		var parts: Array = []
		for wid in bucket["order"]:
			parts.append("%s(%d/%d)" % [wid, int((bucket["count"] as Dictionary)[wid]), int(bucket["runs"])])
		print("  %-24s %s" % [rid, ", ".join(parts) if not parts.is_empty() else "(ни одного)"])
	print("  формат: окно(сработало/прогонов маршрута)")
	print("")


func _print_outcome_matrix(routes: Array, rows: Array, number: String, title: String) -> void:
	print("== %s. %s: матрица исходов маршрут × поведение (5 сидов) ==" % [number, title])
	print("  %-24s %-16s %-24s %-12s %s" % ["маршрут", "поведение", "extracted/caught/timeout",
		"цель взята", "окон за прогон (мин/макс)"])
	for r in routes:
		for behavior in BEHAVIORS:
			var outcomes: Dictionary = {}
			var goals := 0
			var runs := 0
			var wmin := 1 << 30
			var wmax := 0
			for row in rows:
				if String(row["route"]) != String(r["id"]) or String(row["behavior"]) != behavior:
					continue
				runs += 1
				var o := String(row["outcome"])
				outcomes[o] = int(outcomes.get(o, 0)) + 1
				if bool(row["objective_done"]):
					goals += 1
				wmin = mini(wmin, int(row["fired_count"]))
				wmax = maxi(wmax, int(row["fired_count"]))
			if runs == 0:
				continue
			print("  %-24s %-16s %-24s %-12s %d/%d" % [String(r["id"]), behavior,
				"%d/%d/%d" % [int(outcomes.get("extracted", 0)), int(outcomes.get("caught", 0)),
					int(outcomes.get("timeout", 0))],
				"%d/%d" % [goals, runs], wmin if wmin <= wmax else 0, wmax])
	print("")


## Окна, не сработавшие ни на одном прогоне матрицы, — с якорем и видом: «окно недостижимо
## на маршруте» и «окно не объявлено» — одна и та же ошибка, и по одному имени её не найти.
func _never_fired(data: Dictionary, rows: Array) -> Array:
	var live: Dictionary = {}
	for row in rows:
		for wid in row["fired"]:
			live[wid] = true
	var out: Array = []
	var windows = data.get("windows", [])
	if typeof(windows) != TYPE_ARRAY:
		return out
	for w in (windows as Array):
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var win: Dictionary = w
		var rid := _declared_window_id(win)
		if live.has(rid):
			continue
		out.append({"id": str(win.get("id", "")), "runtime": rid, "kind": str(win.get("kind", "")),
			"anchor": _anchor_of(win), "reasons": _dead_reasons(data, win)})
	return out


## Составной id ОБЪЯВЛЕННОГО окна — тем же правилом, что у ядра (`WindowScript.kind_for`):
## `locked_edge` в рантайме зовётся `locked_door`, и сверка с событиями без этого
## превращения не находит ни одного окна у запертого ребра (ловится пробой M2).
func _declared_window_id(win: Dictionary) -> String:
	var kind := WindowScript.kind_for(str(win.get("kind", "")))
	var trigger = win.get("trigger", null)
	if typeof(trigger) != TYPE_DICTIONARY:
		return kind
	var trig: Dictionary = trigger
	for key in ["edge", "node", "sensor"]:
		if trig.has(key):
			return "%s:%s" % [kind, str(trig[key])]
	return kind


func _anchor_of(win: Dictionary) -> String:
	var trigger = win.get("trigger", null)
	if typeof(trigger) != TYPE_DICTIONARY:
		return "—"
	var trig: Dictionary = trigger
	for key in ["edge", "node", "sensor"]:
		if trig.has(key):
			return "%s=%s" % [key, str(trig[key])]
	return "—"


## Окна, не сработавшие ни на одном прогоне матрицы, — с якорем, видом и ПРИЧИНОЙ:
## «окно недостижимо на маршруте» и «окно не объявлено» — одна и та же ошибка, и по одному
## имени её не найти. Для окна по сенсору причина называется прямо: сенсор срабатывает
## только на ОХРАНЕ (`sim.gd:_actor_in_sensor`), и если ни один маршрут патруля не заходит
## в его зону, окно не откроется ни при каком прохождении — это факт данных, а не маршрута.
##
## Счёт ведётся по ОБЕИМ выборкам (D53): доказательство «окно способно сработать» — это
## как раз автоматические маршруты, и окно, сработавшее только на BFS-маршруте, живое.
## Поэтому рядом печатается, сколько окон сработало на каждой выборке отдельно: иначе
## «13 из 13» читалось бы как «нормативные маршруты показывают все окна».
func _print_never_fired(dead: Array, routes_norm: Array, routes_proof: Array, rows: Array) -> void:
	print("== 5и. Окна, не сработавшие ни на одном прогоне матрицы ==")
	print("  сработало окон на объявленных маршрутах: %d; на автоматических BFS: %d (объединение — вердикт критерия)"
		% [_live_count(routes_norm, rows), _live_count(routes_proof, rows)])
	if dead.is_empty():
		print("  (нет: сработали все объявленные окна)")
	for d in dead:
		print("  %s: вид %s, якорь %s, объявленный id %s" % [String(d["id"]), String(d["kind"]),
			String(d["anchor"]), String(d["runtime"])])
		for reason in d["reasons"]:
			print("      %s" % String(reason))
	print("")


## Сколько РАЗНЫХ окон сработало на прогонах этой выборки.
func _live_count(routes: Array, rows: Array) -> int:
	var ids: Dictionary = {}
	var wanted: Dictionary = {}
	for r in routes:
		wanted[String(r["id"])] = true
	for row in rows:
		if not wanted.has(String(row["route"])):
			continue
		for wid in row["fired"]:
			ids[wid] = true
	return ids.size()


## Почему окно не может сработать на этой матрице. Пусто — причина не выводится (окно
## срабатывает в принципе, но не сработало на построенных маршрутах).
func _dead_reasons(data: Dictionary, win: Dictionary) -> Array:
	var out: Array = []
	var trigger = win.get("trigger", null)
	if typeof(trigger) != TYPE_DICTIONARY:
		return out
	var trig: Dictionary = trigger
	if str(trig.get("type", "")) != "guard_in_sensor":
		return out
	var sensor_id := str(trig.get("sensor", ""))
	var zone := _sensor_zone(data, sensor_id)
	var guards: Array = []
	var patrols = data.get("patrols", [])
	if typeof(patrols) == TYPE_ARRAY:
		for p in (patrols as Array):
			if typeof(p) != TYPE_DICTIONARY:
				continue
			var route = (p as Dictionary).get("route", [])
			if typeof(route) != TYPE_ARRAY:
				continue
			for n in (route as Array):
				if zone.has(str(n)):
					guards.append("%s" % str((p as Dictionary).get("id", "")))
					break
	out.append("зона сенсора %s: %s; патрулей, заходящих в неё: %s" % [sensor_id,
		", ".join(_strings(zone)) if not zone.is_empty() else "(зона пуста)",
		", ".join(guards) if not guards.is_empty() else "НИ ОДНОГО"])
	if guards.is_empty():
		out.append("сенсор срабатывает только на охране, а охрана ходит строго по своему маршруту:")
		out.append("в этой зоне не бывает никто — окно не откроется ни при каком прохождении.")
	return out


func _sensor_zone(data: Dictionary, sensor_id: String) -> Array:
	var sensors = data.get("sensors", [])
	if typeof(sensors) != TYPE_ARRAY:
		return []
	for s in (sensors as Array):
		if typeof(s) != TYPE_DICTIONARY or str((s as Dictionary).get("id", "")) != sensor_id:
			continue
		var raw = (s as Dictionary).get("nodes", [])
		if typeof(raw) == TYPE_ARRAY:
			return _strings(raw)
	return []


func _windows_total(data: Dictionary) -> int:
	var windows = data.get("windows", [])
	return 0 if typeof(windows) != TYPE_ARRAY else (windows as Array).size()


func _dead_names(dead: Array) -> String:
	var names: Array = []
	for d in dead:
		names.append("%s (%s, %s)" % [d["id"], d["kind"], d["anchor"]])
	return "; ".join(names)


## Число сработавших окон за прохождение — НОРМАТИВ, и считается он на ОБЪЯВЛЕННЫХ
## маршрутах (D47/D53), а не на кратчайших BFS-путях: кратчайший путь — наша догадка о
## замысле, а объявленный маршрут — сам замысел. Мерой взято лучшее прохождение каждого
## объявленного маршрута (3 поведения × 5 сидов): «сколько окон маршрут СПОСОБЕН показать».
##
## Требование тройное, и все три половины несущие:
##   * каждому объявленному маршруту есть чем набрать не меньше `FIRING_MIN` окон (иначе
##     замысел пуст на этом входе);
##   * ни одно прохождение ЛЮБОЙ выборки не показывает больше `FIRING_MAX` окон (иначе
##     окон больше, чем есть голоса: пул приказов — 3);
##   * объявленный маршрут вообще есть (иначе «нарушителей нет» на пустом обходе).
## Ориентир исполнителя (8–9) печатается рядом, но вердиктом не является: это сверка
## замысла с числом, а не критерий приёмки.
func _print_firing_range(routes: Array, rows: Array) -> Dictionary:
	var total := 0
	var wmin := 1 << 30
	var wmax := 0
	for row in rows:
		var count := int(row["fired_count"])
		total += count
		wmin = mini(wmin, count)
		wmax = maxi(wmax, count)
	var avg := 0.0 if rows.is_empty() else float(total) / float(rows.size())
	var base_lines: Array = []
	var base_bad: Array = []
	for r in routes:
		var best := 0
		for row in rows:
			if String(row["route"]) == String(r["id"]):
				best = maxi(best, int(row["fired_count"]))
		base_lines.append("%s: макс %d" % [String(r["id"]), best])
		if best < FIRING_MIN or best > FIRING_MAX:
			base_bad.append("%s: %d" % [String(r["id"]), best])
	print("== 5е. НОРМАТИВ: срабатывающих окон за прохождение по ОБЪЯВЛЕННЫМ маршрутам (критерий: %d…%d, ориентир исполнителя %s) ==" % [
		FIRING_MIN, FIRING_MAX, FIRING_TARGET])
	print("  число взято с объявленных маршрутов; автоматические BFS-маршруты считаются отдельно (5ж) и на норматив не влияют.")
	print("  по всем %d прогонам ОБЕИХ выборок: мин %d, среднее %.1f, макс %d" % [rows.size(),
		wmin if wmin <= wmax else 0, avg, wmax])
	print("  по объявленным маршрутам (лучшее прохождение маршрута): %s" % [
		", ".join(base_lines) if not base_lines.is_empty() else "(объявленных маршрутов нет)"])
	print("  вердикт: каждый объявленный маршрут способен показать %d…%d окон, и ни одно" % [
		FIRING_MIN, FIRING_MAX])
	print("  прохождение любой выборки не показывает больше %d. Ориентир %s — сверка замысла." % [
		FIRING_MAX, FIRING_TARGET])
	print("")
	var ok := not base_lines.is_empty() and base_bad.is_empty() and wmax <= FIRING_MAX
	var fact := "по объявленным маршрутам: %s; по всем прогонам обеих выборок мин %d, среднее %.1f, макс %d" % [
		(", ".join(base_lines) if not base_lines.is_empty() else "объявленных маршрутов нет"),
		wmin if wmin <= wmax else 0, avg, wmax]
	if not base_bad.is_empty():
		fact += "; вне %d…%d: %s" % [FIRING_MIN, FIRING_MAX, ", ".join(base_bad)]
	return {"ok": ok, "fact": fact}


## Та же мера на АВТОМАТИЧЕСКИХ маршрутах — и она НЕ вердикт: BFS-маршруты доказывают, что
## каждое окно способно сработать, а не что замысел уровня даёт 5…12 окон за прохождение.
## Печатается отдельной строкой именно поэтому: короткий путь через грузовой лифт заведомо
## показывает меньше окон, и принять это за дефицит голоса значило бы судить не то.
func _print_proof_range(routes: Array, rows: Array) -> void:
	print("== 5ж. ДОКАЗАТЕЛЬСТВО: та же мера на автоматических BFS-маршрутах (не вердикт) ==")
	var base_lines: Array = []
	for r in routes:
		if String(r["kind"]) != "базовый":
			continue
		var best := 0
		for row in rows:
			if String(row["route"]) == String(r["id"]):
				best = maxi(best, int(row["fired_count"]))
		base_lines.append("%s: макс %d" % [String(r["id"]), best])
	print("  автоматические маршруты «вход → цель»: %s" % [
		", ".join(base_lines) if not base_lines.is_empty() else "(нет)"])
	print("  эта строка на норматив не влияет (D53): она про способность окон, а не про замысел.")
	print("")


## Поведения отдельными строками (D53): «молчание» и «первый вариант» — крайности, и
## требование §3.4 («при разумных приказах — успех») покрывается третьим поведением.
## Здесь же ловится вырождение: если «разумные приказы» не отдали НИ ОДНОГО приказа НА ТОЙ
## ВЫБОРКЕ, ПО КОТОРОЙ ВЫНОСИТСЯ КРИТЕРИЙ (объявленные маршруты), они не отличаются от
## молчания на норме, и требование §3.4 этим прогоном не проверено вовсе.
##
## ПОЧЕМУ СЧЁТ ИНВАРИАНТА И СЧЁТ КРИТЕРИЯ — ПО ОДНОЙ ВЫБОРКЕ (I6 ревью 01–04). Прежде
## невырожденность считалась по ОБЕИМ выборкам (`rows` содержит и объявленные маршруты, и
## автоматические BFS), а критерий судил только объявленные: на каноническом контенте это
## давало «приказов 27 — поведение отличается от молчания» рядом с «`DECL:…`: приказов 0» на
## всех трёх маршрутах нормы. То есть защита от вырождения проходила за счёт BFS-маршрутов,
## а на нормативной выборке третье поведение было неотличимо от молчания — «выглядело
## проверенным, не будучи им». Теперь инвариант считается по норме, а число по обеим
## выборкам печатается рядом СПРАВКОЙ, чтобы разница была видна, а не сглажена.
##
## Доля вмешательства считается у замера как Σ`order_issued` / Σ`window_opened` — тем же
## правилом: два счёта одного и того же разошлись бы молча, и число читалось бы не с той
## строки.
func _print_behaviors(routes: Array, rows: Array) -> Dictionary:
	print("== 5з. Поведения: как решаются окна (каждое поведение — своей строкой) ==")
	print("  %-18s %-9s %-7s %-9s %-10s %-9s %s" % ["поведение", "прогонов", "оконΣ",
		"приказовΣ", "молчанийΣ", "доля", "extracted/caught/timeout"])
	## Выборка нормы — по id объявленных маршрутов: тот же список, по которому судит критерий.
	var declared_ids: Array = []
	for r in routes:
		declared_ids.append(String(r["id"]))
	print("  строки таблицы — по ОБЕИМ выборкам (объявленные + автоматические BFS).")
	print("  инвариант невырожденности считается по НОРМАТИВНОЙ выборке (объявленных маршрутов: %d) —"
		% routes.size())
	print("  по той же, по которой выносится критерий `REASONABLE_ORDERS_SUCCEED` (I6 ревью 01–04).")
	var reasonable_orders := 0
	var reasonable_orders_all := 0
	## Отказы по каждой причине — рядом с приказами, а не вместо них: «приказов 0» и
	## «ядро отказало 0 раз» — РАЗНЫЕ факты, и без этой строки первое читалось бы как
	## «игрок молчал», хотя приказ был отдан и не прошёл (D50: экранированный подвал).
	var refused_totals: Dictionary = {}
	var unknown_reasons: Array = []
	for behavior in BEHAVIORS:
		var runs := 0
		var opened := 0
		var issued := 0
		var silenced := 0
		var outcomes: Dictionary = {}
		for row in rows:
			if String(row["behavior"]) != behavior:
				continue
			runs += 1
			opened += int(row["opened"])
			issued += int(row["issued"])
			silenced += int(row["silenced"])
			if behavior == BEHAVIOR_REASONABLE:
				reasonable_orders_all += int(row["issued"])
				if declared_ids.has(String(row["route"])):
					reasonable_orders += int(row["issued"])
			var refused: Dictionary = row.get("refused", {})
			for reason in refused:
				var name := String(reason)
				refused_totals[name] = int(refused_totals.get(name, 0)) + int(refused[reason])
			for reason in (row.get("unknown_reasons", []) as Array):
				if not unknown_reasons.has(String(reason)):
					unknown_reasons.append(String(reason))
			var o := String(row["outcome"])
			outcomes[o] = int(outcomes.get(o, 0)) + 1
		print("  %-18s %-9d %-7d %-9d %-10d %-9s %s" % [behavior, runs, opened, issued, silenced,
			_share(issued, opened),
			"%d/%d/%d" % [int(outcomes.get("extracted", 0)), int(outcomes.get("caught", 0)),
				int(outcomes.get("timeout", 0))]])
	print("  приказовΣ — ОТДАННЫЕ приказы (`order_issued`); отказ ядра (`order_refused`) в него не входит")
	print("  и печатается своим счётом ниже: «приказов 0» и «ядро отказало 0 раз» — разные факты.")
	var refusal_total := 0
	var refusal_parts: Array = []
	for reason in REFUSAL_REASONS:
		var count := int(refused_totals.get(reason, 0))
		refusal_total += count
		refusal_parts.append("%s %d" % [reason, count])
	for reason in unknown_reasons:
		var count := int(refused_totals.get(String(reason), 0))
		refusal_total += count
		refusal_parts.append("%s %d (причина не объявлена инструментом)" % [String(reason), count])
	print("  ОТКАЗОВ ЯДРА всего: %d (%s)" % [refusal_total, ", ".join(refusal_parts)])
	if not unknown_reasons.is_empty():
		_instrument.append("REFUSAL_REASONS: причины отказа, не объявленные инструментом: %s"
			% ", ".join(unknown_reasons))
	for behavior in BEHAVIORS:
		var per_route: Array = []
		for r in routes:
			var counts: Dictionary = {}
			var runs := 0
			for row in rows:
				if String(row["route"]) != String(r["id"]) or String(row["behavior"]) != behavior:
					continue
				runs += 1
				var refused: Dictionary = row.get("refused", {})
				for reason in refused:
					counts[String(reason)] = int(counts.get(String(reason), 0)) + int(refused[reason])
			var parts: Array = []
			for reason in REFUSAL_REASONS:
				var count := int(counts.get(reason, 0))
				if count > 0:
					parts.append("%s %d" % [reason, count])
			for reason in counts:
				if not REFUSAL_REASONS.has(String(reason)) and int(counts[reason]) > 0:
					parts.append("%s %d" % [String(reason), int(counts[reason])])
			if not parts.is_empty():
				per_route.append("%s: %s" % [String(r["id"]), ", ".join(parts)])
		print("  отказы по маршрутам, поведение «%s»: %s" % [behavior,
			"; ".join(per_route) if not per_route.is_empty() else "(ни одного отказа)"])
	print("")
	print("  РАЗУМНЫЕ_ПРИКАЗЫ по объявленным маршрутам (решения, отданные третьим поведением):")
	print("  требование — ПРОХОДИМОСТЬ (задание §3.4: «при разумном плане и разумных приказах миссия")
	print("  должна завершаться успехом; оба исхода обязаны быть достижимы»), поэтому спрашивается")
	print("  достижимость: хотя бы один сид на маршрут. Доля extracted печатается рядом — по ней")
	print("  видно, «проходится» это или «проходится чудом».")
	var fact_lines: Array = []
	var bad: Array = []
	for r in routes:
		var runs := 0
		var ok_runs := 0
		var issued_r := 0
		for row in rows:
			if String(row["route"]) != String(r["id"]) or String(row["behavior"]) != BEHAVIOR_REASONABLE:
				continue
			runs += 1
			issued_r += int(row["issued"])
			if str(row["outcome"]) == "extracted":
				ok_runs += 1
		fact_lines.append("%s: extracted %d/%d, приказов %d" % [String(r["id"]), ok_runs, runs, issued_r])
		if runs > 0 and ok_runs == 0:
			bad.append("%s: extracted 0/%d" % [String(r["id"]), runs])
	if reasonable_orders == 0:
		print("    НАРУШЕНИЕ: на ОБЪЯВЛЕННЫХ маршрутах приказов 0 — поведение «%s» не отличается"
			% BEHAVIOR_REASONABLE)
		print("    от молчания на НОРМАТИВНОЙ выборке (справка: на обеих выборках приказов %d)."
			% reasonable_orders_all)
		_instrument.append("РАЗУМНЫЕ_ПРИКАЗЫ: поведение «%s» не отличается от молчания на нормативной выборке: приказов 0 на объявленных маршрутах (на обеих выборках %d)"
			% [BEHAVIOR_REASONABLE, reasonable_orders_all])
	else:
		print("    приказов на ОБЪЯВЛЕННЫХ маршрутах %d (справка: на обеих выборках %d) — поведение"
			% [reasonable_orders, reasonable_orders_all])
		print("    отличается от молчания на норме (нарушений 0).")
	print("    исход на объявленных маршрутах: %s" % [
		"; ".join(fact_lines) if not fact_lines.is_empty() else "(объявленных маршрутов нет)"])
	print("")
	var fact := "приказов на объявленных маршрутах: %d (на обеих выборках: %d); исход по объявленным маршрутам: %s" % [
		reasonable_orders, reasonable_orders_all,
		("; ".join(fact_lines) if not fact_lines.is_empty() else "объявленных маршрутов нет")]
	var ok := reasonable_orders > 0 and not fact_lines.is_empty() and bad.is_empty()
	if not bad.is_empty():
		fact += "; НЕ достижим успех: %s" % ", ".join(bad)
	return {"ok": ok, "fact": fact, "orders": reasonable_orders}


## Доля вмешательства строкой: пустой знаменатель — «n/a», а не выдуманный ноль.
func _share(part: int, whole: int) -> String:
	if whole <= 0:
		return "n/a"
	return "%.1f%%" % (100.0 * float(part) / float(whole))


func _determinism(mission, routes: Array) -> Dictionary:
	if routes.is_empty():
		return {"same": false, "line": "маршрутов нет — повторять нечего"}
	var route: Dictionary = routes[0]
	var behavior := BEHAVIOR_SILENCE
	var seed := int(SEEDS[0])
	var first := _run_route(mission, route, behavior, seed)
	var second := _run_route(mission, route, behavior, seed)
	var same := str(first["run"]["out"]["digest"]) == str(second["run"]["out"]["digest"])
	return {"same": same, "line": "%s / сид %d / %s: digest повтора %s первому\n      отпечаток 1: %s\n      отпечаток 2: %s" % [
		String(route["id"]), seed, behavior, "СОВПАЛ" if same else "РАЗОШЁЛСЯ",
		str(first["run"]["out"]["digest"]), str(second["run"]["out"]["digest"])]}

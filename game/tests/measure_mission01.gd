extends SceneTree
## Замер поведения РЕАЛЬНОЙ миссии 01 на штатном контенте (`game/content/`).
##
## Это ИНСТРУМЕНТ, а не кейс набора: в `tests/suite.gd` он не зарегистрирован и вердиктом
## набора не является (разные вопросы — разные ответы). Печатает числа в stdout; код
## возврата относится к самому замеру: 0 — замер состоялся и внутренние инварианты
## инструмента целы (миссия собрана, сценарий вмешательства сошёлся на неподвижной точке,
## детерминизм подтверждён повторным прогоном), 1 — иначе. Аборт внутри `_measure()`
## (рантайм-сбой) — тоже 1: вердикт выносится конвертом, и «прервалось» неотличимо от
## «не сошлось» только по тексту, но не по коду возврата.
##
## Каждое число берётся из журнала `sim.events` (`docs/architecture.md` §5) и в отчёте
## названо событием-источником. Ничего не настраивается: замер измеряет, а не подгоняет.
##
## Границы модели, которые замер НЕ преодолевает (и не должен) — в отчёте отдельным
## разделом: покрытие разведкой в ядре не моделируется, план Б не играется, `money`/`trace`
## из окон нигде не считаются. Прежняя граница «прямой отрезок цель → выход требует ребра
## между целью и выходом» снята задачей 8: отход строится от узла агента по пройденному
## пути (`sim.gd:_withdraw_route`), поэтому выход не обязан быть смежен цели.
## Выбор выхода для матрицы (`EXIT_NODE`) оставлен прежним: иначе «до/после» сравнивало бы
## разные входы. Проба выхода (раздел 4г) показывает остальные выходы отдельно.

const Loader := preload("res://content/loader.gd")
const Problems := preload("res://content/problems.gd")
const Plan := preload("res://sim/plan.gd")
const WindowScript := preload("res://sim/window.gd")
## Построение сценария вмешательства (`_order_script`, `_window_sequence`, `_pick`) вынесено
## в общий модуль: тот же сценарий строит приёмочный инструмент поставки
## (`tests/accept_delivery.gd`), и копия разошлась бы с этим замером молча.
const OrderBuilder := preload("res://tests/order_builder.gd")

const MISSION_PATH := "res://content/mission-01.json"
const TEXTS_PATH := "res://content/texts.ru.json"

## Выход плана для матрицы. `hall0` — не потому, что он единственный сосед цели: соседей
## у `archive0` два (`hall0` через `e_hall0_archive0` и `it_open4` через `e_freight_4_0`),
## а прежняя формулировка «единственный узел, смежный с целью» была неверной. `hall0`
## выбран потому, что он даёт сравнимый выход: на нём матрица снята ДО правки задачи 8
## (`extracted` 15 из 60), и «до/после» обязано считаться на одном и том же входе.
## Проба других выходов — раздел 4г.
const EXIT_NODE := "hall0"

## Ребро сцены ★27 и ребро первого плеча грузового лифта (док → 4-й этаж).
const STUCK_LIFT_EDGE := "e_freight_4_0"
const FREIGHT_UP_EDGE := "e_freight_1_4"
const LIFT_NODE4 := "it_open4"
## Ребро окна `w_archivist`. Это НЕ единственное ребро `archive0`: у него их два —
## `e_hall0_archive0` (дверь из `hall0`, заперта) и `e_freight_4_0` (грузовой лифт из
## `it_open4`, перекрывается тревогой). `ARCHIVE_DOOR_EDGE` называет именно ДВЕРЬ, потому
## что на ней висит окно архивариуса (его `trigger.edge`), и по этому ребру считается
## столбец «архив» раздела 2; второе ребро к окну не относится.
const ARCHIVE_DOOR_EDGE := "e_hall0_archive0"
## Сенсор окна `w_off_schedule`. Его актор — ОХРАНА, а не группа (`sim.gd:_actor_in_sensor`),
## поэтому отдельно проверяется, что выданная «игроку» задержка уходит охраннику.
const OFF_SCHEDULE_SENSOR := "s_it_open4"

const SEEDS := [1, 2, 3, 4, 5]

const BEHAVIOR_SILENCE := "молчание"
const BEHAVIOR_FIRST := "вмешательство"
const BEHAVIOR_LOUD := "громкое"
const BEHAVIORS := [BEHAVIOR_SILENCE, BEHAVIOR_FIRST, BEHAVIOR_LOUD]

## Маршруты — из фактических замыслов уровня: входы помечены тегом `entry`
## (`main_entry1`, `dock1`, `roof`), цель — `archive0`; описание прохождений —
## `levels/mission-01-content/report.md` §1. Слова «обход» и «заявка движку» в данных
## ядром не исполняются (`engine_proposal` → `fallback`), поэтому маршрут — явный список
## помещений, и каждая пара соседей обязана быть ребром (иначе `invalid_mission`).
const ROUTES := [
	{
		"id": "A_2floor",
		"entry": "main_entry1",
		"why": "report.md §1: вход → лестница (Л1 на 2-й не ходит) → свидетель и кухня 2-го → логи терминала → спуск в подвал обратно через охраняемый первый этаж",
		"route": ["main_entry1", "reception1", "hall1", "stair1", "stair2", "hall2",
			"kitchen2", "hall2", "term2", "hall2", "stair2", "stair1", "hall0", "archive0"],
	},
	{
		"id": "B_freight",
		"entry": "dock1",
		"why": "report.md §1: док → Л2 сразу в ИТ-зону 4-го → грузовым вниз в подвал (короткое плечо ветки 4-го без акта)",
		"route": ["dock1", "hall1", "lift_freight1", "it_open4", "archive0"],
	},
	{
		"id": "B_full",
		"entry": "dock1",
		"why": "report.md §1: док → Л2 до ИТ-зоны → рамки/терминал 4-го, биометрия серверной, кэш → спуск Л2 напрямую в подвал (полный акт 4-го)",
		"route": ["dock1", "hall1", "lift_freight1", "it_open4", "hall4", "it4",
			"hall4", "it_open4", "archive0"],
	},
	{
		"id": "C_roof",
		"entry": "roof",
		"why": "report.md §1: кровля → терминал руководства на 5-м → вниз за фактом пешком (лестница: выход с 5-го, scales.md §5)",
		"route": ["roof", "hall5", "office5", "hall5", "stair5", "stair4", "stair3",
			"stair2", "stair1", "hall0", "archive0"],
	},
]

## Пробы условий сцены ★27: тревога взведена до старта (`noise_start = 25`) — так
## проверяется, ИГРАЕТ ли сцена вообще и чего не хватает на штатных маршрутах.
const PROBES := [
	{
		"id": "P1_alarm_early_on4",
		"seed": 1,
		"behavior": BEHAVIOR_SILENCE,
		"noise_start": 25,
		"why": "тревога с 1-го шага, группа уже на 4-м у Л2: грейс 3 шага обязан дать успеть (scales.md §5)",
		"route": ["hall4", "it_open4", "archive0"],
	},
	{
		"id": "P2_alarm_early_from5",
		"seed": 1,
		"behavior": BEHAVIOR_SILENCE,
		"noise_start": 25,
		"why": "тревога с 1-го шага, группа идёт с 5-го пешком (15 шагов): подходит к Л2 позже грейса — сцена ★27 обязана открыться",
		"route": ["hall5", "stair5", "stair4", "hall4", "it_open4", "archive0"],
	},
	{
		"id": "P3_alarm_early_from_dock",
		"seed": 1,
		"behavior": BEHAVIOR_SILENCE,
		"noise_start": 25,
		"why": "тревога с 1-го шага, штатный вход док1: что делает блокировка Л2 с группой, ещё не севшей в кабину",
		"route": ["dock1", "hall1", "lift_freight1", "it_open4", "archive0"],
	},
]

## Прогоны, хронология которых печатается целиком. Каждый назван под свой вывод отчёта:
##   B_full/1 — тайминг сцены ★27 (тревога, подход к Л2, окно, конец);
##   A_2floor/4 — тревога на шаге 5 БЕЗ единого приказа (состав шума из `agent_compromised`);
##   C_roof/1 — окно `w_floor5` не открывается: вход в office5 совпал по шагу с чужим окном.
const TRACE_RUNS := [
	{"route": "B_full", "seed": 1},
	{"route": "A_2floor", "seed": 4},
	{"route": "C_roof", "seed": 1},
]
const TRACE_EVENTS := ["agent_moved", "window_opened", "order_silenced", "order_issued",
	"order_refused", "alarm_raised", "path_blocked", "objective_reached", "mission_ended",
	"sensor_contact", "agent_compromised"]

var _verdict_reached := false


func _initialize() -> void:
	## Результат замера — КОНВЕРТ, а не код возврата, и это не украшение. Рантайм-сбой
	## внутри `_measure()` прерывает ТОЛЬКО её: рантайм-ошибка возвращает управление
	## вызывающему, и `var code := _measure()` получает правдоподобный ноль при уже
	## напечатанном `SCRIPT ERROR` — сторож `_process` при этом молчит, потому что
	## `_verdict_reached` выставляется следующей строкой. Механизм тот же, что пойман
	## пробой P7 в `accept_delivery.gd` (и ради него там стоит такой же конверт).
	var result = _measure()
	if typeof(result) != TYPE_DICTIONARY or not (result as Dictionary).has("verdict_code"):
		print("АБОРТ  вердикт не выставлен: _measure() прервался, а не дошёл до вердикта (код 1)")
		_verdict_reached = true
		quit(1)
		return
	_verdict_reached = true
	quit(int((result as Dictionary)["verdict_code"]))


## Код вердикта в конверте (см. `_initialize`): код едет ключом, а не значением функции.
func _verdict(code: int) -> Dictionary:
	return {"verdict_code": code}


## Сторож как у `run.gd`: прерванный `_initialize()` иначе оставил бы процесс висеть
## (главный цикл сам не завершается), а вердикт замера — код возврата.
func _process(_delta: float) -> bool:
	if _verdict_reached:
		return false
	print("LOAD FAIL  вердикт не выставлен: _initialize() прервался до quit()")
	quit(1)
	return true


func _measure() -> Dictionary:
	var loaded := _load_mission()
	if loaded["mission"] == null:
		print("МИССИЯ НЕ СОБРАНА: %s" % _brief(loaded["problems"]))
		return _verdict(1)
	var mission = loaded["mission"]

	print("=== Замер миссии 01 «Холодный архив»: поведение на реальном контенте ===")
	print("окон в данных: %d, рёбер: %d, помещений: %d" % [
		OrderBuilder.windows(mission).size(), mission.edges.size(), mission.nodes.size()])
	print("seeds: %s; маршрутов: %d; поведений: %d; состав по умолчанию: %s" % [
		str(SEEDS), ROUTES.size(), BEHAVIORS.size(), _crew(mission)])
	print("выход плана в матрице: %s (тот же вход, что и в замере ДО правки задачи 8: %s)" % [
		EXIT_NODE, str(mission.objective)])
	print("")

	var rows: Array = []
	var missed: Array = []
	for r in ROUTES:
		var plan := _plan_for(r)
		for behavior in BEHAVIORS:
			for seed in SEEDS:
				var built := _build_run(mission, plan, r, seed, behavior)
				var row := _row(mission, r, built, seed, behavior)
				rows.append(row)
				if not bool(built["stable"]):
					missed.append("%s/%s/seed %d: сценарий не сошёлся" % [r["id"], behavior, seed])
				if int(row["unknown_option"]) > 0:
					missed.append("%s/%s/seed %d: unknown_option=%d" % [
						r["id"], behavior, seed, int(row["unknown_option"])])

	_print_routes()
	_print_per_run(rows)
	_print_aggregate(rows)
	_print_window_coverage(mission, rows)
	var archive_mismatch := _check_archive_total(rows)
	_print_skip_reasons(rows)
	_print_scene27(rows)
	_print_stalled(rows)
	_print_guard_delay(rows)
	_print_trace(mission)
	_print_exit_probe(mission)

	var probes: Array = []
	print("")
	print("== 5. Пробы условий сцены ★27: тревога взведена до старта (noise_start = 25) ==")
	print("Смысл: отделить «механика мертва» от «на штатном маршруте не хватает шума или времени».")
	for p in PROBES:
		var probe_route := {"id": String(p["id"]), "entry": "", "why": String(p["why"]), "route": p["route"]}
		var plan := _plan_for(probe_route)
		var built := _build_run(mission, plan, probe_route, int(p["seed"]), String(p["behavior"]),
			int(p["noise_start"]))
		var row := _row(mission, probe_route, built, int(p["seed"]), String(p["behavior"]))
		row["why"] = String(p["why"])
		row["noise_start"] = int(p["noise_start"])
		probes.append(row)
	_print_rows(probes, true)

	var det := _determinism(mission)
	print("")
	print("== 6. Детерминизм замеров: тот же маршрут + seed + сценарий → тот же harness.digest ==")
	for d in det:
		print("%s" % str(d))

	print("")
	print("== 7. Сводка ==")
	_print_summary(rows)
	if not missed.is_empty():
		print("ВНИМАНИЕ, инструмент: %s" % "; ".join(missed))
	var ok := bool(det[0]["same"]) and bool(det[1]["same"]) and missed.is_empty() \
		and archive_mismatch == ""
	if ok:
		print("ИТОГ ЗАМЕРА: состоялся (код 0; вердиктом набора инструмент не является)")
	else:
		print("ИТОГ ЗАМЕРА: НЕПОЛОН — см. предупреждения и детерминизм выше (код 1)")
	return _verdict(0 if ok else 1)


# ---------------------------------------------------------------- вход и прогон

## Миссия из канонического артефакта (`game/content/`), тексты — вторым аргументом
## валидатора: сверка ключей обязана идти на том, что читают прогоны.
func _load_mission() -> Dictionary:
	var mission_json := _read_json(MISSION_PATH)
	if mission_json["data"] == null:
		return {"mission": null, "problems": mission_json["problems"]}
	var texts_json := _read_json(TEXTS_PATH)
	if texts_json["data"] == null:
		return {"mission": null, "problems": texts_json["problems"]}
	return Loader.load_mission(mission_json["data"], texts_json["data"])


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"data": null, "problems": ["%s не открыт (код %d)" % [path, FileAccess.get_open_error()]]}
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		return {"data": null, "problems": ["%s не разобран: %s (строка %d)"
			% [path, json.get_error_message(), json.get_error_line()]]}
	return {"data": json.data, "problems": []}


func _brief(problems: Array) -> String:
	var parts: Array = []
	for p in problems:
		parts.append(Problems.brief(p))
	return "; ".join(parts)


func _plan_for(r: Dictionary, exit_node := EXIT_NODE) -> Plan:
	var plan := Plan.new()
	plan.route = (r["route"] as Array).duplicate()
	plan.exit_node = exit_node
	plan.exit_backup_node = exit_node
	return plan


## Состав по умолчанию `plan.gd` (Кира-тактик + Эхо-связист) не переопределяем:
## штатный состав — часть замера (от него зависит исход молчания, ledger.md §8).
func _crew(mission) -> String:
	var plan := Plan.new()
	var parts: Array = []
	for a in plan.agents:
		parts.append("%s/%s" % [a["id"], a["role"]])
	return ", ".join(parts)


## Прогон одного поведения: молчание — пустой сценарий (игрок молчит на каждом окне),
## приказы — сценарий, найденный до неподвижной точки. И прогон, и построение сценария
## живут в общем модуле `order_builder.gd`: тот же код зовёт приёмочный инструмент,
## поэтому «приказы» здесь и там считаются по одному правилу.
func _build_run(mission, plan, r: Dictionary, seed: int, behavior: String,
		noise_start := 0) -> Dictionary:
	var config := {"seed": seed}
	if noise_start > 0:
		config["noise_start"] = noise_start
	if behavior == BEHAVIOR_SILENCE:
		return {"script": [], "iterations": 1, "stable": true,
			"run": OrderBuilder.run(mission, plan, [], config)}
	var picker := OrderBuilder.PICK_FIRST if behavior == BEHAVIOR_FIRST else OrderBuilder.PICK_LOUD
	var built := OrderBuilder.order_script(mission, plan, seed, picker, noise_start)
	return built


## Проба выхода: один и тот же маршрут, меняется только `plan.exit_node`. До правки задачи 8
## здесь ломалось всё сразу: отход шёл одним ребром «цель → выход» (`sim.gd:_check_objective`),
## поэтому выход, не смежный `archive0`, оставлял группу в архиве до `timeout`, а выход
## `hall0` (узел ПЕРЕД запертой дверью архива) не открывал окно `w_archivist`: агент в
## `plan.exit_node` пропускался (`sim.gd:_actor_before_locked_edge`). Проба называет, что
## именно ломается от выбора выхода, и потому идёт отдельным блоком.
## Доступные выходы перечислены по одному на каждый замысел: «выход = вход» для всех
## четырёх маршрутов и «выход на маршруте, но не у цели» для двух.
const EXIT_PROBES := [
	{"route": "A_2floor", "exit": "main_entry1",
		"why": "выход = вход (2-й этаж): обратный путь до входа, прямого ребра archive0 → main_entry1 нет"},
	{"route": "A_2floor", "exit": "stair1",
		"why": "выход НЕ у цели, зато на пройденном пути: обратный путь обрывается на выходе"},
	{"route": "C_roof", "exit": "roof",
		"why": "выход = вход (кровля): то же для длинного пешего маршрута"},
	{"route": "C_roof", "exit": "stair1",
		"why": "то же для кровельного маршрута, выход на пройденном пути"},
	{"route": "B_freight", "exit": "dock1",
		"why": "выход = вход (док): короткая ветка Л2, выход обратным путём"},
	{"route": "B_full", "exit": "dock1",
		"why": "полный акт 4-го, выход = вход (док)"},
]

# ---------------------------------------------------------------- сбор чисел

## Одна строка замера. Все счётчики — по типам событий `architecture.md` §5.
func _row(mission, r: Dictionary, built: Dictionary, seed: int, behavior: String) -> Dictionary:
	var run: Dictionary = built["run"]
	var out: Dictionary = run["out"]
	var ev: Array = run["events"]
	var opened := 0
	var issued := 0
	var silenced := 0
	var jammed_tx := 0
	var alarm_step := -1
	var arrive4 := -1
	var by_kind: Dictionary = {}
	var by_window: Dictionary = {}
	var refused: Dictionary = {}
	var stuck_steps: Array = []
	var board_steps: Array = []
	var blocked_steps: Array = []
	var archivist_steps: Array = []
	var up_steps: Array = []
	var last_move := -1
	var guard_moves: Dictionary = {}
	var off_actor := ""
	var off_qualities: Dictionary = {}
	var quality_counts: Dictionary = {}
	var bad_silences := 0
	var compromises := 0
	for e in ev:
		var t := str(e["type"])
		var step := int(e["step"])
		if t == "window_opened":
			var d: Dictionary = e["data"]
			var kind := str(d.get("kind", ""))
			opened += 1
			by_kind[kind] = int(by_kind.get(kind, 0)) + 1
			var rid := "%s:%s" % [kind, _anchor_value(d)]
			by_window[rid] = int(by_window.get(rid, 0)) + 1
			if kind == WindowScript.kind_for("locked_edge") and str(d.get("edge", "")) == STUCK_LIFT_EDGE:
				stuck_steps.append(step)
			if kind == WindowScript.kind_for("locked_edge") and str(d.get("edge", "")) == ARCHIVE_DOOR_EDGE:
				archivist_steps.append(step)
			if str(d.get("sensor", "")) == OFF_SCHEDULE_SENSOR:
				off_actor = str(d.get("agent", ""))
		elif t == "order_issued":
			issued += 1
			var tx: Dictionary = e["data"].get("radio", {})
			if bool(tx.get("jammed", false)):
				jammed_tx += 1
		elif t == "order_silenced":
			silenced += 1
			var win := str(e["data"].get("window", ""))
			var eff: Dictionary = e["data"].get("effect", {})
			var q := str(eff.get("quality", ""))
			quality_counts[q] = int(quality_counts.get(q, 0)) + 1
			if q == "bad":
				bad_silences += 1
			if win == "guard_in_sensor:%s" % OFF_SCHEDULE_SENSOR:
				off_qualities[q] = int(off_qualities.get(q, 0)) + 1
		elif t == "agent_compromised":
			compromises += 1
		elif t == "order_refused":
			var reason := str(e["data"].get("reason", ""))
			refused[reason] = int(refused.get(reason, 0)) + 1
		elif t == "alarm_raised":
			alarm_step = step
		elif t == "path_blocked":
			blocked_steps.append("%d:%s" % [step, str(e["data"].get("edge", ""))])
		elif t == "agent_moved":
			var d2: Dictionary = e["data"]
			last_move = step
			if str(d2.get("edge", "")) == STUCK_LIFT_EDGE:
				board_steps.append(step)
			if str(d2.get("edge", "")) == FREIGHT_UP_EDGE:
				up_steps.append(step)
			if str(d2.get("node", "")) == LIFT_NODE4 and arrive4 < 0:
				arrive4 = step
		elif t == "guard_moved":
			var gid := str(e["data"].get("agent", ""))
			if not guard_moves.has(gid):
				guard_moves[gid] = []
			(guard_moves[gid] as Array).append(step)
	return {
		"route": str(r["id"]),
		"entry": str(r.get("entry", "")),
		"why": str(r.get("why", "")),
		"route_list": (r.get("route", []) as Array).duplicate(),
		"seed": seed,
		"behavior": behavior,
		"iterations": int(built["iterations"]),
		"stable": bool(built["stable"]),
		"script": built["script"],
		"opened": opened,
		"issued": issued,
		"silenced": silenced,
		"refused": refused,
		"unknown_option": int(refused.get("unknown_option", 0)),
		"no_orders": int(refused.get("no_orders", 0)),
		"jammed_refusals": int(refused.get("jammed", 0)),
		"jammed_tx": jammed_tx,
		"by_kind": by_kind,
		"by_window": by_window,
		"alarm_step": alarm_step,
		"arrive4_step": arrive4,
		"board_steps": board_steps,
		"up_steps": up_steps,
		"stuck_steps": stuck_steps,
		"blocked_steps": blocked_steps,
		"archivist_steps": archivist_steps,
		"last_move": last_move,
		"off_actor": off_actor,
		"actor_moves": guard_moves.get(off_actor, []),
		"off_qualities": off_qualities,
		"quality_counts": quality_counts,
		"bad_silences": bad_silences,
		"compromises": compromises,
		"objective_done": bool(out["objective_done"]),
		"own_pos": _own_positions(out),
		"outcome": str(out["outcome"]),
		"steps": int(out["steps"]),
		"noise": int(out["noise"]),
		"radio": int(out["radio"]),
		"imprint": int(out["imprint"]),
		"orders_left": int(out["orders_left"]),
		"injured": out["injured"],
		"dead": out["dead"],
		"digest": str(out["digest"]),
	}


## Якорь события `window_opened` — зеркало `WindowScript.anchor_key` только для печати:
## у `locked_edge` это `edge`, у `node_entered` — `node`, у `guard_in_sensor` — `sensor`
## (`sim.gd:_window_event_data`).
func _anchor_value(d: Dictionary) -> String:
	for key in ["edge", "node", "sensor"]:
		if d.has(key):
			return str(d.get(key, ""))
	return ""


## Где стоят свои в конце прогона (`result().positions`): «застряли» — это факт позиции,
## а не вывод из молчания отчёта.
func _own_positions(out: Dictionary) -> String:
	var pos: Dictionary = out.get("positions", {})
	var keys: Array = []
	for k in pos.keys():
		if not str(k).begins_with("guard_"):
			keys.append(str(k))
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append("%s=%s" % [k, str(pos[k])])
	return ", ".join(parts)


# ---------------------------------------------------------------- печать


# ---------------------------------------------------------------- печать

func _print_routes() -> void:
	print("== 1. Маршруты замера (все пары соседей — рёбра графа, иначе прогон был бы invalid_mission) ==")
	for r in ROUTES:
		print("%s (вход %s): %s" % [r["id"], r["entry"], " → ".join(r["route"])])
		print("    почему: %s" % r["why"])
	print("")


func _print_per_run(rows: Array) -> void:
	print("== 2. Прогоны: строка = маршрут × поведение × seed; выход плана = %s ==" % EXIT_NODE)
	print("окон  прик  молч  отказы(no_orders/jammed/unknown)  исход        шагов шум эфир отп пул ран пог засв bad трев 4эт посадка ★27 архив")
	for row in rows:
		print("%-9s %-9s s=%-2d %3d %5d %5d  %d/%d/%d   %-11s %5d %4d %4d %3d %3d %3d %3d %4d %3d  %-4s %-4s %-7s %-5s %s" % [
			row["route"], row["behavior"], int(row["seed"]),
			int(row["opened"]), int(row["issued"]), int(row["silenced"]),
			int(row["no_orders"]), int(row["jammed_refusals"]), int(row["unknown_option"]),
			row["outcome"], int(row["steps"]), int(row["noise"]), int(row["radio"]),
			int(row["imprint"]), int(row["orders_left"]),
			(row["injured"] as Array).size(), (row["dead"] as Array).size(),
			int(row["compromises"]), int(row["bad_silences"]),
			_step_or_dash(int(row["alarm_step"])), _step_or_dash(int(row["arrive4_step"])),
			_steps_or_dash(_unique(row["board_steps"])), _steps_or_dash(row["stuck_steps"]),
			str((row["archivist_steps"] as Array).size())])
	print("")
	print("Источники: окон — `window_opened`; приказов — `order_issued`; молчаний — `order_silenced`;")
	print("отказы — `order_refused.reason`; тревога — `alarm_raised.step`; 4эт — `agent_moved.node=%s`;" % LIFT_NODE4)
	print("посадка — `agent_moved.edge=%s`; ★27 — `window_opened` (kind=locked_door, edge=%s);" % [
		STUCK_LIFT_EDGE, STUCK_LIFT_EDGE])
	print("архив — СКОЛЬКО раз открылось окно архивариуса (`window_opened`, edge=%s), а не шаг:" % ARCHIVE_DOOR_EDGE)
	print("его шаги печатают разделы 4г и 4д, а сходимость суммы столбца с разделом 4 проверяет 4а;")
	print("ран/пог — `result().injured`/`dead`;")
	print("засв — `agent_compromised` (каждое +5 шума на бойца), bad — молчаний с исходом `bad` (+5 шума);")
	print("шум/эфир/отпечаток/пул — `result()`.")
	print("Остальные столбцы после «bad» (трев, 4эт, посадка, ★27) — ШАГИ событий, а не счётчики.")
	print("")


func _print_rows(rows: Array, with_why: bool) -> void:
	for row in rows:
		if with_why:
			print("%s" % str(row["why"]))
		print("  %s (старт %s): %s" % [
			row["route"], row["entry"], " → ".join(_strings(row["route_list"]))])
		if row.has("noise_start"):
			print("  тревога взведена до старта: noise_start=%d" % int(row["noise_start"]))
		print("  окон=%d приказов=%d молчаний=%d отказы=%s; исход=%s шагов=%d шум=%d эфир=%d отпечаток=%d пул=%d" % [
			int(row["opened"]), int(row["issued"]), int(row["silenced"]), _fmt_counts(row["refused"]),
			row["outcome"], int(row["steps"]), int(row["noise"]), int(row["radio"]),
			int(row["imprint"]), int(row["orders_left"])])
		print("  тревога=%s; вход в %s=%s; первое плечо Л2 %s=%s; поездки по %s=%s; ★27=%s; path_blocked=%s" % [
			_step_or_dash(int(row["alarm_step"])), LIFT_NODE4, _step_or_dash(int(row["arrive4_step"])),
			FREIGHT_UP_EDGE, _steps_or_dash(_unique(row["up_steps"])), STUCK_LIFT_EDGE,
			_steps_or_dash(_unique(row["board_steps"])),
			_steps_or_dash(row["stuck_steps"]), _list_or_dash(row["blocked_steps"])])
	print("")


func _print_aggregate(rows: Array) -> void:
	print("== 3. Свод по маршруту × поведению (5 seeds) ==")
	print("маршрут   поведение  оконΣ прикΣ молчΣ  доля    исходы(extracted/caught/timeout)  тревога  ★27  шум")
	for r in ROUTES:
		for behavior in BEHAVIORS:
			var opened := 0
			var issued := 0
			var silenced := 0
			var alarms := 0
			var stucks := 0
			var outcomes: Dictionary = {}
			var noise_min := 1 << 30
			var noise_max := 0
			for row in rows:
				if str(row["route"]) != str(r["id"]) or str(row["behavior"]) != behavior:
					continue
				opened += int(row["opened"])
				issued += int(row["issued"])
				silenced += int(row["silenced"])
				if int(row["alarm_step"]) > 0:
					alarms += 1
				if not (row["stuck_steps"] as Array).is_empty():
					stucks += 1
				var o := str(row["outcome"])
				outcomes[o] = int(outcomes.get(o, 0)) + 1
				noise_min = mini(noise_min, int(row["noise"]))
				noise_max = maxi(noise_max, int(row["noise"]))
			print("%-9s %-9s %5d %5d %5d  %-6s  %s  %d/%d    %d/%d   %d..%d" % [
				r["id"], behavior, opened, issued, silenced, _share(issued, opened),
				"%d/%d/%d" % [int(outcomes.get("extracted", 0)), int(outcomes.get("caught", 0)),
					int(outcomes.get("timeout", 0))],
				alarms, SEEDS.size(), stucks, SEEDS.size(), noise_min, noise_max])
	print("")


## Покрытие окон данных: сколько раз открылось КАЖДОЕ окно поставки за все прогоны.
func _print_window_coverage(mission, rows: Array) -> void:
	print("== 4. Окна данных: сколько раз каждое окно открылось за все %d прогонов ==" % rows.size())
	var total: Dictionary = {}
	for row in rows:
		var by_window: Dictionary = row["by_window"]
		for wid in by_window:
			total[wid] = int(total.get(wid, 0)) + int(by_window[wid])
	for w in OrderBuilder.windows(mission):
		var rid := OrderBuilder.runtime_id(w)
		print("  %-16s %-24s открылось: %d" % [
			str(w.get("id", "")), rid, int(total.get(rid, 0))])
	print("")


## Сходимость двух счётчиков одного и того же: столбца «архив» раздела 2 и раздела 4.
## Это РАЗНЫЕ пути учёта — `if` по виду и якорю события в `_row` против карты `by_window`
## там же, — и расхождение означает, что подпись столбца и его счёт разошлись. Ровно так и
## вышло у столбца «архив»: он печатал ШАГ открытия окна (40), читался как число открытий,
## и рядом стоял раздел 4 с честными 32 (находка Minor 1 финального ревью). Теперь столбец
## считает открытия, а сходимость с разделом 4 проверяется здесь и входит в вердикт
## инструмента (код 1 при расхождении): проба — подмена ребра в ветке `archivist_steps`.
func _check_archive_total(rows: Array) -> String:
	var rid := "%s:%s" % [WindowScript.kind_for("locked_edge"), ARCHIVE_DOOR_EDGE]
	var column := 0
	var section4 := 0
	for row in rows:
		column += (row["archivist_steps"] as Array).size()
		section4 += int((row["by_window"] as Dictionary).get(rid, 0))
	print("== 4а. Сходимость счёта: столбец «архив» раздела 2 против раздела 4 (окно %s) ==" % rid)
	print("  открытий по столбцу (Σ по %d прогонам) — %d; по разделу 4 (карта `by_window`) — %d" % [
		rows.size(), column, section4])
	if column == section4:
		print("  сходится: столбец «архив» считает то же, что раздел 4.")
		return ""
	print("  РАСХОЖДЕНИЕ: два счёта одного и того же разошлись — починить инструмент, не данные.")
	return "столбец «архив» = %d, раздел 4 = %d (окно %s)" % [column, section4, rid]


func _print_skip_reasons(rows: Array) -> void:
	var no_orders := 0
	var jammed := 0
	var unknown := 0
	var jam_tx := 0
	var silenced := 0
	for row in rows:
		no_orders += int(row["no_orders"])
		jammed += int(row["jammed_refusals"])
		unknown += int(row["unknown_option"])
		jam_tx += int(row["jammed_tx"])
		silenced += int(row["silenced"])
	print("== 4б. Три причины пропуска окна — раздельно (scales.md §10 п. 5) ==")
	print("  (а) кончились приказы: отказов `order_refused.reason=no_orders` — %d" % no_orders)
	print("  (в) канал был заглушён: отказов `order_refused.reason=jammed` — %d" % jammed)
	print("      передач, которые САМИ включили глушение (`order_issued.data.radio.jammed=true`) — %d" % jam_tx)
	print("  молчаний всего (`order_silenced`) — %d (в них входят и отказы: харнесс добивает окно" % silenced)
	print("  молчанием, поэтому отказ по пулу/глушению — это тоже пропущенное окно)")
	print("  (б) окно вне покрытия разведкой: в ядре НЕ моделируется вовсе — окно открывается")
	print("      независимо от купленных каналов, и признака «игрок его не видит» в событиях нет.")
	print("      Это граница замера, а не ноль: число назвать нечем.")
	if unknown > 0:
		print("  ДИАГНОСТИКА: `order_refused.reason=unknown_option` — %d (сценарий вмешательства" % unknown)
		print("      разошёлся с фактическим порядком окон; числа «приказов» в этих прогонах занижены).")
	print("")


func _print_scene27(rows: Array) -> void:
	print("== 4в. Сцена ★27: `window_opened` по окну `w_stuck_lift` (якорь %s) ==" % STUCK_LIFT_EDGE)
	print("Разбор по каждому прогону, у которого маршрут вообще выходит на это ребро:")
	var relevant := 0
	var fired := 0
	for row in rows:
		var boards: Array = row["board_steps"]
		var stucks: Array = row["stuck_steps"]
		var touches := not boards.is_empty() or not stucks.is_empty() \
			or int(row["arrive4_step"]) > 0 or str(row["route"]) == "B_full"
		if not touches:
			continue
		relevant += 1
		var alarm := int(row["alarm_step"])
		var verdict := ""
		if not stucks.is_empty():
			fired += 1
			verdict = "СЫГРАЛА на шаге %s (тревога на шаге %s)" % [
				_steps_or_dash(_unique(stucks)), _step_or_dash(alarm)]
		elif boards.is_empty():
			verdict = "не сыграла: группа вообще не поехала по %s" % STUCK_LIFT_EDGE
		elif alarm < 0:
			verdict = "не сыграла: тревоги не было вовсе (`alarm_raised` нет)"
		else:
			verdict = "не сыграла: тревога на шаге %d, посадка на шаге %s (грейс 3 шага не истёк)" % [
				alarm, _steps_or_dash(_unique(boards))]
		print("  %-9s %-9s s=%-2d %s; первое плечо Л2 (%s) пройдено на шаге %s" % [
			row["route"], row["behavior"], int(row["seed"]), verdict,
			FREIGHT_UP_EDGE, _steps_or_dash(_unique(row["up_steps"]))])
	print("Итого: прогонов с выходом на ребро — %d, из них сцена сыграла — %d." % [relevant, fired])
	print("")

## Где встали группы, не дошедшие до выхода: позиция своих в конце прогона и шаг последнего
## `agent_moved`. «Застрял» — это факт позиции и остановки журнала, а не вывод из молчания отчёта.
func _print_stalled(rows: Array) -> void:
	print("== 4д. Незавершённые прогоны: где встала группа (`result().positions`, последний `agent_moved`) ==")
	var stuck := 0
	for row in rows:
		if str(row["outcome"]) == "extracted":
			continue
		stuck += 1
		print("  %-9s %-9s s=%-2d исход=%-8s цель_взята=%-5s окон=%d архив=%s свои: %s; последнее движение — шаг %d" % [
			row["route"], row["behavior"], int(row["seed"]), row["outcome"],
			str(row["objective_done"]), int(row["opened"]), _steps_or_dash(row["archivist_steps"]),
			row["own_pos"], int(row["last_move"])])
	print("Незавершённых прогонов: %d из %d." % [stuck, rows.size()])
	print("")


## Побочное наблюдение замера: актор окна `w_off_schedule` — охрана (`sim.gd:_actor_in_sensor`),
## а `delay` ядро выдаёт актору окна (`sim.gd:_apply_delay`), при этом `_advance_guards`
## поле `delay` не читает вовсе. Значит задержка этого окна не действует ни на кого.
## Проверяем прогоном: ряд шагов `guard_moved` актора обязан быть одним и тем же во всех
## прогонах, хотя молчание по этому окну выдавало задержку в большинстве из них.
func _print_guard_delay(rows: Array) -> void:
	print("== 4е. Наблюдение: задержка окна `w_off_schedule` выдана охране и не действует ==")
	var sigs: Dictionary = {}
	var longest := ""
	var with_delay := 0
	var without_delay := 0
	for row in rows:
		var qualities: Dictionary = row["off_qualities"]
		for q in qualities:
			if str(q) == "good":
				without_delay += int(qualities[q])
			else:
				with_delay += int(qualities[q])
		var moves: Array = row["actor_moves"]
		if moves.is_empty():
			continue
		var sig := " → ".join(_strings(moves))
		sigs[sig] = int(sigs.get(sig, 0)) + 1
		if sig.length() > longest.length():
			longest = sig
	var all_prefix := true
	for sig in sigs.keys():
		if not longest.begins_with(str(sig)):
			all_prefix = false
	var head: Array = []
	for i in range(mini(8, longest.split(" → ").size())):
		head.append(longest.split(" → ")[i])
	print("Молчаний по этому окну: %d, из них с задержкой (`neutral`/`bad`/`safe`) — %d, без (`good`) — %d." % [
		with_delay + without_delay, with_delay, without_delay])
	print("Различных рядов шагов актора: %d; все — префиксы одного ряда: %s" % [
		sigs.size(), "да" if all_prefix else "НЕТ"])
	print("Ряд шагов актора (начало): %s → …" % " → ".join(head))
	print("Значит выданная охраннику задержка не влияет ни на что: `sim.gd:_advance_guards` считает")
	print("только `progress`/`patrol_period` и поле `delay` не читает. Задержка окна с актором-охраной")
	print("не достаётся ни группе, ни охране — окно бесплатно, кроме своего шума.")
	print("")


## Хронология прогонов: без неё тайминг сцены ★27 и состав шума не проверить глазами.
func _print_trace(mission) -> void:
	for run in TRACE_RUNS:
		var r := _route_by_id(str(run["route"]))
		var plan := _plan_for(r)
		var built := _build_run(mission, plan, r, int(run["seed"]), BEHAVIOR_SILENCE)
		print("== 4ж. Хронология прогона %s / seed %d / молчание (выборочные события журнала) ==" % [
			run["route"], int(run["seed"])])
		for e in built["run"]["events"]:
			var t := str(e["type"])
			if not TRACE_EVENTS.has(t):
				continue
			print("  шаг %3d  %-18s %s" % [int(e["step"]), t, _event_brief(e)])
		print("")


func _event_brief(e: Dictionary) -> String:
	var d: Dictionary = e["data"]
	match str(e["type"]):
		"agent_moved":
			return "%s → %s (ребро %s, шум %d)" % [str(d.get("agent", "")), str(d.get("node", "")),
				str(d.get("edge", "")), int(d.get("noise", 0))]
		"window_opened":
			return "%s, якорь %s, актор %s" % [str(d.get("kind", "")), _anchor_value(d),
				str(d.get("agent", ""))]
		"order_silenced":
			var eff: Dictionary = d.get("effect", {})
			return "%s: молчание, решал %s, исход %s" % [str(d.get("window", "")),
				str(eff.get("by", "")), str(eff.get("quality", ""))]
		"order_issued":
			var tx: Dictionary = d.get("radio", {})
			return "%s: приказ %s (эфир %d, отпечаток %d, заглушил себя: %s)" % [
				str(d.get("window", "")), str(d.get("option", "")), int(tx.get("radio", 0)),
				int(tx.get("imprint", 0)), str(tx.get("jammed", false))]
		"order_refused":
			return "%s: отказ, причина %s" % [str(d.get("window", "")), str(d.get("reason", ""))]
		"path_blocked":
			return "%s упёрся в %s (%s)" % [str(d.get("agent", "")), str(d.get("edge", "")),
				str(d.get("kind", ""))]
		"alarm_raised":
			return "тревога взведена"
		"objective_reached":
			return "%s взял цель %s" % [str(d.get("agent", "")), str(d.get("node", ""))]
		"mission_ended":
			return "исход %s" % str(d.get("outcome", ""))
		"sensor_contact":
			return "%s в зоне сенсора (%s)" % [str(d.get("agent", "")), str(d.get("node", ""))]
		"agent_compromised":
			return "%s засвечен (состояние %d, триггеров %d)" % [str(d.get("agent", "")),
				int(d.get("state", 0)), int(d.get("triggers", 0))]
	return str(d)


## Проба выхода: тот же маршрут, но выход другой. Показывает, что «прямой отрезок
## цель → выход» делает с прохождением, и почему основная матрица считает выходом `hall0`.
func _print_exit_probe(mission) -> void:
	print("== 4г. Проба выхода: как выбор `exit_node` меняет сам прогон (seed 1, молчание) ==")
	print("Одна и та же миссия, один и тот же маршрут — меняется только `plan.exit_node`.")
	var rows: Array = []
	for p in EXIT_PROBES:
		var r := _route_by_id(str(p["route"]))
		var plan := _plan_for(r, str(p["exit"]))
		var built := _build_run(mission, plan, r, 1, BEHAVIOR_SILENCE)
		var row := _row(mission, r, built, 1, BEHAVIOR_SILENCE)
		row["exit"] = str(p["exit"])
		row["why"] = str(p["why"])
		rows.append(row)
	for row in rows:
		print("  %s, выход=%s: %s" % [row["route"], row["exit"], row["why"]])
		## Раненые и погибшие печатаются здесь не для полноты: `_check_end` зачитывает уход
		## по ЖИВЫМ, и «исход=extracted, а один свой в конце не на выходе» читается верно
		## только вместе с числом погибших. Без этих двух чисел строка выглядит как дефект.
		print("    исход=%s шагов=%d цель_взята=%s окон=%d (окно архивариуса=%s) ран=%d пог=%d свои в конце: %s" % [
			row["outcome"], int(row["steps"]), str(row["objective_done"]), int(row["opened"]),
			_steps_or_dash(row["archivist_steps"]), (row["injured"] as Array).size(),
			(row["dead"] as Array).size(), row["own_pos"]])
	print("")


func _print_summary(rows: Array) -> void:
	var opened := 0
	var issued := 0
	var silenced := 0
	var qualities: Dictionary = {}
	for row in rows:
		opened += int(row["opened"])
		issued += int(row["issued"])
		silenced += int(row["silenced"])
		var qc: Dictionary = row["quality_counts"]
		for q in qc:
			qualities[q] = int(qualities.get(q, 0)) + int(qc[q])
	print("Исходы молчания по качествам (`order_silenced.effect.quality`): %s" % _fmt_counts(qualities))
	print("При составе со связистом `safe` не выпадает (ledger.md §8): %s" % [
		"подтверждено" if int(qualities.get("safe", 0)) == 0 else "ОПРОВЕРГНУТО (%d)" % int(qualities.get("safe", 0))])
	print("Доля вмешательства по всем прогонам (Σ`order_issued` / Σ`window_opened`): %s" % _share(issued, opened))
	var first_opened := 0
	var first_issued := 0
	for row in rows:
		if str(row["behavior"]) != BEHAVIOR_FIRST:
			continue
		first_opened += int(row["opened"])
		first_issued += int(row["issued"])
	print("Доля вмешательства в поведении «%s»: %s (цель scales.md §10 п. 5 — 30–40%%)" % [
		BEHAVIOR_FIRST, _share(first_issued, first_opened)])
	print("Молчаний всего: %d; приказов всего: %d; окон всего: %d" % [silenced, issued, opened])
	print("")


func _determinism(mission) -> Array:
	var out: Array = []
	var cases := [
		{"route": "A_2floor", "seed": 3, "behavior": BEHAVIOR_SILENCE},
		{"route": "B_full", "seed": 4, "behavior": BEHAVIOR_FIRST},
	]
	for c in cases:
		var r := _route_by_id(str(c["route"]))
		var plan := _plan_for(r)
		var first := _build_run(mission, plan, r, int(c["seed"]), str(c["behavior"]))
		var second_plan := _plan_for(r)
		var second := OrderBuilder.run(mission, second_plan, first["script"], {"seed": int(c["seed"])})
		var same := str(first["run"]["out"]["digest"]) == str(second["out"]["digest"])
		out.append({
			"same": same,
			"line": "%s / seed %d / %s: digest повтора %s первому (сценарий из %d вариантов, итераций %d)\n      отпечаток 1: %s\n      отпечаток 2: %s" % [
				c["route"], int(c["seed"]), c["behavior"],
				"СОВПАЛ" if same else "РАЗОШЁЛСЯ",
				(first["script"] as Array).size(), int(first["iterations"]),
				str(first["run"]["out"]["digest"]), str(second["out"]["digest"])],
		})
	return out


func _route_by_id(id: String) -> Dictionary:
	for r in ROUTES:
		if str(r["id"]) == id:
			return r
	return {}


# ---------------------------------------------------------------- мелочи печати

func _share(part: int, whole: int) -> String:
	if whole <= 0:
		return "n/a"
	return "%.1f%%" % (100.0 * float(part) / float(whole))


func _step_or_dash(step: int) -> String:
	return "-" if step < 0 else str(step)


func _steps_or_dash(steps: Array) -> String:
	return _list_or_dash(steps)


func _list_or_dash(items: Array) -> String:
	return "-" if items.is_empty() else ",".join(_strings(items))


func _strings(items: Array) -> Array:
	var out: Array = []
	for i in items:
		out.append(str(i))
	return out


## Уникальные значения с сохранением порядка: двое своих едут по ребру в один шаг, и в
## журнале это два `agent_moved`, а не два разных события по смыслу.
func _unique(items: Array) -> Array:
	var out: Array = []
	for i in items:
		if not out.has(i):
			out.append(i)
	return out


func _first(items: Array) -> int:
	return int(items[0]) if not items.is_empty() else -1


func _fmt_counts(counts: Dictionary) -> String:
	if counts.is_empty():
		return "-"
	var keys := counts.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append("%s=%d" % [str(k), int(counts[k])])
	return ", ".join(parts)

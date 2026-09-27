extends RefCounted
## Построение сценария вмешательства: общий модуль инструментов.
##
## Зачем отдельный модуль. Логика «прогон → фактическая последовательность окон → список
## вариантов по ней → снова прогон до неподвижной точки» нужна ДВУМ инструментам сразу:
## замеру реальной миссии (`tests/measure_mission01.gd`) и приёмочному прогону поставки
## (`tests/accept_delivery.gd`). Копия этих функций во втором инструменте разошлась бы
## с первой молча: замер и приёмка считали бы «приказы» по разным правилам, и расхождение
## выглядело бы как расхождение данных. Поэтому построение сценария живёт здесь, а
## инструменты только зовут его — ровно так же, как валидатор и загрузчик живут в
## `content/` и не дублируются инструментами.
##
## Числа модуль не задаёт: `MAX_SCRIPT_ITERATIONS` — граница поиска неподвижной точки,
## а не баланс. Всё остальное — данные миссии и план, которые приносит вызывающий.

const Harness := preload("res://sim/harness.gd")
const WindowScript := preload("res://sim/window.gd")

## Сколько раз искать неподвижную точку сценария вмешательства (см. `order_script`).
const MAX_SCRIPT_ITERATIONS := 6

## Имена выбора варианта: `first` — первый вариант автора данных, `loud` — самый шумный,
## `reasonable` — вариант, снимающий препятствие (D53).
## Строки, а не enum: они приходят из инструмента и печатаются в отчёте дословно.
const PICK_FIRST := "first"
const PICK_LOUD := "loud"
const PICK_REASONABLE := "reasonable"


## Один прогон штатным харнессом; журнал берём у самого `Sim` (4-й аргумент харнесса).
static func run(mission, plan, script: Array, config: Dictionary) -> Dictionary:
	var box := RefCounted.new()
	var out: Dictionary = Harness.run_scenario(mission, plan, script, config, box)
	var sim = box.get_meta("sim")
	return {"out": out, "events": sim.events}


## Сценарий вмешательства: приказ отдаётся на КАЖДОМ окне (пул кончится — отказы
## `no_orders`, канал заглохнет — отказы `jammed`; и то и другое и есть замер).
##
## Харнесс принимает плоский список вариантов, а окна открываются в порядке, зависящем
## от эффектов предыдущих, поэтому список ищется до неподвижной точки: прогон →
## фактическая последовательность окон (`order_issued`/`order_silenced`) → список
## вариантов по ней → снова прогон. Устойчивость видна в `stable`/`iterations`.
static func order_script(mission, plan, seed: int, picker: String, noise_start: int) -> Dictionary:
	var config := {"seed": seed}
	if noise_start > 0:
		config["noise_start"] = noise_start
	var draft: Array = []
	var last: Array = []
	for attempt in range(1, MAX_SCRIPT_ITERATIONS + 1):
		var run := run(mission, plan, draft, config)
		var seq := window_sequence(run["events"])
		if seq == last:
			return {"script": draft, "iterations": attempt, "stable": true, "run": run}
		last = seq
		draft = options_for(mission, seq, picker)
	var final_run := run(mission, plan, draft, config)
	return {"script": draft, "iterations": MAX_SCRIPT_ITERATIONS, "stable": false, "run": final_run}


## Последовательность открывшихся окон: у каждого окна ровно одно из событий
## `order_issued` / `order_silenced` (отказ харнесс добивает молчанием), и оба несут
## составной id окна `вид:якорь` (`sim.gd:order`).
static func window_sequence(events: Array) -> Array:
	var out: Array = []
	for e in events:
		var t := str(e["type"])
		if t == "order_issued" or t == "order_silenced":
			out.append(str(e["data"]["window"]))
	return out


## Варианты окон последовательности: `first` — первый вариант автора данных,
## `loud` — самый шумный вариант (проба «а если шуметь сильнее»: влияет ли это
## на тревогу и на сцену ★27), `reasonable` — снимающий препятствие (D53).
## Порядок окон — фактический порядок прогона.
static func options_for(mission, seq: Array, picker: String) -> Array:
	var by_id: Dictionary = {}
	for w in windows(mission):
		by_id[runtime_id(w)] = w
	var out: Array = []
	for wid in seq:
		var w = by_id.get(String(wid), null)
		if w == null:
			## Неизвестное окно — сценарий разошёлся с данными; это ловится счётчиком
			## `unknown_option` в строке замера, а не молчанием.
			out.append("silence")
			continue
		out.append(pick(WindowScript.from_data(w, ""), picker))
	return out


static func pick(w: Dictionary, picker: String) -> String:
	if picker == PICK_REASONABLE:
		return _pick_reasonable(w)
	var best := ""
	var best_noise := -1
	for o in w["options"]:
		var id := String(o["id"])
		if id == WindowScript.SILENCE:
			continue
		if picker == PICK_FIRST:
			return id
		var noise := int(o.get("noise", 0))
		if noise > best_noise:
			best_noise = noise
			best = id
	return best


## «Разумные приказы» (D53): вариант, СНИМАЮЩИЙ ПРЕПЯТСТВИЕ, — тот, чьи эффекты открывают
## ребро. Из нескольких таких берётся вариант с наименьшим шумом; равный шум разрешает
## порядок данных (первый из равных), а не кубик: поведение детерминировано, как и весь
## остальной прогон. Нет ни одного варианта, снимающего препятствие, — окно МОЛЧИТ:
## молчание — законный ход (D23), а не пропуск решения.
##
## Почему не «оптимальная игра»: требование задания §3.4 — правдоподобный план, а не
## выигрывающий. Разумный игрок снимает ровно то препятствие, из-за которого окно
## открылось, и делает это тише, если может.
static func _pick_reasonable(w: Dictionary) -> String:
	var best := ""
	var best_noise := 0
	for o in w["options"]:
		var id := String(o["id"])
		if id == WindowScript.SILENCE or not removes_obstacle(o):
			continue
		var noise := int(o.get("noise", 0))
		if best == "" or noise < best_noise:
			best = id
			best_noise = noise
	return WindowScript.SILENCE if best == "" else best


## Снимает ли вариант препятствие: есть ли среди его эффектов открытие ребра (`unlock`).
## Смотрим и в `fallback` заявки движку: ядро применяет `fallback` тем же применятелем
## эффектов, поэтому «заявка» с `unlock` внутри `fallback` ребро открывает НА САМОМ ДЕЛЕ,
## а не в замысле, — и для выбора варианта это одно и то же.
static func removes_obstacle(option: Dictionary) -> bool:
	return _unlocks(option.get("effects", []))


static func _unlocks(raw) -> bool:
	if typeof(raw) == TYPE_ARRAY:
		for effect in raw:
			if _unlocks(effect):
				return true
		return false
	if typeof(raw) != TYPE_DICTIONARY:
		return false
	var effect: Dictionary = raw
	var type := String(effect.get("type", ""))
	if type == "unlock":
		return true
	if type == "engine_proposal":
		return _unlocks(effect.get("fallback", []))
	return false


static func windows(mission) -> Array:
	var raw = mission.data.get("windows", [])
	return raw if typeof(raw) == TYPE_ARRAY else []


## Составной id рантайм-формы окна (`вид:якорь`) — тот же, что в событиях `order_*`
## и в `window_opened`; по нему инструмент складывает счётчики.
static func runtime_id(w: Dictionary) -> String:
	return String(WindowScript.from_data(w, "").get("id", ""))

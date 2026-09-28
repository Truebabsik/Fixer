extends RefCounted
## Ядро операции. Только композиция правил — ни одного собственного числа баланса.
## Чистый RefCounted: ни нод, ни сцен, ни рендера.
##
## Автопауза: пока открыто окно решения, advance() не двигает мир.
## Давление создаёт дефицит приказов и эфир, а не таймер.

const Agent := preload("res://sim/agent.gd")
const Scales := preload("res://sim/scales.gd")
const Radio := preload("res://sim/radio.gd")
const Response := preload("res://sim/response.gd")
const Understanding := preload("res://sim/understanding.gd")
## Имя константы не может быть `Window`: в Godot 4.7 это тень нативной ноды
## и жёсткая ошибка разбора. Смысл `Window.locked_door` сохранён дословно.
const WindowScript := preload("res://sim/window.gd")

const MAX_STEPS := 500

## Виды эффектов, которые ядро ИСПОЛНЯЕТ. Список живёт ЗДЕСЬ, рядом с применятелем
## (`_apply_effect`), и форма спрашивает его оттуда (`content/validator.gd`), а не держит
## свою копию: две копии расходятся молча — ровно так `noop` уже разошёлся (был у формы
## и не назван у ядра).
##
## `noop` стоит в списке осознанно и ветки в `_apply_effect` не имеет: это ЗАЯВЛЕННОЕ
## «ничего не делать» (пустой эффект в данных), а не забытая ветка. Любой вид вне списка
## форма отвергает: новое поведение входит через `engine_proposal`, а не «молча ничего».
const EFFECT_TYPES := ["unlock", "noise", "delay", "noop", "engine_proposal", "money", "trace", "mark"]

var mission
var plan
var scales
var radio
var response
var own: Array = []
var guards: Array = []
var events: Array = []
## id ребра -> true, если дверь открыта приказом или молчанием. Состояние живёт
## в Sim, а не в Mission: миссия — неизменяемые данные, и один и тот же её объект
## обязан давать одинаковый исход при повторном прогоне.
var unlocked: Dictionary = {}
var ghost_positions: Dictionary = {}
var visible_last: Dictionary = {}
var ghost_reported: Dictionary = {}
## id бойца -> помещение, где его уже засекли. Сбрасывается в setup().
var compromised_at: Dictionary = {}
## Учёт сработавших окон: id окна из данных -> true и ребро окна запертой двери ->
## true. Сбрасывается в setup(). Нужен, чтобы окно не открывалось второй раз:
## «одно окно — один срабатывающий раз» (см. раздел формы про окна).
var fired_windows: Dictionary = {}
var fired_edges: Dictionary = {}
var orders_left: int = 3
## Счётчики и метки эффектов. Копятся ТОЛЬКО в `_apply_effect` — одной ветке
## применения эффектов, которая обслуживает варианты окна, четыре исхода молчания и
## `fallback` заявки. Вторая ветка применения означала бы, что часть мест эффекты
## «принимает», а часть — нет, то есть ровно тот дефект, из-за которого счётчиков
## не существовало вовсе (решение записано в журнале решений).
var money: int = 0
var trace: int = 0
## Метки — множество фактов («взяли копию», «видели ответ»), а не счётчик: повтор
## эффекта оставляет одну запись. В результат уходят отсортированными (`marks_sorted`).
var marks: Array[String] = []
var rng := RandomNumberGenerator.new()
var current_window = null
var objective_done := false
var finished := false
var outcome := ""

## Ключи config, которые setup() читает. Неизвестный ключ — почти всегда опечатка
## (`orders_left` вместо `orders`), и молча терять её нельзя.
const CONFIG_KEYS := ["orders", "seed", "noise_start"]


func setup(mission_, plan_, config := {}) -> void:
	mission = mission_
	plan = plan_
	orders_left = int(config.get("orders", 3))
	money = 0
	trace = 0
	marks = []
	rng.seed = int(config.get("seed", 1))
	scales = Scales.new()
	radio = Radio.new()
	response = Response.new()
	events = []
	own = []
	guards = []
	unlocked = {}
	ghost_positions = {}
	visible_last = {}
	ghost_reported = {}
	compromised_at = {}
	fired_windows = {}
	fired_edges = {}
	current_window = null
	objective_done = false
	finished = false
	outcome = ""

	# Вход проверяется ДО того, как ядро начнёт считать: неверная миссия или
	# разорванный маршрут обязаны кончиться громким invalid_mission, а не тихо
	# притвориться caught/timeout. Так балансировщик узнаёт об опечатке в данных
	# из кода возврата и отчёта, а не из «странных» исходов.
	var problems: Array = mission.validate()
	problems.append_array(mission.validate_route(plan.route))
	for key in config:
		if not CONFIG_KEYS.has(String(key)):
			problems.append("неизвестный ключ config: %s" % key)
	if plan.route.is_empty():
		problems.append("маршрут пуст")
	if not problems.is_empty():
		finished = true
		outcome = "invalid_mission"
		_emit("invalid_mission", {"problems": problems})
		return

	var start := String(plan.route[0])
	for a in plan.agents:
		var agent := Agent.new()
		agent.id = String(a["id"])
		agent.kind = Agent.Kind.OWN
		agent.role = String(a.get("role", "tactician"))
		agent.understanding = int(a.get("understanding", 3))
		agent.node = start
		agent.waypoints = plan.route.duplicate()
		agent.waypoint_index = 1
		## Начало пройденного пути: без него отход после взятой цели нечем выразить
		## (`_withdraw_route` строит обратный путь от текущего узла до узла старта).
		agent.path = [start]
		own.append(agent)

	for p in mission.patrols:
		var guard := Agent.new()
		guard.id = String(p["id"])
		guard.kind = Agent.Kind.GUARD
		guard.node = String(p["route"][0])
		## duplicate(true) — глубокая копия: охрана не имеет права писать в массив
		## миссии, иначе прогон менял бы вход для следующего прогона.
		guard.patrol_route = p["route"].duplicate(true)
		guard.patrol_index = 0
		guard.patrol_period = int(p.get("period", 4))
		guards.append(guard)

	# Снимок разведки: призраки замирают там, где охрана была на момент съёмки.
	for g in guards:
		ghost_positions[g.id] = g.node
		visible_last[g.id] = false
		ghost_reported[g.id] = false

	scales.add_noise(int(config.get("noise_start", 0)))
	_emit("mission_started", {"node": start})


## Один шаг мира. Возвращает события этого шага. При открытом окне — ничего.
func advance() -> Array:
	var from := events.size()
	if finished or current_window != null:
		return []
	scales.tick()
	radio.tick_decay(scales.step - 1)
	if scales.alarm_state() == Scales.Alarm.ALARM and not response.active:
		response.engage(scales.step)
		_emit("alarm_raised", {"step": scales.step})
	_advance_own()
	## Зона считается ПОСЛЕ движения своих: экранированное помещение важно тогда, когда
	## в нём кто-то есть, а не тогда, когда группа туда собиралась (`_refresh_shield`).
	_refresh_shield()
	_advance_guards()
	_update_visibility()
	_check_contacts()
	_check_objective()
	_check_end()
	# Инвариант «исход есть — окна нет» держим по построению, а не по случайности
	# порядка вызовов: конец миссии закрывает окно и снимает возможность приказа.
	if finished:
		current_window = null
	else:
		_maybe_open_window()
	return events.slice(from)


func result() -> Dictionary:
	var injured: Array = []
	var dead: Array = []
	var escaped: Array = []
	for a in own:
		if a.is_dead():
			dead.append(a.id)
			continue
		if a.state != Agent.State.OK:
			injured.append(a.id)
		# «Вышел» = дошёл до выхода ПОСЛЕ взятой цели. Без второй половины условия
		# агент, стартующий на выходе (такие маршруты есть в тестах), попадал бы
		# в escaped с нулевого шага, и проверки на маршрутах были бы пустыми.
		# Погибший до этой строки не доходит: труп не зачитывается как уход.
		if objective_done and a.node == plan.exit_node:
			escaped.append(a.id)
	return {
		"outcome": outcome,
		"steps": scales.step,
		"objective_done": objective_done,
		"orders_left": orders_left,
		"noise": scales.noise,
		"radio": radio.radio,
		"imprint": radio.imprint,
		"alarm": scales.alarm_state(),
		## Эффекты-счётчики и метки: на них смотрят «Итоги», а не события,
		## поэтому они обязаны быть в отчёте прогона, а не только в журнале.
		"money": money,
		"trace": trace,
		"marks": marks_sorted(),
		"injured": injured,
		"dead": dead,
		"escaped": escaped,
		"positions": _positions(),
	}


## Метки результата — по алфавиту (так требует контракт отчёта). Порядок постановки меток
## зависит от порядка окон и вариантов в данных, то есть от того, что к отпечатку
## отношения не имеет: один и тот же набор фактов обязан читаться одинаково.
## Копия обязательна — сортировка результата не имеет права переставлять состояние Sim.
func marks_sorted() -> Array[String]:
	var out: Array[String] = marks.duplicate()
	out.sort()
	return out


func _positions() -> Dictionary:
	var out: Dictionary = {}
	for a in own:
		out[a.id] = a.node
	for g in guards:
		out[g.id] = g.node
	return out


func _emit(type: String, data: Dictionary) -> void:
	events.append({"step": scales.step, "type": type, "data": data})


func _advance_own() -> void:
	for a in own:
		if a.is_dead():
			continue
		## `exit_node` здесь — точка входа и сбора, а не «уже вышел»: агент,
		## стоящий в ней, обязан идти по маршруту. Остановку даёт исчерпание
		## маршрута ниже, поэтому отдельного пропуска по exit_node нет.
		if a.delay > 0:
			a.delay -= 1
			continue
		if a.waypoint_index >= a.waypoints.size():
			continue
		var target := String(a.waypoints[a.waypoint_index])
		var e: Dictionary = mission.edge_between(a.node, target)
		if e.is_empty():
			continue
		if _is_blocked_for(a, e):
			## О запертой двери скажет окно, а не событие: `path_blocked` — про тревогу,
			## а не про замок. Ребро бывает заперто и перекрыто сразу — тогда
			## причина упора замок, и событие молчит, как молчало прежде.
			if _alarm_sealed(e) and not _is_locked(e):
				_emit("path_blocked", {"agent": a.id, "edge": e["id"], "kind": e["kind"]})
			continue
		a.progress += 1
		if a.progress >= int(e["steps"]) + a.speed_penalty():
			a.progress = 0
			a.node = target
			a.waypoint_index += 1
			## Пройденный путь растёт здесь и только здесь: узел агента меняется ровно
			## в этой строке. Обратный путь обязан идти по факту, а не по `waypoints`
			## агента: их ядро подменяет (`_check_objective`), а `plan.route` хранит и то,
			## что агент ещё не прошёл, — из него берётся только передняя половина
			## (`_exit_ahead`).
			a.path.append(target)
			var noise := int(e["noise"])
			if noise > 0:
				scales.add_noise(noise)
			_emit("agent_moved", {"agent": a.id, "node": a.node, "edge": e["id"], "noise": noise})


func _advance_guards() -> void:
	for g in guards:
		if g.patrol_route.size() < 2:
			continue
		g.progress += 1
		if g.progress < g.patrol_period:
			continue
		g.progress = 0
		g.patrol_index = (g.patrol_index + 1) % g.patrol_route.size()
		g.node = String(g.patrol_route[g.patrol_index])
		_emit("guard_moved", {"agent": g.id, "node": g.node})


func is_visible(guard) -> bool:
	for s in mission.sensors:
		if s["nodes"].has(guard.node):
			return true
	return false


func ghost_mismatch() -> bool:
	for g in guards:
		if String(ghost_positions.get(g.id, "")) != g.node:
			return true
	return false


func _update_visibility() -> void:
	for g in guards:
		var seen := is_visible(g)
		if seen and not bool(visible_last.get(g.id, false)):
			_emit("sensor_contact", {"agent": g.id, "node": g.node})
		visible_last[g.id] = seen
		var ghost := String(ghost_positions.get(g.id, ""))
		if ghost != g.node and not bool(ghost_reported.get(g.id, false)):
			ghost_reported[g.id] = true
			_emit("ghost_mismatch", {"agent": g.id, "ghost": ghost, "real": g.node})


## Охрана и свои в одном помещении — это увидение. Пока в лоб: без проверки
## направления взгляда и без «заметил, но не понял» (это фаза планирования).
## Засчитывается один раз на помещение: вернулся в то же помещение — это уже
## не новое увидение, и триггеры не капают за каждый тик.
func _check_contacts() -> void:
	for a in own:
		if a.is_dead():
			continue
		for g in guards:
			if g.node == a.node:
				if String(compromised_at.get(a.id, "")) != a.node:
					compromised_at[a.id] = a.node
					_compromise(a)
				break   # break, а не return: иначе все, кто идёт в списке после
				        # первого, не получат триггер даже в том же помещении


func _check_objective() -> void:
	if objective_done:
		return
	for a in own:
		if a.is_dead():
			continue
		if a.node == mission.objective:
			objective_done = true
			_emit("objective_reached", {"agent": a.id, "node": a.node})
			# На выход идут ВСЕ живые, а не только тот, кто взял цель. Иначе
			# группа из двух бойцов никогда не соберётся на выходе, а конец
			# миссии требует именно всех — и уход не зачтётся никогда.
			# Путь каждому строится ОТ ЕГО узла: группа идёт не строем, отставший
			# к моменту взятия цели стоит в другом помещении.
			for b in own:
				if b.is_dead():
					continue
				b.waypoints = _withdraw_route(b)
				b.waypoint_index = 1
				b.progress = 0
			return


## Путь отхода агента: от его текущего узла к выходу плана.
##
## Поиска пути в ядре нет и он сюда не вводится (решение владельца): путь собирается из
## ДВУХ явных списков, которые уже есть на руках, — пройденного пути агента (`Agent.path`)
## и маршрута плана (`plan.route`).
##
## Правила по порядку, и порядок несущий:
##  0. выход не задан (`exit_node == ""`) либо агент уже в выходе — путь кончается
##     здесь же. Половины этой ветки НЕ равны по весу, и обе проверены (`test_movement`,
##     блоки 10–12):
##     * `exit_node == ""` — НЕСУЩАЯ половина: без неё `_exit_ahead` не находит пустую
##       строку в маршруте, обратный путь доводит группу до узла входа, и «выхода нет»
##       превращалось бы в поход назад (блок 12 краснит снятие именно этой половины);
##     * `here == exit_node` — ЗАЩИТА В ГЛУБИНУ, а не несущее правило: на КАЖДОМ
##       состоянии, которое производит модель, `plan.route[waypoint_index - 1] == a.node`
##       (`setup` даёт `waypoints` копией `plan.route`, а `_advance_own` растит узел и
##       индекс вместе — блок 10 держит это ассертом). Значит, стоящий в выходе агент
##       имеет выход на своём же индексе, и правило 2 отдаёт ту же `[here]`; снятие
##       половины оставляет набор зелёным (проба отчёта 09). Несёт она ровно один случай —
##       СЛОМАННЫЙ инвариант (индекс разошёлся с узлом): тогда правило 2 молчит, и без неё
##       уже пришедший на выход пошёл бы назад по пройденному пути (блок 11 краснит снятие
##       половины). Тот же класс охраны, что ветка `_exit_ahead` (`plan.route[current] == here`);
##  1. выход смежен текущему узлу — одно ребро. Это прежнее поведение, и оно обязано
##     остаться: у цели миссии 01 два соседа (`hall0` и `it_open4`), и вошедший через
##     грузовой лифт выходит в `hall0` именно так. Обратный путь увёл бы его наверх;
##  2. выход лежит на маршруте плана ВПЕРЕДИ (отставший до выхода ещё не дошёл) — идём по
##     оставшемуся маршруту до выхода. Без этого правила отставший, которому до выхода два
##     перехода и больше, уходил бы назад к узлу входа, и группа не собралась бы вовсе;
##  3. выход лежит на пройденном пути ПОЗАДИ — идём обратным путём и ОСТАНАВЛИВАЕМСЯ на
##     выходе (причина та же, что в правиле 0: путь, уходящий за выход, не дал бы группе
##     собраться — передний ушёл бы дальше, пока отставший только подходит);
##  4. иначе — весь обратный путь до узла входа и, если от входа к выходу есть ребро,
##     «хвост» до выхода: «выход = вход» либо выход рядом со входом. Выход, до которого от
##     входа ребра нет, выразить нечем: второго явного списка рёбер у ядра нет, а поиск пути
##     запрещён. Агент в этом случае доходит до входа и останавливается.
func _withdraw_route(a) -> Array:
	var here := String(a.node)
	var exit_node := String(plan.exit_node)
	if exit_node == "" or here == exit_node:
		return [here]
	if not mission.edge_between(here, exit_node).is_empty():
		return [here, exit_node]
	var ahead := _exit_ahead(here, exit_node, a.waypoint_index - 1)
	if not ahead.is_empty():
		return ahead
	var walked: Array = a.path
	## Охрана пути не ведёт, а у своего он непуст по построению (`setup`). Пустой путь
	## или путь, кончающийся не текущим узлом, — сломанный инвариант: вести группу
	## наугад нельзя, поэтому агент остаётся там, где стоит.
	if walked.is_empty() or String(walked[walked.size() - 1]) != here:
		return [here]
	var out: Array = [here]
	for i in range(walked.size() - 2, -1, -1):
		var node := String(walked[i])
		out.append(node)
		if node == exit_node:
			return out
	## Хвост до выхода от узла входа. Ребро проверяется отдельно: узел входа равен выходу
	## только тогда, когда выход на обратном пути уже встретился (см. `return out` выше),
	## поэтому здесь `out` кончается входом, отличным от выхода.
	if not mission.edge_between(String(out[out.size() - 1]), exit_node).is_empty():
		out.append(exit_node)
	return out


## Оставшийся путь до выхода, если выход лежит на маршруте плана ВПЕРЕДИ текущего узла.
## `current` — индекс текущего узла в маршруте плана: до взятия цели агент идёт по плану
## с нулевого узла, а `waypoint_index` указывает на следующий. Совпадение узла проверяется
## (`plan.route[current] == here`): при сломанном инварианте правило молчит и уступает
## обратному пути, а не ведёт группу по чужому индексу.
func _exit_ahead(here: String, exit_node: String, current: int) -> Array:
	if current < 0 or current >= plan.route.size():
		return []
	if String(plan.route[current]) != here:
		return []
	for i in range(current, plan.route.size()):
		if String(plan.route[i]) != exit_node:
			continue
		var out: Array = []
		for j in range(current, i + 1):
			out.append(String(plan.route[j]))
		return out
	return []


func _check_end() -> void:
	if finished:
		return
	# Уход засчитывается ТОЛЬКО после взятой цели. Иначе агент, стартующий на
	# выходе (а такие маршруты есть в тестах), завершал бы миссию на первом шаге.
	# И только если на выходе есть ЖИВОЙ: «все погибли» — это не успешный уход.
	if objective_done:
		var alive := 0
		var all_out := true
		for a in own:
			if a.is_dead():
				continue
			alive += 1
			if a.node != plan.exit_node:
				all_out = false
		if alive > 0 and all_out:
			finished = true
			outcome = "extracted"
			_emit("mission_ended", {"outcome": outcome})
			return
	if response.has_arrived(scales.step, radio.is_intercepted()):
		finished = true
		outcome = "caught"
		_emit("mission_ended", {"outcome": outcome})
		return
	if scales.step >= MAX_STEPS:
		finished = true
		outcome = "timeout"
		_emit("mission_ended", {"outcome": outcome})


## Заперто ли ребро ПРЯМО СЕЙЧАС. Состояние открытия — в Sim (unlocked), а
## mission.edge(id)["locked"] — только исходные данные миссии.
func _is_locked(e: Dictionary) -> bool:
	if not bool(e.get("locked", false)):
		return false
	return not bool(unlocked.get(String(e["id"]), false))


## Перекрыто ли ребро тревогой ПРЯМО СЕЙЧАС и не снята ли блокировка. Вид ребра
## спрашивает ядро (`Response.edge_blocked`), а не второй список здесь.
##
## Снятие блокировки — то же, что снятие замка: одна запись в `unlocked` (см. `_unlock`).
## Прежде `unlocked` читал только `_is_locked`, и тревожную блокировку снять было нечем:
## группа стояла перед перекрытым ребром до конца миссии.
func _alarm_sealed(e: Dictionary) -> bool:
	if bool(unlocked.get(String(e["id"]), false)):
		return false
	return response.edge_blocked(String(e["kind"]), scales.step)


## Не может ли ЭТОТ агент пройти по ЭТОМУ ребру прямо сейчас. ОДНО понятие на два места:
## запрет шага (`_advance_own`) и выбор актора окна (`_actor_before_locked_edge`). Прежде
## актор спрашивал `_is_locked`, и окно у ребра, перекрытого тревогой, не открывалось
## вовсе: данные окно описывают, а сцены нет.
##
## Замок и тревожная блокировка держат по-разному, и это не небрежность:
##  * замок — при любом `progress`: дверь не отпереть на ходу;
##  * тревога — только на СТАРТЕ перехода (`progress == 0`): лифт, который уже поехал,
##    назад не отзывают (иначе игрок наказан за то, чего не мог предвидеть). По той же
##    причине окно идущему по ребру не открывается, а память о сработавшем окне
##    (`fired_edges`, «одно окно на ребро») не тратится на того, кто не стоит.
func _is_blocked_for(a, e: Dictionary) -> bool:
	if _is_locked(e):
		return true
	return a.progress == 0 and _alarm_sealed(e)


## Окно выбирается по триггеру из данных миссии (`Mission.data["windows"]`).
## Окна перебираются в порядке массива: порядок элементов — порядок проверки
## (см. раздел формы про окна). Запертая дверь симметрична: подход со стороны `b`
## упирается в неё так же, как со стороны `a`, поэтому ребро ищется через
## `edge_between`, а не по якорю записи.
## Сработавшее окно запоминается (`_window_fired`): «одно окно — один
## срабатывающий раз». Без этой памяти окно у всё ещё запертого ребра
## открывалось бы заново каждый шаг, если его эффекты дверь не открыли.
## Завершённая миссия окна не открывает: его некому закрыть.
func _maybe_open_window() -> void:
	if finished:
		current_window = null
		return
	current_window = null
	var windows = mission.data.get("windows", [])
	if typeof(windows) != TYPE_ARRAY:
		return
	for w in windows:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		if _window_fired(w):
			continue
		var actor := _window_actor(w)
		if actor.is_empty():
			continue
		var agent_id := String(actor["agent"])
		_mark_window_fired(w)
		current_window = WindowScript.from_data(w, agent_id)
		_emit("window_opened", _window_event_data(w, agent_id))
		return


## Кто и по какому поводу открывает окно. Пусто — сейчас не открывает никто.
func _window_actor(w: Dictionary) -> Dictionary:
	var trigger = w.get("trigger", {})
	if typeof(trigger) != TYPE_DICTIONARY:
		return {}
	var trigger_dict: Dictionary = trigger
	match String(trigger_dict.get("type", "")):
		"locked_edge":
			return _actor_before_locked_edge(String(trigger_dict.get("edge", "")))
		"node_entered":
			return _actor_entered_node(String(trigger_dict.get("node", "")))
		"guard_in_sensor":
			return _actor_in_sensor(String(trigger_dict.get("sensor", "")))
	return {}


## Группа стоит перед ребром, которое сейчас непроходимо (замок или тревога). Порядок
## своих — порядок `own`, правила пропуска прежние: мёртвый и кончивший маршрут окна
## не открывают.
##
## Условие берётся у `_is_blocked_for` — то же самое, что запрещает шаг в `_advance_own`.
## Своё условие здесь и было дефектом: `_is_locked` на ребре, перекрытом тревогой, ложно,
## и окно ★27 не открывалось ни разу.
##
## Пропуск агента в `plan.exit_node` был снят НЕ целиком, а сужен до одного случая:
## «маршрут ещё не начат» (`waypoint_index <= 1` и `progress == 0`). Причина, по которой
## пропуск стоял вовсе: агент, стоящий в выходе, считался «уже вне игры», и окно у двери
## в нём открывалось бы «просто так». Стоимость этого пропуска оказалась выше пользы:
## выход `hall0` — это и узел ПЕРЕД запертой дверью холодного зала, поэтому окно
## `w_archivist` не открывалось никогда, цель не бралась, и два прохождения из трёх не
## завершались (по измерениям первых прогонов). Оставшаяся половина пропуска
## закрывает ровно то, что он и должен был закрывать: маршрут, НАЧИНАЮЩИЙСЯ в выходе,
## на первом шаге окна не открывает. Всё остальное — агент, дошедший до выхода по
## маршруту и упёршийся в дверь на пути к цели или на выход, — окно получает.
func _actor_before_locked_edge(edge_id: String) -> Dictionary:
	if edge_id == "":
		return {}
	for a in own:
		if a.is_dead():
			continue
		if a.waypoint_index >= a.waypoints.size():
			continue
		if a.node == plan.exit_node and a.waypoint_index <= 1 and a.progress == 0:
			continue
		var target := String(a.waypoints[a.waypoint_index])
		var e: Dictionary = mission.edge_between(a.node, target)
		if e.is_empty() or String(e["id"]) != edge_id:
			continue
		if _is_blocked_for(a, e):
			return {"agent": a.id}
	return {}


## Группа ВОШЛА в помещение: в этом шаге был `agent_moved` в него. «Находится
## в помещении давно» окном быть не может — иначе оно открывалось бы каждый шаг.
func _actor_entered_node(node_id: String) -> Dictionary:
	if node_id == "":
		return {}
	for e in _step_events():
		if String(e["type"]) == "agent_moved" and String(e["data"]["node"]) == node_id:
			return {"agent": String(e["data"]["agent"])}
	return {}


## Охрана вошла в зону сенсора: в этом шаге был `sensor_contact`, а помещение
## контакта видно этому сенсору. Контакт снимается на входе (переход «не видно ->
## видно»), поэтому «охрана стоит в зоне давно» окна не открывает.
func _actor_in_sensor(sensor_id: String) -> Dictionary:
	if sensor_id == "":
		return {}
	for e in _step_events():
		if String(e["type"]) != "sensor_contact":
			continue
		if _sensor_sees(sensor_id, String(e["data"]["node"])):
			return {"agent": String(e["data"]["agent"])}
	return {}


func _sensor_sees(sensor_id: String, node_id: String) -> bool:
	for s in mission.sensors:
		if String(s["id"]) == sensor_id:
			return (s["nodes"] as Array).has(node_id)
	return false


## События текущего шага: триггеры `node_entered` и `guard_in_sensor` смотрят на
## вход именно в этом шаге, а не на состояние мира вообще.
func _step_events() -> Array:
	var out: Array = []
	for e in events:
		if int(e["step"]) == scales.step:
			out.append(e)
	return out


## Сработавшее окно помним по id из данных; окно у запертого ребра — ещё и по
## ребру: «повторные окна на одно и то же ребро не поддерживаются».
func _window_fired(w: Dictionary) -> bool:
	var wid := String(w.get("id", ""))
	if wid != "" and bool(fired_windows.get(wid, false)):
		return true
	var edge_id := _locked_edge_of(w)
	return edge_id != "" and bool(fired_edges.get(edge_id, false))


func _mark_window_fired(w: Dictionary) -> void:
	var wid := String(w.get("id", ""))
	if wid != "":
		fired_windows[wid] = true
	var edge_id := _locked_edge_of(w)
	if edge_id != "":
		fired_edges[edge_id] = true


## Ребро окна, если его триггер — запертое ребро; иначе пусто.
func _locked_edge_of(w: Dictionary) -> String:
	var trigger = w.get("trigger", {})
	if typeof(trigger) != TYPE_DICTIONARY:
		return ""
	var trigger_dict: Dictionary = trigger
	if String(trigger_dict.get("type", "")) != "locked_edge":
		return ""
	return String(trigger_dict.get("edge", ""))


## Данные события `window_opened`. У запертого ребра набор полей прежний
## (`kind`, `edge`, `agent`); у новых триггеров якорь лежит в поле своего вида:
## подставлять id помещения в `edge` значило бы врать в данных события.
func _window_event_data(w: Dictionary, agent_id: String) -> Dictionary:
	var trigger = w.get("trigger", {})
	var type := ""
	if typeof(trigger) == TYPE_DICTIONARY:
		type = String((trigger as Dictionary).get("type", ""))
	var out := {"kind": WindowScript.kind_for(type)}
	var anchor := WindowScript.anchor_key(type)
	if anchor != "" and typeof(trigger) == TYPE_DICTIONARY:
		out[anchor] = String((trigger as Dictionary).get(anchor, ""))
	out["agent"] = agent_id
	return out


## Приказ или молчание. Возвращает решение и причину отказа, если он есть.
func order(option_id: String) -> Dictionary:
	# После конца миссии приказов нет: иначе отчёт правился бы задним числом,
	# а «исход уже есть, но окно ещё открыто» стало бы достижимым состоянием.
	if finished:
		return {"accepted": false, "reason": "finished"}
	if current_window == null:
		return {"accepted": false, "reason": "no_window"}
	var w: Dictionary = current_window
	if option_id == WindowScript.SILENCE:
		var eff := _resolve_silence(w)
		_apply_silence(w, eff)
		current_window = null
		_emit("order_silenced", {"window": w["id"], "effect": eff})
		## Текст исхода выбирается ПО ВЫБРАННОМУ качеству и отдаётся здесь: презентация
		## берёт строку молчания из ответа на приказ, а окно к этому моменту уже закрыто
		## (`current_window = null` выше), и спросить качество у него больше нечем.
		## Ключ едет в ответе, а не в событии: формат `order_silenced`
		## (`{window, effect}`) — и менять его ради ключа нельзя.
		return {"accepted": true, "kind": "silence", "effect": eff,
			"text_key": WindowScript.silence_key_for(w, String(eff["quality"]))}
	# Проверка варианта — ДО списания. Иначе опечатка в идентификаторе сожгла бы
	# приказ, добавила передачу в эфир и вернула «принято» — а прогон
	# верит полю accepted и не отступил бы к молчанию.
	var known := false
	for o in w["options"]:
		if String(o["id"]) == option_id:
			known = true
	if not known:
		_emit("order_refused", {"window": w["id"], "reason": "unknown_option"})
		return {"accepted": false, "reason": "unknown_option"}
	if orders_left <= 0:
		_emit("order_refused", {"window": w["id"], "reason": "no_orders"})
		return {"accepted": false, "reason": "no_orders"}
	## Право голоса проверяется ОДНИМ условием, а причина отказа называется раздельно:
	## замолчать можно двумя способами — канал заглушён порогом эфира и эфир мёртв в
	## экранированном помещении. Игрок обязан видеть, что именно его замолчало,
	## а отказ — не закрытие окна: окно остаётся, и его закрывает молчание.
	_refresh_shield()
	if not radio.can_speak(scales.step):
		var reason := "shielded" if radio.shielded else "jammed"
		_emit("order_refused", {"window": w["id"], "reason": reason})
		return {"accepted": false, "reason": reason}
	orders_left -= 1
	var tx: Dictionary = radio.transmit(scales.step)
	var literal: Dictionary = _apply_option(w, option_id)
	current_window = null
	_emit("order_issued", {"window": w["id"], "option": option_id, "radio": tx})
	## Буквальность видна в журнале ОТДЕЛЬНЫМ событием и ПОСЛЕ приказа: приказ состоялся,
	## и уж потом выяснилось, что исполнен он ровно как сказано. Надбавка к этому
	## моменту уже применена — как и у `agent_moved`, событие описывает случившееся,
	## а не служит ему причиной. Кубика здесь нет: разрыв детерминирован.
	if not literal.is_empty():
		_emit("order_literal", literal)
	return {"accepted": true, "kind": "order", "transmit": tx}


## Импровизация — единственное место с кубиком. Ровно поэтому seed обязателен.
func _resolve_silence(w: Dictionary) -> Dictionary:
	var comms = null
	var tactician = null
	for a in own:
		if a.is_dead():
			continue
		match a.role:
			"comms":
				comms = a
			"tactician":
				tactician = a
	if comms == null:
		return {"by": "tactician" if tactician != null else "nobody", "quality": "safe"}
	var roll := rng.randf()
	if roll < 0.5:
		return {"by": "comms", "quality": "good"}
	if roll < 0.8:
		return {"by": "comms", "quality": "neutral"}
	return {"by": "comms", "quality": "bad"}


## Приказ из окна. Порядок применения фиксирован: сначала цена варианта, потом надбавка
## за буквальность (она — часть цены), потом эффекты. Все эффекты идут через один
## применятель, чтобы правило жило в одном месте, а не порознь в приказе и молчании.
##
## Возвращает данные события `order_literal` (пустой словарь — исполнено как задумано):
## событие публикует `order()`, а решение о буквальности принимается здесь, где известен
## выбранный вариант.
func _apply_option(w: Dictionary, option_id: String) -> Dictionary:
	var chosen: Dictionary = {}
	for o in w["options"]:
		if String(o["id"]) == option_id:
			chosen = o
	if chosen.is_empty():
		return {}
	_apply_cost(w, chosen)
	var literal := _apply_literal(w, chosen, option_id)
	for effect in chosen.get("effects", []):
		_apply_effect(w, effect)
	return literal


## Надбавка за буквальное исполнение: `complexity` выбранного варианта против
## Понимания окна. Вариант ИСПОЛНЯЕТСЯ — буквальность не провал, а цена; поэтому надбавка
## ложится тем же `_apply_cost`, что и цена варианта, до его эффектов.
##
## Актор надбавки — тот же, кому достаётся `delay` варианта (`_apply_delay`): задержка
## есть цена ПРИКАЗА, а не свойство бойца, поэтому её платит актор окна, а не самое слабое
## звено, из-за которого она возникла.
func _apply_literal(w: Dictionary, chosen: Dictionary, option_id: String) -> Dictionary:
	var understanding := window_understanding()
	if understanding < 0:
		## Живых своих нет — исполнять некому, и буквальности не у кого случиться.
		## Приказ при этом принимается и списывается: конец миссии наступает по своим
		## правилам (`_check_end`), а не по «нет живых» в окне.
		return {}
	var complexity := int(chosen.get("complexity", 1))
	var cost: Dictionary = Understanding.literal_cost(complexity, understanding)
	if cost.is_empty():
		return {}
	_apply_cost(w, cost)
	return {
		"window": String(w["id"]),
		"option": option_id,
		"complexity": complexity,
		"understanding": understanding,
		"noise": int(cost["noise"]),
		"delay": int(cost["delay"]),
	}


## Понимание ОКНА — минимум по живым своим: приказ исполняет самое слабое звено группы,
## а не тот, кто его отдал, и не средний по отряду. −1 — живых нет, исполнять некому.
func window_understanding() -> int:
	var worst := -1
	for a in own:
		if a.is_dead():
			continue
		if worst < 0 or int(a.understanding) < worst:
			worst = int(a.understanding)
	return worst


## Есть ли ЖИВОЙ свой в экранированном помещении. Мёртвый голоса не отнимает:
## правило — про то, что кто-то в зоне не может говорить, а не про то, что там лежит тело.
func in_shielded_zone() -> bool:
	for a in own:
		if a.is_dead():
			continue
		if _node_has_tag(String(a.node), "shielded"):
			return true
	return false


## Есть ли у помещения тег. Список тегов открытый (`entry`, `shielded`, `locked_room`):
## ядро спрашивает ИМЯ тега, а не перечисляет известные ему виды, иначе новый тег
## контента потребовал бы правки ядра. Отсутствующее помещение и мусор в `tags` —
## не тег: миссию собирает конвейер, а падать ядру на неполных данных нечем.
##
## Живёт здесь, а не в `Mission`, намеренно: `sim/mission.gd` входит в комплект наружу,
## и кейс самодостаточности пакета (`test_package_purity.gd`) требует побайтового равенства
## боевого модуля и его копии в комплекте. Правка модели миссии ради одного вопроса ядра
## уронила бы чужие ворота и потребовала бы правки пакета — то есть работы вне зоны ядра.
func _node_has_tag(node_id: String, tag: String) -> bool:
	var node = mission.nodes.get(node_id, null)
	if typeof(node) != TYPE_DICTIONARY:
		return false
	var tags = (node as Dictionary).get("tags", [])
	return typeof(tags) == TYPE_ARRAY and (tags as Array).has(tag)


## Пересчитать признак мёртвого эфира. Радио о помещениях и позициях не знает — знает ядро,
## и оно же кладёт ответ туда, откуда его читают `can_speak` и причина отказа `order()`.
func _refresh_shield() -> void:
	radio.shielded = in_shielded_zone()


## Цена: `noise` и `delay` из словаря цены (прежде — поля варианта). Тот же путь несёт
## и надбавку за буквальность (`_apply_literal`) — у цены приказа одно применение,
## сколько бы слагаемых в неё ни входило.
func _apply_cost(w: Dictionary, chosen: Dictionary) -> void:
	var noise := int(chosen.get("noise", 0))
	if noise > 0:
		scales.add_noise(noise)
	_apply_delay(w, int(chosen.get("delay", 0)))


## Молчание: качество выбирает `_resolve_silence` (кубик только там), а набор
## эффектов приходит из данных — `silence[quality]`. Порядок — как записан в данных.
func _apply_silence(w: Dictionary, eff: Dictionary) -> void:
	var by_quality: Dictionary = w.get("silence", {})
	for effect in by_quality.get(String(eff["quality"]), []):
		_apply_effect(w, effect)


## Один применятель эффектов из данных: цена варианта, эффекты молчания и
## `fallback` заявки на новую механику (см. раздел формы про запрос движку).
##
## Счётчики `money`/`trace` и метки `mark` копятся ЗДЕСЬ и только здесь: эффекты
## приходят из вариантов окна, из четырёх исходов молчания и из `fallback` заявки, а
## `fallback` вызывает тот же применятель — значит место применения одно по построению,
## а не по договорённости.
func _apply_effect(w: Dictionary, effect) -> void:
	if typeof(effect) != TYPE_DICTIONARY:
		return
	var effect_dict: Dictionary = effect
	match String(effect_dict.get("type", "")):
		"unlock":
			_unlock(w, String(effect_dict.get("edge", "")))
		"noise":
			var added := int(effect_dict.get("value", 0))
			if added > 0:
				scales.add_noise(added)
		"delay":
			_apply_delay(w, int(effect_dict.get("value", 0)))
		"money":
			money += int(effect_dict.get("value", 0))
		"trace":
			trace += int(effect_dict.get("value", 0))
		"mark":
			## Метка — факт, а не счётчик: повтор того же имени не двоит запись.
			## Пустое имя меткой не является (это ошибка формы, а не «метка без имени»),
			## и в результат ему ехать нечем.
			var mark_id := String(effect_dict.get("id", ""))
			if mark_id != "" and not marks.has(mark_id):
				marks.append(mark_id)
		"engine_proposal":
			## Ядро заявку не исполняет и ничего не «дорисовывает»: применяется
			## `fallback` — то, что делает уровень проходимым уже сегодня (см. раздел формы).
			_apply_fallback(w, effect_dict.get("fallback", []))


## `fallback` бывает объектом или массивом эффектов: форматы равнозначны (см. раздел формы).
func _apply_fallback(w: Dictionary, fallback) -> void:
	if typeof(fallback) == TYPE_ARRAY:
		for effect in fallback:
			_apply_effect(w, effect)
	elif typeof(fallback) == TYPE_DICTIONARY:
		_apply_effect(w, fallback)


func _apply_delay(w: Dictionary, amount: int) -> void:
	if amount <= 0:
		return
	for a in own:
		if a.id == String(w.get("agent", "")):
			a.delay += amount


## Открыть ребро. Ребро приходит из эффекта; если эффект его не назвал, берём ребро
## окна — так же, как это делал прежний `_unlock(w)`.
##
## Одна запись снимает ОБА запрета: замок (`_is_locked`) и тревожную блокировку
## (`_alarm_sealed`). Так правило одно для обоих случаев и совпадает с разделом формы («`unlock`
## во всех четырёх исходах у двери»): молчание, у которого хотя бы в одном исходе есть
## `unlock`, выводит группу из тупика. Снимается блокировка ИМЕННО этого ребра — по id,
## а не по виду: соседний лифт того же вида остаётся перекрытым.
func _unlock(w: Dictionary, edge_id: String) -> void:
	var target := edge_id
	if target == "":
		target = String(w.get("edge", ""))
	if target != "":
		unlocked[target] = true


## Свидетель. Один триггер ранит, три убивают — не наоборот.
func _compromise(agent) -> void:
	agent.add_trigger()
	scales.add_noise(5)
	_emit("agent_compromised", {"agent": agent.id, "state": agent.state, "triggers": agent.triggers})

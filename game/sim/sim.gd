extends RefCounted
## Ядро операции. Только композиция правил — ни одного собственного числа баланса.
## Чистый RefCounted: ни нод, ни сцен, ни рендера (D14).
##
## Автопауза: пока открыто окно решения, advance() не двигает мир (D4).
## Давление создаёт дефицит приказов и эфир, а не таймер.

const Agent := preload("res://sim/agent.gd")
const Scales := preload("res://sim/scales.gd")
const Radio := preload("res://sim/radio.gd")
const Response := preload("res://sim/response.gd")
## Имя константы не может быть `Window`: в Godot 4.7 это тень нативной ноды
## и жёсткая ошибка разбора. Смысл `Window.locked_door` сохранён дословно.
const WindowScript := preload("res://sim/window.gd")

const MAX_STEPS := 500

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
## обязан давать одинаковый исход при повторном прогоне (D7).
var unlocked: Dictionary = {}
var ghost_positions: Dictionary = {}
var visible_last: Dictionary = {}
var ghost_reported: Dictionary = {}
## id бойца -> помещение, где его уже засекли. Сбрасывается в setup().
var compromised_at: Dictionary = {}
## Учёт сработавших окон: id окна из данных -> true и ребро окна запертой двери ->
## true. Сбрасывается в setup(). Нужен, чтобы окно не открывалось второй раз:
## «одно окно — один срабатывающий раз» (`02-format.md` §4.2).
var fired_windows: Dictionary = {}
var fired_edges: Dictionary = {}
var orders_left: int = 3
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
		# в escaped с нулевого шага, и проверки в задачах 10–11 были бы пустыми.
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
		"injured": injured,
		"dead": dead,
		"escaped": escaped,
		"positions": _positions(),
	}


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
		if _is_locked(e):
			continue                  # упёрлись в запертую дверь: её откроет окно
		if a.progress == 0 and response.edge_blocked(String(e["kind"]), scales.step):
			_emit("path_blocked", {"agent": a.id, "edge": e["id"], "kind": e["kind"]})
			continue
		a.progress += 1
		if a.progress >= int(e["steps"]) + a.speed_penalty():
			a.progress = 0
			a.node = target
			a.waypoint_index += 1
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
## направления взгляда и без «заметил, но не понял» (это П2).
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
			for b in own:
				if b.is_dead():
					continue
				b.waypoints = [b.node, plan.exit_node]
				b.waypoint_index = 1
				b.progress = 0
			return


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


## Окно выбирается по триггеру из данных миссии (`Mission.data["windows"]`).
## Окна перебираются в порядке массива: порядок элементов — порядок проверки
## (`02-format.md` §9). Запертая дверь симметрична: подход со стороны `b`
## упирается в неё так же, как со стороны `a`, поэтому ребро ищется через
## `edge_between`, а не по якорю записи.
## Сработавшее окно запоминается (`_window_fired`): «одно окно — один
## срабатывающий раз» (§4.2). Без этой памяти окно у всё ещё запертого ребра
## открывалось бы заново каждый шаг, если его эффекты дверь не открыли.
## Завершённая миссия окна не открывает: его некому закрыть (D4).
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


## Группа стоит перед запертым ребром. Порядок своих — порядок `own`, правила
## пропуска прежние: мёртвый, дошедший до выхода и кончивший маршрут окна не открывают.
func _actor_before_locked_edge(edge_id: String) -> Dictionary:
	if edge_id == "":
		return {}
	for a in own:
		if a.is_dead() or a.node == plan.exit_node:
			continue
		if a.waypoint_index >= a.waypoints.size():
			continue
		var target := String(a.waypoints[a.waypoint_index])
		var e: Dictionary = mission.edge_between(a.node, target)
		if e.is_empty() or String(e["id"]) != edge_id:
			continue
		if _is_locked(e):
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
## ребру: «повторные окна на одно и то же ребро не поддерживаются» (§4.2).
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
		return {"accepted": true, "kind": "silence", "effect": eff}
	# Проверка варианта — ДО списания. Иначе опечатка в идентификаторе сожгла бы
	# приказ, добавила передачу в эфир и вернула «принято» — а харнесс задачи 11
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
	if not radio.can_speak(scales.step):
		_emit("order_refused", {"window": w["id"], "reason": "jammed"})
		return {"accepted": false, "reason": "jammed"}
	orders_left -= 1
	var tx: Dictionary = radio.transmit(scales.step)
	_apply_option(w, option_id)
	current_window = null
	_emit("order_issued", {"window": w["id"], "option": option_id, "radio": tx})
	return {"accepted": true, "kind": "order", "transmit": tx}


## Импровизация — единственное место с кубиком (D7). Ровно поэтому seed обязателен.
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


## Приказ из окна. Порядок применения фиксирован: сначала цена варианта, потом его
## эффекты. Все эффекты идут через один применятель, чтобы правило жило в одном
## месте, а не порознь в приказе и молчании.
func _apply_option(w: Dictionary, option_id: String) -> void:
	var chosen: Dictionary = {}
	for o in w["options"]:
		if String(o["id"]) == option_id:
			chosen = o
	if chosen.is_empty():
		return
	_apply_cost(w, chosen)
	for effect in chosen.get("effects", []):
		_apply_effect(w, effect)


## Цена варианта: `cost.noise` и `cost.delay` из данных (прежде — поля варианта).
func _apply_cost(w: Dictionary, chosen: Dictionary) -> void:
	var noise := int(chosen.get("noise", 0))
	if noise > 0:
		scales.add_noise(noise)
	_apply_delay(w, int(chosen.get("delay", 0)))


## Молчание: качество выбирает `_resolve_silence` (кубик только там, D7), а набор
## эффектов приходит из данных — `silence[quality]`. Порядок — как записан в данных.
func _apply_silence(w: Dictionary, eff: Dictionary) -> void:
	var by_quality: Dictionary = w.get("silence", {})
	for effect in by_quality.get(String(eff["quality"]), []):
		_apply_effect(w, effect)


## Один применятель эффектов из данных: цена варианта, эффекты молчания и
## `fallback` заявки на новую механику (`02-format.md` §4.4, §7).
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
		"engine_proposal":
			## Ядро заявку не исполняет и ничего не «дорисовывает»: применяется
			## `fallback` — то, что делает уровень проходимым уже сегодня (§7).
			_apply_fallback(w, effect_dict.get("fallback", []))


## `fallback` бывает объектом или массивом эффектов: форматы равнозначны (§7).
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
func _unlock(w: Dictionary, edge_id: String) -> void:
	var target := edge_id
	if target == "":
		target = String(w.get("edge", ""))
	if target != "":
		unlocked[target] = true


## Свидетель. Один триггер ранит, три убивают — не наоборот (design.md §13.5).
func _compromise(agent) -> void:
	agent.add_trigger()
	scales.add_noise(5)
	_emit("agent_compromised", {"agent": agent.id, "state": agent.state, "triggers": agent.triggers})

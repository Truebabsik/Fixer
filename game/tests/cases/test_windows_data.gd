extends RefCounted
## Окна из данных: триггеры (`locked_edge`, `node_entered`, `guard_in_sensor`),
## учёт сработавших окон и эффекты, включая `fallback` заявки на новую механику.
##
## Отдельный кейс от `test_windows.gd` намеренно: там живут прежние проверки окон,
## приказов и молчания на фикстуре, и они — часть контракта П1. Здесь проверяется
## ровно то, чего до перевода ядра на данные не было.

const Assert := preload("res://tests/assert.gd")
const Mission := preload("res://sim/mission.gd")
const Plan := preload("res://sim/plan.gd")
const Sim := preload("res://sim/sim.gd")
## Имя константы не может быть `Window`: в Godot 4.7 это тень нативной ноды.
const WindowScript := preload("res://sim/window.gd")


func run() -> Array:
	var t := Assert.new()

	# 1. Триггер `node_entered`: окно открывается на ВХОД в помещение. Прежде окно
	# знало единственный повод — запертое ребро перед агентом (`sim.gd:342`).
	var entered = _make(
		_window("w_mid", {"type": "node_entered", "node": "mid"}, [
			_option("hurry", 0, 2, [{"type": "noise", "value": 4}]),
			_option("wait", 0, 0, [{"type": "noop"}]),
		]),
		["start", "mid", "goal"], "goal"
	)
	t.eq("до входа окна нет", entered.current_window, null)
	entered.advance()
	t.is_true("окно входа открылось", entered.current_window != null)
	## Пустое окно уронило бы кейс целиком на первой же строке ниже: тогда провал
	## выглядел бы абортом, а не ассертом. Выходим с одним честным провалом.
	if entered.current_window == null:
		return t.results
	t.eq("вид окна входа", String(entered.current_window["kind"]), "node_entered")
	t.eq("id окна входа", String(entered.current_window["id"]), "node_entered:mid")
	t.eq("окно знает помещение", String(entered.current_window["node"]), "mid")
	t.eq("окно знает вошедшего", String(entered.current_window["agent"]), "kira")
	t.is_true("у окна из данных есть молчание", WindowScript.has_silence(entered.current_window))
	t.eq("событие несёт вид окна", _event_field(entered, "window_opened", "kind"), "node_entered")
	t.eq("событие несёт помещение", _event_field(entered, "window_opened", "node"), "mid")
	t.eq("событие несёт агента", _event_field(entered, "window_opened", "agent"), "kira")
	var frozen: int = entered.scales.step
	t.eq("без ответа шагов нет", entered.advance().size(), 0)
	t.eq("часы стоят", entered.scales.step, frozen)

	# 1б. Цена варианта — из `cost`, эффекты — из `effects`: одно без другого
	# проверку не пройдёт (шум 4 даёт только эффект, задержку 2 — только цена).
	var noise_before: int = entered.scales.noise
	var taken: Dictionary = entered.order("hurry")
	t.is_true("вариант из данных принят", taken["accepted"])
	t.eq("шум цены и эффекта", entered.scales.noise - noise_before, 4)
	t.eq("задержка цены", entered.own[0].delay, 2)
	for i in 2:
		entered.advance()
	t.eq("задержанный стоит на месте", entered.own[0].node, "mid")
	entered.advance()
	t.eq("после задержки агент пошёл", entered.own[0].node, "goal")
	t.eq("окно входа не открылось второй раз", entered.current_window, null)

	# 2. «Одно окно — один срабатывающий раз» (`02-format.md` §4.2). Проверка ловит
	# и прежний латентный дефект: пока память о сработавшем окне не велась, окно
	# у всё ещё запертого ребра открывалось заново КАЖДЫЙ шаг.
	var noop_silence := [{"type": "noop"}]
	var stubborn = _make_locked(
		_window("w_stubborn", {"type": "locked_edge", "edge": "e_cell_hall"},
			[_option("wait", 0, 0, [{"type": "noop"}])], noop_silence)
	)
	t.is_true("дверь заперта на входе", bool(stubborn.mission.edge("e_cell_hall")["locked"]))
	stubborn.advance()
	t.is_true("окно запертой двери открылось", stubborn.current_window != null)
	if stubborn.current_window == null:
		return t.results
	t.eq("id окна запертой двери прежний", String(stubborn.current_window["id"]),
		"locked_door:e_cell_hall")
	t.eq("окно называет ребро", String(stubborn.current_window["edge"]), "e_cell_hall")
	t.is_true("окно приняло вариант без эффектов", bool(stubborn.order("wait")["accepted"]))
	t.eq("noop ничего не сделал", stubborn.scales.noise, 0)
	t.is_false("дверь осталась заперта", bool(stubborn.unlocked.get("e_cell_hall", false)))
	for i in 3:
		stubborn.advance()
	t.eq("окно не сработало второй раз", stubborn.current_window, null)
	t.is_false("дверь всё ещё заперта", bool(stubborn.unlocked.get("e_cell_hall", false)))
	t.is_true("миссия не тронута", bool(stubborn.mission.edge("e_cell_hall")["locked"]))

	# 2б. Молчание у запертой двери — тот же один раз. В данных этой миссии
	# `unlock` нет вовсе, поэтому дверь остаётся запертой, и без памяти об окне
	# оно вернулось бы следующим шагом.
	var silent_door = _make_locked(
		_window("w_stubborn_silence", {"type": "locked_edge", "edge": "e_cell_hall"},
			[_option("wait", 0, 0, [{"type": "noop"}])], noop_silence)
	)
	silent_door.advance()
	t.is_true("окно открылось и здесь", silent_door.current_window != null)
	if silent_door.current_window == null:
		return t.results
	t.is_true("молчание принято", bool(silent_door.order("silence")["accepted"]))
	for i in 2:
		silent_door.advance()
	t.eq("после молчания окно не вернулось", silent_door.current_window, null)
	t.is_false("молчание без unlock дверь не открыло", bool(silent_door.unlocked.get("e_cell_hall", false)))

	# 2в. Память о сработавших окнах сбрасывается в `setup()`: тот же Sim,
	# перезапущенный на той же миссии, обязан показать то же окно. Иначе прогон
	# был бы невоспроизводим, а балансировщик — недетерминирован.
	stubborn.setup(stubborn.mission, stubborn.plan, {"orders": 3, "seed": 1})
	t.eq("после setup окно снято", stubborn.current_window, null)
	t.is_true("память сброшена: сработавший id пуст", stubborn.fired_windows.is_empty())
	t.is_true("память сброшена: рёбра пусты", stubborn.fired_edges.is_empty())
	stubborn.advance()
	t.is_true("после setup окно открылось снова", stubborn.current_window != null)

	# 3. `engine_proposal`: ядро заявку не исполняет, а применяет `fallback`
	# (`02-format.md` §7). Проверка падает и если `fallback` игнорируется, и если
	# ядро «исполняет» заявку само.
	var asked = _make_locked(
		_window("w_ask", {"type": "locked_edge", "edge": "e_cell_hall"},
			[_option("ask", 0, 0, [_proposal([
				{"type": "unlock", "edge": "e_cell_hall"},
				{"type": "delay", "value": 1},
			])])], noop_silence)
	)
	asked.advance()
	t.is_true("окно заявки открылось", asked.current_window != null)
	if asked.current_window == null:
		return t.results
	t.is_true("заявка принята как приказ", bool(asked.order("ask")["accepted"]))
	t.is_true("fallback-массив открыл дверь", bool(asked.unlocked.get("e_cell_hall", false)))
	t.eq("fallback-массив задержал агента", asked.own[0].delay, 1)

	# 3б. `fallback` одиночным объектом — вторая разрешённая форма (§7).
	var single = _make_locked(
		_window("w_ask_one", {"type": "locked_edge", "edge": "e_cell_hall"},
			[_option("ask", 0, 0, [_proposal({"type": "noise", "value": 6})])], noop_silence)
	)
	single.advance()
	t.is_true("окно заявки открылось и здесь", single.current_window != null)
	if single.current_window == null:
		return t.results
	var single_noise: int = single.scales.noise
	single.order("ask")
	t.eq("fallback-объект добавил шум", single.scales.noise - single_noise, 6)
	t.is_false("и ничего сверх fallback не сделал", bool(single.unlocked.get("e_cell_hall", false)))

	# 4. Триггер `guard_in_sensor`: окно открывается, когда охрана ВХОДИТ в зону
	# сенсора. Период охраны 1: на третьем шаге она входит в зону снова — и окно
	# обязано молчать, потому что уже сработало.
	var watched = _make(
		_window("w_guard", {"type": "guard_in_sensor", "sensor": "s_mid"},
			[_option("listen", 0, 0, [{"type": "noise", "value": 2}])], noop_silence),
		["start", "goal"], "start",
		{
			"edges": [["e_start_goal", "start", "goal", "corridor", 5, 0]],
			"patrols": [{"id": "guard_1", "route": ["start", "mid"], "period": 1}],
			"sensors": [{"id": "s_mid", "nodes": ["mid"]}],
		}
	)
	watched.advance()
	t.is_true("окно сенсора открылось", watched.current_window != null)
	if watched.current_window == null:
		return t.results
	t.eq("вид окна сенсора", String(watched.current_window["kind"]), "guard_in_sensor")
	t.eq("id окна сенсора", String(watched.current_window["id"]), "guard_in_sensor:s_mid")
	t.eq("окно знает сенсор", String(watched.current_window["sensor"]), "s_mid")
	t.eq("окно знает охранника", String(watched.current_window["agent"]), "guard_1")
	t.eq("событие несёт сенсор", _event_field(watched, "window_opened", "sensor"), "s_mid")
	var guard_noise: int = watched.scales.noise
	t.is_true("вариант окна сенсора принят", bool(watched.order("listen")["accepted"]))
	t.eq("эффект из данных добавил шум", watched.scales.noise - guard_noise, 2)
	for i in 3:
		watched.advance()
	t.eq("повторный вход в сенсор окна не открывает", watched.current_window, null)

	return t.results


## Данные окна с заданным триггером. Молчание описано всегда: у окна обязан быть
## вариант «молчать» (D23), и его эффекты задаются явно, а не по умолчанию.
func _window(id: String, trigger: Dictionary, options: Array, silence_effects := []) -> Dictionary:
	return {
		"id": id,
		"kind": String(trigger["type"]),
		"trigger": trigger,
		"text_key": "window.%s.text" % id,
		"options": options,
		"silence": {
			"text_key": "window.%s.silence" % id,
			"good": silence_effects.duplicate(true),
			"neutral": silence_effects.duplicate(true),
			"bad": silence_effects.duplicate(true),
			"safe": silence_effects.duplicate(true),
		},
	}


## Вариант в авторской форме: цена в `cost`, последствия в `effects`.
func _option(id: String, noise: int, delay: int, effects: Array) -> Dictionary:
	return {
		"id": id,
		"text_key": "window.option.%s" % id,
		"complexity": 1,
		"cost": {"noise": noise, "delay": delay},
		"effects": effects,
	}


## Заявка на новую механику: ядро обязано применить `fallback`, а не её саму.
## `want`/`needs` заполнены как в данных — на исход они влиять не должны.
func _proposal(fallback) -> Dictionary:
	return {
		"type": "engine_proposal",
		"id": "lure_engineer",
		"want": "инженер выходит из серверной",
		"needs": "состояние «вне поста» и таймер возврата",
		"fallback": fallback,
	}


## Маленькая миссия с данными окнами: `start -> mid -> goal` по одному шагу.
## `extra` добавляет рёбра, патрули и сенсоры — граф фикстуры для новых триггеров
## не годится: в нём нет входа в помещение по сенсору.
func _make(window: Dictionary, route: Array, exit_node: String, extra := {}):
	var m := Mission.new()
	m.id = "windows_data"
	m.add_node("start", 1, ["entry"])
	m.add_node("mid", 1, [])
	m.add_node("goal", 1, [])
	m.add_edge("e_start_mid", "start", "mid", "corridor", 1, 0)
	m.add_edge("e_mid_goal", "mid", "goal", "corridor", 1, 0)
	for e in extra.get("edges", []):
		var locked: bool = bool(e[6]) if e.size() > 6 else false
		m.add_edge(String(e[0]), String(e[1]), String(e[2]), String(e[3]), int(e[4]), int(e[5]), locked)
	for p in extra.get("patrols", []):
		m.add_patrol(String(p["id"]), p["route"], int(p.get("period", 4)))
	for s in extra.get("sensors", []):
		m.add_sensor(String(s["id"]), s["nodes"])
	m.objective = String(extra.get("objective", "goal"))
	m.set_data({"windows": [window]})
	var p := Plan.new()
	p.route = route
	p.exit_node = exit_node
	p.agents = [{"id": "kira", "role": "tactician", "understanding": 3}]
	var sim := Sim.new()
	sim.setup(m, p, {"orders": 3, "seed": 1})
	return sim


## Миссия с запертой дверью и окном на неё: у фикстуры дверь открывается эффектами,
## а здесь нужно окно, которое дверь НЕ открывает — иначе память о сработавшем
## окне ничем не проверяется.
func _make_locked(window: Dictionary):
	var m := Mission.new()
	m.id = "windows_data_locked"
	m.add_node("cell", 1, [])
	m.add_node("hall", 1, [])
	m.add_edge("e_cell_hall", "cell", "hall", "door", 1, 0, true)
	m.objective = "hall"
	m.set_data({"windows": [window]})
	var p := Plan.new()
	p.route = ["cell", "hall"]
	p.exit_node = "hall"
	p.agents = [{"id": "kira", "role": "tactician", "understanding": 3}]
	var sim := Sim.new()
	sim.setup(m, p, {"orders": 3, "seed": 1})
	sim.guards = []
	return sim


## Поле события заданного вида ("" — события нет). Событие берём первое: в каждом
## прогоне этого кейса окно одно, и второго `window_opened` быть не должно.
func _event_field(sim, type: String, field: String) -> String:
	for e in sim.events:
		if String(e["type"]) == type:
			return String(e["data"].get(field, ""))
	return ""

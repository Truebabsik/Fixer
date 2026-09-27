extends RefCounted
## Ядро под v3: счётчики и метки эффектов (D49), экранированная зона (D50),
## буквальное исполнение приказа (D51).
##
## Три обещания, которые форма принимала, а ядро не исполняло. Здесь они проверяются
## ПОВЕДЕНИЕМ, а не наличием поля: счётчики доходят до `Sim.result()`, метки приходят
## отсортированными, зона отказывает приказу с причиной `shielded` и не ломает окно,
## а сложный приказ слабого бойца ИСПОЛНЯЕТСЯ — ценой шума и задержки из
## `docs/spr/mercs.md` §1.

const Assert := preload("res://tests/assert.gd")
const Mission := preload("res://sim/mission.gd")
const Plan := preload("res://sim/plan.gd")
const Sim := preload("res://sim/sim.gd")
const Understanding := preload("res://sim/understanding.gd")

## Полигон: вход → холл → подвал → цель. Одна линия на все блоки: окна висят на входе
## в помещение (`node_entered`), поэтому порядок окон — порядок шагов, и `_to_window`
## доводит до нужного окна, не зная о маршруте.
const LINE := ["entry", "hall", "cellar", "deep"]

const EDGES := [
	["e_entry_hall", "entry", "hall"],
	["e_hall_cellar", "hall", "cellar"],
	["e_cellar_deep", "cellar", "deep"],
]


func run() -> Array:
	var t := Assert.new()
	_money_trace_marks(t)
	_effects_everywhere(t)
	_shielded_zone(t)
	_shielded_zone_guards(t)
	_determinism(t)
	_understanding(t)
	return t.results


# ---------------------------------------------------------------- полигон

## Полигон. `shielded` — тег экранированного помещения у `cellar`: блок про зону его
## включает, остальные выключают, чтобы отказ приказа не подменял собой цену приказа.
## `patrols` — объявленные патрули (список словарей `{id, route, period}`): нужны там, где
## проверяется ОХРАНА (вторая половина D50). Без них охраны нет вовсе.
func _make(agents: Array, windows: Array, shielded := false, patrols := []):
	var m := Mission.new()
	m.id = "core_v3"
	m.add_node("entry", 1, ["entry"])
	m.add_node("hall", 1, [])
	m.add_node("cellar", 1, ["shielded"] if shielded else [])
	m.add_node("deep", 2, [])
	for e in EDGES:
		m.add_edge(String(e[0]), String(e[1]), String(e[2]), "corridor", 1, 0)
	m.objective = "deep"
	## Окна — в авторской форме данных (`02-format.md` §4): рантайм-окно ядро собирает
	## само (`WindowScript.from_data`), и второй формы в кейсе быть не может.
	m.set_data({"windows": windows.duplicate(true)})
	## Патрули объявляются ДО `setup`: охрана строится из `mission.patrols`, и её позиция
	## на первом шаге — `route[0]` (`sim.gd:setup`), а не вход группы. Одноузловой маршрут
	## охрана не обходит (`_advance_guards` пропускает маршрут короче двух): сторож стоит
	## там, куда его поставили, и проверка не зависит от тайминга шагов.
	for patrol in patrols:
		var patrol_dict: Dictionary = patrol
		m.add_patrol(String(patrol_dict["id"]), patrol_dict["route"], int(patrol_dict.get("period", 4)))
	var p := Plan.new()
	p.route = LINE.duplicate()
	p.exit_node = "entry"
	p.agents = agents
	var sim := Sim.new()
	sim.setup(m, p, {"orders": 3, "seed": 1})
	## Охраны нет, когда патрули не объявлены: проверяются эффекты, цена приказа и эфир,
	## а не контакты (`test_casualties`). Объявленные патрули остаются — их и проверяет
	## блок про экранированную зону с охраной (D50, вторая половина).
	if patrols.is_empty():
		sim.guards = []
	return sim


## Окно на вход в помещение. Пустое `silence` — исходы молчания без эффектов.
func _window(node: String, options: Array, silence := {}) -> Dictionary:
	var w := {
		"id": "w_%s" % node,
		"trigger": {"type": "node_entered", "node": node},
		"text_key": "window.w_%s.text" % node,
		"options": options,
	}
	if not silence.is_empty():
		w["silence"] = silence
	return w


## Вариант окна: сложность, цена и эффекты — как в данных.
func _option(id: String, complexity: int, effects: Array, noise := 0, delay := 0) -> Dictionary:
	return {
		"id": id,
		"text_key": "window.%s" % id,
		"complexity": complexity,
		"cost": {"noise": noise, "delay": delay},
		"effects": effects,
	}


## Один свой — тактик с заданным Пониманием. Без связиста молчание решается тактиком
## безопасно и кубика не бросает (D7): там, где кейс молчит, исход детерминирован.
func _solo(understanding: int) -> Array:
	return [{"id": "kira", "role": "tactician", "understanding": understanding}]


## Довести до ближайшего окна. Мир при открытом окне не двигается (D4), поэтому цикл
## останавливается сам; сторож — от вечного цикла на сломанных данных.
func _to_window(sim) -> void:
	var guard := 0
	while sim.current_window == null and not sim.finished and guard < 10:
		sim.advance()
		guard += 1


# ---------------------------------------------------------------- D49: счётчики и метки

## Счётчики копятся и доходят до отчёта; метки в отчёте — по алфавиту.
##
## Порядок меток выбран НЕ алфавитным намеренно: первый вариант ставит метку, которая
## по алфавиту ПОЗЖЕ (`took_copy`), второй — раньше (`saw_answer`). Снять сортировку —
## и `marks` вернутся в порядке постановки, а ассерт покраснеет.
func _money_trace_marks(t) -> void:
	var sim = _make(_solo(3), [
		_window("hall", [_option("copy", 1, [
			{"type": "money", "value": 15},
			{"type": "trace", "value": 5},
			{"type": "mark", "id": "took_copy"}])]),
		_window("cellar", [_option("answer", 1, [
			{"type": "money", "value": 40},
			{"type": "trace", "value": 8},
			{"type": "mark", "id": "saw_answer"}])]),
	])
	_to_window(sim)
	t.is_true("окно первого варианта открылось", sim.current_window != null)
	var first: Dictionary = sim.order("copy")
	t.is_true("первый вариант принят", first["accepted"])
	t.eq("деньги первого варианта дошли до результата", int(sim.result()["money"]), 15)
	t.eq("след первого варианта дошёл до результата", int(sim.result()["trace"]), 5)
	t.eq("метка первого варианта на месте", sim.result()["marks"], ["took_copy"])

	_to_window(sim)
	t.is_true("окно второго варианта открылось", sim.current_window != null)
	var second: Dictionary = sim.order("answer")
	t.is_true("второй вариант принят", second["accepted"])
	var out: Dictionary = sim.result()
	## Непустота полей — отдельные ассерты: сверка `marks` с пустым списком приняла бы
	## «метки не доехали» за «меток нет».
	t.is_true("в отчёте есть поле money", out.has("money"))
	t.is_true("в отчёте есть поле trace", out.has("trace"))
	t.is_true("в отчёте есть поле marks", out.has("marks"))
	t.eq("счётчик денег дошёл до результата", int(out["money"]), 55)
	t.eq("счётчик следа дошёл до результата", int(out["trace"]), 13)
	t.eq("метки в результате отсортированы по алфавиту", out["marks"], ["saw_answer", "took_copy"])
	## Сортировка идёт по КОПИИ: отчёт не имеет права переставлять состояние Sim,
	## иначе следующий вызов `result()` вернул бы другую историю.
	t.eq("сортировка отчёта не тронула порядок постановки", sim.marks, ["took_copy", "saw_answer"])

	## Метка — факт, а не счётчик: повтор имени не двоит запись, а имя без имени
	## меткой не является (это ошибка формы, а не метка).
	var dup = _make(_solo(3), [
		_window("hall", [_option("a", 1, [
			{"type": "mark"}, {"type": "mark", "id": "same"}])]),
		_window("cellar", [_option("b", 1, [{"type": "mark", "id": "same"}])]),
	])
	_to_window(dup)
	dup.order("a")
	_to_window(dup)
	dup.order("b")
	t.eq("повтор метки не двоит запись, метка без имени не ставится", dup.result()["marks"], ["same"])


## Эффекты живут в ТРЁХ местах: вариант окна, четыре исхода молчания, `fallback` заявки
## движку. Место применения обязано быть одно (`sim.gd:_apply_effect`), иначе «форма
## принимает, а ядро не считает» повторится в одном из мест молча.
func _effects_everywhere(t) -> void:
	var sim = _make(_solo(3), [
		_window("hall", [_option("ask", 1, [
			{"type": "engine_proposal", "fallback": [
				{"type": "money", "value": 11},
				{"type": "mark", "id": "proposal"}]}])]),
		_window("cellar", [_option("open", 1, [])], {
			"text_key": "window.silence",
			"good": [],
			"neutral": [],
			"bad": [],
			"safe": [
				{"type": "money", "value": 7},
				{"type": "trace", "value": 2},
				{"type": "mark", "id": "waited"}],
		}),
	])
	_to_window(sim)
	t.is_true("окно заявки открылось", sim.current_window != null)
	var asked: Dictionary = sim.order("ask")
	t.is_true("заявка принята", asked["accepted"])
	t.eq("fallback заявки накопил деньги", int(sim.money), 11)
	t.eq("fallback заявки поставил метку", sim.result()["marks"], ["proposal"])

	_to_window(sim)
	t.is_true("окно молчания открылось", sim.current_window != null)
	var silent: Dictionary = sim.order("silence")
	t.is_true("молчание принято", silent["accepted"])
	t.eq("молчание решено тактиком безопасно", String(silent["effect"]["quality"]), "safe")
	t.eq("эффекты исхода молчания накоплены", [int(sim.money), int(sim.trace)], [18, 2])
	t.eq("метка исхода молчания на месте", sim.result()["marks"], ["proposal", "waited"])


# ---------------------------------------------------------------- D50: экранированная зона

## Пока хотя бы один ЖИВОЙ свой в экранированном помещении, приказ не проходит: причина
## отказа `shielded`, окно остаётся и миссию не ломает, а «пока» — не навсегда.
##
## Блок идёт по одной линии тремя окнами: холл (вне зоны) → подвал (зона) → цель (снова
## вне зоны). Половина «вне зоны приказ проходит» здесь несущая: без неё отказ в зоне
## ничего не доказывал бы — он мог бы приходить по любой другой причине.
func _shielded_zone(t) -> void:
	var sim = _make(_solo(3), [
		_window("hall", [_option("go_hall", 1, [{"type": "mark", "id": "before_zone"}])]),
		_window("cellar", [_option("go_cellar", 1, [{"type": "mark", "id": "zone_ignored"}])]),
		_window("deep", [_option("go_deep", 1, [{"type": "mark", "id": "after_zone"}])]),
	], true)

	# 1. Вне зоны.
	_to_window(sim)
	t.is_true("окно вне зоны открылось", sim.current_window != null)
	t.is_true("вне зоны говорить можно", sim.radio.can_speak(sim.scales.step))
	var outside: Dictionary = sim.order("go_hall")
	t.is_true("вне зоны приказ проходит", outside["accepted"])

	# 2. Зона.
	_to_window(sim)
	t.is_true("окно в экранированной зоне открылось", sim.current_window != null)
	t.eq("окно открылось именно в подвале", String(sim.current_window.get("node", "")), "cellar")
	t.is_false("в экранированной зоне говорить нельзя", sim.radio.can_speak(sim.scales.step))
	## Пул и эфир сверяются ДО/ПОСЛЕ, а не абсолютом: до зоны приказ в холле прошёл,
	## и абсолютное «пул цел» показывало бы не отказ в зоне, а всю историю окна.
	var orders_before: int = sim.orders_left
	var radio_before: int = sim.radio.radio
	var refused: Dictionary = sim.order("go_cellar")
	t.is_false("в экранированной зоне приказ не проходит", bool(refused.get("accepted", true)))
	## `reason` читается через `has`/`get`, а не по ключу: у ПРИНЯТОГО приказа этого поля нет
	## вовсе, и `refused["reason"]` обрывал бы `_shielded_zone` рантайм-сбоем — вместе со всеми
	## ассертами блока (M1 ревью 01–04: 18 из 74 пропадали молча). Сломанное правило обязано
	## называться провалом, а не съедать доказательства.
	t.is_true("отказ приказа несёт причину (`reason`)", refused.has("reason"))
	t.eq("причина отказа — экранирование", String(refused.get("reason", "")), "shielded")
	t.eq("отказ в зоне назван событием с той же причиной", _refused_reasons(sim), ["shielded"])
	t.is_true("окно в зоне не пропало", sim.current_window != null)
	t.eq("приказ в зоне не потрачен", sim.orders_left, orders_before)
	t.eq("в зоне эфир не вырос", sim.radio.radio, radio_before)
	## Отказ не применяет эффекты варианта: метка `zone_ignored` появиться не имеет права.
	t.eq("отказ не применил эффекты варианта", sim.result()["marks"], ["before_zone"])

	# 3. Молчание в зоне проходит: зона отнимает голос, а не решение (D37).
	var silent: Dictionary = sim.order("silence")
	t.is_true("молчание в зоне принято", silent["accepted"])
	t.is_true("окно в зоне закрылось молчанием", sim.current_window == null)
	t.is_false("молчание в зоне не сломало миссию", sim.finished)

	# 4. «Пока»: вышли из зоны — голос вернулся. Иначе признак зоны был бы липким.
	_to_window(sim)
	t.is_true("окно после зоны открылось", sim.current_window != null)
	t.is_true("из зоны голос вернулся", sim.radio.can_speak(sim.scales.step))
	var after: Dictionary = sim.order("go_deep")
	t.is_true("после зоны приказ проходит", after["accepted"])
	t.eq("после зоны метка поставлена", sim.result()["marks"], ["after_zone", "before_zone"])

	# 5. Мёртвый в зоне голоса не отнимает: правило — про ЖИВОГО своего. Позиции ставятся
	# прямо: разделить группу по разным помещениям ядро умеет только смертью бойца,
	# а проверяется здесь именно признак «живой», а не маршрут.
	var pair = _make([
		{"id": "kira", "role": "tactician", "understanding": 3},
		{"id": "echo", "role": "tactician", "understanding": 3},
	], [_window("hall", [_option("go", 1, [])])], true)
	_to_window(pair)
	t.is_true("окно у пары открылось", pair.current_window != null)
	for i in 3:
		pair._compromise(pair.own[0])
	pair.own[0].node = "cellar"   # труп в экранированной зоне
	pair.own[1].node = "hall"     # живой вне зоны
	t.is_true("в отчёте о позициях виден и труп, и живой",
		String(pair.result()["positions"]["kira"]) == "cellar"
		and String(pair.result()["positions"]["echo"]) == "hall")
	t.is_false("труп в зоне зоны не создаёт", pair.in_shielded_zone())
	t.is_true("мёртвый в зоне голоса не отнимает", pair.order("go")["accepted"])
	pair.own[1].node = "cellar"
	t.is_true("живой в зоне зону создаёт", pair.in_shielded_zone())


## D50, ВТОРАЯ ПОЛОВИНА: зона гасит голос, когда в ней ЖИВОЙ СВОЙ, и НЕ гасит, когда там
## только ОХРАНА. Правило — про своих (`sim.gd:in_shielded_zone` обходит `own`), и вторая
## половина несущая: без неё «в зоне приказ не проходит» ничего не доказывало бы — отказ
## приходил бы по любой причине, а экранированное помещение с патрулём глушило бы связь
## там, где своих нет.
##
## Обе половины стоят на ОДНОМ полигоне (тег `shielded` у `cellar`), различаясь только тем,
## кто в зоне: охрана (приказ проходит) или свой (приказ глушится). Проба, сломавшая
## правило обходом `guards` в `in_shielded_zone`, краснит первый ассерт по имени.
func _shielded_zone_guards(t) -> void:
	# 1. Охрана в зоне, свои снаружи: голос есть, приказ проходит.
	var with_guard = _make(_solo(3),
		[_window("hall", [_option("go", 1, [{"type": "mark", "id": "sent"}])])],
		true, [{"id": "guard_1", "route": ["cellar"], "period": 4}])
	_to_window(with_guard)
	t.is_true("окно при охране в зоне открылось", with_guard.current_window != null)
	t.eq("охрана стоит в экранированном помещении", String(with_guard.guards[0].node), "cellar")
	t.is_true("свои — вне зоны", not with_guard.in_shielded_zone())
	t.is_true("охрана в зоне голоса не отнимает", with_guard.radio.can_speak(with_guard.scales.step))
	var guarded: Dictionary = with_guard.order("go")
	t.is_true("приказ при охране в экранированной зоне проходит", bool(guarded.get("accepted", false)))
	t.eq("приказ при охране в зоне исполнен", with_guard.result()["marks"], ["sent"])

	# 2. Та же зона, но в ней СВОЙ (охрана — вне): приказ не проходит. Это не повтор
	# блока `_shielded_zone`, а его вторая половина сравнения: различается РОВНО состав зоны.
	var own_in_zone = _make(_solo(3),
		[_window("hall", [_option("go", 1, [{"type": "mark", "id": "sent"}])])],
		true, [{"id": "guard_1", "route": ["deep"], "period": 4}])
	_to_window(own_in_zone)
	own_in_zone.own[0].node = "cellar"   # свой в экранированном помещении
	own_in_zone._refresh_shield()
	t.is_true("свой в зоне — признак зоны поднят", own_in_zone.in_shielded_zone())
	t.is_false("свой в зоне — говорить нельзя", own_in_zone.radio.can_speak(own_in_zone.scales.step))
	var refused: Dictionary = own_in_zone.order("go")
	t.is_false("свой в экранированной зоне — приказ не проходит", bool(refused.get("accepted", true)))
	t.eq("свой в зоне — причина отказа `shielded`", String(refused.get("reason", "")), "shielded")
	t.eq("свой в зоне — эффекты варианта не применены", own_in_zone.result()["marks"], [])


# ---------------------------------------------------------------- Детерминизм

## ДЕТЕРМИНИЗМ СЧЁТЧИКОВ И МЕТОК — свой ассерт, отдельный от отпечатка. `Harness.digest`
## счётчики не описывает намеренно (решение ведущего, леджер §2.2): он — СОСТОЯНИЕ
## (позиции, исход, шаги), и расширять его ради новых полей значило бы ломать чужие
## ожидания. Значит, детерминизм `money`/`trace`/`marks` обязан проверяться ЗДЕСЬ:
## два одинаковых прогона (те же данные, тот же seed) дают те же значения.
##
## Прогон ПОЛНЫЙ и со связистом: молчание решает кубик `rng`, засеянный из `config.seed`,
## то есть проверяется детерминизм вместе со случайностью, а не вместо неё.
func _determinism(t) -> void:
	var first := _full_run()
	var second := _full_run()
	## Невырожденность: сравнение нулей с нулями ничего не проверяет, и без этих трёх
	## ассертов «детерминизм» держался бы на пустых значениях.
	t.is_true("прогон накопил деньги (сравнение не вырождено)", int(first["money"]) > 0)
	t.is_true("прогон накопил след (сравнение не вырождено)", int(first["trace"]) > 0)
	t.is_true("прогон поставил метки (сравнение не вырождено)", (first["marks"] as Array).size() > 0)
	t.eq("два одинаковых прогона — те же деньги", int(second["money"]), int(first["money"]))
	t.eq("два одинаковых прогона — тот же след", int(second["trace"]), int(first["trace"]))
	t.eq("два одинаковых прогона — те же метки", second["marks"], first["marks"])


## Полный прогон полигона до конца миссии: вариант в холле (счётчики и метка) и молчание
## в подвале (кубик связиста, исход которого ставит ещё одну метку). Возвращает `result()`.
func _full_run() -> Dictionary:
	var sim = _make([
		{"id": "kira", "role": "tactician", "understanding": 3},
		{"id": "echo", "role": "comms", "understanding": 3},
	], [
		_window("hall", [_option("copy", 1, [
			{"type": "money", "value": 15},
			{"type": "trace", "value": 5},
			{"type": "mark", "id": "took_copy"}])]),
		_window("cellar", [_option("open", 1, [])], {
			"text_key": "window.silence",
			"good": [{"type": "mark", "id": "went_good"}],
			"neutral": [{"type": "mark", "id": "went_neutral"}],
			"bad": [{"type": "mark", "id": "went_bad"}],
			"safe": [{"type": "mark", "id": "waited"}],
		}),
	])
	_to_window(sim)
	sim.order("copy")
	_to_window(sim)
	sim.order("silence")
	## До конца миссии: сторож — от вечного цикла, если маршрут отхода не сойдётся.
	for i in 40:
		if sim.finished:
			break
		sim.advance()
	return sim.result()


# ---------------------------------------------------------------- D51: Понимание

## Один приказ одного варианта: что он сделал с ценой.
##
## Шум сверяется ПРИРАЩЕНИЕМ (от значения перед приказом), а не абсолютом: у полигона
## рёбра без шума, но проверка не должна зависеть от того, сколько шума набрал путь.
## `kill` — id бойцов, которых до приказа доводят до смерти (проверка «живых»).
func _order_case(agents: Array, complexity: int, kill: Array = []) -> Dictionary:
	var sim = _make(agents, [_window("hall", [
		_option("go", complexity, [{"type": "mark", "id": "executed"}])])])
	_to_window(sim)
	if sim.current_window == null:
		return {"window": false}
	for id in kill:
		for a in sim.own:
			if String(a.id) == String(id):
				for i in 3:
					sim._compromise(a)
	var noise_before: int = sim.scales.noise
	var res: Dictionary = sim.order("go")
	return {
		"window": true,
		"accepted": bool(res["accepted"]),
		"noise": int(sim.scales.noise) - noise_before,
		"delay": int(sim.own[0].delay),
		"literal": _literal_event(sim),
		"marks": sim.result()["marks"],
	}


## Понимание окна — МИНИМУМ по живым своим; если сложность варианта больше, вариант
## исполняется, но к цене добавляется детерминированная надбавка (D31 — без кубика).
## Числа — таблица `docs/spr/mercs.md` §1; здесь сверяются её края и граница правила.
func _understanding(t) -> void:
	# 1. Граница: сложность РАВНА Пониманию — уже не буквально. Без этой половины
	# кейс не отличал бы «строго больше» от «больше или равно».
	var boundary = _order_case(_solo(3), 3)
	t.is_true("окно граничного случая открылось", bool(boundary["window"]))
	t.is_true("граничный приказ принят", bool(boundary["accepted"]))
	t.eq("сложность равна Пониманию — без надбавки: шум", int(boundary["noise"]), 0)
	t.eq("сложность равна Пониманию — без надбавки: задержка", int(boundary["delay"]), 0)
	t.eq("сложность равна Пониманию — события буквальности нет", boundary["literal"], {})

	# 2. Слабее сложности — буквально: цена растёт по таблице.
	var weak = _order_case(_solo(1), 3)
	t.is_true("приказ слабого бойца принят", bool(weak["accepted"]))
	t.eq("буквальное исполнение добавило шум", int(weak["noise"]), 6)
	t.eq("буквальное исполнение добавило задержку", int(weak["delay"]), 2)
	t.eq("буквальность — не провал: вариант исполнен", weak["marks"], ["executed"])
	t.eq("событие буквальности называет разрыв", weak["literal"], {
		"window": "node_entered:hall",
		"option": "go",
		"complexity": 3,
		"understanding": 1,
		"noise": 6,
		"delay": 2,
	})

	# 3. Края таблицы: разрыв 1 и разрыв 3. Обе половины нужны, иначе надбавка
	# могла бы оказаться константой «на любой разрыв», и таблица в справочнике соврала бы.
	var gap_one = _order_case(_solo(1), 2)
	t.is_true("приказ с разрывом 1 принят", bool(gap_one["accepted"]))
	t.eq("разрыв 1 — надбавка 3/1 (mercs.md §1)",
		[int(gap_one["noise"]), int(gap_one["delay"])], [3, 1])
	var gap_three = _order_case(_solo(0), 3)
	t.is_true("приказ с разрывом 3 принят", bool(gap_three["accepted"]))
	t.eq("разрыв 3 — надбавка 9/3 (mercs.md §1)",
		[int(gap_three["noise"]), int(gap_three["delay"])], [9, 3])

	# 4. Исполняет САМОЕ СЛАБОЕ звено: пара «сильный + слабый» на сложном приказе
	# буквальна, хотя сильный сам бы справился. Это и есть «минимум по живым своим».
	var mixed = _order_case([
		{"id": "kira", "role": "tactician", "understanding": 3},
		{"id": "echo", "role": "comms", "understanding": 1},
	], 3)
	t.is_true("приказ пары принят", bool(mixed["accepted"]))
	t.eq("минимум по живым своим: слабое звено решает", int(mixed["noise"]), 6)
	t.eq("надбавку платит актор окна", int(mixed["delay"]), 2)

	# 5. Мёртвое звено не считает: та же пара, слабый убит — надбавки нет.
	var with_dead = _order_case([
		{"id": "kira", "role": "tactician", "understanding": 3},
		{"id": "echo", "role": "comms", "understanding": 1},
	], 3, ["echo"])
	t.is_true("приказ пары с убитым слабым принят", bool(with_dead["accepted"]))
	t.eq("мёртвое звено в Понимании не считается", int(with_dead["noise"]), 0)
	t.eq("мёртвое звено — и события буквальности нет", with_dead["literal"], {})

	# 6. Живых нет — исполнять некому: приказ принимается, надбавки нет.
	var nobody = _order_case(_solo(3), 3, ["kira"])
	t.is_true("приказ без живых принят", bool(nobody["accepted"]))
	t.eq("некому исполнять — надбавки нет", int(nobody["noise"]), 0)
	t.eq("некому исполнять — события нет", nobody["literal"], {})

	# 7. Сам расчёт надбавки, без окна: граница и разрыв 2 — прямо по функции.
	t.eq("Понял точно — цены нет", Understanding.literal_cost(2, 3), {})
	t.eq("разрыв 2 — цена 6/2 (mercs.md §1)",
		Understanding.literal_cost(3, 1), {"noise": 6, "delay": 2})


# ---------------------------------------------------------------- мелочи

## Данные события `order_literal`, если оно было. Пусто — буквальности не случилось.
func _literal_event(sim) -> Dictionary:
	for e in sim.events:
		if String(e["type"]) == "order_literal":
			return e["data"]
	return {}


## Причины отказов приказа по порядку. Причина — часть контракта отказа: по ней
## презентация отличает мёртвый эфир в зоне от глушения каналом и от пустого пула.
func _refused_reasons(sim) -> Array:
	var out: Array = []
	for e in sim.events:
		if String(e["type"]) == "order_refused":
			out.append(String(e["data"]["reason"]))
	return out

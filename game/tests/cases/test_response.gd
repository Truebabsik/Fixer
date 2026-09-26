extends RefCounted
## Тревога — перелом (D16). Из подвала уйти можно, с 4-го этажа — нет.

const Assert := preload("res://tests/assert.gd")
const Fixture := preload("res://tests/fixtures/small_mission.gd")
const Plan := preload("res://sim/plan.gd")
const Response := preload("res://sim/response.gd")
const Sim := preload("res://sim/sim.gd")


func _make(route: Array):
	var m = Fixture.build()
	var p := Plan.new()
	p.route = route
	p.exit_node = "dock"
	p.agents = [{"id": "kira", "role": "tactician", "understanding": 3}]
	var sim := Sim.new()
	# noise_start = 25: тревога взводится на первом же шаге
	sim.setup(m, p, {"orders": 3, "seed": 1, "noise_start": 25})
	return sim


func _run_until_end(sim, limit := 60) -> void:
	var i := 0
	while not sim.finished and i < limit:
		sim.advance()
		i += 1


func _has(sim, type: String) -> bool:
	for e in sim.events:
		if String(e["type"]) == type:
			return true
	return false


func run() -> Array:
	var t := Assert.new()

	# 1. Тревога взводится сама и блокирует пассажирский лифт.
	# Маршрут начинается в холле, а не на выходе: агенту нужно куда-то идти,
	# чтобы было видно, как тревога перекрывает пути.
	var rise = _make(["hall"])
	rise.advance()
	t.is_true("тревога взведена", rise.response.active)
	t.is_true("пассажирский лифт закрыт", rise.response.edge_blocked("lift_main", rise.scales.step))
	t.is_false("лестница открыта", rise.response.edge_blocked("stairs", rise.scales.step))
	t.is_true("грузовой пока жив", not rise.response.edge_blocked("lift_freight", rise.scales.step))
	for i in 4:
		rise.advance()
	t.is_true("грузовой закрылся с задержкой", rise.response.edge_blocked("lift_freight", rise.scales.step))

	# 2. Из подвала уходим грузовым лифтом до прибытия группы.
	var away = _make(["dock", "archive0"])
	_run_until_end(away)
	t.is_true("цель взята", away.result()["objective_done"])
	t.eq("исход — ушли", String(away.result()["outcome"]), "extracted")
	t.is_true("группа ещё не приехала", away.scales.step < 11)

	# 3. С 4-го этажа пешком не успеть: лифт закрыт, лестница длинная.
	var stuck = _make(["dock", "hall", "it4"])
	_run_until_end(stuck)
	t.is_true("упёрлись в закрытый лифт", _has(stuck, "path_blocked"))
	t.eq("исход — накрыли", String(stuck.result()["outcome"]), "caught")
	t.is_true("группа приехала", stuck.response.has_arrived(stuck.scales.step))

	# 4. Без тревоги лифт работает.
	var calm = _make(["dock", "hall", "it4"])
	calm.scales.noise = 0
	for i in 5:
		calm.advance()
	t.eq("до тревоги лифт довёз", calm.own[0].node, "it4")

	# 5. Все погибли — это НЕ успешный уход, даже если цель взята.
	# Мёртвые пропускаются в проверке «все на выходе», поэтому без счётчика живых
	# полностью погибшая группа проходила бы как extracted.
	var lost = _make(["dock"])
	lost.objective_done = true
	for i in 3:
		lost.own[0].add_trigger()
	lost._check_end()
	t.is_true("боец мёртв", lost.own[0].is_dead())
	t.is_false("все погибшие — не extracted", String(lost.result()["outcome"]) == "extracted")

	# 6. Границы чисел закреплены напрямую: ARRIVE_STEPS = 10, FREIGHT_GRACE = 3.
	# Без этих проверок значения констант можно было менять, оставаясь зелёным.
	var resp := Response.new()
	resp.engage(5)
	t.is_true("грузовой открыт на тревоге +3", not resp.edge_blocked("lift_freight", 8))
	t.is_true("грузовой закрыт на тревоге +4", resp.edge_blocked("lift_freight", 9))
	t.is_false("группа не приехала на тревоге +9", resp.has_arrived(14))
	t.is_true("группа приехала на тревоге +10", resp.has_arrived(15))

	# 7. Перехват эфира ускоряет выезд ровно на 3 шага (design.md §13.7, D33).
	# Правило описано и в дизайне, и в D33, но до этой правки в sim.gd не читалось
	# вовсе: перехват вёл бухгалтерию и не имел последствий.
	t.is_false("без перехвата на тревоге +6 рано", resp.has_arrived(11, false))
	t.is_false("с перехватом на тревоге +6 ещё рано", resp.has_arrived(11, true))
	t.is_true("с перехватом на тревоге +7 уже приехали", resp.has_arrived(12, true))
	t.is_false("без перехвата на тревоге +7 ещё нет", resp.has_arrived(12, false))
	t.is_true("без перехвата на тревоге +10 приехали", resp.has_arrived(15, false))

	# 8. Проводка перехвата в sim.gd: с отпечатком 3 миссия накрывается тремя
	# шагами раньше. Без этой проверки `has_arrived(step, intercepted)` мог бы
	# существовать, а ядро — по-прежнему не спрашивать радио (ровно тот дефект,
	# ради которого правило и заводилось). Перехвата здесь не «добывается» тремя
	# приказами, а ставится признак на шкале: проверяется проводка, не эфир.
	# Тревога взводится на первом шаге, значит перехват накрывает на шаге 8
	# (тревога +7), а без перехвата — на шаге 11 (тревога +10).
	var fast = _make(["hall"])
	fast.radio.imprint = 3
	fast.advance()
	t.is_true("тревога взведена", fast.response.active)
	t.eq("тревога взведена на шаге 1", fast.response.alarm_step, 1)
	for i in 7:
		fast.advance()
	t.eq("миссия дошла до тревоги +7", fast.scales.step, 8)
	t.is_true("с перехватом группа уже приехала", fast.response.has_arrived(fast.scales.step, fast.radio.is_intercepted()))
	t.eq("перехват накрыл миссию", String(fast.result()["outcome"]), "caught")
	t.eq("накрытие случилось на тревоге +7", fast.scales.step - 1, 7)

	var slow = _make(["hall"])
	slow.advance()
	for i in 7:
		slow.advance()
	t.eq("без перехвата миссия дошла до того же шага", slow.scales.step, 8)
	t.is_false("без перехвата группа ещё не приехала", slow.response.has_arrived(slow.scales.step, slow.radio.is_intercepted()))
	t.eq("без перехвата миссия ещё идёт", String(slow.result()["outcome"]), "")

	return t.results

extends RefCounted
## Движение по маршруту, стоимость переходов в шуме, автопауза.

const Assert := preload("res://tests/assert.gd")
const Fixture := preload("res://tests/fixtures/small_mission.gd")
const Mission := preload("res://sim/mission.gd")
const Plan := preload("res://sim/plan.gd")
const Sim := preload("res://sim/sim.gd")


## Аннотации типов у параметров нет намеренно: хелпер отдаёт sim без типа,
## и обращение к нему динамическое, как в остальных кейсах. `exit_node` и `agents`
## параметрами, потому что кейс отхода проверяет выход, НЕ смежный цели, и отстающего бойца.
func _make(route: Array, exit_node := "dock", agents = null):
	var m = Fixture.build()
	var p := Plan.new()
	p.route = route
	p.exit_node = exit_node
	p.exit_backup_node = exit_node
	p.agents = agents if agents != null else [{"id": "kira", "role": "tactician", "understanding": 3}]
	var sim := Sim.new()
	sim.setup(m, p, {"orders": 3, "seed": 1})
	return sim


func run() -> Array:
	var t := Assert.new()

	# 1. Лестница: hall -> office2 стоит 3 шага.
	# Патруль уводим: кейс про цену перехода. С Task 10 контакт с охраной ранит
	# бойца в холле, добавляет 5 шума и +1 шаг к следующему переходу — цена
	# перехода перестала бы быть измеримой. Контакты проверяет test_casualties.gd.
	var sim = _make(["dock", "hall", "office2"])
	sim.guards = []
	sim.advance()
	t.eq("один шаг — один тик часов", sim.scales.step, 1)
	t.eq("переход в холл — 1 шаг", sim.own[0].node, "hall")
	t.eq("шум перехода в холл нулевой", sim.scales.noise, 0)

	for i in 3:
		sim.advance()
	t.eq("лестница — 3 шага", sim.own[0].node, "office2")
	t.eq("шум лестницы нулевой", sim.scales.noise, 0)

	# 2. Лифт: hall -> it4 стоит 2 шага и 4 шума. Охрану уводим — см. пункт 1.
	var sim2 = _make(["dock", "hall", "it4"])
	sim2.guards = []
	for i in 5:
		sim2.advance()
	t.eq("лифт довёз", sim2.own[0].node, "it4")
	t.eq("шум лифта на виду", sim2.scales.noise, 4)

	# 3. Раненый идёт медленнее: штраф +1 шаг на переход.
	var sim3 = _make(["dock", "hall"])
	sim3.own[0].add_trigger()
	sim3.advance()
	t.eq("первый шаг потрачен", sim3.own[0].node, "dock")
	sim3.advance()
	t.eq("раненый дошёл за 2 шага вместо 1", sim3.own[0].node, "hall")

	# 4. Автопауза: при открытом окне мир не двигается.
	var sim4 = _make(["dock", "hall"])
	sim4.advance()
	sim4.current_window = {"id": "w1", "kind": "locked_door", "options": []}
	var before: int = sim4.scales.step
	var ev: Array = sim4.advance()
	t.eq("мир замер", sim4.scales.step, before)
	t.eq("событий нет", ev.size(), 0)

	# 5. Охрана ходит по маршруту с заданным периодом.
	var sim5 = _make(["dock"])
	t.eq("охрана на первом узле", sim5.guards[0].node, "hall")
	sim5.advance()
	sim5.advance()
	t.eq("через период охрана ушла на второй узел", sim5.guards[0].node, "office2")

	# 6. Штраф скорости по состояниям: OK — 0, WOUNDED — +1, CRITICAL — +2.
	# CRITICAL не был закреплён ничем: `speed_penalty` мог вернуть 1, и все
	# проверки набора оставались зелёными.
	var pen = _make(["dock", "hall"])
	var own_agent = pen.own[0]
	t.eq("здоровый идёт без штрафа", own_agent.speed_penalty(), 0)
	own_agent.add_trigger()
	t.eq("раненый: штраф +1", own_agent.speed_penalty(), 1)
	own_agent.add_trigger()
	t.eq("тяжёлый: штраф +2", own_agent.speed_penalty(), 2)
	# И это видно в шагах: переход dock -> hall стоит 1 + 2 = 3 шага.
	pen.advance()
	t.eq("тяжёлый не прошёл и половины", pen.own[0].node, "dock")
	pen.advance()
	t.eq("тяжёлый всё ещё идёт", pen.own[0].node, "dock")
	pen.advance()
	t.eq("тяжёлый дошёл за три шага вместо одного", pen.own[0].node, "hall")

	# 7. Отход после взятой цели: группа идёт к выходу ОБРАТНЫМ ПУТЁМ, а не одним ребром
	# «цель → выход». Прежняя строка `waypoints = [b.node, plan.exit_node]` работала только
	# тогда, когда выход смежен цели; здесь выход `office2` с целью `archive0` не смежен
	# (у `archive0` соседи `dock` и `hall`), ребра `archive0 → office2` нет, и группа
	# оставалась в архиве до `timeout` — поиска пути в ядре нет.
	#
	# Маршрут входит в цель со стороны `hall`, то есть НЕ со стороны выхода, и второй боец
	# намеренно отстаёт: путь каждому строится от его собственного узла, а не от узла того,
	# кто взял цель. Охрану уводим: кейс про путь отхода, а контакт ранит и добавляет шум
	# (см. пункт 1).
	var home = _make(["dock", "hall", "office2", "hall", "archive0"], "office2", [
		{"id": "kira", "role": "tactician", "understanding": 3},
		{"id": "echo", "role": "comms", "understanding": 3},
	])
	home.guards = []
	home.own[1].delay = 2
	for i in 10:
		home.advance()
	t.is_true("цель взята: в архив вошли со стороны hall, а выход — office2", home.objective_done)
	t.eq("первый стоит в цели", home.own[0].node, "archive0")
	t.eq("отставший ждёт в hall, а не в цели", home.own[1].node, "hall")
	## Сторож вырожденности: маршрута «archive0 → office2» нет, иначе кейс не отличался бы
	## от прежнего поведения и не покраснел бы на возврате одного ребра.
	t.is_true("ребра «цель → выход» нет: прямой отрезок невозможен",
		home.mission.edge_between("archive0", "office2").is_empty())
	for i in 6:
		home.advance()
	t.eq("вошедший к цели не со стороны выхода дошёл до выхода", home.own[0].node, "office2")
	t.eq("отставший дошёл до выхода своим путём", home.own[1].node, "office2")
	t.eq("миссия завершилась уходом", String(home.result()["outcome"]), "extracted")

	# 8. Выход в СЕРЕДИНЕ маршрута: ведущий идёт к нему назад, отставший — вперёд, и оба
	# пути кончаются НА выходе. Это проверка двух свойств сразу: путь строится от узла
	# каждого (правило 2), а дойдя до выхода группа останавливается (правило 3) — иначе
	# передний ушёл бы дальше, пока отставший только подходит, и на выходе они не сошлись бы.
	# В фикстуре выхода в середине маршрута нет: там любой узел — сосед одного из концов,
	# и «идти вперёд» неотличимо от «дойти по одному ребру».
	var corridor = _make_corridor("b", 5)
	for i in 7:
		corridor.advance()
	t.is_true("цель взята ведущим", corridor.objective_done)
	t.eq("ведущий ждёт на выходе", corridor.own[0].node, "b")
	t.eq("отставший дошёл до выхода вперёд по маршруту", corridor.own[1].node, "b")
	t.eq("миссия завершилась уходом", String(corridor.result()["outcome"]), "extracted")

	# 9. Выход ВНЕ маршрута, но смежен узлу входа: группа доходит обратным путём до входа и
	# «хвостом» от входа к выходу. Это вторая половина требования к отходу: выход не обязан
	# лежать на маршруте — но выразить его можно только ребром от входа, потому что поиска
	# пути в ядре нет.
	var outside = _make_corridor("z", 5)
	t.is_false("выхода нет ни в маршруте, ни рядом с целью",
		(outside.plan.route as Array).has("z") or not outside.mission.edge_between("goal", "z").is_empty())
	t.is_true("от входа к выходу ребро есть",
		not outside.mission.edge_between("start", "z").is_empty())
	for i in 9:
		outside.advance()
	t.eq("ведущий дошёл до выхода вне маршрута", outside.own[0].node, "z")
	t.eq("отставший ждёт его на выходе", outside.own[1].node, "z")
	t.eq("миссия завершилась уходом", String(outside.result()["outcome"]), "extracted")

	return t.results


## Мини-миссия «коридор»: `start → a → b → c → goal`, цель `goal`, выход задаётся
## параметром. Нужна там, где выход лежит в СЕРЕДИНЕ маршрута: он не сосед ни цели, ни узла
## входа, поэтому годятся только правила 2 и 3 отхода, а не прямое ребро.
## Узел `z` висит на входе отдельным ребром и в маршрут не входит: это выход «вне маршрута»
## для правила 4 (хвост от узла входа).
## `second_delay` — насколько отстаёт второй боец: он должен стоять ДО выхода в момент
## взятия цели, иначе проверяется не тот случай.
func _make_corridor(exit_node: String, second_delay: int):
	var m := Mission.new()
	m.id = "corridor"
	for node_id in ["start", "a", "b", "c", "goal", "z"]:
		m.add_node(String(node_id), 1, [])
	m.add_edge("e_start_a", "start", "a", "corridor", 1, 0)
	m.add_edge("e_a_b", "a", "b", "corridor", 1, 0)
	m.add_edge("e_b_c", "b", "c", "corridor", 1, 0)
	m.add_edge("e_c_goal", "c", "goal", "corridor", 1, 0)
	m.add_edge("e_start_z", "start", "z", "corridor", 1, 0)
	m.objective = "goal"
	var p := Plan.new()
	p.route = ["start", "a", "b", "c", "goal"]
	p.exit_node = exit_node
	p.agents = [
		{"id": "kira", "role": "tactician", "understanding": 3},
		{"id": "echo", "role": "comms", "understanding": 3},
	]
	var sim := Sim.new()
	sim.setup(m, p, {"orders": 3, "seed": 1})
	sim.own[1].delay = int(second_delay)
	return sim

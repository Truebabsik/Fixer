extends RefCounted
## Движение по маршруту, стоимость переходов в шуме, автопауза.

const Assert := preload("res://tests/assert.gd")
const Fixture := preload("res://tests/fixtures/small_mission.gd")
const Plan := preload("res://sim/plan.gd")
const Sim := preload("res://sim/sim.gd")


func _make(route: Array):
	var m = Fixture.build()
	var p := Plan.new()
	p.route = route
	p.exit_node = "dock"
	p.exit_backup_node = "hall"
	p.agents = [{"id": "kira", "role": "tactician", "understanding": 3}]
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

	return t.results

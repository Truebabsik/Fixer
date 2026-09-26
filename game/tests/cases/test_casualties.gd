extends RefCounted
## Ранения и порог смерти. Один промах не убивает — ни при каких настройках.

const Assert := preload("res://tests/assert.gd")
const Fixture := preload("res://tests/fixtures/small_mission.gd")
const Plan := preload("res://sim/plan.gd")
const Sim := preload("res://sim/sim.gd")
const Agent := preload("res://sim/agent.gd")


func _make(route: Array):
	var m = Fixture.build()
	var p := Plan.new()
	p.route = route
	p.exit_node = "dock"
	p.agents = [{"id": "kira", "role": "tactician", "understanding": 3}]
	var sim := Sim.new()
	sim.setup(m, p, {"orders": 3, "seed": 1})
	return sim


func run() -> Array:
	var t := Assert.new()
	var sim = _make(["dock"])

	# 1. Один триггер — ранение, не смерть.
	sim._compromise(sim.own[0])
	t.eq("состояние — ранен", sim.own[0].state, Agent.State.WOUNDED)
	t.is_false("после одного промаха не мёртв", sim.own[0].is_dead())

	# 2. Два — тяжёлый.
	sim._compromise(sim.own[0])
	t.eq("состояние — тяжёлый", sim.own[0].state, Agent.State.CRITICAL)
	t.is_false("и всё ещё жив", sim.own[0].is_dead())

	# 3. Три — смерть, и только тогда.
	sim._compromise(sim.own[0])
	t.eq("состояние — мёртв", sim.own[0].state, Agent.State.DEAD)
	t.is_true("мёртв", sim.own[0].is_dead())

	# 4. Свидетель шумит.
	t.eq("шум от трёх свидетелей", sim.scales.noise, 15)

	# 5. Отчёт миссии называет раненых и мёртвых.
	var rep: Dictionary = sim.result()
	t.is_true("мёртвый в отчёте", rep["dead"].has("kira"))
	t.eq("раненых нет — он уже мёртв", rep["injured"].size(), 0)

	# 6. Раненый движется медленнее и не успевает за здоровым.
	var slow = _make(["dock", "hall"])
	slow.own[0].add_trigger()
	slow.advance()
	t.eq("половина перехода позади", slow.own[0].node, "dock")
	slow.advance()
	t.eq("раненый дошёл за два шага", slow.own[0].node, "hall")

	# 7. Живой и вышедший попадает в escaped.
	var out = _make(["dock"])
	out.objective_done = true
	out._check_end()
	t.eq("исход — ушли", String(out.result()["outcome"]), "extracted")
	t.is_true("вышедший в отчёте", out.result()["escaped"].has("kira"))

	# 8. Никто не убит при верном прохождении: инвариант «один промах не убивает».
	# Маршрут идёт через док и подвал, где патруля нет: на этом кейсе проверяется
	# отсутствие смертей, а не взаимодействие с охраной (оно — в пункте 9).
	var clean = _make(["dock", "archive0", "dock"])
	for i in 10:
		clean.advance()
	t.eq("никто не погиб на пустой миссии", clean.result()["dead"].size(), 0)

	# 9. Контакт с охраной — один раз на помещение, а не каждый тик.
	# Иначе три тика в одном коридоре с патрулём убивали бы бойца, и обещание
	# «смерть — цена серии ошибок» превращалось бы в «цену трёх шагов».
	var contact = _make(["dock", "hall"])
	for i in 4:
		contact.advance()
	t.eq("контакт ранил", contact.own[0].state, Agent.State.WOUNDED)
	t.eq("триггер ровно один, хотя охрана возвращалась", contact.own[0].triggers, 1)
	t.is_false("и это не смерть", contact.own[0].is_dead())

	# 10. Погибший на выходе — не «вышедший»: труп не зачитывается как уход.
	var corpse = _make(["dock"])
	corpse.objective_done = true
	for i in 3:
		corpse._compromise(corpse.own[0])
	corpse._check_end()
	var crep: Dictionary = corpse.result()
	t.is_true("погибший в отчёте", crep["dead"].has("kira"))
	t.eq("погибший не в ушедших", crep["escaped"].size(), 0)

	# 11. Двое в одном помещении с охраной — триггер у КАЖДОГО.
	# `return` вместо `break` в обходе охраны обрывал бы весь проход по группе, и
	# все, кто идёт в списке после первого засвеченного, не получали бы триггер
	# никогда — при том что группа из двух бойцов поддержана и в цели, и в молчании.
	var duo_mission = Fixture.build()
	var duo_plan := Plan.new()
	duo_plan.route = ["dock", "hall"]
	duo_plan.exit_node = "dock"
	duo_plan.agents = [
		{"id": "kira", "role": "tactician", "understanding": 3},
		{"id": "echo", "role": "comms", "understanding": 3},
	]
	var duo := Sim.new()
	duo.setup(duo_mission, duo_plan, {"orders": 3, "seed": 1})
	duo.advance()
	t.eq("первый засвечен", duo.own[0].triggers, 1)
	t.eq("второй тоже засвечен", duo.own[1].triggers, 1)

	return t.results

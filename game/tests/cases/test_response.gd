extends RefCounted
## Тревога — перелом (D16). Из подвала уйти можно, с 4-го этажа — нет.

const Assert := preload("res://tests/assert.gd")
const Fixture := preload("res://tests/fixtures/small_mission.gd")
const Plan := preload("res://sim/plan.gd")
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

	return t.results

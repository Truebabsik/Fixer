extends RefCounted
## Данные миссии и их валидация.

const Assert := preload("res://tests/assert.gd")
const Fixture := preload("res://tests/fixtures/small_mission.gd")
const Plan := preload("res://sim/plan.gd")


func run() -> Array:
	var t := Assert.new()
	var m = Fixture.build()

	t.eq("миссия валидна", m.validate(), [])
	t.eq("узлов шесть", m.nodes.size(), 6)
	t.eq("цель существует", m.nodes.has(m.objective), true)

	var e: Dictionary = m.edge_between("dock", "hall")
	t.eq("ребро найдено в обе стороны", m.edge_between("hall", "dock")["id"], e["id"])
	t.eq("второй конец", m.other_end(e, "dock"), "hall")
	t.eq("неизвестного ребра нет", m.edge_between("dock", "it4"), {})

	var ids: Array = []
	for x in m.edges_at("hall"):
		ids.append(x["id"])
	t.eq("рёбра узла отсортированы по id", ids, ["e_dock_hall", "e_hall_archive", "e_hall_lift", "e_hall_office"])

	# Валидация умеет называть проблемы, а не молчать.
	var broken = Fixture.build()
	broken.add_edge("e_bad", "hall", "nope", "door", 1, 0)
	var problems: Array = broken.validate()
	t.eq("проблема найдена одна", problems.size(), 1)
	t.is_true("проблема называет помещение", String(problems[0]).contains("nope"))

	var plan := Plan.new()
	plan.route = ["dock", "hall", "office2"]
	t.eq("маршрут непрерывен", m.validate_route(plan.route), [])
	plan.route = ["dock", "it4"]
	t.eq("разрыв маршрута пойман", m.validate_route(plan.route).size(), 1)

	# Миссия без цели невалидна: раньше проверка стояла под `objective != ""`
	# и отсутствие цели не ловилось вовсе.
	var no_goal = Fixture.build()
	no_goal.objective = ""
	var goal_problems: Array = no_goal.validate()
	t.eq("миссия без цели — одна проблема", goal_problems.size(), 1)
	t.is_true("проблема называет цель", String(goal_problems[0]).contains("цель"))

	return t.results

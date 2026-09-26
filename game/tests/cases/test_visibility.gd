extends RefCounted
## Что игрок видит: сенсоры дают контакт, призраки стареют и расходятся.

const Assert := preload("res://tests/assert.gd")
const Fixture := preload("res://tests/fixtures/small_mission.gd")
const Plan := preload("res://sim/plan.gd")
const Sim := preload("res://sim/sim.gd")


func _count(sim, type: String) -> int:
	var n := 0
	for e in sim.events:
		if String(e["type"]) == type:
			n += 1
	return n


func run() -> Array:
	var t := Assert.new()
	var m = Fixture.build()
	var p := Plan.new()
	p.route = ["dock"]
	p.exit_node = "dock"
	p.agents = [{"id": "kira", "role": "tactician", "understanding": 3}]
	var sim := Sim.new()
	sim.setup(m, p, {"orders": 3, "seed": 1})

	t.eq("охрана стартует в холле", sim.guards[0].node, "hall")
	t.is_true("холл под сенсором — охрана видна", sim.is_visible(sim.guards[0]))
	t.is_false("призрак пока совпадает", sim.ghost_mismatch())

	sim.advance()
	t.eq("контакт зафиксирован один раз", _count(sim, "sensor_contact"), 1)

	sim.advance()
	t.eq("охрана ушла на второй этаж", sim.guards[0].node, "office2")
	t.is_false("вне сенсоров не видна", sim.is_visible(sim.guards[0]))
	t.eq("призрак остался в холле", String(sim.ghost_positions["guard_1"]), "hall")
	t.is_true("призрак разошёлся с реальностью", sim.ghost_mismatch())
	t.eq("расхождение сообщено один раз", _count(sim, "ghost_mismatch"), 1)

	for i in 4:
		sim.advance()
	t.eq("расхождение не спамит каждый шаг", _count(sim, "ghost_mismatch"), 1)

	return t.results

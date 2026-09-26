extends RefCounted
## Окна, приказы, эфир и молчание.

const Assert := preload("res://tests/assert.gd")
const Fixture := preload("res://tests/fixtures/small_mission.gd")
const Plan := preload("res://sim/plan.gd")
const Sim := preload("res://sim/sim.gd")
## Имя константы не может быть `Window`: в Godot 4.7 это тень нативной ноды
## и жёсткая ошибка разбора. Смысл и вызовы `Window.*` сохранены дословно.
const WindowScript := preload("res://sim/window.gd")


## Аннотации типов у параметров нет намеренно: хелпер отдаёт sim без типа,
## и обращение к нему — динамическое, как в остальных кейсах.
func _make(config = {}, agents = null):
	var m = Fixture.build()
	var p := Plan.new()
	p.route = ["dock", "hall", "office2", "vault"]
	p.exit_node = "dock"
	p.agents = agents if agents != null else [{"id": "kira", "role": "tactician", "understanding": 3}]
	var sim := Sim.new()
	sim.setup(m, p, config)
	return sim


## Довести до окна: 1 шаг в холл, 3 шага до office2, затем запертая дверь.
func _to_window(sim) -> void:
	for i in 5:
		sim.advance()


func run() -> Array:
	var t := Assert.new()

	# 1. Окно открывается и замораживает мир.
	var sim = _make()
	_to_window(sim)
	t.is_true("окно открыто", sim.current_window != null)
	t.eq("вид окна", String(sim.current_window["kind"]), "locked_door")
	t.is_true("у окна всегда есть молчание", WindowScript.has_silence(sim.current_window))
	var step_before: int = sim.scales.step
	sim.advance()
	t.eq("при открытом окне шагов нет", sim.scales.step, step_before)

	# 2. Молчание: приказ не тратится, эфир молчит, дверь открывают обходом.
	var sil: Dictionary = sim.order("silence")
	t.is_true("молчание принято", sil["accepted"])
	t.eq("вид ответа", String(sil["kind"]), "silence")
	t.eq("приказы целы", sim.orders_left, 3)
	t.eq("эфир молчит", sim.radio.radio, 0)
	t.eq("окно закрылось", sim.current_window, null)
	t.is_false("дверь открыта обходом", bool(sim.mission.edge("e_office_vault")["locked"]))
	t.eq("обход стоит времени", sim.own[0].delay, 3)

	# 3. Приказ: тратит пул, шумит и уходит в эфир.
	# Шум сверяем приращением, а не абсолютом: после Task 10 по маршруту могут
	# случиться контакты с охраной, и они тоже добавят шума.
	var sim2 = _make()
	_to_window(sim2)
	var noise_before: int = sim2.scales.noise
	var ord: Dictionary = sim2.order("breach")
	t.is_true("приказ принят", ord["accepted"])
	t.eq("приказ списан", sim2.orders_left, 2)
	t.eq("эфир вырос", sim2.radio.radio, 8)
	t.eq("отпечаток вырос", sim2.radio.imprint, 1)
	t.eq("шум выбитой двери", sim2.scales.noise - noise_before, 8)
	t.is_false("дверь открыта силой", bool(sim2.mission.edge("e_office_vault")["locked"]))

	# 4. Отказы приходят с причиной.
	var sim3 = _make({"orders": 0})
	_to_window(sim3)
	var no_orders: Dictionary = sim3.order("breach")
	t.is_false("без приказов отказ", no_orders["accepted"])
	t.eq("причина названа", String(no_orders["reason"]), "no_orders")

	var sim4 = _make()
	_to_window(sim4)
	sim4.radio.jam_until_step = 999
	var jammed: Dictionary = sim4.order("breach")
	t.is_false("заглушённому отказ", jammed["accepted"])
	t.eq("причина названа", String(jammed["reason"]), "jammed")

	# 5. Молчание со связистом: импровизация, но детерминированная по seed.
	var crew := [
		{"id": "kira", "role": "tactician", "understanding": 3},
		{"id": "echo", "role": "comms", "understanding": 3},
	]
	var a = _make({"seed": 7}, crew)
	_to_window(a)
	var eff_a: Dictionary = a.order("silence")["effect"]
	var b = _make({"seed": 7}, crew)
	_to_window(b)
	var eff_b: Dictionary = b.order("silence")["effect"]
	t.eq("тот же seed — та же импровизация", eff_a, eff_b)
	t.is_true("импровизировал связист", String(eff_a["by"]) == "comms")

	# 6. Без связиста молчание всегда безопасно.
	var c = _make({"seed": 7})
	_to_window(c)
	var eff_c: Dictionary = c.order("silence")["effect"]
	t.eq("решает тактик", String(eff_c["by"]), "tactician")
	t.eq("тактик не рискует", String(eff_c["quality"]), "safe")

	return t.results

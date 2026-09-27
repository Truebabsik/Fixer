extends RefCounted
## Окна, приказы, эфир и молчание.

const Assert := preload("res://tests/assert.gd")
const Fixture := preload("res://tests/fixtures/small_mission.gd")
const Mission := preload("res://sim/mission.gd")
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
	# Патруль уводим: кейс про окна, приказы и эфир. Маршрут к запертой двери идёт
	# через холл, где стоит патруль; контакт ранит бойца и добавляет 5 шума —
	# цена перехода и окно мерились бы не в чистом виде. Контакты — test_casualties.gd.
	sim.guards = []
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
	# Открытие живёт в Sim (unlocked), а миссия остаётся неизменяемыми данными:
	# `mission.edge(...)["locked"]` после прогона обязан быть тем же, что и до него.
	t.is_true("дверь заперта на входе", bool(sim.mission.edge("e_office_vault")["locked"]))
	var sil: Dictionary = sim.order("silence")
	t.is_true("молчание принято", sil["accepted"])
	t.eq("вид ответа", String(sil["kind"]), "silence")
	t.eq("приказы целы", sim.orders_left, 3)
	t.eq("эфир молчит", sim.radio.radio, 0)
	t.eq("окно закрылось", sim.current_window, null)
	t.is_true("дверь открыта обходом", bool(sim.unlocked.get("e_office_vault", false)))
	t.is_true("миссия не тронута", bool(sim.mission.edge("e_office_vault")["locked"]))
	t.eq("обход стоит времени", sim.own[0].delay, 3)

	# 3. Приказ: тратит пул, шумит и уходит в эфир.
	# Шум сверяем приращением, а не абсолютом: так проверка не зависит от того,
	# сколько шума набралось по дороге к окну.
	var sim2 = _make()
	_to_window(sim2)
	var noise_before: int = sim2.scales.noise
	var ord: Dictionary = sim2.order("breach")
	t.is_true("приказ принят", ord["accepted"])
	t.eq("приказ списан", sim2.orders_left, 2)
	t.eq("эфир вырос", sim2.radio.radio, 8)
	t.eq("отпечаток вырос", sim2.radio.imprint, 1)
	t.eq("шум выбитой двери", sim2.scales.noise - noise_before, 8)
	t.is_true("дверь открыта силой", bool(sim2.unlocked.get("e_office_vault", false)))
	t.is_true("миссия не тронута", bool(sim2.mission.edge("e_office_vault")["locked"]))

	# 4. Отказы приходят с причиной и НЕ закрывают окно: иначе игрок терял бы
	# решение из-за отказа, а харнесс задачи 11 не смог бы отступить к молчанию.
	var sim3 = _make({"orders": 0})
	_to_window(sim3)
	var no_orders: Dictionary = sim3.order("breach")
	t.is_false("без приказов отказ", no_orders["accepted"])
	t.eq("причина названа", String(no_orders["reason"]), "no_orders")
	t.is_true("окно осталось открытым", sim3.current_window != null)

	var sim4 = _make()
	_to_window(sim4)
	sim4.radio.jam_until_step = 999
	var jammed: Dictionary = sim4.order("breach")
	t.is_false("заглушённому отказ", jammed["accepted"])
	t.eq("причина названа", String(jammed["reason"]), "jammed")
	t.is_true("окно осталось открытым", sim4.current_window != null)

	# 5. Неизвестный вариант отвергается, не тратя приказ. Иначе опечатка в
	# идентификаторе молча сжигала бы приказ, шумела в эфир и отчитывалась успехом.
	var sim5 = _make()
	_to_window(sim5)
	var unknown: Dictionary = sim5.order("нет_такого_варианта")
	t.is_false("неизвестный вариант отвергнут", unknown["accepted"])
	t.eq("причина названа", String(unknown["reason"]), "unknown_option")
	t.eq("приказ не потрачен", sim5.orders_left, 3)
	t.eq("эфир молчит", sim5.radio.radio, 0)
	t.is_true("окно осталось открытым", sim5.current_window != null)

	# 6. Молчание со связистом: импровизация, но детерминированная по seed.
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

	# 7. Без связиста молчание всегда безопасно.
	var c = _make({"seed": 7})
	_to_window(c)
	var eff_c: Dictionary = c.order("silence")["effect"]
	t.eq("решает тактик", String(eff_c["by"]), "tactician")
	t.eq("тактик не рискует", String(eff_c["quality"]), "safe")

	# 8. Запертая дверь симметрична: подход со стороны `b` открывает окно так же,
	# как со стороны `a`. Пока проверялось `a.node == e["a"]`, агент, идущий против
	# записи ребра, стоял бы до caught/timeout без окна и без события.
	# ВНИМАНИЕ: этот блок идёт из `a` (маршрут начинается с якоря ребра) — им
	# покрыт обычный случай. Настоящий подход со стороны `b` — в блоке 8б.
	var back = _make_b_side()
	back.advance()
	t.is_true("окно открылось со стороны b", back.current_window != null)
	t.eq("вид окна со стороны b", String(back.current_window["kind"]), "locked_door")
	t.eq("окно называет то же ребро", String(back.current_window["edge"]), "e_cell_hall")
	t.is_true("событие окна тоже есть", _has_event(back, "window_opened"))
	t.is_true("дверь со стороны b открывается приказом", bool(back.order("pick")["accepted"]))
	t.is_true("дверь со стороны b открыта", bool(back.unlocked.get("e_cell_hall", false)))
	t.is_true("миссия не тронута", bool(back.mission.edge("e_cell_hall")["locked"]))
	# И после открытия агент действительно идёт — а не стоит у открытой двери.
	# `pick` стоит 2 шага задержки, поэтому дверь он проходит на четвёртом шаге.
	for i in 2:
		back.advance()
	t.eq("задержка вскрытия отработана", back.own[0].node, "cell")
	back.advance()
	t.eq("агент со стороны b прошёл дверь", back.own[0].node, "hall")
	back.advance()
	t.eq("агент со стороны b дошёл до цели", back.own[0].node, "exit")
	t.eq("миссия со стороны b завершилась уходом", String(back.result()["outcome"]), "extracted")

	# 8б. ТОТ ЖЕ дефект, но по-настоящему: агент идёт ОТ конца `b` К концу `a`.
	# Ребро асимметрично (`a`="far_hall", `b`="near_hall") и заперто; маршрут
	# начинается с `b`. Прежний блок этого не проверял: там маршрут стартовал с
	# якоря `e["a"]`, то есть условие направления выполнялось и дефект молчал.
	var rev = _make_reverse_side()
	rev.advance()
	t.is_true("окно открылось при ходе от b к a", rev.current_window != null)
	## При сломанной симметрии окна нет, и обращение к нему уронило бы кейс целиком —
	## тогда провал выглядел бы абортом, а не ассертом. Выходим с одним честным провалом.
	if rev.current_window == null:
		return t.results
	t.eq("окно называет ребро при ходе от b к a", String(rev.current_window["edge"]), "e_far_near")
	t.eq("окно знает агента", String(rev.current_window["agent"]), "kira")
	t.is_true("событие окна есть и при ходе от b", _has_event(rev, "window_opened"))
	t.is_true("окно не открыло дверь само", not bool(rev.unlocked.get("e_far_near", false)))
	t.is_true("приказ принят при ходе от b", bool(rev.order("breach")["accepted"]))
	t.is_true("дверь открыта приказом из b", bool(rev.unlocked.get("e_far_near", false)))
	t.is_true("миссия не тронута и здесь", bool(rev.mission.edge("e_far_near")["locked"]))
	# `breach` без задержки: один шаг перехода — и агент на дальнем конце.
	rev.advance()
	t.eq("агент из b прошёл запертую дверь", rev.own[0].node, "far_hall")
	rev.advance()
	t.eq("агент из b дошёл до цели", rev.own[0].node, "far_exit")
	t.eq("миссия из b завершилась уходом", String(rev.result()["outcome"]), "extracted")

	# 9. Завершённая миссия окна не открывает, и приказов после конца нет.
	# `finished` был достижим при открытом окне: _check_end() шёл перед
	# _maybe_open_window(), и первый же приказ открывал окно, которое уже некому
	# закрыть. Теперь конец миссии снимает окно, а order() отказывает с причиной.
	var dead = _make({"orders": 3})
	_to_window(dead)
	var sil_dead: Dictionary = dead.order("silence")
	t.is_true("обход принят перед смертью", sil_dead["accepted"])
	for i in 3:
		dead._compromise(dead.own[0])
	# Агент в доке — выход, но цель не взята, поэтому уход не зачитывается;
	# счётчик шагов доводит миссию до исхода timeout.
	for i in 500:
		dead.advance()
	t.eq("миссия окончена", String(dead.result()["outcome"]), "timeout")
	t.eq("окна при исходе нет", dead.current_window, null)
	var after: Dictionary = dead.order("breach")
	t.is_false("после конца приказ не принят", after["accepted"])
	t.eq("после конца названа причина", String(after["reason"]), "finished")
	t.eq("приказы после конца не списаны", dead.orders_left, 3)
	var step_late: int = dead.scales.step
	dead.advance()
	t.eq("мир после конца не идёт", dead.scales.step, step_late)
	t.eq("окно после конца не открывается", dead.current_window, null)

	# 9б. Сам сторож `_maybe_open_window`: даже если конец миссии выставлен
	# извне, окно не появится. Это отдельная ветка — проверяем её напрямую.
	var guard_case = _make({"orders": 3})
	_to_window(guard_case)
	guard_case.finished = true
	guard_case._maybe_open_window()
	t.eq("завершённая миссия окна не открывает", guard_case.current_window, null)

	return t.results


## Подход к запертой двери СО СТОРОНЫ `b`. В фикстуре запертая дверь ведёт в
## тупик (vault), поэтому маршрут «из vault» был бы разорван: соберём маленькую
## миссию, где дверь — обычный проход, записанный как `a` -> `b`.
## ВНИМАНИЕ: маршрут здесь начинается с `cell`, а ребро записано `a`="cell", поэтому
## агент идёт ИЗ `a`. Для настоящей проверки стороны `b` — `_make_reverse_side()`.
func _make_b_side():
	var m := Mission.new()
	m.id = "b_side"
	m.add_node("cell", 1, [])
	m.add_node("hall", 1, [])
	m.add_node("exit", 1, [])
	m.add_edge("e_cell_hall", "cell", "hall", "door", 1, 0, true)
	m.add_edge("e_hall_exit", "hall", "exit", "corridor", 1, 0)
	m.objective = "exit"
	var p := Plan.new()
	p.route = ["cell", "hall", "exit"]
	p.exit_node = "exit"
	p.agents = [{"id": "kira", "role": "tactician", "understanding": 3}]
	var sim := Sim.new()
	sim.setup(m, p, {"orders": 3, "seed": 1})
	sim.guards = []
	return sim


## Настоящий подход со стороны `b`: ребро записано как `a`="far_hall" -> `b`="near_hall",
## а маршрут начинается с `near_hall`. Значит агент идёт ОТ конца `b` К концу `a` —
## именно тот случай, который условие `a.node == e["a"]` ломало.
func _make_reverse_side():
	var m := Mission.new()
	m.id = "reverse_side"
	m.add_node("near_hall", 1, [])
	m.add_node("far_hall", 1, [])
	m.add_node("far_exit", 1, [])
	m.add_edge("e_far_near", "far_hall", "near_hall", "door", 1, 0, true)
	m.add_edge("e_far_exit", "far_hall", "far_exit", "corridor", 1, 0)
	m.objective = "far_exit"
	var p := Plan.new()
	p.route = ["near_hall", "far_hall", "far_exit"]
	p.exit_node = "far_exit"
	p.agents = [{"id": "kira", "role": "tactician", "understanding": 3}]
	var sim := Sim.new()
	sim.setup(m, p, {"orders": 3, "seed": 1})
	sim.guards = []
	return sim


func _has_event(sim, type: String) -> bool:
	for e in sim.events:
		if String(e["type"]) == type:
			return true
	return false

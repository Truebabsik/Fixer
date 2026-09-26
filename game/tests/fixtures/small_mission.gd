extends RefCounted
## Минимальная миссия для тестов ядра. Числа шагов подобраны так, чтобы
## воспроизвести главный перекос уровня: из подвала уйти можно, с 4-го этажа — нет.

const Mission := preload("res://sim/mission.gd")


static func build():
	var m = Mission.new()
	m.id = "small"
	m.add_node("dock", 1, ["entry"])
	m.add_node("hall", 1, [])
	m.add_node("office2", 2, [])
	m.add_node("vault", 2, ["locked_room"])
	m.add_node("it4", 4, [])
	m.add_node("archive0", 0, ["cold_archive"])

	m.add_edge("e_dock_hall", "dock", "hall", "corridor", 1, 0)
	m.add_edge("e_hall_office", "hall", "office2", "stairs", 3, 0)
	m.add_edge("e_office_it", "office2", "it4", "stairs", 12, 0)
	m.add_edge("e_office_vault", "office2", "vault", "door", 1, 8, true)
	m.add_edge("e_hall_lift", "hall", "it4", "lift_main", 2, 4)
	m.add_edge("e_dock_freight", "dock", "archive0", "lift_freight", 3, 4)
	m.add_edge("e_hall_archive", "hall", "archive0", "stairs", 3, 0)

	m.add_sensor("s_hall", ["hall"])
	m.add_sensor("s_it", ["it4"])
	m.add_patrol("guard_1", ["hall", "office2"], 2)
	m.objective = "archive0"
	return m

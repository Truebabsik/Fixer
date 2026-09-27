extends RefCounted
## Минимальная миссия для тестов ядра. Числа шагов подобраны так, чтобы
## воспроизвести главный перекос уровня: из подвала уйти можно, с 4-го этажа — нет.

const Mission := preload("res://sim/mission.gd")

## Окно запертой двери в авторской форме контента (`02-format.md` §4), а не в
## рантайм-форме: рантайм-окно ядро собирает само из этих данных (`WindowScript.from_data`),
## и составной id `locked_door:<edge>` получается из `trigger.edge`.
## Исходы молчания: `good` — открыть ребро и не потратить времени, `neutral` — задержка 3,
## `bad` — задержка 3 и шум 5, `safe` — задержка 3. `unlock` стоит во ВСЕХ четырёх исходах:
## молчание у запертой двери открывает её всегда, разной бывает только цена (D37). Меньше
## четырёх `unlock` означало бы, что часть исходов молчания оставляет группу перед дверью,
## а окно возвращается на следующем шаге.
const WINDOWS := [
	{
		"id": "w_locked_door",
		"kind": "locked_edge",
		"trigger": {"type": "locked_edge", "edge": "e_office_vault"},
		"text_key": "window.w_locked_door.text",
		"options": [
			{"id": "breach", "text_key": "window.w_locked_door.breach", "complexity": 1,
				"cost": {"noise": 8, "delay": 0},
				"effects": [{"type": "unlock", "edge": "e_office_vault"}]},
			{"id": "pick", "text_key": "window.w_locked_door.pick", "complexity": 2,
				"cost": {"noise": 1, "delay": 2},
				"effects": [{"type": "unlock", "edge": "e_office_vault"}]},
		],
		"silence": {
			"text_key": "window.w_locked_door.silence",
			"good": [{"type": "unlock", "edge": "e_office_vault"}],
			"neutral": [{"type": "delay", "value": 3}, {"type": "unlock", "edge": "e_office_vault"}],
			"bad": [{"type": "delay", "value": 3}, {"type": "noise", "value": 5},
				{"type": "unlock", "edge": "e_office_vault"}],
			"safe": [{"type": "delay", "value": 3}, {"type": "unlock", "edge": "e_office_vault"}],
		},
	},
]


static func build():
	var m := Mission.new()
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
	## Копия обязательна: константа read-only, и миссия не должна делить с ней состояние.
	m.set_data({"windows": WINDOWS.duplicate(true)})
	return m

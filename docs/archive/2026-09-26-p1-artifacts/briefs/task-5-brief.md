### Task 5: Данные миссии, агент, план

**Files:**
- Create: `game/sim/mission.gd`
- Create: `game/sim/agent.gd`
- Create: `game/sim/plan.gd`
- Create: `game/tests/fixtures/small_mission.gd`
- Create: `game/tests/cases/test_mission.gd`
- Modify: `game/tests/run.gd`

**Interfaces:**
- Consumes: ничего.
- Produces:
  - `Mission`: `add_node(id, floor, tags)`, `add_edge(id, a, b, kind, steps, noise, locked)`, `add_patrol(id, route, period)`, `add_sensor(id, nodes)`, `objective`, `edge(id) -> Dictionary`, `edges_at(node) -> Array` (отсортировано по id), `edge_between(a, b) -> Dictionary`, `other_end(edge, node) -> String`, `validate() -> Array`, `validate_route(route) -> Array`.
  - `Agent`: `id`, `kind` (`Kind.OWN`/`Kind.GUARD`), `role` (`"tactician"`/`"comms"`), `understanding`, `node`, `state` (`State.OK/WOUNDED/CRITICAL/DEAD`), `triggers`, `progress`, `delay`, `waypoints`, `waypoint_index`, `patrol_route`, `patrol_index`, `patrol_period`; методы `speed_penalty() -> int`, `add_trigger() -> void`, `is_dead() -> bool`, `is_own() -> bool`.
  - `Plan`: `route: Array` (id помещений по порядку), `exit_node: String`, `exit_backup_node: String`, `cargo_heavy: bool`, `agents: Array`.

**Решение, которое надо знать:** маршрут в плане — **авторский список помещений**, а не результат поиска пути. Поиск пути появится в П2 вместе с интерфейсом планирования; для ядра важно, что маршрут задан явно и проверяем.

- [ ] **Step 1: Написать `game/sim/agent.gd`**

```gdscript
extends RefCounted
## Агент: свой боец или охранник. Состояние растёт только через накопленные
## триггеры — один промах убить не может ни при каких настройках (design.md §13.5).

enum Kind { OWN, GUARD }
enum State { OK, WOUNDED, CRITICAL, DEAD }

const TRIGGERS_DEAD := 3

var id: String = ""
var kind: int = Kind.OWN
var role: String = "tactician"
var understanding: int = 3
var node: String = ""
var state: int = State.OK
var triggers: int = 0
var progress: int = 0
var delay: int = 0

# свои
var waypoints: Array = []
var waypoint_index: int = 1

# охрана
var patrol_route: Array = []
var patrol_index: int = 0
var patrol_period: int = 4


func speed_penalty() -> int:
	match state:
		State.WOUNDED:
			return 1
		State.CRITICAL:
			return 2
		_:
			return 0


func add_trigger() -> void:
	triggers += 1
	state = mini(triggers, TRIGGERS_DEAD)


func is_dead() -> bool:
	return state == State.DEAD


func is_own() -> bool:
	return kind == Kind.OWN
```

- [ ] **Step 2: Написать `game/sim/mission.gd`**

```gdscript
extends RefCounted
## Описание миссии: граф помещений, патрули, сенсоры, цель.
## Только данные и валидация — никакой логики хода.

const EDGE_KINDS := ["door", "corridor", "lift_main", "lift_freight", "stairs"]

var id: String = ""
var nodes: Dictionary = {}
var edges: Array = []
var patrols: Array = []
var sensors: Array = []
var objective: String = ""


func add_node(node_id: String, floor: int, tags: Array = []) -> void:
	nodes[node_id] = {"floor": floor, "tags": tags}


func add_edge(edge_id: String, a: String, b: String, kind: String, steps: int, noise: int, locked := false) -> void:
	edges.append({"id": edge_id, "a": a, "b": b, "kind": kind, "steps": steps, "noise": noise, "locked": locked})


func add_patrol(patrol_id: String, route: Array, period := 4) -> void:
	patrols.append({"id": patrol_id, "route": route, "period": period})


func add_sensor(sensor_id: String, node_ids: Array) -> void:
	sensors.append({"id": sensor_id, "nodes": node_ids})


func edge(edge_id: String) -> Dictionary:
	for e in edges:
		if String(e["id"]) == edge_id:
			return e
	return {}


## Рёбра узла, отсортированные по id: фиксированный порядок обхода ради детерминизма.
func edges_at(node_id: String) -> Array:
	var out: Array = []
	for e in edges:
		if String(e["a"]) == node_id or String(e["b"]) == node_id:
			out.append(e)
	out.sort_custom(func(x, y): return String(x["id"]) < String(y["id"]))
	return out


func edge_between(a: String, b: String) -> Dictionary:
	for e in edges_at(a):
		var ea := String(e["a"])
		var eb := String(e["b"])
		if (ea == a and eb == b) or (eb == a and ea == b):
			return e
	return {}


func other_end(e: Dictionary, node_id: String) -> String:
	return String(e["b"]) if String(e["a"]) == node_id else String(e["a"])


## Пустой список = миссия валидна. Иначе — человекочитаемые проблемы.
func validate() -> Array:
	var problems: Array = []
	if nodes.is_empty():
		problems.append("нет ни одного помещения")
	if objective == "":
		problems.append("цель не задана")
	elif not nodes.has(objective):
		problems.append("цель ссылается на несуществующее помещение %s" % objective)
	for e in edges:
		if not nodes.has(String(e["a"])):
			problems.append("ребро %s ссылается на несуществующее помещение %s" % [e["id"], e["a"]])
		if not nodes.has(String(e["b"])):
			problems.append("ребро %s ссылается на несуществующее помещение %s" % [e["id"], e["b"]])
		if not EDGE_KINDS.has(String(e["kind"])):
			problems.append("ребро %s: неизвестный вид %s" % [e["id"], e["kind"]])
	for p in patrols:
		for n in p["route"]:
			if not nodes.has(String(n)):
				problems.append("патруль %s ссылается на несуществующее помещение %s" % [p["id"], n])
	for s in sensors:
		for n in s["nodes"]:
			if not nodes.has(String(n)):
				problems.append("сенсор %s ссылается на несуществующее помещение %s" % [s["id"], n])
	return problems


## Непрерывность маршрута: между соседними точками должно быть ребро.
func validate_route(route: Array) -> Array:
	var problems: Array = []
	for i in range(route.size() - 1):
		if edge_between(String(route[i]), String(route[i + 1])).is_empty():
			problems.append("между %s и %s нет ребра" % [route[i], route[i + 1]])
	return problems
```

- [ ] **Step 3: Написать `game/sim/plan.gd`**

```gdscript
extends RefCounted
## План игрока: маршрут, отход и состав.
## Пока это данные, которые кто-то задал снаружи. Фаза планирования (П2) будет
## их собирать; ядру важно лишь то, что маршрут задан явно и проверяем.

var route: Array = []              # id помещений по порядку
var exit_node: String = ""         # куда выходим
var exit_backup_node: String = ""  # запасной выход (D32): есть всегда
var cargo_heavy: bool = false      # планируем вынос носителей (нужен Л2)
var agents: Array = [
	{"id": "kira", "role": "tactician", "understanding": 3},
	{"id": "echo", "role": "comms", "understanding": 3},
]
```

- [ ] **Step 4: Написать фикстуру `game/tests/fixtures/small_mission.gd`**

```gdscript
extends RefCounted
## Минимальная миссия для тестов ядра. Числа шагов подобраны так, чтобы
## воспроизвести главный перекос уровня: из подвала уйти можно, с 4-го этажа — нет.

const Mission := preload("res://sim/mission.gd")


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
	return m
```

- [ ] **Step 5: Написать падающий тест `game/tests/cases/test_mission.gd`**

```gdscript
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
```

- [ ] **Step 6: Прогнать — ожидаем зелёный** (добавив кейс в `CASES`)

Expected: `failed: 0`, `код: 0`.

- [ ] **Step 7: Закоммитить**

```powershell
git add game/sim/mission.gd game/sim/agent.gd game/sim/plan.gd game/tests/fixtures/small_mission.gd game/tests/cases/test_mission.gd game/tests/run.gd
git commit -m "feat(sim): данные миссии, агент, план и их валидация"
```

---


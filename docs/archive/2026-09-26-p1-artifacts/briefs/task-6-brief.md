### Task 6: Шаг симуляции — движение по плану и шум переходов

**Files:**
- Create: `game/sim/sim.gd`
- Create: `game/tests/cases/test_movement.gd`
- Modify: `game/tests/run.gd`

**Interfaces:**
- Consumes: `Mission`, `Agent`, `Plan`, `Scales`, `Radio`, `Window`, `Response`.
- Produces: `Sim` — `setup(mission, plan, config)`, `advance() -> Array` (события одного шага), `events -> Array`, `scales`, `radio`, `own`, `guards`, `finished`, `outcome`, `result() -> Dictionary`, `_emit(type, data)`.

**Автопауза уже здесь:** `advance()` не двигает мир, если открыто окно. Это не оптимизация, а правило темпа (D4).

- [ ] **Step 1: Написать падающий тест `game/tests/cases/test_movement.gd`**

```gdscript
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
	var sim = _make(["dock", "hall", "office2"])
	sim.advance()
	t.eq("один шаг — один тик часов", sim.scales.step, 1)
	t.eq("переход в холл — 1 шаг", sim.own[0].node, "hall")
	t.eq("шум перехода в холл нулевой", sim.scales.noise, 0)

	for i in 3:
		sim.advance()
	t.eq("лестница — 3 шага", sim.own[0].node, "office2")
	t.eq("шум лестницы нулевой", sim.scales.noise, 0)

	# 2. Лифт: hall -> it4 стоит 2 шага и 4 шума.
	var sim2 = _make(["dock", "hall", "it4"])
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

	return t.results
```

- [ ] **Step 2: Прогнать — ожидаем провал**

Expected: `LOAD FAIL  res://tests/cases/test_movement.gd`, `код: 1` (`sim/sim.gd` ещё нет).

- [ ] **Step 3: Написать `game/sim/sim.gd`**

```gdscript
extends RefCounted
## Ядро операции. Только композиция правил — ни одного собственного числа баланса.
## Чистый RefCounted: ни нод, ни сцен, ни рендера (D14).
##
## Автопауза: пока открыто окно решения, advance() не двигает мир (D4).
## Давление создаёт дефицит приказов и эфир, а не таймер.

const Agent := preload("res://sim/agent.gd")
const Scales := preload("res://sim/scales.gd")
const Radio := preload("res://sim/radio.gd")
const Response := preload("res://sim/response.gd")

const MAX_STEPS := 500

var mission
var plan
var scales
var radio
var response
var own: Array = []
var guards: Array = []
var events: Array = []
var ghost_positions: Dictionary = {}
var visible_last: Dictionary = {}
var orders_left: int = 3
var rng := RandomNumberGenerator.new()
var current_window = null
var objective_done := false
var finished := false
var outcome := ""


func setup(mission_, plan_, config := {}) -> void:
	mission = mission_
	plan = plan_
	orders_left = int(config.get("orders", 3))
	rng.seed = int(config.get("seed", 1))
	scales = Scales.new()
	radio = Radio.new()
	response = Response.new()
	events = []
	own = []
	guards = []
	ghost_positions = {}
	visible_last = {}
	current_window = null
	objective_done = false
	finished = false
	outcome = ""

	if plan.route.is_empty():
		finished = true
		outcome = "no_route"
		return

	var start := String(plan.route[0])
	for a in plan.agents:
		var agent := Agent.new()
		agent.id = String(a["id"])
		agent.kind = Agent.Kind.OWN
		agent.role = String(a.get("role", "tactician"))
		agent.understanding = int(a.get("understanding", 3))
		agent.node = start
		agent.waypoints = plan.route.duplicate()
		agent.waypoint_index = 1
		own.append(agent)

	for p in mission.patrols:
		var guard := Agent.new()
		guard.id = String(p["id"])
		guard.kind = Agent.Kind.GUARD
		guard.node = String(p["route"][0])
		guard.patrol_route = p["route"]
		guard.patrol_index = 0
		guard.patrol_period = int(p.get("period", 4))
		guards.append(guard)

	# Снимок разведки: призраки замирают там, где охрана была на момент съёмки.
	for g in guards:
		ghost_positions[g.id] = g.node
		visible_last[g.id] = false

	scales.add_noise(int(config.get("noise_start", 0)))
	_emit("mission_started", {"node": start})


## Один шаг мира. Возвращает события этого шага. При открытом окне — ничего.
func advance() -> Array:
	var from := events.size()
	if finished or current_window != null:
		return []
	scales.tick()
	radio.tick_decay(scales.step - 1)
	_advance_own()
	_advance_guards()
	_update_visibility()
	_check_objective()
	_check_end()
	return events.slice(from)


func result() -> Dictionary:
	var injured: Array = []
	var dead: Array = []
	var escaped: Array = []
	for a in own:
		if a.is_dead():
			dead.append(a.id)
		elif a.state != Agent.State.OK:
			injured.append(a.id)
		# «Вышел» = дошёл до выхода ПОСЛЕ взятой цели. Без второй половины условия
		# агент, стартующий на выходе (такие маршруты есть в тестах), попадал бы
		# в escaped с нулевого шага, и проверки в задачах 10–11 были бы пустыми.
		if objective_done and a.node == plan.exit_node:
			escaped.append(a.id)
	return {
		"outcome": outcome,
		"steps": scales.step,
		"objective_done": objective_done,
		"orders_left": orders_left,
		"noise": scales.noise,
		"radio": radio.radio,
		"imprint": radio.imprint,
		"alarm": scales.alarm_state(),
		"injured": injured,
		"dead": dead,
		"escaped": escaped,
		"positions": _positions(),
	}


func _positions() -> Dictionary:
	var out: Dictionary = {}
	for a in own:
		out[a.id] = a.node
	for g in guards:
		out[g.id] = g.node
	return out


func _emit(type: String, data: Dictionary) -> void:
	events.append({"step": scales.step, "type": type, "data": data})


func _advance_own() -> void:
	for a in own:
		if a.is_dead():
			continue
		if a.delay > 0:
			a.delay -= 1
			continue
		if a.waypoint_index >= a.waypoints.size():
			continue
		var target := String(a.waypoints[a.waypoint_index])
		var e: Dictionary = mission.edge_between(a.node, target)
		if e.is_empty():
			continue
		if response.edge_blocked(String(e["kind"]), scales.step):
			_emit("path_blocked", {"agent": a.id, "edge": e["id"], "kind": e["kind"]})
			continue
		a.progress += 1
		if a.progress >= int(e["steps"]) + a.speed_penalty():
			a.progress = 0
			a.node = target
			a.waypoint_index += 1
			var noise := int(e["noise"])
			if noise > 0:
				scales.add_noise(noise)
			_emit("agent_moved", {"agent": a.id, "node": a.node, "edge": e["id"], "noise": noise})


func _advance_guards() -> void:
	for g in guards:
		if g.patrol_route.size() < 2:
			continue
		g.progress += 1
		if g.progress < g.patrol_period:
			continue
		g.progress = 0
		g.patrol_index = (g.patrol_index + 1) % g.patrol_route.size()
		g.node = String(g.patrol_route[g.patrol_index])
		_emit("guard_moved", {"agent": g.id, "node": g.node})


## Заготовки под Task 7; пока ничего не делают — их наполняет следующий шаг.
func _update_visibility() -> void:
	pass


func _check_objective() -> void:
	pass


func _check_end() -> void:
	pass
```

- [ ] **Step 4: Создать заглушку `game/sim/response.gd`** (наполняется в Task 9)

```gdscript
extends RefCounted
## Группа реагирования. В Task 6 — заглушка, чтобы ядро собиралось.

func edge_blocked(_kind: String, _step: int) -> bool:
	return false
```

- [ ] **Step 5: Прогнать — ожидаем зелёный**

Expected: `failed: 0`, `код: 0`.

- [ ] **Step 6: Закоммитить**

```powershell
git add game/sim/sim.gd game/sim/response.gd game/tests/cases/test_movement.gd game/tests/run.gd
git commit -m "feat(sim): шаг мира — движение по плану, стоимость переходов, автопауза"
```


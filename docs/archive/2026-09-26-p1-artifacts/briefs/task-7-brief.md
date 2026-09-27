### Task 7: Сенсоры и призраки

**Files:**
- Modify: `game/sim/sim.gd` (наполнить `_update_visibility`, добавить `is_visible`, `ghost_mismatch`, словарь `ghost_reported`)
- Create: `game/tests/cases/test_visibility.gd`
- Modify: `game/tests/run.gd`

**Interfaces:**
- Consumes: `Sim`, `Mission.sensors`, `ghost_positions`.
- Produces: `Sim.is_visible(guard) -> bool`, `Sim.ghost_mismatch() -> bool`, события `sensor_contact` и `ghost_mismatch` (по одному на переход состояния, не каждый шаг).

**Смысл:** красные видны только в зоне сенсоров; остальные — бледные призраки там, где их застала разведка. Расхождение призрака с реальностью и есть индикатор тревоги (D16) — поэтому событие о расхождении должно быть **однократным**, а не потоком.

- [ ] **Step 1: Написать падающий тест `game/tests/cases/test_visibility.gd`**

```gdscript
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
```

- [ ] **Step 2: Прогнать — ожидаем провал**

Expected: провал на `is_visible` — метода ещё нет (`Invalid call. Nonexistent function`), `код: 1`.

- [ ] **Step 3: Дополнить `game/sim/sim.gd`**

В объявление полей (рядом с `var visible_last: Dictionary = {}`) добавить:

```gdscript
var ghost_reported: Dictionary = {}
```

В `setup()`, рядом со сбросом `visible_last = {}`, добавить `ghost_reported = {}`; в цикле по охране — `ghost_reported[g.id] = false`.

Заменить заглушку `_update_visibility` на:

```gdscript
func is_visible(guard) -> bool:
	for s in mission.sensors:
		if s["nodes"].has(guard.node):
			return true
	return false


func ghost_mismatch() -> bool:
	for g in guards:
		if String(ghost_positions.get(g.id, "")) != g.node:
			return true
	return false


func _update_visibility() -> void:
	for g in guards:
		var seen := is_visible(g)
		if seen and not bool(visible_last.get(g.id, false)):
			_emit("sensor_contact", {"agent": g.id, "node": g.node})
		visible_last[g.id] = seen
		var ghost := String(ghost_positions.get(g.id, ""))
		if ghost != g.node and not bool(ghost_reported.get(g.id, false)):
			ghost_reported[g.id] = true
			_emit("ghost_mismatch", {"agent": g.id, "ghost": ghost, "real": g.node})
```

- [ ] **Step 4: Прогнать — ожидаем зелёный**

Expected: `failed: 0`, `код: 0`.

- [ ] **Step 5: Закоммитить**

```powershell
git add game/sim/sim.gd game/tests/cases/test_visibility.gd game/tests/run.gd
git commit -m "feat(sim): сенсоры и призраки — что видно и что устарело"
```

---


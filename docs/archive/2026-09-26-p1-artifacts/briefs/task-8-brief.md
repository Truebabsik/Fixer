### Task 8: Окна решений, приказы, эфир и молчание

**Files:**
- Create: `game/sim/window.gd`
- Modify: `game/sim/sim.gd` (окна, `order()`, применение вариантов, разрешение молчания)
- Create: `game/tests/cases/test_windows.gd`
- Modify: `game/tests/run.gd`

**Interfaces:**
- Consumes: `Radio`, `Understanding`, `Agent.role`.
- Produces:
  - `WindowScript.locked_door(edge_id, agent_id) -> Dictionary`, `WindowScript.SILENCE = "silence"`.
  - `Sim.current_window`, `Sim.order(option_id) -> Dictionary` (`{"accepted": bool, "kind", "reason"?, "effect"?}`), `Sim._compromise(agent)` (понадобится в Task 10).

**Три правила, которые здесь кодируются:**
1. У окна **всегда** есть вариант «молчать» (D23).
2. Приказ стоит приказа и **передачи в эфир**; отказ приходит с причиной (нет приказов / заглушён).
3. Молчание ничего не тратит, но решает именной. Если в составе есть связист — он **импровизирует**, и это единственное место с кубиком (D7), поэтому seed обязателен.

- [ ] **Step 1: Написать `game/sim/window.gd`**

```gdscript
extends RefCounted
## Окно решения. Инвариант: у каждого окна есть вариант «молчать» (D23).
## Молчание — не отмена, а ход: именной решает за игрока безопасно и не его способом.

const SILENCE := "silence"


static func locked_door(edge_id: String, agent_id: String) -> Dictionary:
	return {
		"id": "locked_door:%s" % edge_id,
		"kind": "locked_door",
		"edge": edge_id,
		"agent": agent_id,
		"text": "Дверь заперта, хотя в плане открыта.",
		"options": [
			{"id": "breach", "label": "Выбить", "noise": 8, "delay": 0, "complexity": 1},
			{"id": "pick", "label": "Вскрыть тихо", "noise": 1, "delay": 2, "complexity": 2},
			{"id": SILENCE, "label": "Молчать — решит именной"},
		],
	}


static func has_silence(w) -> bool:
	for o in w["options"]:
		if String(o["id"]) == SILENCE:
			return true
	return false
```

- [ ] **Step 2: Написать падающий тест `game/tests/cases/test_windows.gd`**

```gdscript
extends RefCounted
## Окна, приказы, эфир и молчание.

const Assert := preload("res://tests/assert.gd")
const Fixture := preload("res://tests/fixtures/small_mission.gd")
const Plan := preload("res://sim/plan.gd")
const Sim := preload("res://sim/sim.gd")
const WindowScript := preload("res://sim/window.gd")


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

	return t.results
```

- [ ] **Step 3: Прогнать — ожидаем провал**

Expected: `LOAD FAIL  res://tests/cases/test_windows.gd`, `код: 1`.

- [ ] **Step 4: Дополнить `game/sim/sim.gd`**

Добавить константу рядом с остальными `preload`:

```gdscript
const WindowScript := preload("res://sim/window.gd")
```

В `advance()` вставить `_maybe_open_window()` **последним** — после `_check_end()`. Порядок именно такой: окно открывается в конце шага, чтобы уже завершённая миссия не оставляла висящее неразрешимое окно. Это подтверждено реализацией задачи 8 и зафиксировано здесь как единственный источник правды.

**И отдельно — движение обязано упираться в запертую дверь.** Без этого агент пройдёт сквозь неё, окно не откроется, и весь Task 8 не имеет смысла. В `_advance_own()` сразу после получения ребра `e` добавить:

```gdscript
		if bool(e.get("locked", false)):
			continue                  # упёрлись в запертую дверь: её откроет окно
```

Добавить методы:

```gdscript
## Окно открывается, когда план упёрся в запертую дверь.
func _maybe_open_window() -> void:
	current_window = null
	for a in own:
		if a.is_dead() or a.node == plan.exit_node:
			continue
		if a.waypoint_index >= a.waypoints.size():
			continue
		var target := String(a.waypoints[a.waypoint_index])
		var e: Dictionary = mission.edge_between(a.node, target)
		if e.is_empty():
			continue
		if bool(e.get("locked", false)) and a.node == String(e["a"]):
			current_window = WindowScript.locked_door(String(e["id"]), a.id)
			_emit("window_opened", {"kind": "locked_door", "edge": e["id"], "agent": a.id})
			return


## Приказ или молчание. Возвращает решение и причину отказа, если он есть.
func order(option_id: String) -> Dictionary:
	if current_window == null:
		return {"accepted": false, "reason": "no_window"}
	var w: Dictionary = current_window
	if option_id == WindowScript.SILENCE:
		var eff := _resolve_silence(w)
		_apply_silence(w, eff)
		current_window = null
		_emit("order_silenced", {"window": w["id"], "effect": eff})
		return {"accepted": true, "kind": "silence", "effect": eff}
	# Проверка варианта — ДО списания. Иначе опечатка в идентификаторе сожгла бы
	# приказ, добавила передачу в эфир и вернула «принято» — а харнесс задачи 11
	# верит полю accepted и не отступил бы к молчанию.
	var known := false
	for o in w["options"]:
		if String(o["id"]) == option_id:
			known = true
	if not known:
		_emit("order_refused", {"window": w["id"], "reason": "unknown_option"})
		return {"accepted": false, "reason": "unknown_option"}
	if orders_left <= 0:
		_emit("order_refused", {"window": w["id"], "reason": "no_orders"})
		return {"accepted": false, "reason": "no_orders"}
	if not radio.can_speak(scales.step):
		_emit("order_refused", {"window": w["id"], "reason": "jammed"})
		return {"accepted": false, "reason": "jammed"}
	orders_left -= 1
	var tx: Dictionary = radio.transmit(scales.step)
	_apply_option(w, option_id)
	current_window = null
	_emit("order_issued", {"window": w["id"], "option": option_id, "radio": tx})
	return {"accepted": true, "kind": "order", "transmit": tx}


## Импровизация — единственное место с кубиком (D7). Ровно поэтому seed обязателен.
func _resolve_silence(w: Dictionary) -> Dictionary:
	var comms = null
	var tactician = null
	for a in own:
		if a.is_dead():
			continue
		match a.role:
			"comms":
				comms = a
			"tactician":
				tactician = a
	if comms == null:
		return {"by": "tactician" if tactician != null else "nobody", "quality": "safe"}
	var roll := rng.randf()
	if roll < 0.5:
		return {"by": "comms", "quality": "good"}
	if roll < 0.8:
		return {"by": "comms", "quality": "neutral"}
	return {"by": "comms", "quality": "bad"}


## Приказ из окна. Все эффекты — здесь, чтобы правило жило в одном месте.
func _apply_option(w: Dictionary, option_id: String) -> void:
	var chosen: Dictionary = {}
	for o in w["options"]:
		if String(o["id"]) == option_id:
			chosen = o
	if chosen.is_empty():
		return
	var noise := int(chosen.get("noise", 0))
	if noise > 0:
		scales.add_noise(noise)
	_apply_delay(w, int(chosen.get("delay", 0)))
	_unlock(w)


func _apply_silence(w: Dictionary, eff: Dictionary) -> void:
	match String(eff["quality"]):
		"good":
			pass                      # связист нашёл способ: дверь открыта, времени не потрачено
		"neutral":
			_apply_delay(w, 3)
		"bad":
			_apply_delay(w, 3)
			scales.add_noise(5)       # шум, которого никто не планировал
		_:
			_apply_delay(w, 3)        # тактик обходит: дольше, но тихо
	_unlock(w)


func _apply_delay(w: Dictionary, amount: int) -> void:
	if amount <= 0:
		return
	for a in own:
		if a.id == String(w.get("agent", "")):
			a.delay += amount


func _unlock(w: Dictionary) -> void:
	var edge_id := String(w.get("edge", ""))
	if edge_id != "":
		mission.edge(edge_id)["locked"] = false


## Свидетель. Один триггер ранит, три убивают — не наоборот (design.md §13.5).
func _compromise(agent) -> void:
	agent.add_trigger()
	scales.add_noise(5)
	_emit("agent_compromised", {"agent": agent.id, "state": agent.state, "triggers": agent.triggers})
```

- [ ] **Step 5: Прогнать — ожидаем зелёный**

Expected: `failed: 0`, `код: 0`.

- [ ] **Step 6: Закоммитить**

```powershell
git add game/sim/window.gd game/sim/sim.gd game/tests/cases/test_windows.gd game/tests/run.gd
git commit -m "feat(sim): окна решений, приказы, эфир и импровизация именного"
```

---


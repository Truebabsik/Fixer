### Task 9: Тревога, группа реагирования, блокировка путей

**Files:**
- Modify: `game/sim/response.gd` (заменить заглушку)
- Modify: `game/sim/sim.gd` (взвод тревоги в `advance`, `_check_end`)
- Create: `game/tests/cases/test_response.gd`
- Modify: `game/tests/run.gd`

**Interfaces:**
- Consumes: `Scales.Alarm.ALARM`.
- Produces: `Response.engage(step)`, `active`, `alarm_step`, `steps_since(step)`, `has_arrived(step)`, `perimeter_closed(step)`, `edge_blocked(kind, step)`; события `alarm_raised`, `path_blocked`, `mission_ended`.

**Числа — `docs/spr/scales.md` §5:** прибытие через 10 шагов, периметр через 15, грузовой лифт живёт 3 шага после тревоги, пассажирский встаёт мгновенно, лестница не блокируется никогда.

**Решение, которое надо знать:** блокировка проверяется **только когда агент начинает переход** (`progress == 0`). Лифт, который уже поехал, назад не отзывают — иначе игрок будет наказан за то, что не мог предвидеть.

- [ ] **Step 1: Написать падающий тест `game/tests/cases/test_response.gd`**

```gdscript
extends RefCounted
## Тревога — перелом (D16). Из подвала уйти можно, с 4-го этажа — нет.

const Assert := preload("res://tests/assert.gd")
const Fixture := preload("res://tests/fixtures/small_mission.gd")
const Plan := preload("res://sim/plan.gd")
const Sim := preload("res://sim/sim.gd")


func _make(route: Array):
	var m = Fixture.build()
	var p := Plan.new()
	p.route = route
	p.exit_node = "dock"
	p.agents = [{"id": "kira", "role": "tactician", "understanding": 3}]
	var sim := Sim.new()
	# noise_start = 25: тревога взводится на первом же шаге
	sim.setup(m, p, {"orders": 3, "seed": 1, "noise_start": 25})
	return sim


func _run_until_end(sim, limit := 60) -> void:
	var i := 0
	while not sim.finished and i < limit:
		sim.advance()
		i += 1


func _has(sim, type: String) -> bool:
	for e in sim.events:
		if String(e["type"]) == type:
			return true
	return false


func run() -> Array:
	var t := Assert.new()

	# 1. Тревога взводится сама и блокирует пассажирский лифт.
	# Маршрут начинается в холле, а не на выходе: агенту нужно куда-то идти,
	# чтобы было видно, как тревога перекрывает пути.
	var rise = _make(["hall"])
	rise.advance()
	t.is_true("тревога взведена", rise.response.active)
	t.is_true("пассажирский лифт закрыт", rise.response.edge_blocked("lift_main", rise.scales.step))
	t.is_false("лестница открыта", rise.response.edge_blocked("stairs", rise.scales.step))
	t.is_true("грузовой пока жив", not rise.response.edge_blocked("lift_freight", rise.scales.step))
	for i in 4:
		rise.advance()
	t.is_true("грузовой закрылся с задержкой", rise.response.edge_blocked("lift_freight", rise.scales.step))

	# 2. Из подвала уходим грузовым лифтом до прибытия группы.
	var away = _make(["dock", "archive0"])
	_run_until_end(away)
	t.is_true("цель взята", away.result()["objective_done"])
	t.eq("исход — ушли", String(away.result()["outcome"]), "extracted")
	t.is_true("группа ещё не приехала", away.scales.step < 11)

	# 3. С 4-го этажа пешком не успеть: лифт закрыт, лестница длинная.
	var stuck = _make(["dock", "hall", "it4"])
	_run_until_end(stuck)
	t.is_true("упёрлись в закрытый лифт", _has(stuck, "path_blocked"))
	t.eq("исход — накрыли", String(stuck.result()["outcome"]), "caught")
	t.is_true("группа приехала", stuck.response.has_arrived(stuck.scales.step))

	# 4. Без тревоги лифт работает.
	var calm = _make(["dock", "hall", "it4"])
	calm.scales.noise = 0
	for i in 5:
		calm.advance()
	t.eq("до тревоги лифт довёз", calm.own[0].node, "it4")

	# 5. Все погибли — это НЕ успешный уход, даже если цель взята.
	# Мёртвые пропускаются в проверке «все на выходе», поэтому без счётчика живых
	# полностью погибшая группа проходила бы как extracted.
	var lost = _make(["dock"])
	lost.objective_done = true
	for i in 3:
		lost.own[0].add_trigger()
	lost._check_end()
	t.is_true("боец мёртв", lost.own[0].is_dead())
	t.is_false("все погибшие — не extracted", String(lost.result()["outcome"]) == "extracted")

	return t.results
```

- [ ] **Step 2: Прогнать — ожидаем провал**

Expected: провал на `response.active`/`edge_blocked` — заглушка не блокирует лифт, `код: 1`.

- [ ] **Step 3: Заменить `game/sim/response.gd` целиком**

```gdscript
extends RefCounted
## Группа реагирования. Тревога — не провал, а перелом: тихая половина кончилась,
## началась гонка (D16).
##
## Числа — docs/spr/scales.md §5. Лестница не блокируется никогда (D19):
## после тревоги она остаётся единственным путём, и он самый медленный.

const ARRIVE_STEPS := 10
const PERIMETER_STEPS := 15
const FREIGHT_GRACE := 3

var active := false
var alarm_step := -1


func engage(step: int) -> void:
	if active:
		return
	active = true
	alarm_step = step


func steps_since(step: int) -> int:
	return step - alarm_step if active else 0


func has_arrived(step: int) -> bool:
	return active and steps_since(step) >= ARRIVE_STEPS


func perimeter_closed(step: int) -> bool:
	return active and steps_since(step) >= PERIMETER_STEPS


func edge_blocked(kind: String, step: int) -> bool:
	if not active:
		return false
	match kind:
		"lift_main":
			return true
		"lift_freight":
			return steps_since(step) > FREIGHT_GRACE
		_:
			return false
```

- [ ] **Step 4: Дополнить `game/sim/sim.gd`**

В `advance()` сразу после `radio.tick_decay(...)` вставить:

```gdscript
	if scales.alarm_state() == Scales.Alarm.ALARM and not response.active:
		response.engage(scales.step)
		_emit("alarm_raised", {"step": scales.step})
```

В `_advance_own()` заменить условие блокировки так, чтобы оно проверялось только на старте перехода:

```gdscript
		if a.progress == 0 and response.edge_blocked(String(e["kind"]), scales.step):
			_emit("path_blocked", {"agent": a.id, "edge": e["id"], "kind": e["kind"]})
			continue
```

Заменить заглушку `_check_end` на:

```gdscript
func _check_end() -> void:
	if finished:
		return
	# Уход засчитывается ТОЛЬКО после взятой цели. Иначе агент, стартующий на
	# выходе (а такие маршруты есть в тестах), завершал бы миссию на первом шаге.
	# И только если на выходе есть ЖИВОЙ: «все погибли» — это не успешный уход.
	if objective_done:
		var alive := 0
		var all_out := true
		for a in own:
			if a.is_dead():
				continue
			alive += 1
			if a.node != plan.exit_node:
				all_out = false
		if alive > 0 and all_out:
			finished = true
			outcome = "extracted"
			_emit("mission_ended", {"outcome": outcome})
			return
	if response.has_arrived(scales.step):
		finished = true
		outcome = "caught"
		_emit("mission_ended", {"outcome": outcome})
		return
	if scales.step >= MAX_STEPS:
		finished = true
		outcome = "timeout"
		_emit("mission_ended", {"outcome": outcome})
```

**Почему здесь нет исхода «ушли без данных» (`aborted`).** В П1 ничто его не порождает: отступление как выбор игрока появится в П2 вместе с фазой планирования. Ветка была бы недостижима, а до этой правки — ещё и вредна (см. комментарий в коде). Вернуть её — задача П2.

Заменить заглушку `_check_objective` на:

```gdscript
func _check_objective() -> void:
	if objective_done:
		return
	for a in own:
		if a.is_dead():
			continue
		if a.node == mission.objective:
			objective_done = true
			_emit("objective_reached", {"agent": a.id, "node": a.node})
			# На выход идут ВСЕ живые, а не только тот, кто взял цель. Иначе
			# группа из двух бойцов никогда не соберётся на выходе, а конец
			# миссии требует именно всех — и уход не зачтётся никогда.
			for b in own:
				if b.is_dead():
					continue
				b.waypoints = [b.node, plan.exit_node]
				b.waypoint_index = 1
				b.progress = 0
			return
```

**Упрощение, которое надо знать:** после взятия цели маршрут заменяется прямым отрезком «цель → выход». Поиск пути появится в П2; здесь важно, что между целью и выходом есть ребро, и тест это проверяет.

- [ ] **Step 5: Прогнать — ожидаем зелёный**

Expected: `failed: 0`, `код: 0`. Если тест 1 падает на «грузовой пока жив» — проверить, что проверка блокировки стоит именно до инкремента `progress` и только при `progress == 0`.

- [ ] **Step 6: Закоммитить**

```powershell
git add game/sim/response.gd game/sim/sim.gd game/tests/cases/test_response.gd game/tests/run.gd
git commit -m "feat(sim): тревога как перелом, группа реагирования, блокировка путей"
```

---


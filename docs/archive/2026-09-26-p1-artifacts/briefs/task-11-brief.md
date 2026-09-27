### Task 11: Харнесс — прогон сценария и проверка детерминизма

**Files:**
- Create: `game/sim/harness.gd`
- Create: `game/tests/cases/test_harness.gd`
- Modify: `game/tests/run.gd`

**Interfaces:**
- Consumes: `Sim`.
- Produces: `Harness.run_scenario(mission, plan, script := [], config := {}) -> Dictionary` (исход + `digest`), `Harness.digest(result) -> String`.

**Зачем:** это и есть инструмент, ради которого построено всё ядро. Любую гипотезу баланса («а если не брать хакера», «а если шуметь») проверяем одной строкой и получаем код возврата.

- [ ] **Step 1: Написать падающий тест `game/tests/cases/test_harness.gd`**

```gdscript
extends RefCounted
## Прогон сценариев и детерминизм: один вход — один исход.

const Assert := preload("res://tests/assert.gd")
const Fixture := preload("res://tests/fixtures/small_mission.gd")
const Plan := preload("res://sim/plan.gd")
const Harness := preload("res://sim/harness.gd")


func _plan(route: Array):
	var p := Plan.new()
	p.route = route
	p.exit_node = "dock"
	p.agents = [
		{"id": "kira", "role": "tactician", "understanding": 3},
		{"id": "echo", "role": "comms", "understanding": 3},
	]
	return p


func run() -> Array:
	var t := Assert.new()
	var route := ["dock", "hall", "office2", "vault"]

	# ВАЖНО: миссию строим заново на каждый прогон. `_unlock` правит миссию
	# НА МЕСТЕ, поэтому переиспользованный объект — это уже другой вход: второй
	# прогон увидел бы дверь открытой, не дошёл бы до окна и получил бы другой исход.

	# 1. Прогон даёт полный отчёт.
	var r: Dictionary = Harness.run_scenario(Fixture.build(), _plan(route), ["breach"], {"seed": 5})
	for key in ["outcome", "steps", "objective_done", "orders_left", "noise", "radio", "imprint", "alarm", "injured", "dead", "positions", "digest"]:
		t.is_true("в отчёте есть %s" % key, r.has(key))
	t.eq("приказ потрачен", r["orders_left"], 2)
	# Эфир затухает: к концу миссии он успевает остыть. Несмываемое свидетельство
	# передачи — отпечаток (D33), по нему и сверяем факт передачи.
	t.eq("передача была одна", r["imprint"], 1)
	t.is_true("эфир успел остыть", int(r["radio"]) < 8)

	# 2. Детерминизм: тот же вход — тот же отпечаток.
	var again: Dictionary = Harness.run_scenario(Fixture.build(), _plan(route), ["breach"], {"seed": 5})
	t.eq("повтор совпал", again["digest"], r["digest"])

	# 3. Другой сценарий — другой исход (иначе сценарий ни на что не влияет).
	var silent: Dictionary = Harness.run_scenario(Fixture.build(), _plan(route), ["silence"], {"seed": 5})
	t.is_true("молчание отличается от приказа", silent["digest"] != r["digest"])
	t.eq("молчание не тратит приказы", silent["orders_left"], 3)
	t.eq("молчание не шумит в эфире", silent["radio"], 0)
	t.eq("молчание не оставляет отпечатка", silent["imprint"], 0)

	# 4. Короткий сценарий: кончились ответы — дальше игрок молчит.
	var short: Dictionary = Harness.run_scenario(Fixture.build(), _plan(["dock"]), [], {"seed": 5})
	t.is_true("исход есть", String(short["outcome"]) != "")

	# 5. Тревога и уход из подвала воспроизводятся через харнесс.
	var run_away: Dictionary = Harness.run_scenario(
		Fixture.build(), _plan(["dock", "archive0"]), [], {"seed": 5, "noise_start": 25}
	)
	t.eq("ушли из подвала", String(run_away["outcome"]), "extracted")
	t.is_true("цель взята", run_away["objective_done"])

	# 6. Импровизация связиста тоже детерминирована через харнесс.
	var crew := ["dock", "hall", "office2", "vault"]
	var i1: Dictionary = Harness.run_scenario(Fixture.build(), _plan(crew), ["silence"], {"seed": 99})
	var i2: Dictionary = Harness.run_scenario(Fixture.build(), _plan(crew), ["silence"], {"seed": 99})
	t.eq("импровизация воспроизводима", i1["digest"], i2["digest"])

	return t.results
```

- [ ] **Step 2: Прогнать — ожидаем провал**

Expected: `LOAD FAIL  res://tests/cases/test_harness.gd`, `код: 1`.

- [ ] **Step 3: Написать `game/sim/harness.gd`**

```gdscript
extends RefCounted
## Прогон сценария: миссия + план + последовательность ответов на окна → исход.
##
## Сценарий — список id вариантов. Когда список кончился, игрок молчит:
## это и есть поведение по умолчанию (D23), поэтому пустой сценарий валиден
## и означает «игрок не вмешивался ни разу».

const Sim := preload("res://sim/sim.gd")


static func run_scenario(mission, plan, script: Array = [], config := {}) -> Dictionary:
	var sim := Sim.new()
	sim.setup(mission, plan, config)
	var index := 0
	var guard := 0
	while not sim.finished and guard < Sim.MAX_STEPS * 2:
		if sim.current_window != null:
			var choice := "silence"
			if index < script.size():
				choice = String(script[index])
			index += 1
			var res: Dictionary = sim.order(choice)
			if not bool(res.get("accepted", false)) and choice != "silence":
				sim.order("silence")
		else:
			sim.advance()
		guard += 1
	var out: Dictionary = sim.result()
	out["digest"] = digest(out)
	return out


## Отпечаток исхода для проверки детерминизма: только смысловые поля, без событий.
static func digest(result: Dictionary) -> String:
	var parts: Array = []
	for key in ["outcome", "steps", "objective_done", "orders_left", "noise", "radio", "imprint", "alarm", "injured", "dead", "positions"]:
		parts.append("%s=%s" % [key, str(result.get(key))])
	return "|".join(parts)
```

- [ ] **Step 4: Прогнать — ожидаем зелёный**

Expected: `tests: ...`, `failed: 0`, `код: 0`.

- [ ] **Step 5: Прогнать весь набор через `--check-only` и полный прогон**

```powershell
& "F:\WORK\Fixer\tools\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path "F:\WORK\Fixer\game" --check-only --script res://tests/run.gd; "разбор: $LASTEXITCODE"
& "F:\WORK\Fixer\tools\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path "F:\WORK\Fixer\game" --script res://tests/run.gd; "тесты: $LASTEXITCODE"
```
Expected: разбор `0`, тесты `0`.

- [ ] **Step 6: Закоммитить**

```powershell
git add game/sim/harness.gd game/tests/cases/test_harness.gd game/tests/run.gd
git commit -m "feat(sim): харнесс прогонов и проверка детерминизма"
```

---

## Что этот план НЕ делает

Осознанно за бортом П1 — чтобы не строить конвейер до того, как проверена модель:

- **Загрузка миссии из JSON.** Миссии в П1 собираются кодом-фикстурой. Контент-конвейер — П3.
- **Поиск пути.** Маршрут задаётся явным списком помещений; после взятия цели — прямой отрезок «цель → выход».
- **Переключение на запасной маршрут** при блокировке. В П1 агент встаёт и сообщает `path_blocked`; выбор запасного пути — задача интерфейса планирования (П2).
- **Направление взгляда и «заметил, но не понял».** Контакт = один узел, без геометрии.
- **Интерфейс, карта, призраки на экране.** П2.

## Самопроверка плана

- **Покрытие документа.** Шум и тревога — Task 2, эфир — Task 3, Понимание — Task 4, вертикаль и стоимость переходов — Task 6, сенсоры и призраки — Task 7, окна и молчание — Task 8, тревога как перелом и группа реагирования — Task 9, ранения и обещание «один промах не убивает» — Task 10, харнесс и детерминизм — Task 11. Числа взяты из `spr/scales.md`, а не придуманы.
- **Что не покрыто и почему.** Цена специалистов и экономика миссии не проверяются кодом П1 — они лежат в данных (`spr/mercs.md`) и станут проверяемыми только с контент-конвейером. Доля вмешательства (цель 30–40 %) требует прогонов на реальной миссии, то есть после П3.
- **Имена и типы.** `Sim.setup/advance/order/result`, `Agent.add_trigger/speed_penalty/is_dead/is_own`, `Mission.edge/edges_at/edge_between/other_end/validate/validate_route`, `Plan.route/exit_node/exit_backup_node/agents`, `WindowScript.SILENCE/has_silence/locked_door`, `Radio.transmit/tick_decay/can_speak/is_intercepted`, `Response.engage/steps_since/has_arrived/perimeter_closed/edge_blocked`, `Harness.run_scenario/digest` — используются во всех задачах одинаково.
- **Места, где легко ошибиться.** (1) Порядок в `advance()`: часы, тревога, движение, контакты, видимость, цель, конец миссии, окно — окно последнее. (2) Проверка блокировки только при `progress == 0`. (3) `edge()` возвращает ссылку на словарь в массиве — `mission.edge(id)["locked"] = false` меняет миссию, и это намеренно.



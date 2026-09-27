### Task 10: Ранения, порог смерти, исход миссии

**Files:**
- Modify: `game/sim/sim.gd` (контакт с охраной → `_compromise`, детализация `result()`)
- Create: `game/tests/cases/test_casualties.gd`
- Modify: `game/tests/run.gd`

**Interfaces:**
- Consumes: `Sim._compromise(agent)`, `Agent.add_trigger()`.
- Produces: событие `agent_compromised`; в `result()` — `injured`, `dead`, `escaped`. Поля `cargo` здесь нет: выбор «копия или оригинал» — это контент миссии (П3), в П1 носить нечего.

**Инвариант, который тест обязан защищать:** **один промах убить не может.** Это не баланс, а обещание игроку (design.md §13.5). Если тест на это когда-нибудь упадёт — сломана не цифра, а обещание.

- [ ] **Step 1: Написать падающий тест `game/tests/cases/test_casualties.gd`**

```gdscript
extends RefCounted
## Ранения и порог смерти. Один промах не убивает — ни при каких настройках.

const Assert := preload("res://tests/assert.gd")
const Fixture := preload("res://tests/fixtures/small_mission.gd")
const Plan := preload("res://sim/plan.gd")
const Sim := preload("res://sim/sim.gd")
const Agent := preload("res://sim/agent.gd")


func _make(route: Array):
	var m = Fixture.build()
	var p := Plan.new()
	p.route = route
	p.exit_node = "dock"
	p.agents = [{"id": "kira", "role": "tactician", "understanding": 3}]
	var sim := Sim.new()
	sim.setup(m, p, {"orders": 3, "seed": 1})
	return sim


func run() -> Array:
	var t := Assert.new()
	var sim = _make(["dock"])

	# 1. Один триггер — ранение, не смерть.
	sim._compromise(sim.own[0])
	t.eq("состояние — ранен", sim.own[0].state, Agent.State.WOUNDED)
	t.is_false("после одного промаха не мёртв", sim.own[0].is_dead())

	# 2. Два — тяжёлый.
	sim._compromise(sim.own[0])
	t.eq("состояние — тяжёлый", sim.own[0].state, Agent.State.CRITICAL)
	t.is_false("и всё ещё жив", sim.own[0].is_dead())

	# 3. Три — смерть, и только тогда.
	sim._compromise(sim.own[0])
	t.eq("состояние — мёртв", sim.own[0].state, Agent.State.DEAD)
	t.is_true("мёртв", sim.own[0].is_dead())

	# 4. Свидетель шумит.
	t.eq("шум от трёх свидетелей", sim.scales.noise, 15)

	# 5. Отчёт миссии называет раненых и мёртвых.
	var rep: Dictionary = sim.result()
	t.is_true("мёртвый в отчёте", rep["dead"].has("kira"))
	t.eq("раненых нет — он уже мёртв", rep["injured"].size(), 0)

	# 6. Раненый движется медленнее и не успевает за здоровым.
	var slow = _make(["dock", "hall"])
	slow.own[0].add_trigger()
	slow.advance()
	t.eq("половина перехода позади", slow.own[0].node, "dock")
	slow.advance()
	t.eq("раненый дошёл за два шага", slow.own[0].node, "hall")

	# 7. Живой и вышедший попадает в escaped.
	var out = _make(["dock"])
	out.objective_done = true
	out._check_end()
	t.eq("исход — ушли", String(out.result()["outcome"]), "extracted")
	t.is_true("вышедший в отчёте", out.result()["escaped"].has("kira"))

	# 8. Никто не убит при верном прохождении: инвариант «один промах не убивает».
	# Маршрут идёт через док и подвал, где патруля нет: на этом кейсе проверяется
	# отсутствие смертей, а не взаимодействие с охраной (оно — в пункте 9).
	var clean = _make(["dock", "archive0", "dock"])
	for i in 10:
		clean.advance()
	t.eq("никто не погиб на пустой миссии", clean.result()["dead"].size(), 0)

	# 9. Контакт с охраной — один раз на помещение, а не каждый тик.
	# Иначе три тика в одном коридоре с патрулём убивали бы бойца, и обещание
	# «смерть — цена серии ошибок» превращалось бы в «цену трёх шагов».
	var contact = _make(["dock", "hall"])
	for i in 4:
		contact.advance()
	t.eq("контакт ранил", contact.own[0].state, Agent.State.WOUNDED)
	t.eq("триггер ровно один, хотя охрана возвращалась", contact.own[0].triggers, 1)
	t.is_false("и это не смерть", contact.own[0].is_dead())

	# 10. Двое в одном помещении с охраной — триггер у КАЖДОГО.
	# `return` вместо `break` в обходе охраны обрывал бы весь проход по группе, и
	# все, кто идёт в списке после первого засвеченного, не получали бы триггер
	# никогда — при том что группа из двух бойцов поддержана и в цели, и в молчании.
	var duo_mission = Fixture.build()
	var duo_plan := Plan.new()
	duo_plan.route = ["dock", "hall"]
	duo_plan.exit_node = "dock"
	duo_plan.agents = [
		{"id": "kira", "role": "tactician", "understanding": 3},
		{"id": "echo", "role": "comms", "understanding": 3},
	]
	var duo := Sim.new()
	duo.setup(duo_mission, duo_plan, {"orders": 3, "seed": 1})
	duo.advance()
	t.eq("первый засвечен", duo.own[0].triggers, 1)
	t.eq("второй тоже засвечен", duo.own[1].triggers, 1)

	return t.results
```

- [ ] **Step 2: Прогнать — ожидаем провал**

Expected: провал на пункте 4 или 5 — `_compromise` уже есть из Task 8, но `result()` пока не отдаёт `injured`/`dead` корректно для этого случая... Если всё зелёное сразу — это **провал планирования**, а не успех: значит, тест не проверяет ничего нового. В таком случае добавить проверку контакта с охраной (пункт 9): довести бойца в один узел с патрулём и убедиться, что `_compromise` вызывается самой симуляцией.

- [ ] **Step 3: Дополнить `game/sim/sim.gd` — контакт с охраной**

Добавить в `advance()` после `_update_visibility()` (окно вызывается последним, так что контакты оказываются раньше него):

```gdscript
	_check_contacts()
```

Порядок вызовов в `advance()` должен остаться таким: часы → тревога → движение своих → движение охраны → видимость → контакты → цель → конец миссии → окно. Окно последнее намеренно: завершённая миссия не должна оставлять открытое окно, которое уже некому разрешить.

И сам метод. **Контакт засчитывается один раз на помещение, а не каждый шаг** — иначе боец, задержавшийся в одном коридоре с патрулём, набирал бы три триггера за три тика и погибал, а обещание «смерть — цена серии ошибок» превращалось бы в «цену трёх шагов». Механика та же, что у контакта сенсора в задаче 7: фронт, а не поток.

Сначала добавить поле рядом с `ghost_reported`:

```gdscript
## id бойца -> помещение, где его уже засекли. Сбрасывается в setup().
var compromised_at: Dictionary = {}
```

и в `setup()`, рядом со сбросом `ghost_reported = {}`, добавить `compromised_at = {}`.

Затем сам метод:

```gdscript
## Охрана и свои в одном помещении — это увидение. Пока в лоб: без проверки
## направления взгляда и без «заметил, но не понял» (это П2).
## Засчитывается один раз на помещение: вернулся в то же помещение — это уже
## не новое увидение, и триггеры не капают за каждый тик.
func _check_contacts() -> void:
	for a in own:
		if a.is_dead():
			continue
		for g in guards:
			if g.node == a.node:
				if String(compromised_at.get(a.id, "")) != a.node:
					compromised_at[a.id] = a.node
					_compromise(a)
				break   # break, а не return: иначе все, кто идёт в списке после
				        # первого, не получат триггер даже в том же помещении
```

И одна правка в `result()`, которую задачи 7–9 не трогали: **мёртвый боец не может быть «вышедшим»**. Сейчас проверка ухода стоит вне ветки смерти, поэтому погибший, оставшийся на узле выхода, попадёт и в `dead`, и в `escaped`. Заменить тело цикла на:

```gdscript
	for a in own:
		if a.is_dead():
			dead.append(a.id)
			continue
		if a.state != Agent.State.OK:
			injured.append(a.id)
		if objective_done and a.node == plan.exit_node:
			escaped.append(a.id)
```

- [ ] **Step 4: Прогнать — ожидаем зелёный**

Expected: `failed: 0`, `код: 0`.

- [ ] **Step 5: Закоммитить**

```powershell
git add game/sim/sim.gd game/tests/cases/test_casualties.gd game/tests/run.gd
git commit -m "feat(sim): ранения, порог смерти и отчёт об исходе"
```

---


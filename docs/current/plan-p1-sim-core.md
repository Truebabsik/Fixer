# Ядро симуляции операции (П1) — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Построить детерминированное ядро операции без единого пикселя графики — такое, чтобы миссию можно было прогнать headless по сценарию приказов и получить проверяемый исход.

**Architecture:** Чистый GDScript на `RefCounted`, без нод, сцен и рендера. Ядро знает только граф помещений, агентов, шкалы и окна решений. Сверху — раннер тестов и харнесс прогона сценариев; вердикт обоих — код возврата процесса.

**Tech Stack:** Godot 4.7.2 stable (GDScript), PowerShell для запуска, никаких внешних зависимостей и тест-фреймворков.

**Spec:** [../../docs/design.md](../../docs/design.md) §13 · [../../levels/mission-01.md](../../levels/mission-01.md) · [../../docs/spr/scales.md](../../docs/spr/scales.md) · [../../docs/spr/channels.md](../../docs/spr/channels.md) · [../../docs/spr/mercs.md](../../docs/spr/mercs.md) · [../../docs/architecture.md](../../docs/architecture.md) · [../../docs/desions.md](../../docs/desions.md) (D7, D14, D20, D23, D29–D33)

## Global Constraints

- **Движок:** `tools/Godot_v4.7.2/Godot_v4.7.2-stable_win64_console.exe`. Версия 4.7.2.
- **Никаких `class_name` в `sim/` и `tests/`.** Только `const X := preload("res://...")`. Проверено: `class_name` не резолвится в headless-прогоне без обновления кэша классов, а `preload` — резолвится.
- **`sim/` не знает о нодах.** Ни `Node`, ни `SceneTree`, ни `preload` сцен, ни рендера. Только `RefCounted`.
- **Детерминизм обязателен.** Фиксированный порядок обхода (сортировка по id, никогда по порядку в словаре). Единственный источник случайности — `RandomNumberGenerator` с seed из конфига.
- **Вердикт — код возврата процесса.** `quit(0)` = зелёно, `quit(1)` = провал. Наличие текста в stderr — **не** признак провала: Godot пишет туда безобидный шум (`Failed to read the root certificate store`, `Cannot save file editor_settings`) даже при коде 0.
- **Числа берутся дословно** из `docs/spr/scales.md`. Не подбирать «на глаз» в коде.
- **Отступы — табы** (конвенция Godot). Идентификаторы английские, комментарии и имена тестов русские.
- **Объекты из `preload`-скриптов создавать через `:=`:** `var s := Scales.new()`. С обычным `=` переменная выходит **нетипизированной**, и любой последующий `var x := s.field` не компилируется (`Cannot infer the type`). По той же причине **никогда не применять `:=` к члену переменной, объявленной через `=`** — в тестах, где объект приходит из функции без аннотации (`var sim = _make(...)`), писать явный тип: `var before: int = sim.scales.step`.
- **Исключение из этого правила — объекты из функций без аннотации возврата** (такова фикстура: `static func build()` без `-> ...`). Там `:=` не выведет тип вовсе, а если аннотировать возврат как `RefCounted`, перестанет компилироваться доступ к членам. Поэтому для фикстуры и подобных ей фабрик **остаётся `=` и динамический доступ**. Правило про `:=` — про объекты, создаваемые напрямую из `preload`-константы (`Scales.new()`, `Plan.new()`).
- **Все команды выполнять из `F:\WORK\Fixer`.**

---

## Структура файлов

| Файл | Ответственность |
|---|---|
| `game/tests/assert.gd` | Мини-ассерты: копит результаты, ничего не печатает |
| `game/tests/run.gd` | Раннер: явный список кейсов, вердикт = код возврата |
| `game/tests/cases/test_runner.gd` | Самопроверка раннера |
| `game/sim/scales.gd` | Шум и три состояния тревоги. Плюс часы симуляции |
| `game/sim/radio.gd` | Эфир: затухание, глушение, отпечаток, перехват |
| `game/sim/understanding.gd` | Сложность приказа против Понимания |
| `game/sim/mission.gd` | Описание миссии: узлы, рёбра, патрули, сенсоры, цель + валидация |
| `game/sim/agent.gd` | Агент: позиция, маршрут, состояние, накопленные триггеры |
| `game/sim/plan.gd` | План игрока: вход, порядок этажей, отход, запасной отход, вес груза |
| `game/sim/window.gd` | Окно решения: ситуация и варианты |
| `game/sim/response.gd` | Группа реагирования: выезд, прибытие, блокировка путей |
| `game/sim/sim.gd` | Фасад: `setup` / `advance` / `order` / `result` |
| `game/sim/harness.gd` | Прогон сценария `{миссия, план, приказы}` → исход |
| `game/tests/fixtures/small_mission.gd` | Минимальная миссия для тестов |
| `game/tests/cases/test_*.gd` | По кейсу на файл |

Почему так: `sim/` разбит по одному правилу на файл (шкалы, эфир, понимание, отклик) — это ровно те правила, которые потом придётся крутить при балансировке, и их надо менять по отдельности. `sim.gd` — только композиция, без собственных правил.

---

### Task 1: Раннер тестов и мини-ассерты

**Files:**
- Create: `game/tests/assert.gd`
- Create: `game/tests/run.gd`
- Create: `game/tests/cases/test_runner.gd`

**Interfaces:**
- Consumes: ничего.
- Produces: `Assert` — объект с `results: Array`; методы `eq(name, actual, expected)`, `is_true(name, actual)`, `is_false(name, actual)`. Кейс — скрипт, `extends RefCounted`, с методом `run() -> Array` (возвращает `Assert.results`).

- [ ] **Step 1: Написать `game/tests/assert.gd`**

```gdscript
extends RefCounted
## Мини-ассерты. Никаких зависимостей и никакой печати: только список результатов.
## Печатает раннер — так один и тот же кейс годится и для прогона, и для отчёта.

var results: Array = []


func eq(name: String, actual, expected) -> void:
	results.append({
		"name": name,
		"ok": _same(actual, expected),
		"actual": actual,
		"expected": expected,
	})


func is_true(name: String, actual) -> void:
	eq(name, bool(actual), true)


func is_false(name: String, actual) -> void:
	eq(name, bool(actual), false)


## int и float сравниваем по значению, всё остальное — строго.
func _same(a, b) -> bool:
	if typeof(a) != typeof(b):
		var a_num := typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT
		var b_num := typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT
		if a_num and b_num:
			return is_equal_approx(float(a), float(b))
		return false
	return a == b
```

- [ ] **Step 2: Написать `game/tests/run.gd`**

```gdscript
extends SceneTree
## Раннер ядра. Вердикт — код возврата процесса: 0 зелёный, 1 есть провалы.
## Список кейсов явный: никакого сканирования каталогов, порядок фиксирован,
## поэтому прогон воспроизводим.

const CASES := [
	"res://tests/cases/test_runner.gd",
]


func _initialize() -> void:
	var total := 0
	var failed := 0
	for path in CASES:
		var case_script: GDScript = load(path)
		if case_script == null:
			print("LOAD FAIL  %s" % path)
			failed += 1
			continue
		var case_obj = case_script.new()
		var results: Array = case_obj.run()
		for r in results:
			total += 1
			if not bool(r["ok"]):
				failed += 1
				print("FAIL  %s :: %s" % [path.get_file(), str(r["name"])])
				print("      ожидалось: %s" % str(r["expected"]))
				print("      получено:  %s" % str(r["actual"]))
	print("tests: %d, failed: %d" % [total, failed])
	quit(1 if failed > 0 else 0)
```

- [ ] **Step 3: Написать `game/tests/cases/test_runner.gd` (проходит)**

```gdscript
extends RefCounted
## Самопроверка раннера: ассерты работают, результаты копятся.

const Assert := preload("res://tests/assert.gd")


func run() -> Array:
	var t := Assert.new()
	t.eq("целые равны", 2, 1 + 1)
	t.eq("int и float по значению", 1, 1.0)
	t.eq("строки равны", "ab", "a" + "b")
	t.is_true("истина", 1 == 1)
	t.is_false("ложь", 1 == 2)
	return t.results
```

- [ ] **Step 4: Прогнать — ожидаем зелёный и код 0**

Run:
```powershell
& "F:\WORK\Fixer\tools\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path "F:\WORK\Fixer\game" --script res://tests/run.gd; "код: $LASTEXITCODE"
```
Expected: строки `tests: 5, failed: 0` и `код: 0`.

- [ ] **Step 5: Проверить, что провал действительно ловится**

Временно добавить в `test_runner.gd` строку `t.eq("нарочно неверно", 1, 2)` и прогнать ту же команду.
Expected: `FAIL  test_runner.gd :: нарочно неверно`, `tests: 6, failed: 1`, `код: 1`.
Затем **удалить эту строку** и прогнать снова — снова `failed: 0`, `код: 0`.

Это не формальность: без этого шага мы не знаем, умеет ли раннер падать, и все дальнейшие «зелёные» прогоны ничего не стоят.

- [ ] **Step 6: Закоммитить**

```powershell
git add game/tests/assert.gd game/tests/run.gd game/tests/cases/test_runner.gd
git commit -m "test: раннер тестов ядра и мини-ассерты"
```

> **Правка после ревью (коммиты `1c0c98e`, `697184c`).** Ревью нашло, что раннер не гарантировал вердикт: кейс, падающий в рантайме, давал **ложный зелёный** (код 0), а кейс с синтаксической ошибкой — **зависание** (в обоих случаях `quit()` не вызывался). В `run.gd` добавлены: `can_instantiate()`, `has_method("run")`, проверка типа возврата, сторож в `_process` (превращает аборт `_initialize()` в код 1) и правило **«кейс без единого ассерта — провал»**. Интерфейс `run() -> Array` и явный `CASES` не менялись.
> **При переносе этой задачи в другой проект код раннера брать из репозитория, а не из сниппета выше** — сниппет оставлен как исходная редакция.
> Остаточное, вне задач П1: непустой `Dictionary` проходит проверку типа и падает позже на `r["ok"]`.

---

### Task 2: Шум и состояния тревоги

**Files:**
- Create: `game/sim/scales.gd`
- Create: `game/tests/cases/test_scales.gd`
- Modify: `game/tests/run.gd` (добавить кейс в `CASES`)

**Interfaces:**
- Consumes: ничего.
- Produces: `Scales` — объект с `noise: int`, `step: int`, `enum Alarm { QUIET, WARY, ALARM }`. Методы: `add_noise(amount: int) -> void`, `alarm_state() -> int`, `tick() -> void`. Константы: `NOISE_WARY = 10`, `NOISE_ALARM = 25`.

- [ ] **Step 1: Написать падающий тест `game/tests/cases/test_scales.gd`**

```gdscript
extends RefCounted
## Шум — невозобновляемый бюджет (D29). Пороги — docs/spr/scales.md §3.

const Assert := preload("res://tests/assert.gd")
const Scales := preload("res://sim/scales.gd")


func run() -> Array:
	var t := Assert.new()

	var s := Scales.new()
	t.eq("на старте тихо", s.alarm_state(), Scales.Alarm.QUIET)

	s.add_noise(9)
	t.eq("9 шума — ещё тихо", s.alarm_state(), Scales.Alarm.QUIET)

	s.add_noise(1)
	t.eq("10 шума — настороже", s.alarm_state(), Scales.Alarm.WARY)

	s.add_noise(14)
	t.eq("24 шума — ещё настороже", s.alarm_state(), Scales.Alarm.WARY)

	s.add_noise(1)
	t.eq("25 шума — тревога", s.alarm_state(), Scales.Alarm.ALARM)

	# Шум не затухает: бюджет, а не след (D29).
	var before := s.noise
	for i in 50:
		s.tick()
	t.eq("через 50 шагов шум не уменьшился", s.noise, before)
	t.eq("счётчик шагов идёт", s.step, 50)

	# Тревога необратима.
	t.eq("тревога держится", s.alarm_state(), Scales.Alarm.ALARM)

	return t.results
```

- [ ] **Step 2: Прогнать — ожидаем провал загрузки**

Run:
```powershell
& "F:\WORK\Fixer\tools\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path "F:\WORK\Fixer\game" --script res://tests/run.gd; "код: $LASTEXITCODE"
```
Expected: `LOAD FAIL  res://tests/cases/test_scales.gd`, `код: 1` — файла `sim/scales.gd` ещё нет.

- [ ] **Step 3: Написать `game/sim/scales.gd`**

```gdscript
extends RefCounted
## Шум и состояния тревоги. Числа — docs/spr/scales.md §3, дословно.
##
## Шум НЕ затухает: это бюджет миссии, а не след. Всё, что сделано громко,
## вычитается навсегда — поэтому громкие решения необратимы (D29).

enum Alarm { QUIET, WARY, ALARM }

const NOISE_WARY := 10
const NOISE_ALARM := 25

var noise: int = 0
var step: int = 0


func add_noise(amount: int) -> void:
	noise += amount


func alarm_state() -> int:
	if noise >= NOISE_ALARM:
		return Alarm.ALARM
	if noise >= NOISE_WARY:
		return Alarm.WARY
	return Alarm.QUIET


func tick() -> void:
	step += 1
```

- [ ] **Step 4: Прогнать кейс — ожидаем зелёный**

Сначала добавить в `CASES` в `run.gd` строку `"res://tests/cases/test_scales.gd",`.
Run: та же команда.
Expected: `failed: 0`, `код: 0`. Общее число тестов не фиксируем: оно растёт с каждой задачей, а ворота — `failed: 0`.

- [ ] **Step 5: Закоммитить**

```powershell
git add game/sim/scales.gd game/tests/cases/test_scales.gd game/tests/run.gd
git commit -m "feat(sim): шум и три состояния тревоги"
```

---

### Task 3: Эфир — затухание, глушение, отпечаток, перехват

**Files:**
- Create: `game/sim/radio.gd`
- Create: `game/tests/cases/test_radio.gd`
- Modify: `game/tests/run.gd`

**Interfaces:**
- Consumes: ничего.
- Produces: `Radio` — объект с `radio: int`, `imprint: int`, `jam_until_step: int`. Методы: `transmit(step: int) -> Dictionary` (возвращает `{"radio", "imprint", "jammed", "intercepted"}`), `tick_decay(step: int) -> void`, `can_speak(step: int) -> bool`, `is_intercepted() -> bool`.

- [ ] **Step 1: Написать падающий тест `game/tests/cases/test_radio.gd`**

```gdscript
extends RefCounted
## Эфир — отдельная шкала (D33). Числа — docs/spr/scales.md §3.1.
## Закон миссии: использовать все приказы = тебя услышали.

const Assert := preload("res://tests/assert.gd")
const Radio := preload("res://sim/radio.gd")


func run() -> Array:
	var t := Assert.new()

	# 1. Две передачи подряд глушат канал.
	var r := Radio.new()
	var step := 0
	r.transmit(step)
	t.eq("после первой передачи эфир 8", r.radio, 8)
	t.is_true("после первой передачи говорить можно", r.can_speak(step))

	var second: Dictionary = r.transmit(step)
	t.eq("после второй эфир 16", r.radio, 16)
	t.is_true("вторая передача заглушила", second["jammed"])
	t.is_false("право голоса потеряно", r.can_speak(step))

	# 2. Глушение проходит за 8 шагов.
	for i in 8:
		r.tick_decay(step)
		step += 1
	t.is_true("через 8 шагов снова можно говорить", r.can_speak(step))

	# 3. Три передачи с паузами: канал чист, но есть перехват.
	# Смысл проверки — не «успел ли канал восстановиться к концу», а «глушило ли
	# хоть раз за весь ход». Раньше здесь стояла проверка can_speak в конце, и она
	# пропускала модель, в которой паузы не помогали вовсе (D34).
	var r2 := Radio.new()
	var jammed_ever := false
	step = 0
	for i in 3:
		var res: Dictionary = r2.transmit(step)
		if bool(res["jammed"]):
			jammed_ever = true
		for j in 10:
			r2.tick_decay(step)
			step += 1
	t.is_false("с паузами не глушит ни разу", jammed_ever)
	t.is_true("но три передачи — перехват", r2.is_intercepted())

	# 4. Затухание: −4 за каждые 5 шагов (D34).
	var r3 := Radio.new()
	r3.transmit(0)
	t.eq("эфир 8", r3.radio, 8)
	for i in 5:
		r3.tick_decay(i)
	t.eq("через 5 шагов эфир 4", r3.radio, 4)
	for i in 5:
		r3.tick_decay(i + 5)
	t.eq("через 10 шагов эфир 0", r3.radio, 0)

	# 5. Отпечаток не затухает.
	t.eq("отпечаток не смылся", r3.imprint, 1)

	return t.results
```

- [ ] **Step 2: Прогнать — ожидаем провал**

Run: команда из Task 1 Step 4 (добавив кейс в `CASES` заранее).
Expected: `LOAD FAIL  res://tests/cases/test_radio.gd`, `код: 1`.

- [ ] **Step 3: Написать `game/sim/radio.gd`**

```gdscript
extends RefCounted
## Радиоэфир. Отдельная шкала от шума команды (D33): наказание за разговор
## должно попадать в право голоса, а не в безопасность группы.
##
## Два ресурса с разными законами:
##   шум команды  — НЕ затухает (бюджет),
##   эфир         — затухает (след: чтобы засечь передатчик, его надо слышать).
## Отпечаток передач не затухает никогда.
## Числа — docs/spr/scales.md §3.1.

const PER_TRANSMIT := 8
const DECAY := 4
const DECAY_PERIOD := 5
const JAM_THRESHOLD := 12
const JAM_STEPS := 8
const IMPRINT_PER_TRANSMIT := 1
const IMPRINT_INTERCEPT := 3

var radio: int = 0
var imprint: int = 0
var jam_until_step: int = -1


## Выход в эфир. Возвращает, чем это обернулось прямо сейчас.
func transmit(step: int) -> Dictionary:
	radio += PER_TRANSMIT
	imprint += IMPRINT_PER_TRANSMIT
	var jammed := false
	if radio >= JAM_THRESHOLD and can_speak(step):
		jam_until_step = step + JAM_STEPS
		jammed = true
	return {
		"radio": radio,
		"imprint": imprint,
		"jammed": jammed,
		"intercepted": is_intercepted(),
	}


func tick_decay(step: int) -> void:
	if step % DECAY_PERIOD == DECAY_PERIOD - 1 and radio > 0:
		radio = maxi(0, radio - DECAY)


func can_speak(step: int) -> bool:
	return step >= jam_until_step


func is_intercepted() -> bool:
	return imprint >= IMPRINT_INTERCEPT
```

- [ ] **Step 4: Прогнать — ожидаем зелёный**

Expected: `tests: ...`, `failed: 0`, `код: 0`.

- [ ] **Step 5: Закоммитить**

```powershell
git add game/sim/radio.gd game/tests/cases/test_radio.gd game/tests/run.gd
git commit -m "feat(sim): эфир — затухание, глушение, отпечаток, перехват"
```

---

### Task 4: Понимание — сложность приказа против понимания

**Files:**
- Create: `game/sim/understanding.gd`
- Create: `game/tests/cases/test_understanding.gd`
- Modify: `game/tests/run.gd`

**Interfaces:**
- Consumes: ничего.
- Produces: `Understanding` — статический метод `resolves_literally(complexity: int, understanding: int) -> bool`.

- [ ] **Step 1: Написать падающий тест `game/tests/cases/test_understanding.gd`**

```gdscript
extends RefCounted
## Понимание — детерминированная проверка, без кубика (D31).
## Таблица — docs/spr/mercs.md §1.

const Assert := preload("res://tests/assert.gd")
const Understanding := preload("res://sim/understanding.gd")


func run() -> Array:
	var t := Assert.new()
	# Строки — Понимание 3/2/1/0, столбцы — сложность 1/2/3.
	var table := [
		[false, false, false],  # понимание 3: всё точно
		[false, false, true],   # понимание 2: сложный приказ — буквально
		[false, true, true],    # понимание 1: средний и сложный — буквально
		[true, true, true],     # понимание 0: даже простой — буквально
	]
	for u in 4:
		var understanding := 3 - u
		for c in 3:
			var complexity := c + 1
			var name := "понимание %d, сложность %d" % [understanding, complexity]
			t.eq(name, Understanding.resolves_literally(complexity, understanding), table[u][c])
	return t.results
```

- [ ] **Step 2: Прогнать — ожидаем провал**

Expected: `LOAD FAIL  res://tests/cases/test_understanding.gd`, `код: 1`.

- [ ] **Step 3: Написать `game/sim/understanding.gd`**

```gdscript
extends RefCounted
## Понимание: исполнит ли боец приказ так, как задумано, или буквально.
##
## Буквальность — это НЕ провал, а окно: исполнил ровно сказанное и создал
## новую проблему. Кубика здесь нет — сравнение детерминировано (D31),
## поэтому дешёвая команда предсказуемо плоха, а не «слаба по статам».
## Таблица — docs/spr/mercs.md §1.


## complexity 1..3 — число условий в приказе, understanding 0..3 — качество бойца.
static func resolves_literally(complexity: int, understanding: int) -> bool:
	return complexity > understanding
```

- [ ] **Step 4: Прогнать — ожидаем зелёный**

Expected: `failed: 0`, `код: 0`.

- [ ] **Step 5: Закоммитить**

```powershell
git add game/sim/understanding.gd game/tests/cases/test_understanding.gd game/tests/run.gd
git commit -m "feat(sim): понимание как детерминированная проверка сложности приказа"
```

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
		if a.node == plan.exit_node:
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

### Task 8: Окна решений, приказы, эфир и молчание

**Files:**
- Create: `game/sim/window.gd`
- Modify: `game/sim/sim.gd` (окна, `order()`, применение вариантов, разрешение молчания)
- Create: `game/tests/cases/test_windows.gd`
- Modify: `game/tests/run.gd`

**Interfaces:**
- Consumes: `Radio`, `Understanding`, `Agent.role`.
- Produces:
  - `Window.locked_door(edge_id, agent_id) -> Dictionary`, `Window.SILENCE = "silence"`.
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
const Window := preload("res://sim/window.gd")


func _make(config := {}, agents := null):
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
	t.is_true("у окна всегда есть молчание", Window.has_silence(sim.current_window))
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

	# 4. Отказы приходят с причиной.
	var sim3 = _make({"orders": 0})
	_to_window(sim3)
	var no_orders: Dictionary = sim3.order("breach")
	t.is_false("без приказов отказ", no_orders["accepted"])
	t.eq("причина названа", String(no_orders["reason"]), "no_orders")

	var sim4 = _make()
	_to_window(sim4)
	sim4.radio.jam_until_step = 999
	var jammed: Dictionary = sim4.order("breach")
	t.is_false("заглушённому отказ", jammed["accepted"])
	t.eq("причина названа", String(jammed["reason"]), "jammed")

	# 5. Молчание со связистом: импровизация, но детерминированная по seed.
	var crew := [
		{"id": "kira", "role": "tactician", "understanding": 3},
		{"id": "echo", "role": "comms", "understanding": 3},
	]
	var a := _make({"seed": 7}, crew)
	_to_window(a)
	var eff_a: Dictionary = a.order("silence")["effect"]
	var b := _make({"seed": 7}, crew)
	_to_window(b)
	var eff_b: Dictionary = b.order("silence")["effect"]
	t.eq("тот же seed — та же импровизация", eff_a, eff_b)
	t.is_true("импровизировал связист", String(eff_a["by"]) == "comms")

	# 6. Без связиста молчание всегда безопасно.
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
const Window := preload("res://sim/window.gd")
```

В `advance()` после `_update_visibility()` вставить `_maybe_open_window()`.

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
			current_window = Window.locked_door(String(e["id"]), a.id)
			_emit("window_opened", {"kind": "locked_door", "edge": e["id"], "agent": a.id})
			return


## Приказ или молчание. Возвращает решение и причину отказа, если он есть.
func order(option_id: String) -> Dictionary:
	if current_window == null:
		return {"accepted": false, "reason": "no_window"}
	var w: Dictionary = current_window
	if option_id == Window.SILENCE:
		var eff := _resolve_silence(w)
		_apply_silence(w, eff)
		current_window = null
		_emit("order_silenced", {"window": w["id"], "effect": eff})
		return {"accepted": true, "kind": "silence", "effect": eff}
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
	if objective_done:
		var all_out := true
		for a in own:
			if a.is_dead():
				continue
			if a.node != plan.exit_node:
				all_out = false
		if all_out:
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
			a.waypoints = [a.node, plan.exit_node]
			a.waypoint_index = 1
			a.progress = 0
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

### Task 10: Ранения, порог смерти, исход миссии

**Files:**
- Modify: `game/sim/sim.gd` (контакт с охраной → `_compromise`, детализация `result()`)
- Create: `game/tests/cases/test_casualties.gd`
- Modify: `game/tests/run.gd`

**Interfaces:**
- Consumes: `Sim._compromise(agent)`, `Agent.add_trigger()`.
- Produces: событие `agent_compromised`; в `result()` — `injured`, `dead`, `escaped`, `cargo`.

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
	var clean = _make(["dock", "hall", "office2"])
	for i in 10:
		clean.advance()
	t.eq("никто не погиб на пустой миссии", clean.result()["dead"].size(), 0)

	return t.results
```

- [ ] **Step 2: Прогнать — ожидаем провал**

Expected: провал на пункте 4 или 5 — `_compromise` уже есть из Task 8, но `result()` пока не отдаёт `injured`/`dead` корректно для этого случая... Если всё зелёное сразу — это **провал планирования**, а не успех: значит, тест не проверяет ничего нового. В таком случае добавить проверку контакта с охраной (пункт 9): довести бойца в один узел с патрулём и убедиться, что `_compromise` вызывается самой симуляцией.

- [ ] **Step 3: Дополнить `game/sim/sim.gd` — контакт с охраной**

Добавить в `advance()` после `_update_visibility()`, **до** `_maybe_open_window()`:

```gdscript
	_check_contacts()
```

Порядок вызовов в `advance()` должен остаться таким: часы → тревога → движение своих → движение охраны → видимость → контакты → окно → цель → конец миссии.

И сам метод:

```gdscript
## Охрана и свои в одном помещении — это увидение. Пока в лоб: без проверки
## направления взгляда и без «заметил, но не понял» (это П2).
func _check_contacts() -> void:
	for a in own:
		if a.is_dead():
			continue
		for g in guards:
			if g.node == a.node:
				_compromise(a)
				return
```

- [ ] **Step 4: Прогнать — ожидаем зелёный**

Expected: `failed: 0`, `код: 0`.

- [ ] **Step 5: Закоммитить**

```powershell
git add game/sim/sim.gd game/tests/cases/test_casualties.gd game/tests/run.gd
git commit -m "feat(sim): ранения, порог смерти и отчёт об исходе"
```

---

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
	var m = Fixture.build()
	var route := ["dock", "hall", "office2", "vault"]

	# 1. Прогон даёт полный отчёт.
	var r: Dictionary = Harness.run_scenario(m, _plan(route), ["breach"], {"seed": 5})
	for key in ["outcome", "steps", "objective_done", "orders_left", "noise", "radio", "imprint", "alarm", "injured", "dead", "positions", "digest"]:
		t.is_true("в отчёте есть %s" % key, r.has(key))
	t.eq("приказ потрачен", r["orders_left"], 2)
	t.eq("эфир от одного приказа", r["radio"], 8)

	# 2. Детерминизм: тот же вход — тот же отпечаток.
	var again: Dictionary = Harness.run_scenario(m, _plan(route), ["breach"], {"seed": 5})
	t.eq("повтор совпал", again["digest"], r["digest"])

	# 3. Другой сценарий — другой исход (иначе сценарий ни на что не влияет).
	var silent: Dictionary = Harness.run_scenario(m, _plan(route), ["silence"], {"seed": 5})
	t.is_true("молчание отличается от приказа", silent["digest"] != r["digest"])
	t.eq("молчание не тратит приказы", silent["orders_left"], 3)
	t.eq("молчание не шумит в эфире", silent["radio"], 0)

	# 4. Короткий сценарий: кончились ответы — дальше игрок молчит.
	var short: Dictionary = Harness.run_scenario(m, _plan(["dock"]), [], {"seed": 5})
	t.is_true("исход есть", String(short["outcome"]) != "")

	# 5. Тревога и уход из подвала воспроизводятся через харнесс.
	var run_away: Dictionary = Harness.run_scenario(
		m, _plan(["dock", "archive0"]), [], {"seed": 5, "noise_start": 25}
	)
	t.eq("ушли из подвала", String(run_away["outcome"]), "extracted")
	t.is_true("цель взята", run_away["objective_done"])

	# 6. Импровизация связиста тоже детерминирована через харнесс.
	var crew := ["dock", "hall", "office2", "vault"]
	var i1: Dictionary = Harness.run_scenario(m, _plan(crew), ["silence"], {"seed": 99})
	var i2: Dictionary = Harness.run_scenario(m, _plan(crew), ["silence"], {"seed": 99})
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
- **Имена и типы.** `Sim.setup/advance/order/result`, `Agent.add_trigger/speed_penalty/is_dead/is_own`, `Mission.edge/edges_at/edge_between/other_end/validate/validate_route`, `Plan.route/exit_node/exit_backup_node/agents`, `Window.SILENCE/has_silence/locked_door`, `Radio.transmit/tick_decay/can_speak/is_intercepted`, `Response.engage/steps_since/has_arrived/perimeter_closed/edge_blocked`, `Harness.run_scenario/digest` — используются во всех задачах одинаково.
- **Места, где легко ошибиться.** (1) Порядок в `advance()`: часы, тревога, движение, контакты, видимость, окно, конец. (2) Проверка блокировки только при `progress == 0`. (3) `edge()` возвращает ссылку на словарь в массиве — `mission.edge(id)["locked"] = false` меняет миссию, и это намеренно.



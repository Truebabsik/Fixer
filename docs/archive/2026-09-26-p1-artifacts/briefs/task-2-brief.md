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


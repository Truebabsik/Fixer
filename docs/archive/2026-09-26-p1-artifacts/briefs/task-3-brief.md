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


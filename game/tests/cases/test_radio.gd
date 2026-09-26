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

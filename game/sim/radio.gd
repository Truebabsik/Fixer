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

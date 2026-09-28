extends RefCounted
## Шум и состояния тревоги. Числа — из таблицы чисел мира, дословно.
##
## Шум НЕ затухает: это бюджет миссии, а не след. Всё, что сделано громко,
## вычитается навсегда — поэтому громкие решения необратимы.

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

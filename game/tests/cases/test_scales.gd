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

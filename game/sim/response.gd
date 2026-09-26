extends RefCounted
## Группа реагирования. Тревога — не провал, а перелом: тихая половина кончилась,
## началась гонка (D16).
##
## Числа — docs/spr/scales.md §5. Лестница не блокируется никогда (D19):
## после тревоги она остаётся единственным путём, и он самый медленный.

const ARRIVE_STEPS := 10
const PERIMETER_STEPS := 15
const FREIGHT_GRACE := 3
## Насколько раньше приезжает группа, если эфир перехвачен (design.md §13.7).
const INTERCEPT_STEPS := 3

var active := false
var alarm_step := -1


func engage(step: int) -> void:
	if active:
		return
	active = true
	alarm_step = step


func steps_since(step: int) -> int:
	return step - alarm_step if active else 0


## Перехват (отпечаток 3) — выезд быстрее на 3 шага (design.md §13.7, D33).
## Читаем признак у радио, а не своего счётчика: перехват считает эфир.
func has_arrived(step: int, intercepted := false) -> bool:
	if not active:
		return false
	var arrive := ARRIVE_STEPS
	if intercepted:
		arrive -= INTERCEPT_STEPS
	return steps_since(step) >= arrive


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

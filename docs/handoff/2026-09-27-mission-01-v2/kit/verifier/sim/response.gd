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

## Виды рёбер, которые тревога перекрывает ВООБЩЕ — не «прямо сейчас»: у видов разный
## момент закрытия (грузовой живёт grace-период).
##
## Это ЕДИНСТВЕННЫЙ источник знания о них в проекте. Им пользуется `edge_blocked` и по нему
## же валидатор контента решает, запираемо ли ребро (`blockable_kind`): окно у двери требует
## ребра, которое запирается замком ИЛИ тревогой. Второй список у валидатора разошёлся бы
## с этим молча, и окно `w_stuck_lift` поставки (ребро `e_freight_4_0`, `lift_freight`)
## получало бы `WINDOW_ON_OPEN_EDGE` — диагноз «сцены не будет» на сцене, которая есть.
const BLOCKED_KINDS := ["lift_main", "lift_freight"]

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


## Может ли тревога вообще перекрыть ребро этого вида. Спрашивает валидатор контента:
## своего списка видов он не заводит (см. BLOCKED_KINDS выше).
static func blockable_kind(kind: String) -> bool:
	return BLOCKED_KINDS.has(kind)


## Перекрыто ли ребро этого вида прямо сейчас. Виды берутся из `BLOCKED_KINDS`: список
## видов один, а не размазан по ветвям `match`, поэтому новое правило (например, льгота
## для ещё одного лифта) добавляется сюда, а не заводит второй перечень.
func edge_blocked(kind: String, step: int) -> bool:
	if not active or not BLOCKED_KINDS.has(kind):
		return false
	## Грузовой лифт закрывают не сразу: grace-период (scales.md §5).
	if kind == "lift_freight":
		return steps_since(step) > FREIGHT_GRACE
	return true

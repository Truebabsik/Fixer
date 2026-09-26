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

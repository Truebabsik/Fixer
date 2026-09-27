extends SceneTree
## КРАСНЫЙ раннер. Проверяет две вещи сразу и падает, если сломана любая:
##
##   1. Нарочно падающий кейс (tests/red_path.gd) действительно валит процесс.
##      Нет падения — ошибка не зафиксирована, и «красный путь» ничего не значит.
##   2. Зелёный набор при этом ПРОХОДИТ. Это и есть защита приговора: зашитый в
##      tests/run.gd `quit(0)` оставит зелёный прогон с кодом 0 и будет пойман здесь
##      как «зелёный набор не проходит», потому что код 2 вернётся вместо 0.
##
## Без второй проверки пара прогонов защищала только себя: красный раннер с жёстким
## quit(1) и зелёный с зашитым quit(0) дали бы ровно предписанные коды при полностью
## неработающем приговоре.
##
## Команды — в docs/architecture.md §8.
##
## `_process`-сторожа здесь нет намеренно: сторож нормального раннера и есть часть
## проверяемой системы, второй его экземпляр ничего не доказывает.
##
## Коды: 0 — обе проверки прошли; 2 — приговор сломан (в т.ч. зелёный набор не прошёл).

const Suite := preload("res://tests/suite.gd")
const Verdict := preload("res://tests/verdict.gd")

const CASES := [
	"res://tests/red_path.gd",
]


func _initialize() -> void:
	var red := Suite.run(CASES, true, Verdict.EXIT_BROKEN)
	if int(red["exit_code"]) != Verdict.EXIT_OK:
		## Нарочная ошибка не зафиксирована: красный путь не работает.
		print("%s  нарочно падающий кейс не упал" % Verdict.BROKEN_MARK)
		quit(Verdict.EXIT_BROKEN)
		return

	var check := Verdict.verify()
	if not bool(check["ok"]):
		for problem in check["problems"]:
			print("%s  %s" % [Verdict.BROKEN_MARK, problem])
		quit(Verdict.EXIT_BROKEN)
		return

	quit(Verdict.EXIT_OK)

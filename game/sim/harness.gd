extends RefCounted
## Прогон сценария: миссия + план + последовательность ответов на окна → исход.
##
## Сценарий — список id вариантов. Когда список кончился, игрок молчит:
## это и есть поведение по умолчанию (D23), поэтому пустой сценарий валиден
## и означает «игрок не вмешивался ни разу».

const Sim := preload("res://sim/sim.gd")


## `sim_out` — необязательный приёмник: если передан, в него кладётся сам `Sim`
## после прогона. Нужен там, где проверять надо не отчёт, а состояние мира
## (например, открытые двери живут в `Sim.unlocked`, а не в отчёте).
static func run_scenario(mission, plan, script: Array = [], config := {}, sim_out = null) -> Dictionary:
	var sim := Sim.new()
	sim.setup(mission, plan, config)
	if sim_out != null:
		sim_out.set_meta("sim", sim)
	var index := 0
	var guard := 0
	while not sim.finished and guard < Sim.MAX_STEPS * 2:
		if sim.current_window != null:
			var choice := "silence"
			if index < script.size():
				choice = String(script[index])
			index += 1
			var res: Dictionary = sim.order(choice)
			if not bool(res.get("accepted", false)) and choice != "silence":
				sim.order("silence")
		else:
			sim.advance()
		guard += 1
	var out: Dictionary = sim.result()
	out["digest"] = digest(out)
	return out


## Отпечаток исхода для проверки детерминизма: только смысловые поля, без событий.
static func digest(result: Dictionary) -> String:
	var parts: Array = []
	for key in ["outcome", "steps", "objective_done", "orders_left", "noise", "radio", "imprint", "alarm", "injured", "dead", "positions"]:
		parts.append("%s=%s" % [key, str(result.get(key))])
	return "|".join(parts)

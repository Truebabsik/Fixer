extends RefCounted
## Окно решения. Инвариант: у каждого окна есть вариант «молчать» (D23).
## Молчание — не отмена, а ход: именной решает за игрока безопасно и не его способом.

const SILENCE := "silence"


static func locked_door(edge_id: String, agent_id: String) -> Dictionary:
	return {
		"id": "locked_door:%s" % edge_id,
		"kind": "locked_door",
		"edge": edge_id,
		"agent": agent_id,
		"text": "Дверь заперта, хотя в плане открыта.",
		"options": [
			{"id": "breach", "label": "Выбить", "noise": 8, "delay": 0, "complexity": 1},
			{"id": "pick", "label": "Вскрыть тихо", "noise": 1, "delay": 2, "complexity": 2},
			{"id": SILENCE, "label": "Молчать — решит именной"},
		],
	}


static func has_silence(w) -> bool:
	for o in w["options"]:
		if String(o["id"]) == SILENCE:
			return true
	return false

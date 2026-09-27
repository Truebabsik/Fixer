extends RefCounted
## Окно решения. Инвариант: у каждого окна есть вариант «молчать» (D23).
## Молчание — не отмена, а ход: именной решает за игрока безопасно и не его способом.
##
## Рантайм-форма окна собирается здесь из авторской формы данных
## (`Mission.data["windows"]`, `02-format.md` §4): триггер, варианты с `cost`
## и `effects`, четыре исхода молчания. Автор данных рантайм-формы не знает,
## ядро не разбирает авторскую форму нигде, кроме этих функций, — граница
## проходит здесь (дизайн конвейера §4.1).

const SILENCE := "silence"

## Четыре исхода молчания. Качество выбирает ядро (кубик по seed, D7),
## а что происходит при каждом качестве — данные.
const SILENCE_QUALITIES := ["good", "neutral", "bad", "safe"]


## Вид окна в рантайме по типу триггера. У запертого ребра вид исторический,
## `locked_door`: на это имя смотрят события, тесты и решение D37.
static func kind_for(trigger_type: String) -> String:
	if trigger_type == "locked_edge":
		return "locked_door"
	return trigger_type


## Поле триггера, за которое окно держится: ребро, помещение, сенсор. Оно же —
## вторая половина составного id окна и поле события `window_opened`.
static func anchor_key(trigger_type: String) -> String:
	match trigger_type:
		"locked_edge":
			return "edge"
		"node_entered":
			return "node"
		"guard_in_sensor":
			return "sensor"
	return ""


## Рантайм-форма окна из данных. `agent_id` — тот, чьё действие окно открыло.
## Составной id (`locked_door:<ребро>`, `node_entered:<помещение>`,
## `guard_in_sensor:<сенсор>`) — ключ событий и `order()`, поэтому он сохранён
## дословно; текст приходит из контента ключом, а не зашитой строкой.
static func from_data(w: Dictionary, agent_id: String) -> Dictionary:
	var trigger = w.get("trigger", {})
	var type := ""
	var anchor_id := ""
	if typeof(trigger) == TYPE_DICTIONARY:
		var trigger_dict: Dictionary = trigger
		type = String(trigger_dict.get("type", ""))
		anchor_id = String(trigger_dict.get(anchor_key(type), ""))
	var kind := kind_for(type)
	var out := {
		"id": "%s:%s" % [kind, anchor_id],
		"kind": kind,
		"agent": agent_id,
		"text_key": String(w.get("text_key", "")),
		"options": _options(w),
		"silence": _silence(w),
	}
	var anchor := anchor_key(type)
	if anchor != "":
		out[anchor] = anchor_id
	return out


## Варианты рантайма: цена (`cost`) переезжает на сам вариант, эффекты остаются
## списком. Ветка молчания добавляется последней — она встроена в форму окна,
## приказом не считается, и `has_silence`/`order("silence")` работают как прежде.
static func _options(w: Dictionary) -> Array:
	var out: Array = []
	var options = w.get("options", [])
	if typeof(options) == TYPE_ARRAY:
		for o in options:
			if typeof(o) != TYPE_DICTIONARY:
				continue
			var option: Dictionary = o
			var cost = option.get("cost", {})
			var cost_dict: Dictionary = cost if typeof(cost) == TYPE_DICTIONARY else {}
			out.append({
				"id": String(option.get("id", "")),
				"text_key": String(option.get("text_key", "")),
				"complexity": int(option.get("complexity", 1)),
				"noise": int(cost_dict.get("noise", 0)),
				"delay": int(cost_dict.get("delay", 0)),
				"effects": _effects(option.get("effects", [])),
			})
	out.append({"id": SILENCE, "text_key": _silence_text_key(w)})
	return out


## Эффекты молчания по качествам: `{good: [...], neutral: [...], ...}`. Качество
## без описанных эффектов — пустой список: ядро на неполных данных не падает,
## а просто ничего не делает (валидатор такие данные до ядра не пропустит).
static func _silence(w: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var silence = w.get("silence", {})
	if typeof(silence) != TYPE_DICTIONARY:
		return out
	var silence_dict: Dictionary = silence
	for quality in SILENCE_QUALITIES:
		out[quality] = _effects(silence_dict.get(quality, []))
	return out


static func _silence_text_key(w: Dictionary) -> String:
	var silence = w.get("silence", {})
	if typeof(silence) != TYPE_DICTIONARY:
		return ""
	return String((silence as Dictionary).get("text_key", ""))


## Эффект в данных бывает и одиночным объектом, и массивом — форматы равнозначны
## (`02-format.md` §7). Копируем: рантайм не делит словари с неизменяемыми данными
## миссии, иначе одно окно могло бы править вход следующего прогона.
static func _effects(raw) -> Array:
	var out: Array = []
	if typeof(raw) == TYPE_ARRAY:
		for effect in raw:
			if typeof(effect) == TYPE_DICTIONARY:
				out.append((effect as Dictionary).duplicate(true))
	elif typeof(raw) == TYPE_DICTIONARY:
		out.append((raw as Dictionary).duplicate(true))
	return out


static func has_silence(w) -> bool:
	for o in w["options"]:
		if String(o["id"]) == SILENCE:
			return true
	return false

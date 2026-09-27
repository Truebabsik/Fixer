extends RefCounted
## Окна из данных: триггеры (`locked_edge`, `node_entered`, `guard_in_sensor`),
## учёт сработавших окон и эффекты, включая `fallback` заявки на новую механику.
##
## Отдельный кейс от `test_windows.gd` намеренно: там живут прежние проверки окон,
## приказов и молчания на фикстуре, и они — часть контракта П1. Здесь проверяется
## ровно то, чего до перевода ядра на данные не было.

const Assert := preload("res://tests/assert.gd")
const Mission := preload("res://sim/mission.gd")
const Plan := preload("res://sim/plan.gd")
const Sim := preload("res://sim/sim.gd")
## Имя константы не может быть `Window`: в Godot 4.7 это тень нативной ноды.
const WindowScript := preload("res://sim/window.gd")


func run() -> Array:
	var t := Assert.new()

	# 1. Триггер `node_entered`: окно открывается на ВХОД в помещение. Прежде окно
	# знало единственный повод — запертое ребро перед агентом (`sim.gd:342`).
	var entered = _make(
		_window("w_mid", {"type": "node_entered", "node": "mid"}, [
			_option("hurry", 0, 2, [{"type": "noise", "value": 4}]),
			_option("wait", 0, 0, [{"type": "noop"}]),
		]),
		["start", "mid", "goal"], "goal"
	)
	t.eq("до входа окна нет", entered.current_window, null)
	entered.advance()
	t.is_true("окно входа открылось", entered.current_window != null)
	## Пустое окно уронило бы кейс целиком на первой же строке ниже: тогда провал
	## выглядел бы абортом, а не ассертом. Выходим с одним честным провалом.
	if entered.current_window == null:
		return t.results
	t.eq("вид окна входа", String(entered.current_window["kind"]), "node_entered")
	t.eq("id окна входа", String(entered.current_window["id"]), "node_entered:mid")
	t.eq("окно знает помещение", String(entered.current_window["node"]), "mid")
	t.eq("окно знает вошедшего", String(entered.current_window["agent"]), "kira")
	t.is_true("у окна из данных есть молчание", WindowScript.has_silence(entered.current_window))
	t.eq("событие несёт вид окна", _event_field(entered, "window_opened", "kind"), "node_entered")
	t.eq("событие несёт помещение", _event_field(entered, "window_opened", "node"), "mid")
	t.eq("событие несёт агента", _event_field(entered, "window_opened", "agent"), "kira")
	var frozen: int = entered.scales.step
	t.eq("без ответа шагов нет", entered.advance().size(), 0)
	t.eq("часы стоят", entered.scales.step, frozen)

	# 1б. Цена варианта — из `cost`, эффекты — из `effects`: одно без другого
	# проверку не пройдёт (шум 4 даёт только эффект, задержку 2 — только цена).
	var noise_before: int = entered.scales.noise
	var taken: Dictionary = entered.order("hurry")
	t.is_true("вариант из данных принят", taken["accepted"])
	t.eq("шум цены и эффекта", entered.scales.noise - noise_before, 4)
	t.eq("задержка цены", entered.own[0].delay, 2)
	for i in 2:
		entered.advance()
	t.eq("задержанный стоит на месте", entered.own[0].node, "mid")
	entered.advance()
	t.eq("после задержки агент пошёл", entered.own[0].node, "goal")
	t.eq("окно входа не открылось второй раз", entered.current_window, null)

	# 2. «Одно окно — один срабатывающий раз» (`02-format.md` §4.2). Проверка ловит
	# и прежний латентный дефект: пока память о сработавшем окне не велась, окно
	# у всё ещё запертого ребра открывалось заново КАЖДЫЙ шаг.
	var noop_silence := [{"type": "noop"}]
	var stubborn = _make_locked(
		_window("w_stubborn", {"type": "locked_edge", "edge": "e_cell_hall"},
			[_option("wait", 0, 0, [{"type": "noop"}])], noop_silence)
	)
	t.is_true("дверь заперта на входе", bool(stubborn.mission.edge("e_cell_hall")["locked"]))
	stubborn.advance()
	t.is_true("окно запертой двери открылось", stubborn.current_window != null)
	if stubborn.current_window == null:
		return t.results
	t.eq("id окна запертой двери прежний", String(stubborn.current_window["id"]),
		"locked_door:e_cell_hall")
	t.eq("окно называет ребро", String(stubborn.current_window["edge"]), "e_cell_hall")
	t.is_true("окно приняло вариант без эффектов", bool(stubborn.order("wait")["accepted"]))
	t.eq("noop ничего не сделал", stubborn.scales.noise, 0)
	t.is_false("дверь осталась заперта", bool(stubborn.unlocked.get("e_cell_hall", false)))
	for i in 3:
		stubborn.advance()
	t.eq("окно не сработало второй раз", stubborn.current_window, null)
	t.is_false("дверь всё ещё заперта", bool(stubborn.unlocked.get("e_cell_hall", false)))
	t.is_true("миссия не тронута", bool(stubborn.mission.edge("e_cell_hall")["locked"]))

	# 2б. Молчание у запертой двери — тот же один раз. В данных этой миссии
	# `unlock` нет вовсе, поэтому дверь остаётся запертой, и без памяти об окне
	# оно вернулось бы следующим шагом.
	var silent_door = _make_locked(
		_window("w_stubborn_silence", {"type": "locked_edge", "edge": "e_cell_hall"},
			[_option("wait", 0, 0, [{"type": "noop"}])], noop_silence)
	)
	silent_door.advance()
	t.is_true("окно открылось и здесь", silent_door.current_window != null)
	if silent_door.current_window == null:
		return t.results
	t.is_true("молчание принято", bool(silent_door.order("silence")["accepted"]))
	for i in 2:
		silent_door.advance()
	t.eq("после молчания окно не вернулось", silent_door.current_window, null)
	t.is_false("молчание без unlock дверь не открыло", bool(silent_door.unlocked.get("e_cell_hall", false)))

	# 2в. Память о сработавших окнах сбрасывается в `setup()`: тот же Sim,
	# перезапущенный на той же миссии, обязан показать то же окно. Иначе прогон
	# был бы невоспроизводим, а балансировщик — недетерминирован.
	stubborn.setup(stubborn.mission, stubborn.plan, {"orders": 3, "seed": 1})
	t.eq("после setup окно снято", stubborn.current_window, null)
	t.is_true("память сброшена: сработавший id пуст", stubborn.fired_windows.is_empty())
	t.is_true("память сброшена: рёбра пусты", stubborn.fired_edges.is_empty())
	stubborn.advance()
	t.is_true("после setup окно открылось снова", stubborn.current_window != null)

	# 3. `engine_proposal`: ядро заявку не исполняет, а применяет `fallback`
	# (`02-format.md` §7). Проверка падает и если `fallback` игнорируется, и если
	# ядро «исполняет» заявку само.
	var asked = _make_locked(
		_window("w_ask", {"type": "locked_edge", "edge": "e_cell_hall"},
			[_option("ask", 0, 0, [_proposal([
				{"type": "unlock", "edge": "e_cell_hall"},
				{"type": "delay", "value": 1},
			])])], noop_silence)
	)
	asked.advance()
	t.is_true("окно заявки открылось", asked.current_window != null)
	if asked.current_window == null:
		return t.results
	t.is_true("заявка принята как приказ", bool(asked.order("ask")["accepted"]))
	t.is_true("fallback-массив открыл дверь", bool(asked.unlocked.get("e_cell_hall", false)))
	t.eq("fallback-массив задержал агента", asked.own[0].delay, 1)

	# 3б. `fallback` одиночным объектом — вторая разрешённая форма (§7).
	var single = _make_locked(
		_window("w_ask_one", {"type": "locked_edge", "edge": "e_cell_hall"},
			[_option("ask", 0, 0, [_proposal({"type": "noise", "value": 6})])], noop_silence)
	)
	single.advance()
	t.is_true("окно заявки открылось и здесь", single.current_window != null)
	if single.current_window == null:
		return t.results
	var single_noise: int = single.scales.noise
	single.order("ask")
	t.eq("fallback-объект добавил шум", single.scales.noise - single_noise, 6)
	t.is_false("и ничего сверх fallback не сделал", bool(single.unlocked.get("e_cell_hall", false)))

	# 4. Триггер `guard_in_sensor`: окно открывается, когда охрана ВХОДИТ в зону
	# сенсора. Период охраны 1: на третьем шаге она входит в зону снова — и окно
	# обязано молчать, потому что уже сработало.
	var watched = _make(
		_window("w_guard", {"type": "guard_in_sensor", "sensor": "s_mid"},
			[_option("listen", 0, 0, [{"type": "noise", "value": 2}])], noop_silence),
		["start", "goal"], "start",
		{
			"edges": [["e_start_goal", "start", "goal", "corridor", 5, 0]],
			"patrols": [{"id": "guard_1", "route": ["start", "mid"], "period": 1}],
			"sensors": [{"id": "s_mid", "nodes": ["mid"]}],
		}
	)
	watched.advance()
	t.is_true("окно сенсора открылось", watched.current_window != null)
	if watched.current_window == null:
		return t.results
	t.eq("вид окна сенсора", String(watched.current_window["kind"]), "guard_in_sensor")
	t.eq("id окна сенсора", String(watched.current_window["id"]), "guard_in_sensor:s_mid")
	t.eq("окно знает сенсор", String(watched.current_window["sensor"]), "s_mid")
	t.eq("окно знает охранника", String(watched.current_window["agent"]), "guard_1")
	t.eq("событие несёт сенсор", _event_field(watched, "window_opened", "sensor"), "s_mid")
	var guard_noise: int = watched.scales.noise
	t.is_true("вариант окна сенсора принят", bool(watched.order("listen")["accepted"]))
	t.eq("эффект из данных добавил шум", watched.scales.noise - guard_noise, 2)
	for i in 3:
		watched.advance()
	t.eq("повторный вход в сенсор окна не открывает", watched.current_window, null)

	# 5. Текст молчания выбирается ПО ВЫБРАННОМУ качеству. Прежде ветка молчания несла
	# один `text_key`, и выпавшее качество на строку не влияло вовсе: при связисте
	# импровизирует Эхо, а текст называл тактика. Здесь проверяется ВЫБОР ключа, а не
	# наличие данных: ожидание построено по имени качества, а не взято из той же
	# константы, что подставлена в окно.
	var qualities := ["good", "neutral", "bad", "safe"]
	var chosen = _make_locked(_with_quality_texts(
		_window("w_texts", {"type": "locked_edge", "edge": "e_cell_hall"},
			[_option("wait", 0, 0, [{"type": "noop"}])], noop_silence)))
	chosen.advance()
	t.is_true("окно с ключами качеств открылось", chosen.current_window != null)
	if chosen.current_window == null:
		return t.results
	# 5а. Имена разведены (M5 ревью 2): поле окна — БАЗОВЫЙ ключ, функция — ключ качества.
	# Пока имя было одно, читатель брал базовый ключ за «текст исхода» и получал базовую
	# строку вместо строки выпавшего исхода. Ассерт держит различие двух ключей, а не факт
	# их существования: одинаковые значения провалили бы его.
	t.eq("поле окна — базовый ключ молчания, а не ключ качества",
		String(chosen.current_window.get("silence_base_key", "")), "window.w_texts.silence")
	for quality in qualities:
		t.eq("текст молчания качества %s — ключ качества, а не базовый" % quality,
			WindowScript.silence_key_for(chosen.current_window, quality),
			"window.w_texts.silence.%s" % quality)

	# 5б. Ответ на молчание несёт ключ ВЫБРАННОГО качества: окно к этому моменту уже
	# закрыто (`current_window = null`), и презентации взять строку больше неоткуда.
	# Ожидание выведено из СОСТАВА этого прогона, а не из ответа ядра: в плане кейса один
	# тактик и связиста нет (`_make_locked`), значит качество определено однозначно —
	# `safe` (`sim.gd:_resolve_silence`, D7/D41). Пока ожидание бралось из
	# `answer["effect"]["quality"]`, ассерт сверял ответ сам с собой и «выбрано не то
	# качество» поймать не мог (M2 ревью 2).
	var expected_quality := "safe"
	var window_before: Dictionary = chosen.current_window
	var answer: Dictionary = chosen.order("silence")
	t.eq("исход молчания при тактике без связиста — %s" % expected_quality,
		String((answer["effect"] as Dictionary).get("quality", "")), expected_quality)
	t.eq("ответ на молчание несёт ключ выбранного качества (%s)" % expected_quality,
		String(answer.get("text_key", "")), "window.w_texts.silence.%s" % expected_quality)
	t.is_true("базовый ключ в ответе не подставлен вместо качественного",
		String(answer.get("text_key", "")) != String(window_before.get("silence_base_key", "")))

	# 5в. Ключа качества в данных нет — читается базовый `silence.text_key`: окна старой
	# формы остаются рабочими, а не превращаются в пустую строку.
	var base_only = _make_locked(_window("w_base_only",
		{"type": "locked_edge", "edge": "e_cell_hall"},
		[_option("wait", 0, 0, [{"type": "noop"}])], noop_silence))
	base_only.advance()
	t.is_true("окно без ключей качеств открылось", base_only.current_window != null)
	if base_only.current_window == null:
		return t.results
	t.eq("без ключа качества читается базовый ключ",
		WindowScript.silence_key_for(base_only.current_window, "good"),
		"window.w_base_only.silence")

	# 5г. Ни ключа качества, ни базового нет — пустая строка. Ядро на неполных данных не
	# падает и НЕ выдумывает ключ по имени окна: «текста нет» видно как пустой текст.
	var no_keys_window := _window("w_no_keys", {"type": "locked_edge", "edge": "e_cell_hall"},
		[_option("wait", 0, 0, [{"type": "noop"}])], noop_silence)
	(no_keys_window["silence"] as Dictionary).erase("text_key")
	var no_keys = _make_locked(no_keys_window)
	no_keys.advance()
	t.is_true("окно без ключей текста открылось", no_keys.current_window != null)
	if no_keys.current_window == null:
		return t.results
	t.eq("нет ни ключа качества, ни базового — пустая строка",
		WindowScript.silence_key_for(no_keys.current_window, "good"), "")

	# 5д. Испорченное поле качества (не-строка) НЕ обнуляет карту: три валидных ключа
	# остаются на месте, испорченный читается пустой строкой. Без охраны типа
	# `String(не-строка)` — недопустимый конструктор: сборка окна обрывается, карта теряет
	# ВСЕ ключи (включая валидные), `silence_key_for` молча отдаёт базовую строку — то есть
	# игрок видит текст не того, кто решил, ровно тот дефект, ради которого ключи качеств
	# и заводились (F2 ревью 2). Ожидание выписано литералами: оно не выведено из
	# проверяемого кода, поэтому порча `_silence_text_keys` его краснит.
	var broken_window := _with_quality_texts(
		_window("w_broken_key", {"type": "locked_edge", "edge": "e_cell_hall"},
			[_option("wait", 0, 0, [{"type": "noop"}])], noop_silence))
	(broken_window["silence"] as Dictionary)["good_key"] = 5
	var broken: Dictionary = WindowScript.from_data(broken_window, "kira")
	t.eq("испорченный ключ качества: карта цела, валидные ключи на месте, испорченный пуст",
		broken["silence_text_keys"],
		{"good": "", "neutral": "window.w_broken_key.silence.neutral",
			"bad": "window.w_broken_key.silence.bad", "safe": "window.w_broken_key.silence.safe"})
	## Вторая половина правила — другой КЛАСС значения: массив. Число и массив ведут себя
	## по-разному (`has` есть у массива и нет у числа), и охрана, «половинчатая» по типу
	## (число пропустила, массив нет), краснит именно этот ассерт, а не первый.
	var array_window := _with_quality_texts(
		_window("w_array_key", {"type": "locked_edge", "edge": "e_cell_hall"},
			[_option("wait", 0, 0, [{"type": "noop"}])], noop_silence))
	(array_window["silence"] as Dictionary)["neutral_key"] = []
	var broken_array: Dictionary = WindowScript.from_data(array_window, "kira")
	t.eq("испорченный ключ качества (массив): карта цела, валидные ключи на месте, испорченный пуст",
		broken_array["silence_text_keys"],
		{"good": "window.w_array_key.silence.good", "neutral": "",
			"bad": "window.w_array_key.silence.bad", "safe": "window.w_array_key.silence.safe"})

	# 5е. Качество молчания определяется СОСТАВОМ, а не данными окна: есть живой связист —
	# кубик даёт `good`/`neutral`/`bad`, нет — всегда `safe` (D7, D41). При штатном составе
	# (тактик + связист) исход `safe` не выпадает НИ РАЗУ, а значит всё, что положено только
	# в него, на штатном составе не играется. Это стык данных и состава, и проверяется он
	# здесь, а не в кейсе окна: правилу нужен состав, а не форма данных.
	var with_comms := _silence_rolls(
		[{"id": "kira", "role": "tactician", "understanding": 3},
			{"id": "echo", "role": "comms", "understanding": 3}], 200)
	var no_comms := _silence_rolls([{"id": "kira", "role": "tactician", "understanding": 3}], 200)
	t.is_true("при составе со связистом исходов молчания больше одного (корпус не вырожден): %s"
		% _quality_line(with_comms), with_comms.size() > 1)
	t.is_false("при составе со связистом исход safe не выпадает ни разу: %s"
		% _quality_line(with_comms), with_comms.has("safe"))
	t.is_true("без связиста исход safe выпадает: %s" % _quality_line(no_comms),
		no_comms.has("safe"))

	return t.results


## Сколько раз какое качество молчания выпало за `throws` бросков на заданном составе.
## Кубик живёт в одном месте (`sim.gd:_resolve_silence`, D7) и зависит только от живых
## ролей: окно передаётся рантайм-формой — той же, что ядро отдаёт в `order("silence")`.
func _silence_rolls(agents: Array, throws: int) -> Dictionary:
	var data := _window("w_rolls", {"type": "locked_edge", "edge": "e_cell_hall"},
		[_option("wait", 0, 0, [{"type": "noop"}])], [{"type": "noop"}])
	var sim = _make_locked(data, agents)
	var w: Dictionary = WindowScript.from_data(data, "kira")
	var counts: Dictionary = {}
	for _i in throws:
		var quality := String(sim._resolve_silence(w)["quality"])
		counts[quality] = int(counts.get(quality, 0)) + 1
	return counts


## Счёт качеств одной строкой и в фиксированном порядке — для имени ассерта: провал
## обязан назвать распределение, а не «условие не выполнено». Порядок задан списком,
## а не порядком словаря (детерминизм, `constraints.md` §1.6).
func _quality_line(counts: Dictionary) -> String:
	var parts: Array = []
	for quality in ["good", "neutral", "bad", "safe"]:
		if counts.has(quality):
			parts.append("%s %d" % [quality, int(counts[quality])])
	if parts.is_empty():
		return "ни одного броска"
	return ", ".join(parts)


## Окно с ключами текста по качествам (`silence.<quality>_key`) — та форма, из которой
## `WindowScript.silence_key_for` выбирает строку исхода. Отдельный хелпер, а не флаг
## у `_window()`: кейс проверяет и окно БЕЗ ключей качеств (запасной базовый ключ), и
## общий флаг сделал бы это неявным.
func _with_quality_texts(window: Dictionary) -> Dictionary:
	var silence: Dictionary = window["silence"]
	for quality in ["good", "neutral", "bad", "safe"]:
		silence["%s_key" % quality] = "window.%s.silence.%s" % [String(window["id"]), quality]
	return window


## Данные окна с заданным триггером. Молчание описано всегда: у окна обязан быть
## вариант «молчать» (D23), и его эффекты задаются явно, а не по умолчанию.
func _window(id: String, trigger: Dictionary, options: Array, silence_effects := []) -> Dictionary:
	return {
		"id": id,
		"kind": String(trigger["type"]),
		"trigger": trigger,
		"text_key": "window.%s.text" % id,
		"options": options,
		"silence": {
			"text_key": "window.%s.silence" % id,
			"good": silence_effects.duplicate(true),
			"neutral": silence_effects.duplicate(true),
			"bad": silence_effects.duplicate(true),
			"safe": silence_effects.duplicate(true),
		},
	}


## Вариант в авторской форме: цена в `cost`, последствия в `effects`.
func _option(id: String, noise: int, delay: int, effects: Array) -> Dictionary:
	return {
		"id": id,
		"text_key": "window.option.%s" % id,
		"complexity": 1,
		"cost": {"noise": noise, "delay": delay},
		"effects": effects,
	}


## Заявка на новую механику: ядро обязано применить `fallback`, а не её саму.
## `want`/`needs` заполнены как в данных — на исход они влиять не должны.
func _proposal(fallback) -> Dictionary:
	return {
		"type": "engine_proposal",
		"id": "lure_engineer",
		"want": "инженер выходит из серверной",
		"needs": "состояние «вне поста» и таймер возврата",
		"fallback": fallback,
	}


## Маленькая миссия с данными окнами: `start -> mid -> goal` по одному шагу.
## `extra` добавляет рёбра, патрули и сенсоры — граф фикстуры для новых триггеров
## не годится: в нём нет входа в помещение по сенсору.
func _make(window: Dictionary, route: Array, exit_node: String, extra := {}):
	var m := Mission.new()
	m.id = "windows_data"
	m.add_node("start", 1, ["entry"])
	m.add_node("mid", 1, [])
	m.add_node("goal", 1, [])
	m.add_edge("e_start_mid", "start", "mid", "corridor", 1, 0)
	m.add_edge("e_mid_goal", "mid", "goal", "corridor", 1, 0)
	for e in extra.get("edges", []):
		var locked: bool = bool(e[6]) if e.size() > 6 else false
		m.add_edge(String(e[0]), String(e[1]), String(e[2]), String(e[3]), int(e[4]), int(e[5]), locked)
	for p in extra.get("patrols", []):
		m.add_patrol(String(p["id"]), p["route"], int(p.get("period", 4)))
	for s in extra.get("sensors", []):
		m.add_sensor(String(s["id"]), s["nodes"])
	m.objective = String(extra.get("objective", "goal"))
	m.set_data({"windows": [window]})
	var p := Plan.new()
	p.route = route
	p.exit_node = exit_node
	p.agents = [{"id": "kira", "role": "tactician", "understanding": 3}]
	var sim := Sim.new()
	sim.setup(m, p, {"orders": 3, "seed": 1})
	return sim


## Миссия с запертой дверью и окном на неё: у фикстуры дверь открывается эффектами,
## а здесь нужно окно, которое дверь НЕ открывает — иначе память о сработавшем
## окне ничем не проверяется.
##
## `agents` — состав группы: по умолчанию один тактик без связиста, потому что на нём
## молчание всегда `safe` и проверки окна не зависят от кубика. Состав передаётся
## явно там, где проверяется сам выбор качества (5е: стык данных и состава, D41).
func _make_locked(window: Dictionary, agents: Array = []):
	var m := Mission.new()
	m.id = "windows_data_locked"
	m.add_node("cell", 1, [])
	m.add_node("hall", 1, [])
	m.add_edge("e_cell_hall", "cell", "hall", "door", 1, 0, true)
	m.objective = "hall"
	m.set_data({"windows": [window]})
	var p := Plan.new()
	p.route = ["cell", "hall"]
	p.exit_node = "hall"
	p.agents = agents if not agents.is_empty() else [{"id": "kira", "role": "tactician", "understanding": 3}]
	var sim := Sim.new()
	sim.setup(m, p, {"orders": 3, "seed": 1})
	sim.guards = []
	return sim


## Поле события заданного вида ("" — события нет). Событие берём первое: в каждом
## прогоне этого кейса окно одно, и второго `window_opened` быть не должно.
func _event_field(sim, type: String, field: String) -> String:
	for e in sim.events:
		if String(e["type"]) == type:
			return String(e["data"].get(field, ""))
	return ""

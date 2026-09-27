extends RefCounted
## Запечатанное ребро: тревога закрывает путь так же, как замок.
##
## Прежде тревожная блокировка держала шаг, но окон не открывала: актор окна выбирался
## по `_is_locked`, а тревога замка не ставит. Снимать её тоже было нечем — `unlock`
## писал в `unlocked`, который блокировку тревоги не читал. То есть окно `w_stuck_lift`
## поставки миссии 01 (ребро `e_freight_4_0`, `lift_freight`) описано в данных, а сцены
## у него не было вовсе.
##
## Здесь проверяется ядро: окно открывается на перекрытом тревогой ребре, `unlock`
## снимает оба запрета (и приказом, и молчанием), без `unlock` группа остаётся перед
## ребром, а идущему по ребру окно не открывается. Отдельно — ребро, запертое И
## перекрытое сразу: событие об упоре молчит, а окно всё равно открывается; и два
## окна данных на одно ребро: срабатывает только первое (память `fired_edges`).

const Assert := preload("res://tests/assert.gd")
const Mission := preload("res://sim/mission.gd")
const Plan := preload("res://sim/plan.gd")
const Sim := preload("res://sim/sim.gd")


func run() -> Array:
	var t := Assert.new()

	# 1. Окно открывается на ребре, которое перекрыто ТРЕВОГОЙ, а не замком.
	# Окно ★27 поставки висит именно на таком ребре, и до правки оно не открывалось.
	var sealed_lift = _make([{"type": "unlock", "edge": "e_mid_goal"}])
	t.eq("до первого шага окна нет", sealed_lift.current_window, null)
	sealed_lift.advance()
	## Сторож вырожденности самого кейса: ребро в данных НЕ заперто, значит всё
	## дальнейшее — про тревогу, а не про замок (на замке окно открывалось и прежде).
	t.is_false("ребро в данных не заперто: дело в тревоге",
		bool(sealed_lift.mission.edge("e_mid_goal")["locked"]))
	t.is_true("тревога перекрыла лифт",
		sealed_lift.response.edge_blocked("lift_main", sealed_lift.scales.step))
	t.is_true("окно открылось на перекрытом тревогой ребре", sealed_lift.current_window != null)
	## Пустое окно уронило бы кейс рантаймом на первой же строке ниже, и провал выглядел
	## бы абортом, а не ассертом. Выходим с одним честным провалом (как `test_windows_data`).
	if sealed_lift.current_window == null:
		return t.results
	t.eq("окно держится за это ребро", String(sealed_lift.current_window["edge"]), "e_mid_goal")
	t.eq("вид окна прежний", String(sealed_lift.current_window["kind"]), "locked_door")
	t.eq("id окна — по ребру", String(sealed_lift.current_window["id"]), "locked_door:e_mid_goal")

	# 2. `unlock` снимает тревожную блокировку так же, как замок. Без этого группа
	# осталась бы перед лифтом навсегда: снимать блокировку было нечем.
	t.is_true("приказ принят", bool(sealed_lift.order("hack")["accepted"]))
	t.is_true("unlock отметил ребро открытым", bool(sealed_lift.unlocked.get("e_mid_goal", false)))
	sealed_lift.advance()
	t.eq("после unlock группа прошла ребро", sealed_lift.own[0].node, "goal")

	# 3. Обратная сторона: без `unlock` блокировка не снимается сама — ни шагом, ни
	# временем. Этот ассерт краснеет на мутации «блокировка спадает сама».
	var stuck_lift = _make([{"type": "noop"}])
	stuck_lift.advance()
	t.is_true("окно открылось и без unlock в эффектах", stuck_lift.current_window != null)
	if stuck_lift.current_window == null:
		return t.results
	t.is_true("приказ без unlock принят", bool(stuck_lift.order("hack")["accepted"]))
	for i in 3:
		stuck_lift.advance()
	t.eq("без unlock группа стоит перед перекрытым ребром", stuck_lift.own[0].node, "mid")
	## Первая попытка пройти по перекрытому ребру публикует событие — прежнее поведение,
	## сохранённое дословно (`architecture.md` §5: `path_blocked` — «тревога перекрыла путь»).
	t.is_true("упор опубликован событием path_blocked", _has(stuck_lift, "path_blocked"))
	t.eq("окно у перекрытого ребра не открывается второй раз", stuck_lift.current_window, null)

	# 4. Молчание у перекрытого ребра: `unlock` в исходе выводит группу из тупика. На это
	# опирается ledger задачи («`wait_rescue` у окна ★27 — осознанный риск игрока, а не
	# безвыходное состояние»). Качество молчания у группы без связиста всегда `safe`
	# (`_resolve_silence`), поэтому `unlock` поставлен именно в `safe`, и это проверяемо:
	# тот же кейс с `unlock` в `good` (см. ниже) группу из тупика не выводит.
	var silent_lift = _make([{"type": "noop"}], {"safe": [{"type": "unlock", "edge": "e_mid_goal"}]})
	silent_lift.advance()
	t.is_true("окно молчания открылось", silent_lift.current_window != null)
	if silent_lift.current_window == null:
		return t.results
	t.is_true("молчание принято", bool(silent_lift.order("silence")["accepted"]))
	silent_lift.advance()
	t.eq("молчание с unlock в нужном исходе вывело группу из тупика", silent_lift.own[0].node, "goal")

	# 4б. Тот же вход, но `unlock` стоит в исходе, который не выпал: группа остаётся.
	# Без этой половины ассерт выше проходил бы и тогда, когда молчание открывает ребро
	# независимо от данных.
	var silent_wrong_quality = _make([{"type": "noop"}],
		{"good": [{"type": "unlock", "edge": "e_mid_goal"}]})
	silent_wrong_quality.advance()
	t.is_true("окно молчания открылось и здесь", silent_wrong_quality.current_window != null)
	if silent_wrong_quality.current_window == null:
		return t.results
	t.is_true("молчание принято и здесь", bool(silent_wrong_quality.order("silence")["accepted"]))
	for i in 2:
		silent_wrong_quality.advance()
	t.eq("unlock не в том исходе группу не выводит", silent_wrong_quality.own[0].node, "mid")

	# 5. Идущему по ребру окно не открывается. Грузовой лифт закрывается через grace-период
	# (`FREIGHT_GRACE` = 3), и агент успевает поехать до закрытия: тревога закрывает путь
	# только на СТАРТЕ перехода (лифт, который уже поехал, назад не отзывают). Окно здесь
	# открывалось бы без причины и — что хуже — сожгло бы память «одно окно на ребро»
	# (`fired_edges`) на того, кто не стоит.
	var riding = _make([{"type": "noop"}], {}, "lift_freight", 6)
	for i in 5:
		riding.advance()
	t.eq("агент ещё не дошёл", riding.own[0].node, "mid")
	t.is_true("агент уже идёт по ребру", riding.own[0].progress > 0)
	t.is_true("тревога перекрыла ребро, пока агент шёл",
		riding.response.edge_blocked("lift_freight", riding.scales.step))
	t.eq("окно идущему по ребру не открывается", riding.current_window, null)

	# 6. Снятие блокировки АДРЕСНОЕ: `unlock` снимает её именно у этого ребра, а не у всех
	# рёбер того же вида. Иначе «запираемость по виду» превратилась бы в «один `unlock`
	# открывает все лифты», и цена приказа исчезла бы. Второй лифт миссии остаётся
	# перекрытым, и группа встаёт перед ним.
	var two_lifts = _make_two_lifts([{"type": "unlock", "edge": "e_mid_mid2"}])
	two_lifts.advance()
	t.is_true("окно первого лифта открылось", two_lifts.current_window != null)
	if two_lifts.current_window == null:
		return t.results
	t.is_true("приказ по первому лифту принят", bool(two_lifts.order("hack")["accepted"]))
	for i in 3:
		two_lifts.advance()
	t.eq("группа прошла открытый лифт и встала перед закрытым", two_lifts.own[0].node, "mid2")
	t.is_false("unlock не размазался на второй лифт", bool(two_lifts.unlocked.get("e_mid2_goal", false)))

	# 7. Замок И тревога на одном ребре: причина упора — замок, поэтому событие об упоре
	# молчит (о запертой двери скажет окно, `architecture.md` §5: `path_blocked` — про
	# тревогу). Гейт события (`not _is_locked(e)`) до этого кейса не охранялся ничем:
	# ребра, запертого И перекрытого сразу, в корпусе не было, и снятие гейта оставляло
	# набор зелёным.
	var locked_sealed = _make([{"type": "noop"}], {}, "lift_main", 1, true)
	t.is_true("ребро заперто в данных", bool(locked_sealed.mission.edge("e_mid_goal")["locked"]))
	locked_sealed.advance()
	## Сторож вырожденности: тревога действительно перекрывает ЭТО ЖЕ ребро, иначе молчание
	## события объяснялось бы тем, что перекрытия нет вовсе.
	t.is_true("тревога перекрыла то же ребро",
		locked_sealed.response.edge_blocked("lift_main", locked_sealed.scales.step))
	t.is_true("окно у запертого и перекрытого ребра открылось", locked_sealed.current_window != null)
	if locked_sealed.current_window == null:
		return t.results
	t.is_true("приказ без unlock принят", bool(locked_sealed.order("hack")["accepted"]))
	for i in 3:
		locked_sealed.advance()
	t.eq("группа осталась перед запертым перекрытым ребром", locked_sealed.own[0].node, "mid")
	t.is_false("у запертого ребра событие об упоре не публикуется", _has(locked_sealed, "path_blocked"))

	# 8. Два окна данных на ОДНО ребро: срабатывает только первое. Требование
	# `02-format.md` §4.2 («одно окно срабатывает один раз; повторных окон на одно ребро
	# не бывает») держится и на памяти по ребру (`fired_edges`), а её до этого кейса не
	# охраняло ничто: снятие записи по ребру оставляло набор зелёным (снятие памяти по id
	# краснит `test_windows_data`).
	#
	# Различить окна по рантайм-id нельзя: у окон запертого ребра он составной по ребру
	# (`locked_door:e_mid_goal`) и у обоих одинаков. Поэтому второе окно отличается
	# ВАРИАНТОМ (`hack_2`), и «сработало первое» доказывается приказом: вариант `hack`
	# принят, значит открылось окно первых данных, а не вторых.
	var two_doors = _make([{"type": "noop"}], {}, "lift_main", 1, true, 2)
	var door_windows: Array = two_doors.mission.data["windows"]
	t.eq("окон на ребре два", door_windows.size(), 2)
	t.eq("id второго окна в данных своё", String(door_windows[1]["id"]), "w_sealed_2")
	t.eq("вариант второго окна свой", String(door_windows[1]["options"][0]["id"]), "hack_2")
	two_doors.advance()
	t.is_true("первое окно на ребре открылось", two_doors.current_window != null)
	if two_doors.current_window == null:
		return t.results
	t.is_true("сработало именно первое окно: его вариант принят", bool(two_doors.order("hack")["accepted"]))
	## Сторож вырожденности: ребро всё ещё заперто, то есть второму окну было бы на что
	## сработать. Молчит именно память по ребру, а не отсутствие повода.
	t.is_true("ребро всё ещё заперто", bool(two_doors.mission.edge("e_mid_goal")["locked"]))
	two_doors.advance()
	t.eq("второе окно на то же ребро не открывается", two_doors.current_window, null)

	# 9. Агент, стоящий в УЗЛЕ ВЫХОДА, окно у запертой двери всё равно открывает.
	# Это форма миссии 01: выход `hall0` — тот самый узел перед запертой дверью холодного
	# зала, а `_actor_before_locked_edge` пропускал агента в `plan.exit_node` целиком,
	# поэтому окно `w_archivist` не открывалось НИКОГДА, цель не бралась, и два
	# прохождения из трёх не завершались (`reports/05-first-measurements.md` §9).
	# Здесь выход — `mid`, то есть узел ПЕРЕД дверью `e_mid_goal`, а не за ней.
	var at_exit = _make([{"type": "unlock", "edge": "e_mid_goal"}], {}, "door", 1, true, 1, "mid")
	at_exit.advance()
	t.eq("агент дошёл до узла выхода и упёрся в запертую дверь", at_exit.own[0].node, "mid")
	t.eq("узел агента — и есть выход плана", at_exit.own[0].node, at_exit.plan.exit_node)
	t.is_true("ребро к цели заперто", bool(at_exit.mission.edge("e_mid_goal")["locked"]))
	t.is_true("окно открылось агенту в узле выхода", at_exit.current_window != null)
	## Имя двери берём через охрану, а не ранним выходом: ранний `return` унёс бы с собой
	## все ассерты ниже (в том числе блоки 10 и 11), и провал «окно не открылось» молча
	## съедал бы половину проверок — ровно та форма, против которой стоит §4 `constraints.md`.
	var at_exit_edge := ""
	if at_exit.current_window != null:
		at_exit_edge = String(at_exit.current_window["edge"])
	t.eq("окно называет дверь к цели", at_exit_edge, "e_mid_goal")
	t.is_true("приказ у двери принят", bool(at_exit.order("hack")["accepted"]))
	at_exit.advance()
	t.eq("после unlock агент прошёл дверь к цели", at_exit.own[0].node, "goal")
	t.eq("цель взята", at_exit.result()["objective_done"], true)
	at_exit.advance()
	t.eq("и вернулся на выход", at_exit.own[0].node, "mid")
	t.eq("миссия завершилась уходом", String(at_exit.result()["outcome"]), "extracted")

	# 10. Маршрут, НАЧИНАЮЩИЙСЯ в узле выхода, окна «на старте» не открывает — вторая
	# половина того же правила, и она проверяется отдельно: без неё снятие пропуска целиком
	# сделало бы окно возможным на нулевом шаге любого маршрута, начинающегося в выходе.
	var from_exit = _make_from_exit()
	from_exit.advance()
	## Сторож вырожденности: состояние агента — ровно то, на которое смотрит пропуск
	## (первый узел маршрута, ни шага пути, стоит в выходе), и дверь заперта. Значит
	## молчит именно пропуск, а не отсутствие повода.
	t.eq("агент стоит в выходе", from_exit.own[0].node, "start")
	t.eq("агент не сделал ни шага маршрута", from_exit.own[0].waypoint_index, 1)
	t.eq("агент не начал переход", from_exit.own[0].progress, 0)
	t.is_true("дверь на первом же ребре заперта", bool(from_exit.mission.edge("e_start_goal")["locked"]))
	t.eq("окно на старте не открывается", from_exit.current_window, null)

	# 11. Прямое ребро к выходу предпочтительнее обратного пути. Это форма ветки, которая
	# сегодня ЕДИНСТВЕННАЯ завершается уходом: в миссии 01 вошедший в цель через грузовой
	# лифт выходит через `hall0` — то есть НЕ тем путём, которым пришёл. Обратный путь без
	# этого правила увёл бы группу наверх, к узлу входа, и миссия не зачлась бы.
	var across = _make_across()
	across.advance()
	t.eq("цель взята с открытой стороны", across.own[0].node, "goal")
	t.eq("выход — узел ЗА запертой дверью, а не тот, откуда пришли",
		String(across.plan.exit_node), "mid")
	## Сторож вырожденности: ребро «цель → выход» есть, значит применимо именно правило
	## прямого ребра, а не обратный путь.
	t.is_false("ребро «цель → выход» есть: правило 1 применимо",
		across.mission.edge_between("goal", "mid").is_empty())
	t.is_true("на пути к выходу окно у двери открылось", across.current_window != null)
	## Без раннего выхода: если окно не открылось, провал виден ещё и остановкой группы
	## в узле входа (assert ниже), а не только отсутствием окна.
	t.is_true("приказ на выходе принят", bool(across.order("hack")["accepted"]))
	across.advance()
	t.eq("группа вышла через запертое прямое ребро", across.own[0].node, "mid")
	t.eq("миссия с запертым выходом завершилась уходом", String(across.result()["outcome"]), "extracted")

	# 11б. Та же форма, но прямое ребро к выходу НЕ заперто: путь домой обязан идти по нему,
	# а не обратным путём. Здесь окна нет вовсе, поэтому провал правила 1 виден не окном, а
	# остановкой группы в узле входа: «вышел» — это факт позиции, а не отсутствие окна.
	var across_open = _make_across(false)
	across_open.advance()
	t.eq("цель взята и на открытом ребре", across_open.own[0].node, "goal")
	t.eq("выход — узел ЗА целью и здесь", String(across_open.plan.exit_node), "mid")
	t.eq("окон на открытом ребре нет", across_open.current_window, null)
	across_open.advance()
	t.eq("группа вышла через открытое прямое ребро", across_open.own[0].node, "mid")
	across_open.advance()
	t.eq("миссия с открытым выходом завершилась уходом", String(across_open.result()["outcome"]), "extracted")

	return t.results


## Миссия: вход → площадка → цель, причём последнее ребро перекрывается тревогой
## (`noise_start` 25 взводит её на первом же шаге). По умолчанию замка на ребре нет:
## `locked` в данных остаётся `false`, и это то, что прежде решало судьбу окна.
##
## `kind`, `steps` и `locked` последнего ребра — параметры: перекрытие тревогой
## (`lift_main`, `lift_freight`), длина перехода (для случая «агент уже на ребре») и замок
## на том же ребре (замок И тревога сразу) проверяются на одной и той же миссии.
##
## `windows_on_edge` — сколько окон данных висит на последнем ребре. Данные такого не
## содержат (§4.2: одно окно на ребро), но ядро обязано пережить это своим правилом,
## а не надеждой на автора. Второе и следующие окна получают свой id данных и свой
## вариант (`hack_2`): рантайм-id окон запертого ребра один и тот же (составной по ребру),
## а память по id считается от id данных — без этого «сработало первое» неотличимо.
##
## `exit_node` — куда выходит группа. Умолчание прежнее (`goal`), а не `mid`: иначе
## сдвинулись бы все блоки выше, где выход равен цели, и кейс 9 проверял бы не форму
## «выход — узел перед дверью», а случайный побочный эффект.
func _make(option_effects: Array, silence_by_quality := {}, kind := "lift_main", steps := 1,
		locked := false, windows_on_edge := 1, exit_node := "goal"):
	var m := Mission.new()
	m.id = "sealed_edge"
	m.add_node("start", 1, ["entry"])
	m.add_node("mid", 1, [])
	m.add_node("goal", 1, [])
	m.add_edge("e_start_mid", "start", "mid", "corridor", 1, 0)
	m.add_edge("e_mid_goal", "mid", "goal", String(kind), int(steps), 0, bool(locked))
	m.objective = "goal"
	var windows: Array = []
	for i in int(windows_on_edge):
		var w := _window(option_effects, silence_by_quality)
		if i > 0:
			w["id"] = "%s_%d" % [String(w["id"]), i + 1]
			w["options"][0]["id"] = "hack_%d" % (i + 1)
		windows.append(w)
	m.set_data({"windows": windows})
	var p := Plan.new()
	p.route = ["start", "mid", "goal"]
	p.exit_node = String(exit_node)
	p.agents = [{"id": "kira", "role": "tactician", "understanding": 3}]
	var sim := Sim.new()
	sim.setup(m, p, {"orders": 3, "seed": 1, "noise_start": 25})
	return sim


## Окно запертой двери в авторской форме (`02-format.md` §4): триггер `locked_edge` на
## ребро лифта, один вариант и четыре исхода молчания. Молчание описано всегда: у окна
## обязан быть вариант «молчать» (D23). `silence_by_quality` перекрывает отдельные исходы —
## этим проверяется, что ребро открывает `unlock` ИМЕННО выпавшего исхода.
func _window(option_effects: Array, silence_by_quality: Dictionary, edge := "e_mid_goal") -> Dictionary:
	var silence := {
		"text_key": "window.w_sealed.silence",
		"good": [{"type": "noop"}],
		"neutral": [{"type": "noop"}],
		"bad": [{"type": "noop"}],
		"safe": [{"type": "noop"}],
	}
	for quality in silence_by_quality:
		silence[String(quality)] = silence_by_quality[quality]
	return {
		"id": "w_sealed",
		"kind": "locked_edge",
		"trigger": {"type": "locked_edge", "edge": String(edge)},
		"text_key": "window.w_sealed.text",
		"options": [{
			"id": "hack",
			"text_key": "window.w_sealed.hack",
			"complexity": 3,
			"cost": {"noise": 0, "delay": 0},
			"effects": option_effects,
		}],
		"silence": silence,
	}


## Миссия с ДВУМЯ перекрываемыми рёбрами одного вида (`lift_main`): `start → mid → mid2 →
## goal`. Окно одно — на первое ребро (`e_mid_mid2`), и `unlock` обязан открыть только его.
func _make_two_lifts(option_effects: Array):
	var m := Mission.new()
	m.id = "sealed_edge_two_lifts"
	m.add_node("start", 1, ["entry"])
	m.add_node("mid", 1, [])
	m.add_node("mid2", 1, [])
	m.add_node("goal", 1, [])
	m.add_edge("e_start_mid", "start", "mid", "corridor", 1, 0)
	m.add_edge("e_mid_mid2", "mid", "mid2", "lift_main", 1, 0)
	m.add_edge("e_mid2_goal", "mid2", "goal", "lift_main", 1, 0)
	m.objective = "goal"
	m.set_data({"windows": [_window(option_effects, {}, "e_mid_mid2")]})
	var p := Plan.new()
	p.route = ["start", "mid", "mid2", "goal"]
	p.exit_node = "goal"
	p.agents = [{"id": "kira", "role": "tactician", "understanding": 3}]
	var sim := Sim.new()
	sim.setup(m, p, {"orders": 3, "seed": 1, "noise_start": 25})
	return sim


## Было ли событие заданного вида за прогон.
func _has(sim, type: String) -> bool:
	for e in sim.events:
		if String(e["type"]) == type:
			return true
	return false


## Маршрут, НАЧИНАЮЩИЙСЯ в узле выхода: `start` — и выход, и первый узел маршрута, а первое
## же ребро заперто и открывается окном. Форма, ради которой пропуск агента в
## `plan.exit_node` сужен до «маршрут ещё не начат», а не снят целиком.
func _make_from_exit():
	var m := Mission.new()
	m.id = "from_exit"
	m.add_node("start", 1, [])
	m.add_node("goal", 1, [])
	m.add_edge("e_start_goal", "start", "goal", "door", 1, 0, true)
	m.objective = "goal"
	m.set_data({"windows": [_window([{"type": "unlock", "edge": "e_start_goal"}], {}, "e_start_goal")]})
	var p := Plan.new()
	p.route = ["start", "goal"]
	p.exit_node = "start"
	p.agents = [{"id": "kira", "role": "tactician", "understanding": 3}]
	var sim := Sim.new()
	sim.setup(m, p, {"orders": 3, "seed": 1})
	return sim


## Цель с ДВУМЯ сторонами: пришли с открытой (`start`), а выход — за дверью (`mid`).
## Форма ветки, которая в миссии 01 сегодня единственная завершается уходом: вошедший в цель
## через грузовой лифт выходит не тем путём, которым пришёл.
##
## `locked` — заперта ли дверь к выходу. Запертая половина проверяет ещё и то, что окно на
## обратном пути открывается агенту, стоящему в ЦЕЛИ (а не в выходе); открытая — что путь
## домой вообще выбирает прямое ребро, а не разворот к узлу входа: окна там нет, и провал
## правила виден остановкой группы, а не отсутствием окна.
func _make_across(locked := true):
	var m := Mission.new()
	m.id = "across"
	m.add_node("start", 1, [])
	m.add_node("goal", 1, [])
	m.add_node("mid", 1, [])
	m.add_edge("e_start_goal", "start", "goal", "corridor", 1, 0)
	m.add_edge("e_goal_mid", "goal", "mid", "door", 1, 0, bool(locked))
	m.objective = "goal"
	if locked:
		m.set_data({"windows": [_window([{"type": "unlock", "edge": "e_goal_mid"}], {}, "e_goal_mid")]})
	var p := Plan.new()
	p.route = ["start", "goal"]
	p.exit_node = "mid"
	p.agents = [{"id": "kira", "role": "tactician", "understanding": 3}]
	var sim := Sim.new()
	sim.setup(m, p, {"orders": 3, "seed": 1})
	return sim

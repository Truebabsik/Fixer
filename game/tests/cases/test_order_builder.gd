extends RefCounted
## Самопроверка модуля построения сценария вмешательства: правило выбора ТРЕТЬЕГО поведения
## («разумные приказы», D53).
##
## Зачем отдельный кейс. Правило «вариант, снимающий препятствие; из равных — тишайший;
## равный шум разрешает порядок данных» жило в `tests/order_builder.gd` и не проверялось
## НИЧЕМ: приёмка (`accept_delivery.gd`) судит только агрегат («приказов > 0»), а `PICK_REASONABLE`
## и `removes_obstacle` не упоминались ни в одном кейсе набора (M3 ревью 01–04). Замена
## `<` на `<=`, выбор «первого попавшегося» или «самого шумного» снимающего оставалась
## зелёной — то есть правило выглядело проверенным, не будучи им.
##
## Что здесь держится:
##   * снятие препятствия важнее шума: дешёвый вариант без `unlock` не перебивает снимающий;
##   * из нескольких снимающих берётся ТИШАЙШИЙ, а не первый в данных (иначе выбор зависит
##     от порядка записи в JSON, а не от цены);
##   * равный шум разрешается порядком данных — и следует за данными при перевороте
##     (значит, это не кубик и не порядок словаря, `constraints.md` §1.6);
##   * `unlock` внутри `fallback` заявки движку считается снятием препятствия — ровно так,
##     как его применяет ядро (заявку исполняет её `fallback`);
##   * нет ни одного снимающего — окно МОЛЧИТ (молчание — законный ход, D23);
##   * вариант с id `silence` приказом не считается;
##   * повтор выбора на одном окне даёт тот же ответ (кубика в правиле нет).
##
## Правило проверяется через ТОТ ЖЕ вход, которым пользуется инструмент:
## `OrderBuilder.pick(WindowScript.from_data(w, ""), PICK_REASONABLE)` — авторская форма
## данных → рантайм-форма окна → выбор. Иначе кейс держал бы копию правила, а не правило:
## проба на `noise` из `cost` (цена переезжает на вариант в `window.gd:_options`) прошла бы
## мимо, и «тишайший» считался бы по полю, которого в данных нет.

const Assert := preload("res://tests/assert.gd")
const OrderBuilder := preload("res://tests/order_builder.gd")
const WindowScript := preload("res://sim/window.gd")


## Окно авторской формы: один вариант — одна цена (`cost.noise`) и, если он снимает
## препятствие, эффект `unlock`. Ветка молчания описана пустыми эффектами: выбору она не
## мешает, а `from_data` обязан её собрать (`window.gd:_options`).
func _window(options: Array) -> Dictionary:
	return {
		"id": "w_door",
		"kind": "locked_edge",
		"trigger": {"type": "locked_edge", "edge": "e_door"},
		"text_key": "window.w_door.text",
		"options": options,
		"silence": {
			"text_key": "window.w_door.silence",
			"good": [], "neutral": [], "bad": [], "safe": [],
		},
	}


func _option(id: String, noise: int, unlocks: bool) -> Dictionary:
	var effects: Array = []
	if unlocks:
		effects.append({"type": "unlock", "edge": "e_door"})
	return {"id": id, "text_key": "window.w_door.%s" % id, "complexity": 1,
		"cost": {"noise": noise, "delay": 0}, "effects": effects}


## Вариант без цены вовсе: `cost` не задан — шум обязан читаться как ноль, а не как пропуск.
func _option_without_cost(id: String, unlocks: bool) -> Dictionary:
	var option := _option(id, 0, unlocks)
	option.erase("cost")
	return option


## Выбор третьего поведения — тем же путём, что у инструмента.
func _pick(raw: Dictionary) -> String:
	return OrderBuilder.pick(WindowScript.from_data(raw, ""), OrderBuilder.PICK_REASONABLE)


func run() -> Array:
	var t := Assert.new()

	# 1. Положительная половина правила: из нескольких снимающих препятствие берётся
	# ТИШАЙШИЙ. Первым в данных стоит громкий — иначе ассерт краснел бы и у выбора
	# «первого попавшегося», то есть не различал бы правило и его отсутствие.
	t.eq("из снимающих препятствие берётся тишайший, а не первый в данных",
		_pick(_window([_option("loud", 9, true), _option("quiet", 1, true)])), "quiet")
	t.eq("порядок данных перевёрнут — выбор по-прежнему у тишайшего",
		_pick(_window([_option("quiet", 1, true), _option("loud", 9, true)])), "quiet")

	# 2. Снятие препятствия важнее шума: вариант без `unlock` дешевле (шум 0) и всё равно
	# не выигрывает. Без этой половины правило читалось бы как «просто тишайший».
	t.eq("дешёвый вариант БЕЗ снятия препятствия не перебивает снимающий",
		_pick(_window([_option("cheap", 0, false), _option("opens", 7, true)])), "opens")

	# 3. Равный шум разрешает ПОРЯДОК ДАННЫХ — и следует за данными при перевороте.
	# Это и есть проверка детерминизма: выбор, зависящий от порядка словаря или от кубика,
	# не мог бы поменяться ровно так, как переставлены варианты.
	t.eq("равный шум — берётся первый по порядку данных",
		_pick(_window([_option("first_in_data", 2, true), _option("second_in_data", 2, true)])),
		"first_in_data")
	t.eq("равный шум, порядок данных перевёрнут — выбор следует за данными",
		_pick(_window([_option("second_in_data", 2, true), _option("first_in_data", 2, true)])),
		"second_in_data")

	# 4. Отсутствие цены — шум 0 (а не «нет варианта»): он тише явного шума.
	t.eq("вариант без цены считается вариантом с шумом 0",
		_pick(_window([_option("priced", 3, true), _option_without_cost("free", true)])), "free")

	# 5. `unlock` внутри `fallback` заявки движку: ядро применяет заявку её `fallback`,
	# поэтому ребро открывается НА САМОМ ДЕЛЕ, и для выбора варианта это снятие препятствия.
	# Вторая половина — заявка БЕЗ `unlock` в `fallback` препятствия не снимает: иначе
	# ассерт выше проходил бы на любом `engine_proposal`.
	var via_fallback := {"id": "proposal", "text_key": "window.w_door.proposal", "complexity": 1,
		"cost": {"noise": 0, "delay": 0},
		"effects": [{"type": "engine_proposal", "id": "hold", "want": "дверь открыта",
			"needs": "таймер", "fallback": [{"type": "unlock", "edge": "e_door"}]}]}
	t.eq("unlock внутри fallback заявки считается снятием препятствия",
		_pick(_window([via_fallback])), "proposal")
	var proposal_without_unlock := {"id": "proposal", "text_key": "window.w_door.proposal",
		"complexity": 1, "cost": {"noise": 0, "delay": 0},
		"effects": [{"type": "engine_proposal", "id": "hold", "want": "дверь открыта",
			"needs": "таймер", "fallback": [{"type": "delay", "value": 2}]}]}
	t.eq("заявка без unlock в fallback препятствия не снимает — окно молчит",
		_pick(_window([proposal_without_unlock])), WindowScript.SILENCE)

	# 6. Нет ни одного снимающего — молчание. Это не «пропуск решения»: молчание —
	# законный ход (D23), и правило обязано возвращать именно его, а не пустую строку.
	t.eq("нет варианта, снимающего препятствие — окно молчит",
		_pick(_window([_option("cheap", 0, false), _option("noisy", 12, false)])),
		WindowScript.SILENCE)
	t.eq("пустой список вариантов — окно молчит", _pick(_window([])), WindowScript.SILENCE)

	# 7. Вариант с id `silence` приказом не считается: это встроенная ветка молчания,
	# и выбрать её как «снимающую препятствие» значило бы отдать приказ, которого нет.
	var fake_silence := _option(WindowScript.SILENCE, 0, true)
	t.eq("вариант с id `silence` приказом не считается — окно молчит",
		_pick(_window([fake_silence])), WindowScript.SILENCE)

	# 8. Повтор выбора на одном окне — тот же ответ: правило детерминировано, кубика в нём нет
	# (единственный источник случайности в прогоне — `rng` ядра из `config.seed`).
	var repeated := _window([_option("a", 4, true), _option("b", 4, true), _option("c", 1, true)])
	var answers: Array = []
	for i in 5:
		answers.append(_pick(repeated))
	t.eq("повтор выбора на одном окне — тот же вариант (кубика нет)", answers,
		["c", "c", "c", "c", "c"])

	# 9. Три поведения — три разных правила, а не три имени одного: на окне, где снимающий
	# вариант тихий, а шумный препятствия не снимает, «самый шумный» и «разумные приказы»
	# обязаны разойтись. Иначе `PICK_REASONABLE` был бы синонимом `PICK_LOUD`, и разговор
	# о третьем поведении не имел бы предмета.
	var mixed := _window([_option("noisy", 9, false), _option("quiet", 1, true)])
	t.eq("«самый шумный» выбирает шумный вариант",
		OrderBuilder.pick(WindowScript.from_data(mixed, ""), OrderBuilder.PICK_LOUD), "noisy")
	t.eq("«разумные приказы» на том же окне выбирают снимающий",
		OrderBuilder.pick(WindowScript.from_data(mixed, ""), OrderBuilder.PICK_REASONABLE), "quiet")

	return t.results

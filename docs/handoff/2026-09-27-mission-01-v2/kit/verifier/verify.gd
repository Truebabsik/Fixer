extends SceneTree
## Самопроверка данных уровня НАШИМ валидатором, без нашего репозитория.
##
## Что делает. Читает два файла, переданные аргументами (`-- <mission.json> <texts.json>`),
## прогоняет их через копии `content/validator.gd` и `content/loader.gd` и печатает
## каждую проблему дословно: код, путь и сообщение. Миссия собирается только тогда,
## когда проблем ноль, — «форма прошла» и «миссия собирается» здесь разные вопросы.
##
## Вердикт — КОД ВОЗВРАТА процесса, а не текст:
##   0 — проблем нет, миссия собрана;
##   1 — проблемы есть (они напечатаны выше);
##   2 — файлы не прочитались или не разобрались как JSON, либо аргументы не переданы.
## Текст в stderr вердиктом не является: Godot пишет туда безобидный шум
## (`Failed to read the root certificate store`, `Could not create directory: 'user://logs'`)
## даже при коде 0. Смотри только на код возврата.
##
## Почему сторож. При рантайм-сбое GDScript прерывает `_initialize()` (а не процесс):
## `quit()` тогда не вызывается, и прогон висит или заканчивается нулём. Флаг превращает
## «аборт до вердикта» в честный код 1. Тот же приём — в раннере нашего набора тестов.

const Validator := preload("res://content/validator.gd")
const Loader := preload("res://content/loader.gd")

const EXIT_OK := 0
const EXIT_PROBLEMS := 1
const EXIT_BAD_INPUT := 2
const EXIT_ABORTED := 1

var _verdict_reached := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		print("ИСПОЛЬЗОВАНИЕ: --script res://verify.gd -- <mission.json> <texts.json>")
		print("передано аргументов: %d (после `--`), а нужно ровно два" % args.size())
		_quit(EXIT_BAD_INPUT)
		return
	var mission_path := String(args[0])
	var texts_path := String(args[1])

	var mission_read := _read_json(mission_path)
	if not mission_read["ok"]:
		print("НЕ ПРОЧИТАНО  mission: %s" % String(mission_read["error"]))
		_quit(EXIT_BAD_INPUT)
		return
	var texts_read := _read_json(texts_path)
	if not texts_read["ok"]:
		print("НЕ ПРОЧИТАНО  texts: %s" % String(texts_read["error"]))
		_quit(EXIT_BAD_INPUT)
		return

	var data = mission_read["data"]
	var texts = texts_read["data"]
	print("ФАЙЛЫ  mission: %s" % mission_path)
	print("ФАЙЛЫ  texts:   %s" % texts_path)

	# Форма корней: `[1, 2]` — валидный JSON, но не контент, и валидатор его не примет.
	# Это ошибка ВХОДА (код 2), а не список проблем: сверять нечего.
	if typeof(data) != TYPE_DICTIONARY:
		print("НЕ ТОТ ФОРМАТ  mission: корень %s, а нужен объект {}" % type_string(typeof(data)))
		_quit(EXIT_BAD_INPUT)
		return
	if typeof(texts) != TYPE_DICTIONARY:
		print("НЕ ТОТ ФОРМАТ  texts: корень %s, а нужен объект {}" % type_string(typeof(texts)))
		_quit(EXIT_BAD_INPUT)
		return

	# Валидатор вызывается со СЛОВАРЁМ текстов: сверка ключей в обе стороны обязательна.
	# `null` вместо словаря означал бы «сверку не делаю», и половина проверок исчезла бы.
	var problems: Array = Validator.validate(data, texts)
	print("ПРОБЛЕМ: %d" % problems.size())
	var i := 1
	for p in problems:
		print("  %d. [%s] %s — %s" % [i, String(p.get("code", "")), String(p.get("path", "")),
			String(p.get("message", ""))])
		i += 1

	if not problems.is_empty():
		print("ВЕРДИКТ: проблемы есть — уровень не принят (код 1)")
		_quit(EXIT_PROBLEMS)
		return

	var loaded := Loader.load_mission(data, texts)
	var loaded_problems: Array = loaded["problems"]
	if loaded["mission"] == null or not loaded_problems.is_empty():
		print("СБОРКА: миссия НЕ собрана, хотя проблем формы нет:")
		for p in loaded_problems:
			print("  [%s] %s — %s" % [String(p.get("code", "")), String(p.get("path", "")),
				String(p.get("message", ""))])
		_quit(EXIT_PROBLEMS)
		return

	var mission = loaded["mission"]
	print("СОБРАНО: миссия «%s», помещений %d, рёбер %d, патрулей %d, сенсоров %d, окон %d, разведка %d, точек доступа %d"
		% [mission.id, mission.nodes.size(), mission.edges.size(), mission.patrols.size(),
			mission.sensors.size(), (mission.data["windows"] as Array).size(),
			(mission.data["intel"] as Array).size(),
			(mission.data["access_points"] as Array).size()])
	print("ВЕРДИКТ: проблем нет, миссия собрана (код 0)")
	_quit(EXIT_OK)


## Чтение и разбор JSON. Возвращает `{"ok": bool, "data": Variant, "error": String}`:
## причина — словами, чтобы провал называл файл, а не «не разобралось».
func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "data": null,
			"error": "не открыт «%s» (код ошибки %d)" % [path, FileAccess.get_open_error()]}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var error := json.parse(text)
	if error != OK:
		return {"ok": false, "data": null,
			"error": "«%s» не разбирается как JSON: %s (строка %d)"
				% [path, json.get_error_message(), json.get_error_line()]}
	return {"ok": true, "data": json.data, "error": ""}


func _quit(code: int) -> void:
	_verdict_reached = true
	quit(code)


## Сторож вердикта: `_initialize()` прервался до `quit()` — говорим об этом вслух и
## выходим кодом 1, а не висим и не отдаём ноль.
func _process(_delta: float) -> bool:
	if _verdict_reached:
		return false
	print("АБОРТ  вердикт не выставлен: прогон прервался до quit() (код 1)")
	quit(EXIT_ABORTED)
	return true

extends RefCounted
## Самодостаточность пакета наружу: модули, которые в него копируются, не имеют права
## ссылаться на наш репозиторий — ни путём, ни номером внутреннего решения.
##
## Зачем кейс. Пакет `docs/handoff/2026-09-27-mission-01-v2/` уходит исполнителю, у
## которого нашего репозитория НЕТ. Задача 13 вычистила наши следы из СООБЩЕНИЙ
## валидатора, но в КОММЕНТАРИЯХ остались внутренние коды решений (`D37`, `D30`, `D9`,
## `D31`, `D32`) и ссылки на документы по старым номерам (`02-format.md`, `04-texts.md`,
## `design.md`, `review-03`). Получатель открывает модуль, видит ссылку на
## несуществующий у него файл и решает, что пакет дали неполный. Словами это не
## стережётся: модуль правится вместе с кодом, и ссылка уезжает наружу молча.
##
## Что проверяется (по всем файлам пакета и по боевым модулям):
##   * `docs/` и `docs\` — пути нашего репозитория;
##   * внутренний код решения по шаблону `\bD[0-9]{2}\b`;
##   * `res://tests` — наш набор тестов;
##   * `review-` — ссылка на наши документы ревью;
##   * `res://content` и `res://sim` — пути ЧУЖОГО проекта, и только ВНЕ собственного
##     проекта комплекта: внутри `kit/verifier/**` они верны (`res://` там и указывает
##     на папку комплекта), а в боевых модулях верны тем более — они и есть тот проект;
##   * имя документа вида `01-format.md`, названное в файле пакета, обязано в пакете
##     существовать: ложная ссылка — дефект, и её в этой сессии ловили девятнадцать раз.
##
## ГЛАВНОЕ ПРО ЭТОТ КЕЙС: он обязан краснеть. Держат это три вещи —
##   1) положительный контроль: детектор ищет грязь в заведомо грязной строке и
##      называет КАЖДОЕ правило (список правил в контроле написан руками, а не взят из
##      `RULES`: эталон, производный от проверяемого, ничего не проверяет);
##   2) отрицательный контроль: на чистом тексте детектор молчит;
##   3) проверка непустоты корпуса: якоря пакета на месте и файлов просмотрено не меньше
##      пола. Исключений из обхода нет ни одного — сканируется и сам скрипт проверки
##      комплекта (`kit/verifier/selfcheck.gd`), поэтому его текст собран так, чтобы не
##      содержать того, что он ищет.
##
## Тот же прогон живёт В САМОМ пакете (`kit/verifier/selfcheck.gd`): получатель может
## проверить комплект, не имея нашего набора тестов, и обязан увидеть то же самое.
## Два экземпляра правил неизбежны (комплект — отдельный проект Godot), поэтому
## расхождение ловится пробами: кейс краснеет на мутации боевого модуля, комплект — на
## мутации файла пакета.

const Assert := preload("res://tests/assert.gd")

## Путь к пакету ОТ КОРНЯ ПРОЕКТА: `res://` → `game/`, на уровень выше — `docs/`.
## Именно относительный: при переезде файла провал называет прочитанный путь целиком.
const PACKAGE_RELATIVE := "../docs/handoff/2026-09-27-mission-01-v2"

## Боевые модули, копии которых лежат в комплекте (`kit/verifier/`). Список явный:
## новый модуль в комплекте обязан появиться здесь, иначе проверка его не увидит.
const BATTLE_MODULES := [
	"content/validator.gd",
	"content/problems.gd",
	"content/loader.gd",
	"sim/mission.gd",
	"sim/plan.gd",
	"sim/response.gd",
]

## Собственный проект комплекта внутри пакета: здесь `res://` указывает на папку
## комплекта, поэтому пути `res://content/...` и `res://sim/...` в этих файлах ВЕРНЫ и
## нарушением не считаются. Префикс привязан к факту: `kit/verifier/verify.gd` назван
## якорем ниже, и без него кейс краснеет раньше этой проверки.
const OWN_PROJECT_PREFIX := "kit/verifier/"

## Якоря пакета. Не перечень состава (пакет может расти), а пол: без этих файлов
## проверять нечего, и молчаливое «нарушений нет» было бы вырожденным. Сюда же входит
## скрипт проверки комплекта: он и есть вторая половина этой же проверки.
const ANCHORS := [
	"README.md",
	"00-task.md",
	"01-format.md",
	"03-texts.md",
	"05-borders.md",
	"kit/verifier/verify.gd",
	"kit/verifier/selfcheck.gd",
	"kit/verifier/content/validator.gd",
	"kit/verifier/content/problems.gd",
	"kit/verifier/content/loader.gd",
	"kit/verifier/sim/mission.gd",
	"kit/verifier/sim/plan.gd",
	"kit/verifier/sim/response.gd",
]

## Пол корпуса: 22 файла на момент правки (документы пакета, комплект, образец,
## сам скрипт проверки). Пол, а не равенство: пакет имеет право расти.
const MIN_PACKAGE_FILES := 18

## Сканируются только текстовые файлы; пропущенное считается и печатается в имени
## ассерта, чтобы «не смотрели» не выглядело как «чисто».
const TEXT_EXTENSIONS := ["md", "gd", "json", "godot", "txt", "cfg"]

## Кэш движка: создаётся прогоном комплекта и к пакету не относится.
const SKIP_DIRECTORIES := [".godot"]

## Правила поиска. `id` — короткое имя для контрольных ассертов, `name` — то, что
## читает человек в провале; `skip_in_own_project` — для путей, верных внутри проекта.
const RULES := [
	{"id": "docs-slash", "name": "путь нашего репозитория `docs/`",
		"pattern": "docs/", "skip_in_own_project": false},
	{"id": "docs-backslash", "name": "путь нашего репозитория `docs\\`",
		"pattern": "docs\\\\", "skip_in_own_project": false},
	{"id": "dnn", "name": "внутренний код решения `DNN`",
		"pattern": "\\bD[0-9]{2}\\b", "skip_in_own_project": false},
	{"id": "res-tests", "name": "наш набор тестов `res://tests`",
		"pattern": "res://tests", "skip_in_own_project": false},
	{"id": "review", "name": "ссылка на наш разбор `review-`",
		"pattern": "review-", "skip_in_own_project": false},
	{"id": "res-content", "name": "путь чужого проекта `res://content`",
		"pattern": "res://content", "skip_in_own_project": true},
	{"id": "res-sim", "name": "путь чужого проекта `res://sim`",
		"pattern": "res://sim", "skip_in_own_project": true},
]

## Имя документа пакета: две цифры, дефис, имя. По такой ссылке и спрашивается файл.
const DOCUMENT_REFERENCE := "[0-9]{2}-[A-Za-z0-9_\\-]+\\.md"

## Контрольные строки. Написаны руками и НЕЗАВИСИМО от `RULES`: эталон, собранный из
## проверяемого списка, мутацию в нём не краснеет.
const DIRTY_SAMPLE := "# docs/spr/scales.md и docs\\spr\\scales.md\n## решение D99\n## res://tests/run.gd\n## review-03 §7.5\n## res://content/x.gd и res://sim/y.gd\n"
const CLEAN_SAMPLE := "## Окно срабатывает один раз за миссию\n## Код проблемы: BAD_VALUE\n"
const DIRTY_RULES := ["dnn", "docs-backslash", "docs-slash", "res-content", "res-sim",
	"res-tests", "review"]
const DIRTY_RULES_OWN_PROJECT := ["dnn", "docs-backslash", "docs-slash", "res-tests", "review"]


## Поиск нарушений в тексте. Нарушение — словарь, а не строка: контрольным ассертам
## нужно ИМЯ сработавшего правила, а провалу — место и строка.
func _scan_text(text: String, relative: String, own_project: bool, regexes: Array) -> Array:
	var out: Array = []
	var lines := text.split("\n")
	for i in lines.size():
		var line := String(lines[i])
		for rule_index in RULES.size():
			var rule: Dictionary = RULES[rule_index]
			if bool(rule["skip_in_own_project"]) and own_project:
				continue
			if (regexes[rule_index] as RegEx).search(line) == null:
				continue
			out.append({
				"id": String(rule["id"]),
				"rule": String(rule["name"]),
				"where": "%s:%d" % [relative, i + 1],
				"line": line.strip_edges(),
			})
	return out


## Имена сработавших правил, по одному разу, по алфавиту: так контроль сверяет НАБОР
## правил, а не число нарушений (число сходится и при неверном наборе).
func _rules_of(violations: Array) -> Array:
	var seen: Dictionary = {}
	for violation in violations:
		seen[String((violation as Dictionary)["id"])] = true
	var out: Array = seen.keys()
	out.sort()
	return out


## Нарушения строкой для имени ассерта: провал обязан называть место и правило.
func _brief(violations: Array) -> String:
	if violations.is_empty():
		return "(нарушений нет)"
	var parts: Array = []
	for i in violations.size():
		if i >= 3:
			parts.append("… и ещё %d" % (violations.size() - 3))
			break
		var v: Dictionary = violations[i]
		parts.append("%s: %s — %s" % [String(v["where"]), String(v["rule"]), String(v["line"])])
	return "; ".join(parts)


## Имена документов пакета, названные в тексте.
func _documents_in_text(text: String, regex: RegEx) -> Array:
	var out: Array = []
	for found in regex.search_all(text):
		out.append(found.get_string())
	return out


## Обход дерева. Порядок фиксирован сортировкой: прогон обязан быть воспроизводимым.
func _collect(directory: String, relative: String, found: Array, skipped: Array) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	var files: Array = dir.get_files()
	files.sort()
	for name in files:
		var rel := _join(relative, String(name))
		if TEXT_EXTENSIONS.has(String(name).get_extension().to_lower()):
			found.append(rel)
		else:
			skipped.append(rel)
	var directories: Array = dir.get_directories()
	directories.sort()
	for name in directories:
		if SKIP_DIRECTORIES.has(String(name)):
			continue
		_collect(directory.path_join(String(name)), _join(relative, String(name)), found, skipped)


func _read_text(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	return text


func _join(relative: String, name: String) -> String:
	return name if relative == "" else "%s/%s" % [relative, name]


func _missing(expected: Array, found: Array) -> Array:
	var out: Array = []
	for item in expected:
		if not found.has(item):
			out.append(String(item))
	return out


func run() -> Array:
	var t := Assert.new()
	var regexes := _compile(RULES)
	var document_regex := RegEx.new()
	document_regex.compile(DOCUMENT_REFERENCE)

	# 1. Контроль детектора. Без него «нарушений нет» — утверждение о корпусе, а не о
	# проверке: ассерт, который не может покраснеть, не является проверкой.
	var dirty := _scan_text(DIRTY_SAMPLE, "(контроль)", false, regexes)
	t.eq("детектор ловит заведомую грязь — сработали правила: %s" % ", ".join(_rules_of(dirty)),
		_rules_of(dirty), DIRTY_RULES)
	var dirty_own := _scan_text(DIRTY_SAMPLE, "(контроль)", true, regexes)
	t.eq("внутри своего проекта пути `res://content` и `res://sim` нарушением не считаются: %s"
		% ", ".join(_rules_of(dirty_own)), _rules_of(dirty_own), DIRTY_RULES_OWN_PROJECT)
	var clean := _scan_text(CLEAN_SAMPLE, "(контроль)", false, regexes)
	t.eq("детектор молчит на чистом тексте: %s" % _brief(clean), clean, [])

	# 2. Корпус. Пустой или обрезанный корпус делает проверку вырожденной, поэтому
	# непустота — отдельные ассерты, а не подразумеваемое условие.
	var root: String = ProjectSettings.globalize_path("res://").path_join(PACKAGE_RELATIVE).simplify_path()
	var package_files: Array = []
	var skipped_files: Array = []
	_collect(root, "", package_files, skipped_files)
	t.is_true("корень пакета существует и читается: %s" % root, DirAccess.dir_exists_absolute(root))
	t.is_true("файлов пакета просмотрено: %d (пол: %d; пропущено по расширению: %d)"
		% [package_files.size(), MIN_PACKAGE_FILES, skipped_files.size()],
		package_files.size() >= MIN_PACKAGE_FILES)
	var missing_anchors := _missing(ANCHORS, package_files)
	t.eq("якоря пакета на месте — нет: %s" % _brief_list(missing_anchors), missing_anchors, [])

	# 3. Обход файлов пакета. Исключений нет: сканируется и сам скрипт проверки
	# комплекта — он лежит в пакете и обязан быть чистым наравне со всеми.
	var violations: Array = []
	var documents: Array = []
	for relative in package_files:
		var text: Variant = _read_text(root.path_join(String(relative)))
		if text == null:
			violations.append({"id": "unreadable", "rule": "файл не прочитан",
				"where": String(relative), "line": ""})
			continue
		violations.append_array(_scan_text(String(text), String(relative),
			String(relative).begins_with(OWN_PROJECT_PREFIX), regexes))
		documents.append_array(_documents_in_text(String(text), document_regex))

	# 4. Ссылка на документ пакета: имя вида `01-format.md` обязано в пакете быть.
	# Именно на этом разъехались старые номера (`02-format.md`, `design.md`).
	var referenced := _unique_sorted(documents)
	var absent_documents: Array = []
	for name in referenced:
		if not package_files.has(String(name)):
			absent_documents.append(String(name))
	t.eq("документы, названные в пакете, в пакете есть — нет: %s" % _brief_list(absent_documents),
		absent_documents, [])

	# 5. Главное: сам пакет. Имя ассерта несёт первое нарушение — провал называет
	# место, правило и строку, а не «список непуст».
	t.eq("пакет наружу самодостаточен (%d файлов, названо документов: %d): %s"
		% [package_files.size(), referenced.size(), _brief(violations)], violations, [])

	# 6. Боевые модули — источник копий комплекта. Проверяются отдельно: правка
	# боевого модуля обязана краснеть здесь ещё до копирования в пакет.
	var module_violations: Array = []
	var module_documents: Array = []
	for module in BATTLE_MODULES:
		var module_path: String = ProjectSettings.globalize_path("res://").path_join(String(module)).simplify_path()
		var module_text: Variant = _read_text(module_path)
		if module_text == null:
			module_violations.append({"id": "unreadable", "rule": "файл не прочитан",
				"where": String(module), "line": module_path})
			continue
		module_violations.append_array(_scan_text(String(module_text), String(module), true, regexes))
		module_documents.append_array(_documents_in_text(String(module_text), document_regex))
	var module_absent: Array = []
	for name in _unique_sorted(module_documents):
		if not package_files.has(String(name)) and not module_absent.has(String(name)):
			module_absent.append(String(name))
	t.eq("боевые модули комплекта называют документы, которые в пакете есть — нет: %s"
		% _brief_list(module_absent), module_absent, [])
	t.eq("боевые модули комплекта чисты (нарушений: %d): %s"
		% [module_violations.size(), _brief(module_violations)], module_violations, [])

	# 7. Обещание README комплекта: модули «скопированы дословно (побайтово)».
	# Проверяется равенством содержимого, а не таблицей SHA в отчёте: таблица живёт до
	# следующей правки, а разошедшаяся копия уезжает наружу получателю — ровно тот класс,
	# которым пакет уже уезжал (архив против папки).
	var diverged: Array = []
	for module in BATTLE_MODULES:
		var battle_text: Variant = _read_text(
			ProjectSettings.globalize_path("res://").path_join(String(module)).simplify_path())
		var copy_text: Variant = _read_text(root.path_join("kit/verifier").path_join(String(module)))
		if battle_text == null or copy_text == null or String(battle_text) != String(copy_text):
			diverged.append("kit/verifier/%s" % String(module))
	t.eq("копии комплекта побайтово равны боевым модулям — разошлись: %s" % _brief_list(diverged),
		diverged, [])

	return t.results


## Список строкой для имени ассерта: пустой список читается словом, а не `[]`.
func _brief_list(items: Array) -> String:
	return "(нет)" if items.is_empty() else ", ".join(items)


func _unique_sorted(items: Array) -> Array:
	var seen: Dictionary = {}
	for item in items:
		seen[String(item)] = true
	var out: Array = seen.keys()
	out.sort()
	return out


func _compile(rules: Array) -> Array:
	var out: Array = []
	for rule in rules:
		var regex := RegEx.new()
		regex.compile(String((rule as Dictionary)["pattern"]))
		out.append(regex)
	return out

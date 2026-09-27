extends RefCounted
## Самодостаточность ДЕЙСТВУЮЩЕГО пакета наружу: он сверяется САМ С СОБОЙ.
##
## Зачем кейс. Пакет `docs/handoff/2026-09-27-mission-v3/` уходит исполнителю, у которого
## нашего репозитория НЕТ. Задача 13 вычистила наши следы из СООБЩЕНИЙ валидатора, но в
## КОММЕНТАРИЯХ оставались внутренние коды решений (`D37`, `D30`, …) и ссылки на документы
## по номерам, которых у получателя нет. Словами это не стережётся: модуль правится вместе
## с кодом, и ссылка уезжает наружу молча.
##
## ПОЧЕМУ ПРОВЕРЯЕТСЯ ИМЕННО ДЕЙСТВУЮЩИЙ ПАКЕТ И ПОЧЕМУ ПРОВЕРКА НЕ ГНИЁТ ОТ ПРАВОК КОДА.
## Пакет — свидетельство на дату: он собран из боевого кода в момент поставки и уехал
## получателю. Поэтому здесь НЕ спрашивается «совпадают ли копии комплекта с сегодняшним
## боевым кодом»: это свойство МОМЕНТА СБОРКИ, и после первой же правки ядра или формы оно
## ложно ПО ОПРЕДЕЛЕНИЮ (`constraints.md` §3, решение ведущего §2.1 леджера) — вечная
## проверка такого равенства краснела бы на здоровом коде и «врала» про дефект. Вечная
## половина — та, что верна всегда, потому что пакет сверяется сам с собой:
##   * манифест `kit/verifier/SHA256SUMS` ↔ файлы комплекта (то, что получатель проверяет
##     `Get-FileHash`/`sha256sum -c`): каждый названный файл на месте, его SHA-256 совпадает,
##     и НИ ОДИН файл комплекта не остался непокрытым — иначе «манифест сошёлся» читалось бы
##     про подмножество;
##   * документы, названные в файлах пакета (в том числе в КОПИЯХ модулей), в пакете
##     существуют: имя вида `01-format.md` — обещание файла получателю;
##   * самодостаточность: в файлах пакета нет путей нашего репозитория, внутренних кодов
##     решений и имени нашего набора тестов.
## Правка боевого кода ничего из этого не задевает. Меняется пакет — меняется и он сам:
## пересобирается из кода, манифест пересчитывается, и все три проверки снова смотрятся
## в одно место.
##
## ГЛАВНОЕ ПРО ЭТОТ КЕЙС: он обязан краснеть. Держат это четыре вещи —
##   1) положительный контроль: детектор ищет грязь в заведомо грязной строке и называет
##      КАЖДОЕ правило (список правил в контроле написан руками, а не взят из `RULES`:
##      эталон, производный от проверяемого, ничего не проверяет);
##   2) отрицательный контроль: на чистом тексте детектор молчит;
##   3) проверка непустоты корпуса: якоря пакета на месте и файлов просмотрено не меньше
##      пола. Исключений из обхода нет ни одного — сканируется и сам скрипт проверки
##      комплекта (`kit/verifier/selfcheck.gd`), и манифест;
##   4) сверка манифеста по существу: проба «испортить файл комплекта» краснит расхождение
##      SHA, проба «убрать строку манифеста» — непокрытый файл.
##
## Тот же прогон живёт В САМОМ пакете (`kit/verifier/selfcheck.gd`): получатель может
## проверить комплект, не имея нашего набора тестов, и обязан увидеть то же самое. Два
## экземпляра правил неизбежны (комплект — отдельный проект Godot), поэтому расхождение
## ловится пробами: кейс краснеет на мутации боевого модуля и на мутации файла пакета.
##
## ЧЕГО ЗДЕСЬ НЕТ И ПОЧЕМУ. Прежняя редакция кейса смотрела на ЗАМОРОЖЕННЫЙ пакет
## `2026-09-27-mission-01-v2` — то есть на историческую поставку, у которой нет ни
## манифеста, ни действующего статуса. Снятая находкой M8 половина ворот (проверка
## «боевые модули называют документы, которые в пакете есть») здесь НЕ возвращается: она
## ложна по построению для любого замороженного пакета, а её место — сборка пакета, где
## копии кладутся из боевых модулей и ссылки сверяются тогда же (отчёт задачи 5, §4.1).

const Assert := preload("res://tests/assert.gd")

## Путь к пакету ОТ КОРНЯ ПРОЕКТА: `res://` → `game/`, на уровень выше — `docs/`.
## Именно относительный: при переезде файла провал называет прочитанный путь целиком.
const PACKAGE_RELATIVE := "../docs/handoff/2026-09-27-mission-v3"

## Собственный проект комплекта внутри пакета: здесь `res://` указывает на папку
## комплекта, поэтому пути `res://content/...` и `res://sim/...` в этих файлах ВЕРНЫ и
## нарушением не считаются. Префикс привязан к факту: `kit/verifier/verify.gd` назван
## якорем ниже, и без него кейс краснеет раньше этой проверки.
const OWN_PROJECT_PREFIX := "kit/verifier/"

## Манифест контрольных сумм комплекта — то, чем получатель проверяет «комплект не подменён».
## Пути внутри манифеста относительны ЭТОЙ папки (у образца — `../example/...`).
const MANIFEST_RELATIVE := "kit/verifier/SHA256SUMS"

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

## Якоря пакета. Не перечень состава (пакет может расти), а пол: без этих файлов
## проверять нечего, и молчаливое «нарушений нет» было бы вырожденным. Сюда же входит
## скрипт проверки комплекта: он и есть вторая половина этой же проверки.
const ANCHORS := [
	"README.md",
	"00-task.md",
	"01-format.md",
	"02-level.md",
	"03-texts.md",
	"04-numbers.md",
	"05-borders.md",
	"07-self-check.md",
	"08-report.md",
	"kit/example/mission.example.json",
	"kit/example/texts.example.json",
	"kit/verifier/README.md",
	"kit/verifier/SHA256SUMS",
	"kit/verifier/project.godot",
	"kit/verifier/verify.gd",
	"kit/verifier/selfcheck.gd",
	"kit/verifier/content/validator.gd",
	"kit/verifier/content/problems.gd",
	"kit/verifier/content/loader.gd",
	"kit/verifier/sim/mission.gd",
	"kit/verifier/sim/plan.gd",
	"kit/verifier/sim/response.gd",
]

## Пол корпуса: 22 файла на момент правки (девять документов, комплект, образец).
## Пол, а не равенство: пакет имеет право расти.
const MIN_PACKAGE_FILES := 22

## Сканируются только текстовые файлы; пропущенное считается и печатается в имени
## ассерта, чтобы «не смотрели» не выглядело как «чисто».
const TEXT_EXTENSIONS := ["md", "gd", "json", "godot", "txt", "cfg"]

## Файлы БЕЗ расширения, которые всё равно сканируются и могут быть якорями: манифест
## контрольных сумм. `get_extension()` у него пустая, и без этого списка он выпал бы из
## обхода молча — то есть «проверено» относилось бы к нему по ошибке.
const TEXT_FILENAMES := ["SHA256SUMS"]

## Кэш движка: создаётся прогоном комплекта и к пакету не относится.
const SKIP_DIRECTORIES := [".godot"]

## Правила поиска. `id` — короткое имя для контрольных ассертов, `name` — то, что
## читает человек в провале; `skip_in_own_project` — для путей, верных внутри проекта.
## Набор тот же, что у `kit/verifier/selfcheck.gd`: два экземпляра правил расходятся молча,
## поэтому расхождение и ловится пробой — но наборы обязаны совпадать.
const RULES := [
	{"id": "docs-slash", "name": "путь нашего репозитория `docs/`",
		"pattern": "docs/", "skip_in_own_project": false},
	{"id": "docs-backslash", "name": "путь нашего репозитория `docs\\`",
		"pattern": "docs\\\\", "skip_in_own_project": false},
	{"id": "repo-game", "name": "путь нашей папки проекта `game/`",
		"pattern": "game/", "skip_in_own_project": false},
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

## Форма строки манифеста: 64 шестнадцатеричных знака, два пробела, путь внутри комплекта
## (у образца — с `../`). Строка другой формы не глотается молча, а называется номером.
const MANIFEST_LINE := "^([0-9A-Fa-f]{64})  (.+)$"

## Контрольные строки. Написаны руками и НЕЗАВИСИМО от `RULES`: эталон, собранный из
## проверяемого списка, мутацию в нём не краснеет.
const DIRTY_SAMPLE := "# docs/spr/scales.md и docs\\spr\\scales.md\n## решение D99\n## res://tests/run.gd\n## review-03 §7.5\n## game/content/validator.gd\n## res://content/x.gd и res://sim/y.gd\n"
const CLEAN_SAMPLE := "## Окно срабатывает один раз за миссию\n## Код проблемы: BAD_VALUE\n"
const DIRTY_RULES := ["dnn", "docs-backslash", "docs-slash", "repo-game", "res-content",
	"res-sim", "res-tests", "review"]
const DIRTY_RULES_OWN_PROJECT := ["dnn", "docs-backslash", "docs-slash", "repo-game",
	"res-tests", "review"]


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
		var v = violations[i]
		parts.append("%s" % String(v) if typeof(v) == TYPE_STRING
			else "%s: %s — %s" % [String(v["where"]), String(v["rule"]), String(v["line"])])
	return "; ".join(parts)


## Имена документов пакета, названные в тексте.
func _documents_in_text(text: String, regex: RegEx) -> Array:
	var out: Array = []
	for found in regex.search_all(text):
		out.append(found.get_string())
	return out


## Разбор манифеста. Строка формы `SHA  путь` — запись; строка другой формы — запись с
## названной ошибкой, а не пропуск: «манифест сошёлся» не имеет права читаться про
## манифест, половину которого не разобрали.
func _manifest_entries(text: String) -> Array:
	var pattern := RegEx.new()
	pattern.compile(MANIFEST_LINE)
	var out: Array = []
	var lines := text.split("\n")
	for i in lines.size():
		var line := String(lines[i]).strip_edges()
		if line == "":
			continue
		var found := pattern.search(line)
		if found == null:
			out.append({"line": i + 1, "hash": "", "path": "",
				"error": "строка манифеста не разобрана: «%s»" % line})
			continue
		out.append({"line": i + 1, "hash": found.get_string(1).to_upper(),
			"path": found.get_string(2).strip_edges(), "error": ""})
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
		if TEXT_EXTENSIONS.has(String(name).get_extension().to_lower()) \
				or TEXT_FILENAMES.has(String(name)):
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
	# комплекта, и манифест — они лежат в пакете и обязаны быть чистыми наравне со всеми.
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
	t.eq("документы, названные в пакете (и в копиях комплекта тоже), в пакете есть — нет: %s"
		% _brief_list(absent_documents), absent_documents, [])

	# 5. Главное: сам пакет. Имя ассерта несёт первое нарушение — провал называет
	# место, правило и строку, а не «список непуст».
	t.eq("пакет наружу самодостаточен (%d файлов, названо документов: %d): %s"
		% [package_files.size(), referenced.size(), _brief(violations)], violations, [])

	# 6. Копии боевых модулей: каждая обязана быть в комплекте. Побайтовое равенство
	# боевому модулю здесь НЕ проверяется — оно свойство момента сборки, а не вечное
	# (см. шапку файла); проверяется то, что верно всегда: копия ЕСТЬ, она чиста (общий
	# обход выше), названные в ней документы в пакете существуют (п. 4) и её SHA-256
	# сходится с манифестом (п. 7).
	var kit_missing: Array = []
	for module in BATTLE_MODULES:
		if not package_files.has("%s%s" % [OWN_PROJECT_PREFIX, String(module)]):
			kit_missing.append("%s%s" % [OWN_PROJECT_PREFIX, String(module)])
	t.eq("копии боевых модулей в комплекте есть — нет: %s" % _brief_list(kit_missing),
		kit_missing, [])

	# 7. МАНИФЕСТ: пакет сверяется сам с собой. Получатель проверяет комплект
	# (`Get-FileHash` / `sha256sum -c`), поэтому проверка обязана быть той же самой:
	#   * каждая строка манифеста разобрана и названный файл лежит В ПАКЕТЕ;
	#   * SHA-256 файла совпадает с названным;
	#   * ни один файл комплекта не остался непокрытым (кроме самого манифеста: хеш
	#     файла, содержащего свой хеш, невозможен — это сказано в README комплекта).
	# Правка боевого кода эту половину не задевает вовсе: она про пакет и только про него.
	var manifest_text: Variant = _read_text(root.path_join(MANIFEST_RELATIVE))
	t.is_true("манифест комплекта прочитан: %s" % MANIFEST_RELATIVE, manifest_text != null)
	var entries := _manifest_entries("" if manifest_text == null else String(manifest_text))
	t.is_true("манифест разобран: строк %d, из них с ошибкой формы: %d"
		% [entries.size(), _manifest_errors(entries).size()], _manifest_errors(entries).is_empty())

	var manifest_absent: Array = []
	var manifest_mismatch: Array = []
	var manifest_listed: Array = []
	for entry in entries:
		if String(entry["error"]) != "":
			continue
		var relative := _join(OWN_PROJECT_PREFIX, String(entry["path"])).simplify_path()
		if relative == MANIFEST_RELATIVE:
			manifest_mismatch.append("%s: манифест не может содержать свой собственный хеш"
				% MANIFEST_RELATIVE)
			continue
		if not package_files.has(relative):
			manifest_absent.append("%s (строка %d)" % [relative, int(entry["line"])])
			continue
		manifest_listed.append(relative)
		var actual := FileAccess.get_sha256(root.path_join(relative)).to_upper()
		if actual != String(entry["hash"]):
			manifest_mismatch.append("%s (строка %d): в манифесте %s, у файла %s"
				% [relative, int(entry["line"]), String(entry["hash"]), actual])
	var kit_files: Array = []
	var kit_skipped: Array = []
	## Обход — с корня комплекта: префикс без хвостового слэша, иначе `_join` удвоил бы его
	## («kit/verifier//README.md») и ни один файл не совпал бы с записью манифеста.
	_collect(root.path_join("kit/verifier"), "kit/verifier", kit_files, kit_skipped)
	_collect(root.path_join("kit/example"), "kit/example", kit_files, kit_skipped)
	var uncovered: Array = []
	var kit_to_cover: Array = []
	for relative in kit_files:
		if String(relative) == MANIFEST_RELATIVE:
			continue
		kit_to_cover.append(String(relative))
		if not manifest_listed.has(String(relative)):
			uncovered.append(String(relative))
	t.eq("манифест называет только файлы пакета — нет или вне пакета: %s"
		% _brief_list(manifest_absent), manifest_absent, [])
	t.eq("SHA-256 файлов комплекта совпадают с манифестом (%d строк сверено) — расхождения: %s"
		% [manifest_listed.size(), _brief_list(manifest_mismatch)], manifest_mismatch, [])
	t.eq("манифест покрывает весь комплект и образец (%d файлов, кроме самого манифеста) — не покрыто: %s"
		% [kit_to_cover.size(), _brief_list(uncovered)], uncovered, [])

	# 8. Боевые модули — источник копий комплекта. Чистота боевого модуля (нет наших путей,
	# внутренних кодов решений, ссылок на наш набор) — свойство, верное ВСЕГДА: боевой модуль
	# уезжает наружу копией, и грязь уедет вместе с ним. А вот «документы, которые называет
	# боевой модуль, есть в пакете» — проверка момента копирования, НЕ вечная: стоит боевому
	# модулю назвать документ новой поставки, как кейс покраснел бы на здоровом коде — тот же
	# класс, что снятое побайтовое равенство. Это свойство проверяет СБОРКА пакета (копии
	# кладутся из боевых модулей, и ссылки сверяются тогда же), а в наборе остаётся его вечная
	# половина — сверка по КОПИЯМ, которые и лежат у получателя (п. 4 и 7 выше).
	var module_violations: Array = []
	for module in BATTLE_MODULES:
		var module_path: String = ProjectSettings.globalize_path("res://").path_join(String(module)).simplify_path()
		var module_text: Variant = _read_text(module_path)
		if module_text == null:
			module_violations.append({"id": "unreadable", "rule": "файл не прочитан",
				"where": String(module), "line": module_path})
			continue
		module_violations.append_array(_scan_text(String(module_text), String(module), true, regexes))
	t.eq("боевые модули комплекта чисты (нарушений: %d): %s"
		% [module_violations.size(), _brief(module_violations)], module_violations, [])

	return t.results


## Ошибки формы строк манифеста — отдельным списком: «разобран» и «разобран верно» —
## разные утверждения, и первое без второго читалось бы как проверка.
func _manifest_errors(entries: Array) -> Array:
	var out: Array = []
	for entry in entries:
		if String(entry["error"]) != "":
			out.append("строка %d: %s" % [int(entry["line"]), String(entry["error"])])
	return out


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

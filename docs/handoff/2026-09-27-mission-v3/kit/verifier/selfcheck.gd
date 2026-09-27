extends SceneTree
## Самодостаточность пакета наружу: прогон по файлам пакета, который краснеет, если в них
## утекло что-то из нашего репозитория.
##
## Зачем. Пакет адресован исполнителю, у которого нашего репозитория НЕТ. Ссылка на
## несуществующий у него файл читается как «пакет дали неполный» — ровно то, за что мы
## гоним внешнюю поставку. Слова в README этого не стерегут: модуль правится вместе с
## кодом, и комментарий со ссылкой уезжает наружу молча. Здесь обещание «наш репозиторий
## тебе не нужен» становится ПРОВЕРЯЕМЫМ.
##
## Что ищется по всем файлам пакета (кэш движка `.godot` не смотрим):
## 1) путь нашего репозитория: `docs` и следующий за ним слэш — прямой или обратный;
## 2) внутренний код решения: латинская `D` и две цифры подряд;
## 3) имя нашего набора тестов: `res://` и следом `tests`;
## 4) ссылка на наши документы ревью: `review` и следом дефис;
## 5) путь папки нашего проекта: `game` и следующий за ним прямой слэш — у получателя
##    такой папки тоже нет;
## 6) пути ЧУЖОГО проекта — `res://` с `content` и `res://` с `sim`, но только ВНЕ
##    собственного проекта комплекта. Внутри `kit/verifier/**` они верны: там `res://`
##    и указывает на папку комплекта (`verify.gd` грузит `res://` с `content`).
##
## Вторая половина той же проверки — ссылки на документы: имя вида `01-format.md`,
## названное в файлах пакета, обязано в пакете существовать. Именно этой половины не
## хватало, когда комментарии ссылались на документы с номерами, которых в пакете нет.
##
## САМ ЭТОТ ФАЙЛ — не исключение: он лежит в пакете и проверяется наравне со всеми,
## поэтому не имеет права содержать то, что ищет. Строки правил и контрольная строка
## собраны из частей именно поэтому: собери любую в одну строку — и проверка начнёт
## краснеть на себе (это и есть её защита от «проверки, которая ничего не проверяет»).
##
## Вердикт — КОД ВОЗВРАТА процесса, а не текст:
##   0 — нарушений нет;
##   1 — нарушения есть (напечатаны выше), либо обязательного файла пакета нет;
##   2 — корень пакета не найден (запускать из пакета, см. README).
## Текст в stderr вердиктом не является: Godot пишет туда безобидный шум и при коде 0.
##
## Сторож вердикта — как в `verify.gd`: рантайм-сбой прерывает `_initialize()`, а не
## процесс, и без сторожа прогон отдал бы ноль или повис.

const EXIT_OK := 0
const EXIT_VIOLATIONS := 1
const EXIT_BAD_ROOT := 2
const EXIT_ABORTED := 1

## Сканируются только текстовые файлы: другого в пакете и быть не должно, а всё
## пропущенное печатается счётчиком, чтобы «не смотрели» не выглядело как «чисто».
const TEXT_EXTENSIONS := ["md", "gd", "json", "godot", "txt", "cfg"]

## Файлы БЕЗ расширения, которые всё равно сканируются и могут быть якорями: манифест
## контрольных сумм. `get_extension()` у него пустая, и без этого списка он выпал бы из
## обхода молча — то есть «проверено» относилось бы к нему по ошибке.
const TEXT_FILENAMES := ["SHA256SUMS"]

## Кэш движка: создаётся прогоном комплекта и к пакету не относится.
const SKIP_DIRECTORIES := [".godot"]

## Якоря пакета: без них проверять нечего, и это НАРУШЕНИЕ, а не «чисто». Список — пол,
## а не перечень: пакет может расти, и лишний файл нарушением не является. Состав —
## фактический состав этой редакции пакета: девять документов, комплект и образец.
## Документы, которых в этой редакции нет (обзорный документ первой редакции и «запасные»
## номера вида `06-…`), в списке отсутствуют намеренно: якорь на отсутствующий файл
## краснел бы на собственном пакете.
const REQUIRED_RELATIVE := [
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

## Правила поиска. `id` — короткое имя для самопроверки детектора, `name` — то, что
## читает человек в нарушении; `skip_in_own_project` — для путей, верных внутри комплекта.
const RULES := [
	{"id": "docs-slash", "name": "путь нашего репозитория (`docs` и прямой слэш)",
		"pattern": "docs" + "/", "skip_in_own_project": false},
	{"id": "docs-backslash", "name": "путь нашего репозитория (`docs` и обратный слэш)",
		"pattern": "docs" + "\\\\", "skip_in_own_project": false},
	{"id": "repo-game", "name": "путь нашего проекта (`game` и прямой слэш)",
		"pattern": "game" + "/", "skip_in_own_project": false},
	{"id": "dnn", "name": "внутренний код решения (`D` и две цифры)",
		"pattern": "\\bD[0-9]{2}\\b", "skip_in_own_project": false},
	{"id": "res-tests", "name": "имя нашего набора тестов (`res://` и `tests`)",
		"pattern": "res://" + "tests", "skip_in_own_project": false},
	{"id": "review", "name": "ссылка на наши документы ревью (`review` и дефис)",
		"pattern": "review" + "-", "skip_in_own_project": false},
	{"id": "res-content", "name": "путь чужого проекта (`res://` и `content`)",
		"pattern": "res://" + "content", "skip_in_own_project": true},
	{"id": "res-sim", "name": "путь чужого проекта (`res://` и `sim`)",
		"pattern": "res://" + "sim", "skip_in_own_project": true},
]

## Имя документа пакета: две цифры, дефис, имя. По такой ссылке и спрашивается файл.
const DOCUMENT_REFERENCE := "[0-9]{2}-[A-Za-z0-9_\\-]+\\.md"

## Контрольная строка самопроверки детектора: та же грязь, собранная из частей. Написана
## руками и НЕЗАВИСИМО от `RULES`: эталон, собранный из проверяемого списка, мутацию в нём
## не краснеет.
const DIRTY_SAMPLE := ("# " + "docs" + "/spr/scales.md и " + "docs" + "\\spr\\scales.md\n"
	+ "## решение " + "D" + "99\n"
	+ "## res://" + "tests/run.gd\n"
	+ "## " + "review" + "-03 §7.5\n"
	+ "## " + "game" + "/content/validator.gd\n"
	+ "## res://" + "content/x.gd и res://" + "sim/y.gd\n")
const DIRTY_RULES := ["dnn", "docs-backslash", "docs-slash", "repo-game", "res-content",
	"res-sim", "res-tests", "review"]
const DIRTY_RULES_OWN_PROJECT := ["dnn", "docs-backslash", "docs-slash", "repo-game",
	"res-tests", "review"]

var _verdict_reached := false
var _regexes: Array = []
var _document_regex: RegEx = null


func _initialize() -> void:
	_compile()
	var root := _find_root()
	if root == "":
		print("НЕ НАЙДЕН КОРЕНЬ ПАКЕТА: ни в одной из папок выше нет `kit/verifier/verify.gd`")
		print("Запускать из пакета: --path <пакет>/kit/verifier --script res://selfcheck.gd")
		_quit(EXIT_BAD_ROOT)
		return
	print("КОРЕНЬ ПАКЕТА: %s" % root)

	var found: Array = []
	var skipped: Array = []
	_collect(root, "", found, skipped)

	## Начинаем со самопроверки детектора, а не с пакета: «нарушений нет» без неё —
	## утверждение о пакете, а не о проверке. Сломанный детектор молчит так же, как
	## чистый пакет, и отличить их больше нечем.
	var violations: Array = _detector_self_check()
	var documents: Array = []
	for relative in found:
		var text: Variant = _read_text(root.path_join(String(relative)))
		if text == null:
			violations.append("%s: файл не прочитан" % String(relative))
			continue
		for violation in _scan_text(String(text), String(relative), _is_own_project(root, String(relative))):
			violations.append(_violation_text(violation))
		documents.append_array(_documents_in_text(String(text)))
	for anchor in REQUIRED_RELATIVE:
		if not found.has(anchor):
			violations.append("пакет: нет обязательного файла «%s»" % String(anchor))
	var referenced := _unique_sorted(documents)
	for name in referenced:
		if not found.has(String(name)):
			violations.append("пакет: назван документ «%s», которого в пакете нет" % String(name))

	print("ФАЙЛОВ ПРОСМОТРЕНО: %d (пропущено по расширению: %d)" % [found.size(), skipped.size()])
	print("САМОПРОВЕРКА ДЕТЕКТОРА: правила сработали — %s" % ", ".join(_rules_of(_scan_text(
		DIRTY_SAMPLE, "(контроль)", false))))
	print("ДОКУМЕНТОВ ПАКЕТА НАЗВАНО: %d — %s"
		% [referenced.size(), ", ".join(referenced) if not referenced.is_empty() else "(ни одного)"])
	print("НАРУШЕНИЙ: %d" % violations.size())
	var index := 1
	for violation in violations:
		print("  %d. %s" % [index, String(violation)])
		index += 1
	if violations.is_empty():
		print("ВЕРДИКТ: пакет самодостаточен — наружу ничего нашего не течёт (код 0)")
		_quit(EXIT_OK)
		return
	print("ВЕРДИКТ: пакет не самодостаточен — нарушений %d, чинить каждое (код 1)" % violations.size())
	_quit(EXIT_VIOLATIONS)


## Самопроверка детектора: на заведомо грязной строке обязаны сработать ВСЕ правила (и
## только они), а внутри своего проекта — все, кроме «чужих» путей. Без этой половины
## «нарушений нет» ничего не доказывает: сломанный детектор молчит так же, как чистый пакет.
func _detector_self_check() -> Array:
	var out: Array = []
	var fired := _rules_of(_scan_text(DIRTY_SAMPLE, "(контроль)", false))
	if fired != DIRTY_RULES:
		out.append("самопроверка детектора: на заведомо грязной строке сработали правила %s, а обязаны были %s"
			% [", ".join(fired), ", ".join(DIRTY_RULES)])
	var fired_own := _rules_of(_scan_text(DIRTY_SAMPLE, "(контроль)", true))
	if fired_own != DIRTY_RULES_OWN_PROJECT:
		out.append("самопроверка детектора: внутри своего проекта сработали правила %s, а обязаны были %s"
			% [", ".join(fired_own), ", ".join(DIRTY_RULES_OWN_PROJECT)])
	return out


## Имена сработавших правил, по одному разу, по алфавиту: сверяется НАБОР правил, а не
## число нарушений — число сходится и при неверном наборе.
func _rules_of(violations: Array) -> Array:
	var seen: Dictionary = {}
	for violation in violations:
		seen[String((violation as Dictionary)["id"])] = true
	var out: Array = seen.keys()
	out.sort()
	return out


## Корень пакета — папка, в которой лежит `kit/verifier/verify.gd`. Ищем её среди папки
## запуска и двух родительских: запускать можно и `--path <пакет>/kit/verifier`, и
## `--path <пакет>`, и угадывать по числу `..` не надо.
func _find_root() -> String:
	var res := ProjectSettings.globalize_path("res://").simplify_path()
	var candidates := [res, res.path_join("..").simplify_path(), res.path_join("../..").simplify_path()]
	for candidate in candidates:
		if FileAccess.file_exists(String(candidate).path_join("kit/verifier/verify.gd")):
			return String(candidate)
	return ""


## Путь папки запуска относительно корня пакета: `kit/verifier`.
func _own_relative(root: String) -> String:
	var own := ProjectSettings.globalize_path("res://").simplify_path()
	if not own.begins_with(root):
		return ""
	return own.substr(root.length()).trim_prefix("/").trim_suffix("/")


## Собственный проект комплекта — та папка, на которую указывает `res://` при запуске.
## Внутри неё пути `res://` с `content` и `res://` с `sim` верны, и правила с
## `skip_in_own_project` там не применяются.
func _is_own_project(root: String, relative: String) -> bool:
	var prefix := _own_relative(root)
	return prefix != "" and relative.begins_with(prefix)


func _compile() -> void:
	_regexes = []
	for rule in RULES:
		var regex := RegEx.new()
		regex.compile(String((rule as Dictionary)["pattern"]))
		_regexes.append(regex)
	_document_regex = RegEx.new()
	_document_regex.compile(DOCUMENT_REFERENCE)


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


## Читает файл как текст. `null` — не прочитан: это нарушение, а не «чисто»: молча
## пропущенный файл неотличим от проверенного.
func _read_text(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	return text


## Ищет правила по строкам. Строка, а не файл целиком: в нарушении видно место, а не
## «где-то в файле». Нарушение — словарь, а не строка: самопроверке детектора нужно ИМЯ
## сработавшего правила, а человеку — место и строка.
func _scan_text(text: String, relative: String, own_project: bool) -> Array:
	var out: Array = []
	var lines := text.split("\n")
	for i in lines.size():
		var line := String(lines[i])
		for rule_index in RULES.size():
			var rule: Dictionary = RULES[rule_index]
			if bool(rule["skip_in_own_project"]) and own_project:
				continue
			if (_regexes[rule_index] as RegEx).search(line) == null:
				continue
			out.append({
				"id": String(rule["id"]),
				"rule": String(rule["name"]),
				"where": "%s:%d" % [relative, i + 1],
				"line": line.strip_edges(),
			})
	return out


## Нарушение строкой — так его читает человек.
func _violation_text(violation: Dictionary) -> String:
	return "%s: %s — %s" % [String(violation["where"]), String(violation["rule"]),
		String(violation["line"])]


## Имена документов пакета, названные в тексте. Проверяются они, а не смысл ссылки.
func _documents_in_text(text: String) -> Array:
	var out: Array = []
	for found in _document_regex.search_all(text):
		out.append(found.get_string())
	return out


func _unique_sorted(items: Array) -> Array:
	var seen: Dictionary = {}
	for item in items:
		seen[String(item)] = true
	var out: Array = seen.keys()
	out.sort()
	return out


func _join(relative: String, name: String) -> String:
	return name if relative == "" else "%s/%s" % [relative, name]


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

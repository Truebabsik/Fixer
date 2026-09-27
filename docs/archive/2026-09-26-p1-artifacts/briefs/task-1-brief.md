### Task 1: Раннер тестов и мини-ассерты

**Files:**
- Create: `game/tests/assert.gd`
- Create: `game/tests/run.gd`
- Create: `game/tests/cases/test_runner.gd`

**Interfaces:**
- Consumes: ничего.
- Produces: `Assert` — объект с `results: Array`; методы `eq(name, actual, expected)`, `is_true(name, actual)`, `is_false(name, actual)`. Кейс — скрипт, `extends RefCounted`, с методом `run() -> Array` (возвращает `Assert.results`).

- [ ] **Step 1: Написать `game/tests/assert.gd`**

```gdscript
extends RefCounted
## Мини-ассерты. Никаких зависимостей и никакой печати: только список результатов.
## Печатает раннер — так один и тот же кейс годится и для прогона, и для отчёта.

var results: Array = []


func eq(name: String, actual, expected) -> void:
	results.append({
		"name": name,
		"ok": _same(actual, expected),
		"actual": actual,
		"expected": expected,
	})


func is_true(name: String, actual) -> void:
	eq(name, bool(actual), true)


func is_false(name: String, actual) -> void:
	eq(name, bool(actual), false)


## int и float сравниваем по значению, всё остальное — строго.
func _same(a, b) -> bool:
	if typeof(a) != typeof(b):
		var a_num := typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT
		var b_num := typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT
		if a_num and b_num:
			return is_equal_approx(float(a), float(b))
		return false
	return a == b
```

- [ ] **Step 2: Написать `game/tests/run.gd`**

```gdscript
extends SceneTree
## Раннер ядра. Вердикт — код возврата процесса: 0 зелёный, 1 есть провалы.
## Список кейсов явный: никакого сканирования каталогов, порядок фиксирован,
## поэтому прогон воспроизводим.

const CASES := [
	"res://tests/cases/test_runner.gd",
]


func _initialize() -> void:
	var total := 0
	var failed := 0
	for path in CASES:
		var case_script: GDScript = load(path)
		if case_script == null:
			print("LOAD FAIL  %s" % path)
			failed += 1
			continue
		var case_obj = case_script.new()
		var results: Array = case_obj.run()
		for r in results:
			total += 1
			if not bool(r["ok"]):
				failed += 1
				print("FAIL  %s :: %s" % [path.get_file(), str(r["name"])])
				print("      ожидалось: %s" % str(r["expected"]))
				print("      получено:  %s" % str(r["actual"]))
	print("tests: %d, failed: %d" % [total, failed])
	quit(1 if failed > 0 else 0)
```

- [ ] **Step 3: Написать `game/tests/cases/test_runner.gd` (проходит)**

```gdscript
extends RefCounted
## Самопроверка раннера: ассерты работают, результаты копятся.

const Assert := preload("res://tests/assert.gd")


func run() -> Array:
	var t := Assert.new()
	t.eq("целые равны", 2, 1 + 1)
	t.eq("int и float по значению", 1, 1.0)
	t.eq("строки равны", "ab", "a" + "b")
	t.is_true("истина", 1 == 1)
	t.is_false("ложь", 1 == 2)
	return t.results
```

- [ ] **Step 4: Прогнать — ожидаем зелёный и код 0**

Run:
```powershell
& "F:\WORK\Fixer\tools\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path "F:\WORK\Fixer\game" --script res://tests/run.gd; "код: $LASTEXITCODE"
```
Expected: строки `tests: 5, failed: 0` и `код: 0`.

- [ ] **Step 5: Проверить, что провал действительно ловится**

Временно добавить в `test_runner.gd` строку `t.eq("нарочно неверно", 1, 2)` и прогнать ту же команду.
Expected: `FAIL  test_runner.gd :: нарочно неверно`, `tests: 6, failed: 1`, `код: 1`.
Затем **удалить эту строку** и прогнать снова — снова `failed: 0`, `код: 0`.

Это не формальность: без этого шага мы не знаем, умеет ли раннер падать, и все дальнейшие «зелёные» прогоны ничего не стоят.

- [ ] **Step 6: Закоммитить**

```powershell
git add game/tests/assert.gd game/tests/run.gd game/tests/cases/test_runner.gd
git commit -m "test: раннер тестов ядра и мини-ассерты"
```

> **Правка после ревью (коммиты `1c0c98e`, `697184c`).** Ревью нашло, что раннер не гарантировал вердикт: кейс, падающий в рантайме, давал **ложный зелёный** (код 0), а кейс с синтаксической ошибкой — **зависание** (в обоих случаях `quit()` не вызывался). В `run.gd` добавлены: `can_instantiate()`, `has_method("run")`, проверка типа возврата, сторож в `_process` (превращает аборт `_initialize()` в код 1) и правило **«кейс без единого ассерта — провал»**. Интерфейс `run() -> Array` и явный `CASES` не менялись.
> **При переносе этой задачи в другой проект код раннера брать из репозитория, а не из сниппета выше** — сниппет оставлен как исходная редакция.
> Остаточное, вне задач П1: непустой `Dictionary` проходит проверку типа и падает позже на `r["ok"]`.

---


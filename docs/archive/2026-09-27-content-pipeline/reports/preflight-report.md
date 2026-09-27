# Отчёт: ворота разбора (preflight) перед прогоном

Задача: закрыть дефект «`--check-only --script res://tests/run.gd` не покрывает конвейер и даёт ложный код 0».
Коммит не делался, изменения оставлены в рабочем дереве.

---

## 1. Что добавлено и изменено (`файл:строка`)

### `game/tests/preflight.gd` — новый, 82 строки

| Место | Что там |
|---|---|
| `:16` | `const Suite := preload("res://tests/suite.gd")` — единственный статический preload; `class_name` нет нигде |
| `:27-44` | `const MODULES` — явный список 13 модулей: 10 из `sim/` и 3 из `content/`, без сканирования каталогов |
| `:50-53` | сборка списка: `MODULES.duplicate()` + `scripts.append_array(Suite.CASES)` — кейсы взяты **из `suite.gd`**, не копией |
| `:56-58` | `_parses(path)` ложно → `print("LOAD FAIL  %s" % path)` в формате раннера, счётчик |
| `:59-61` | `preflight: scripts: %d, failed: %d`; вердикт — `quit(1 if failed > 0 else 0)` |
| `:67-71` | `_parses()`: `load(path)` → `null` **или** `can_instantiate() == false` → провал |
| `:77-82` | `_process`-сторож вердикта, по смыслу как в `game/tests/run.gd:26-31` |

Порядок в `MODULES` — от листьев к зависимым (`sim/`-листья, `sim.gd`, `harness.gd`, затем `problems.gd`, `validator.gd`, `loader.gd`).
Причина: сломанный модуль роняет через `preload` и тех, кто от него зависит, поэтому первый `LOAD FAIL` обязан
называть причину, а не следствие. Это проверено (см. §3: первой строкой идёт `validator.gd`, а не `loader.gd`).

Раннеры `run.gd` / `run_red.gd` в список не входят — обоснование и проверка в §6 п. 3.

### Проверки, которых не было (по п. «Проверки на `bool()`-приведение»)

| Место | Что проверяет |
|---|---|
| `game/tests/cases/test_content_validator.gd:457-472` | P9: `edges[1].locked` = `"да"` и `= 1` → `WRONG_TYPE` на поле **и** `WINDOW_ON_OPEN_EDGE` на окне (ребро обязано считаться НЕзапертым) |
| `game/tests/cases/test_content_loader.gd:243-251` | `cargo_heavy`: `true` берётся; `"да"`, `1`, отсутствие ключа → `false` |

Обе проверки написаны как ловушки на регресс и проверены мутацией (§5), а не «на глаз».

### Документация

| Место | Что |
|---|---|
| `docs/architecture.md:192-205` | в блок команд §8 первой строкой вписана команда `preflight.gd`; `--check-only --script res://tests/run.gd` убрана; добавлен абзац «Ворота разбора — `tests/preflight.gd`, а не `--check-only`» с обеими пробами |
| `docs/architecture.md:245` | счёт проверок в «Состоянии на 2026-09-27»: `602` → `620` (изменился моими проверками) |
| `README.md:9-21` | команда `preflight.gd` в «Быстром старте» первой строкой (разбор → прогон → красный путь → редактор); дублирующая строка `--check-only` убрана |

---

## 2. Почему один процесс, а не N запусков `--check-only` (ответ на дополнение к брифу)

Требование из дополнения выполнено: **однопроцессный вариант называет битый файл так же ясно**, поэтому N запусков
не нужны. Дословный вывод — §3. Дополнительно:

* причина называется **первой же строкой** `LOAD FAIL` за счёт порядка «листья → зависимые»;
* вердикт один (`failed: M` + код возврата), а не N кодов, которые ещё надо сворачивать;
* вариант «N дешёвых запусков» не только дороже, но и **слабее**: `--check-only` по одиночному файлу вернул код 0
  на файле, чей статический `preload` уже не разобрался (дословно в §3.2). То есть одиночный запуск даёт ложную
  уверенность на своём же уровне.

---

## 3. Проба со внесённой ошибкой (в копии дерева)

Все пробы — в копии `%TEMP%\fx_final` (сдаваемое дерево не трогалось; ошибка вносилась только в копию).
Копия делалась так: `Copy-Item -Recurse F:\WORK\Fixer\game $tmp\game` (плюс `docs`, см. §3.3),
движок — тот же бинарник из `tools\`; `git worktree` не годился: бинарник и незакоммиченные правки в него не попадают.

### 3.1. Внесение ошибки и вывод `preflight` с ошибкой

Внесено (убрана закрывающая скобка у статического `preload`):

```
$v = "$tmp\game\content\validator.gd"
Set-Content -Path $v -Value ((Get-Content -Raw $v).Replace(
  'const Problems := preload("res://content/problems.gd")',
  'const Problems := preload("res://content/problems.gd"')) -Encoding utf8 -NoNewline

строка 13: const Problems := preload("res://content/problems.gd"
```

```
& $exe --headless --path $proj --script res://tests/preflight.gd
broken preflight exit=1
```

stdout дословно:

```
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

LOAD FAIL  res://content/validator.gd
LOAD FAIL  res://content/loader.gd
LOAD FAIL  res://tests/cases/test_content_validator.gd
LOAD FAIL  res://tests/cases/test_handoff_skeleton.gd
preflight: scripts: 30, failed: 4
```

stderr (ключевое, дословно; остальное — безобидный шум движка про `user://logs` и корневые сертификаты):

```
SCRIPT ERROR: Parse Error: Expected ")" after preload path.
   at: GDScript::reload (res://content/validator.gd:13)
   GDScript backtrace (most recent call first):
       [0] _parses (res://tests/preflight.gd:64)
       [1] _initialize (res://tests/preflight.gd:52)
ERROR: Failed to load script "res://content/validator.gd" with error "Parse error".
   at: load (modules/gdscript/gdscript_resource_format.cpp:46)
```

Итог: **код 1**, причина названа первой строкой (`validator.gd`), а не только следствие (`loader.gd`).

### 3.2. Контраст: что давали прежние команды на том же сломанном дереве

| Команда | Код | Комментарий |
|---|---|---|
| `--check-only --script res://tests/run.gd` | **0** | ложная зелень; в stderr **ноль** упоминаний `validator` |
| `--check-only --script res://content/validator.gd` | **1** | одиночный файл разбирается, ошибка видна |
| `--check-only --script res://tests/cases/test_content_loader.gd` | **0** | при уже напечатанном `Parse Error: Could not preload resource script` и `ERROR: Failed to load script "res://tests/cases/test_content_loader.gd" with error "Compilation failed"` |
| `--script res://tests/run.gd` (полный прогон) | **1** | ловит, но только полным прогоном |

Дословно третья строка (то, что `--check-only` печатает, но не считает провалом):

```
SCRIPT ERROR: Parse Error: Could not preload resource script "res://content/validator.gd".
SCRIPT ERROR: Parse Error: Could not resolve script "res://content/validator.gd".
SCRIPT ERROR: Parse Error: Cannot infer the type of "Validator" constant because the value doesn't have a set type.
ERROR: Failed to load script "res://tests/cases/test_content_loader.gd" with error "Compilation failed".
broken check-only test_content_loader.gd exit=0
```

### 3.3. После отката (та же копия, ошибка убрана)

```
& $exe --headless --path $proj --script res://tests/preflight.gd
restored preflight exit=0
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

preflight: scripts: 30, failed: 0

& $exe --headless --path $proj --script res://tests/run.gd
restored run exit=0
tests: 620, failed: 0
```

(Копии нужен ещё и каталог `docs/`: кейс `test_handoff_skeleton.gd` читает `../docs/handoff/...`. Без него полный
прогон в копии даёт один лишний провал `FAIL test_handoff_skeleton.gd :: скелет не открыт (код 7)` — это артефакт
копии, а не дефект. С `docs/` копия даёт ровно `tests: 620, failed: 0`.)

---

## 4. Гейт (сдаваемое дерево, после всех правок)

Команды из брифа, вердикт по коду возврата.

```powershell
# 1. разбор всех модулей — новые ворота
tools\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/preflight.gd
```
```
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

preflight: scripts: 30, failed: 0
```
**код 0**

```powershell
# 2. полный набор
tools\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/run.gd
```
```
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

tests: 620, failed: 0
```
**код 0**

```powershell
# 3. красный путь
tools\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/run_red.gd
```
```
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

FAIL  red_path.gd :: нарочно неверный ассерт
      ожидалось: 2
      получено:  1
red-path: tests: 2, failed: 1 (ожидаем failed > 0)
tests: 620, failed: 0
```
**код 0**

В stderr всех трёх — только шум движка (`Failed to open 'user://logs/...'`, `Failed to read the root certificate store`);
вердикт по нему не выносится.

Числа: было **612 / failed: 0** (код 0) → стало **620 / failed: 0** (код 0) — плюс ровно 8 проверок, которые я завёл
(2 входа × 2 ассерта в `test_content_validator.gd` + 4 в `test_content_loader.gd`). Красный путь — код 0, как и был.

---

## 5. Проверка, что новые проверки — ловушки, а не декорация

В отдельной копии (`%TEMP%\fx_regress`) обе правки прошлого захода откачены к прежнему поведению:

```
validator.gd:158  out[String(e["id"])] = typeof(locked) == TYPE_BOOL and bool(locked)
                  → out[String(e["id"])] = bool(locked)
loader.gd:91      if data.has("cargo_heavy") and typeof(data["cargo_heavy"]) == TYPE_BOOL:
                  → if data.has("cargo_heavy"):
```

Прогон в копии:

```
regress run exit=1
LOAD FAIL  res://tests/cases/test_content_loader.gd: кейс не предъявил ни одного ассерта
FAIL  test_content_validator.gd :: locked = да — ребро не считается запертым: WINDOW_ON_OPEN_EDGE
      ожидалось: ["WINDOW_ON_OPEN_EDGE"]
      получено:  []
FAIL  test_content_validator.gd :: locked = 1 — ребро не считается запертым: WINDOW_ON_OPEN_EDGE
      ожидалось: ["WINDOW_ON_OPEN_EDGE"]
      получено:  []
tests: 484, failed: 7
```

Обе новые проверки краснеют на старом коде; в сдаваемом дереве они зелёные.

**Что именно было сломано (пробы `bool()` на 4.7.2).** `bool(<String>)` — это не «истина для непустой строки»,
а `SCRIPT ERROR: Invalid call. Nonexistent 'bool' constructor.` с **абортом вызванной функции**:

```
SCRIPT ERROR: Invalid call. Nonexistent 'bool' constructor.
after str                 <- вызвавшая функция продолжилась, а _p() прервалась
dyn int 1 -> true
dyn int 0 -> false
SCRIPT ERROR: Invalid call. Nonexistent 'bool' constructor.
```

Отсюда два разных следствия прежнего кода, и оба закрыты проверками:
* строка `locked: "да"` — аборт `_known_edges` (и, судя по прогону выше, каскад диагнозов по всей миссии);
* число `locked: 1` — тихая коэрцировка в `true`, то есть ребро считалось запертым, и окно проходило как выполнимое.

То есть правка прошлого захода — не только «убрать строку `SCRIPT ERROR` из лога»: она меняет вердикт на числовом входе.

**Сторож.** Проверен отдельной пробой: скрипт с тем же `_process`-сторожем, у которого `_initialize()` прерван
`bool("да")`, завершается сам:

```
SCRIPT ERROR: Invalid call. Nonexistent 'bool' constructor.
LOAD FAIL  вердикт не выставлен: _initialize() прервался до quit()
guard probe exit=1
```

---

## 6. Решения и почему

1. **Один процесс, явный список путей** — см. §2. Список не сканируется: рядом со скриптами лежат `.uid`-файлы,
   и сканирование требовало бы фильтра по расширению, то есть состав ворот молча менялся бы от появления файла.
2. **`can_instantiate()` обязателен, проверки на `null` недостаточно** — доказано пробой: `load()` сломанного
   скрипта вернул **не null**, а `GDScript` с `can_instantiate=false`:

   ```
   res://content/validator.gd -> GDScript can_instantiate=false
   res://content/loader.gd -> GDScript can_instantiate=false
   res://tests/cases/test_content_loader.gd -> GDScript can_instantiate=true
   ```
3. **Раннеры в список не включены** — движок сам разбирает названный `--script`; проверено: сломанный `run.gd`
   даёт код 1 и у `--check-only --script res://tests/run.gd`, и у `--script res://tests/run.gd`; `preflight` при
   сломанном `run.gd` даёт 0 (по построению). В списке его нет, чтобы ворота разбора не зависели от самих ворот.
   `tests/fixtures/small_mission.gd` отдельно не перечислен: он приходит через статический `preload` кейса,
   а кейс в списке.
4. **`README.md` — команда `preflight` первой строкой** (разбор до прогона), в `architecture.md` §8 — так же;
   прежняя строка `--check-only` удалена, а не оставлена «на всякий случай»: её код 0 на сломанном дереве и есть
   дефект, который мы закрываем.
5. **Проверки на `bool()` заведены в оба кейса** (`test_content_validator.gd` — `locked`, `test_content_loader.gd` —
   `cargo_heavy`), хотя бриф называл только загрузчик: `_known_edges` живёт в валидаторе, и проверка на него
   в кейсе загрузчика была бы проверкой не по месту. Оба файла — в разрешённой зоне (`game/tests/**`).

---

## 7. Что заметил и не стал делать

1. **Каскад из двух проблем на один дефект `locked`.** С исправленным `_known_edges` ребро с `locked: "да"` даёт
   `WRONG_TYPE` на `edges[1].locked` **и** `WINDOW_ON_OPEN_EDGE` на окне, хотя корень один. Это противоречит правилу
   шапки `validator.gd` («одна ошибка — одно следствие»), но `game/content/**` заморожен, и правка там требует нового
   ревью, поэтому не трогал. Моя проверка фиксирует **текущее** поведение (оба диагноза); если владелец конвейера
   решит каскад подавить, проверку надо будет осознанно поправить. Это же относится к числу: `locked: 1`.
2. **Ограничение однопроцессного варианта.** Скрипт, который тянет сломанный файл через `preload`, может загрузиться
   как годный: в пробе `test_content_loader.gd` дал `can_instantiate=true` и в список `LOAD FAIL` не попал (а
   `test_content_validator.gd` и `test_handoff_skeleton.gd` — попали, потому что их собственный разбор упал на
   неразрешимом `preload`). Дыры в диагнозе нет только потому, что перечислены **все** модули: причина называется
   первой же строкой. Это и есть ответ на просьбу из дополнения — «называет так же ясно, как отдельные запуски»;
   а отдельные запуски здесь ещё и слабее (§3.2).
3. **`--check-only` по одиночному файлу врёт и на своём уровне** — код 0 при уже напечатанном
   `Failed to load script ... "Compilation failed"`. В документированную формулировку это добавлено (§8), потому что
   иначе остаётся соблазн «ну хотя бы по одному файлу прогоню».
4. **`docs/current/2026-09-27-plan-content-pipeline.md:20`** и **`docs/current/2026-09-27-design-content-pipeline.md:128`**,
   а также `docs/archive/2026-09-26-plan-p1-sim-core.md:2151` и `docs/archive/2026-09-26-p1-execution-ledger.md:18`
   всё ещё называют `--check-only` шагом гейта. Не правил: это план и история, а не инструкция; скажи, если надо
   довести и там.
5. **`README.md:30`** — «12 кейсов», а их 17. Не мой участок, не правил; в §8 число проверок обновил, потому что
   его изменил я сам.
6. **Дефектов в `game/content/**` и `game/sim/**` не нашёл** (кроме п. 1 — спорного каскада, а не ошибки).
   Правок там я не делал: все пробы с внесённой ошибкой шли по путям `%TEMP%`, а в сдаваемом дереве `preflight` даёт
   30/0 и полный прогон 620/0. Для протокола: `game/content/loader.gd` и `game/content/validator.gd` несут
   незакоммиченные правки прошлых потоков (mtime `11:00:24` / `11:00:40` — раньше моего первого запуска движка
   в `11:03:55`); я их только читал.

---

## 8. Открытые вопросы

1. Подавлять ли каскад `WRONG_TYPE` + `WINDOW_ON_OPEN_EDGE` на не-bool `locked` (нужно новое ревью `content/`)?
2. Править ли упоминания `--check-only` в `docs/current/*` и `docs/archive/*` (§7 п. 4)?
3. Чинить ли «12 кейсов» в таблице `README.md` (§7 п. 5)?

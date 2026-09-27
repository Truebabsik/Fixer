# Отчёт: восьмой заход — охрана второй половины контракта текстов

Коммит не делался, редактор не запускался, `.uid` не создавались. `game/sim/**`, `docs/**`,
`game/content/validator.gd` — не тронуты (SHA `validator.gd` до и после совпал, см. §4).
Область правки: два файла тестов и док `game/content/loader.gd`.

---

## 1. Что изменено (`файл:строка`)

| Файл | Строки | Что |
|---|---|---|
| `game/tests/cases/test_content_validator.gd` | 850–872 (комментарий), **874** (корпус) | в корпус неверных типов добавлен `[]`; в комментарий кейса 12в добавлено объяснение, почему именно `[]` держит вторую половину контракта (пункт 1 брифа), и пометка про типы вне таблицы `type_name` (пункт 4) |
| `game/tests/cases/test_content_loader.gd` | 92–99 | новый локальный помощник `_codes(problems) -> Array` (аналог одноимённого в валидаторном кейсе) |
| `game/tests/cases/test_content_loader.gd` | 226–233 (комментарий), **234** (корпус), 237–242 (ассерт) | в корпус неверных типов добавлен `[]`; вместо пары «ровно одна проблема» + «среди них WRONG_TYPE» стоит сверка ПОЛНОГО списка кодов `== [WRONG_TYPE]` — она и называет каскад |
| `game/tests/cases/test_content_loader.gd` | 454–458 | комментарий про дубль `id` приведён к факту: двойник в ХВОСТЕ (`[kira, echo, kira]`), в середине — выживший `echo` (пункт 3 брифа) |
| `game/content/loader.gd` | 33, 40–44 | док `load_mission`: `texts` в ответе — ровно то, что передал вызывающий; `Dictionary\|null` не обещается, потому что на пути отказа туда попадает и не-словарь (пункт 2 брифа) |

Правка боевого кода — только док: тело `load_mission`/`validate` не менялось ни на байт.

Точные места правки:

- `test_content_validator.gd:874` — `for wrong_texts in ["мусор-строка", 7, false, []]:`
  (ассерт `test_content_validator.gd:876-877` — уже существовавший, сверка полного списка кодов);
- `test_content_loader.gd:234` — тот же корпус; `test_content_loader.gd:241-242` — новый ассерт.
- Число проверок: было `727`, стало `728`. Арифметика: валидаторный цикл `+1` вход × `2` ассерта
  = `+2`; цикл загрузчика `−1` ассерт на вход (`3` → `2`) × `4` входа = `−1`. Итого `727 + 2 − 1 = 728`.

**Ожидаемое поведение (проверено прогоном).** Верный код: `validate(_good(), [])` и
`load_mission(_fixture_data(), [])` дают ровно `["WRONG_TYPE"]`. Сломанный «сверка вызывается
всегда»: `["WRONG_TYPE"]` плюс `MISSING_TEXT` на каждый ключ данных — у `_good()` их **шесть**
(7 кодов), у фикстуры загрузчика — **пять** (6 кодов). Число «шесть кодов» из брифа — это
счёт фикстуры загрузчика; в валидаторном кейсе ключей текстов шесть, поэтому кодов семь.

---

## 2. Мутация E. Дословный вывод ДО правки

Дерево-копия в `%TEMP%\fixer8` (см. §5), правка ТОЛЬКО в копии:

```gdscript
# game/content/validator.gd, было
	if texts != null and typeof(texts) != TYPE_DICTIONARY:
		problems.append(Problems.wrong_type("(тексты)", TYPE_DICTIONARY, typeof(texts)))
	else:
		_check_texts(data, texts, problems)
# стало (мутация E: `else` снят, вызов сдвинут на уровень ветки — сверка идёт ВСЕГДА)
	if texts != null and typeof(texts) != TYPE_DICTIONARY:
		problems.append(Problems.wrong_type("(тексты)", TYPE_DICTIONARY, typeof(texts)))
	_check_texts(data, texts, problems)
```

Команда: `... --headless --path %TEMP%\fixer8\game --script res://tests/run.gd`
(тесты — ещё НЕправленые, строка цикла валидатора 856, загрузчика 219):

```
ERROR: Failed to open 'user://logs/godot2026-09-27T12.32.30.log'.
   at: copy (core/io/dir_access.cpp:429)
ERROR: Failed to open log file for writing: user://logs/godot.log
   at: rotate_file (core/io/logger.cpp:169)
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

ERROR: Resource file not found: res:// (expected type: unknown)
   at: _load (core/io/resource_loader.cpp:325)
ERROR: Failed to instantiate an autoload, can't load from path: .
   at: start (main/main.cpp:4533)
ERROR: Failed to read the root certificate store.
   at: get_system_ca_certificates (platform/windows/os_windows.cpp:2582)
SCRIPT ERROR: Invalid call. Nonexistent function 'has' in base 'String'.
   at: _check_texts (res://content/validator.gd:1052)
   GDScript backtrace (most recent call first):
       [0] _check_texts (res://content/validator.gd:1052)
       [1] validate (res://content/validator.gd:132)
       [2] run (res://tests/cases/test_content_validator.gd:856)
       [3] _collect (res://tests/suite.gd:69)
       [4] run (res://tests/suite.gd:45)
       [5] _initialize (res://tests/run.gd:18)
SCRIPT ERROR: Invalid call. Nonexistent function 'has' in base 'int'.
   at: _check_texts (res://content/validator.gd:1052)
   GDScript backtrace (most recent call first):
       [0] _check_texts (res://content/validator.gd:1052)
       [1] validate (res://content/validator.gd:132)
       [2] run (res://tests/cases/test_content_validator.gd:856)
       [3] _collect (res://tests/suite.gd:69)
       [4] run (res://tests/suite.gd:45)
       [5] _initialize (res://tests/run.gd:18)
SCRIPT ERROR: Invalid call. Nonexistent function 'has' in base 'bool'.
   at: _check_texts (res://content/validator.gd:1052)
   GDScript backtrace (most recent call first):
       [0] _check_texts (res://content/validator.gd:1052)
       [1] validate (res://content/validator.gd:132)
       [2] run (res://tests/cases/test_content_validator.gd:856)
       [3] _collect (res://tests/suite.gd:69)
       [4] run (res://tests/suite.gd:45)
       [5] _initialize (res://tests/run.gd:18)
SCRIPT ERROR: Invalid call. Nonexistent function 'has' in base 'String'.
   at: _check_texts (res://content/validator.gd:1052)
   GDScript backtrace (most recent call first):
       [0] _check_texts (res://content/validator.gd:1052)
       [1] validate (res://content/validator.gd:132)
       [2] load_mission (res://content/loader.gd:41)
       [3] run (res://tests/cases/test_content_loader.gd:219)
       [4] _collect (res://tests/suite.gd:69)
       [5] run (res://tests/suite.gd:45)
       [6] _initialize (res://tests/run.gd:18)
SCRIPT ERROR: Invalid call. Nonexistent function 'has' in base 'int'.
   at: _check_texts (res://content/validator.gd:1052)
   GDScript backtrace (most recent call first):
       [0] _check_texts (res://content/validator.gd:1052)
       [1] validate (res://content/validator.gd:132)
       [2] load_mission (res://content/loader.gd:41)
       [3] run (res://tests/cases/test_content_loader.gd:219)
       [4] _collect (res://tests/suite.gd:69)
       [5] run (res://tests/suite.gd:45)
       [6] _initialize (res://tests/run.gd:18)
SCRIPT ERROR: Invalid call. Nonexistent function 'has' in base 'bool'.
   at: _check_texts (res://content/validator.gd:1052)
   GDScript backtrace (most recent call first):
       [0] _check_texts (res://content/validator.gd:1052)
       [1] validate (res://content/validator.gd:132)
       [2] load_mission (res://content/loader.gd:41)
       [3] run (res://tests/cases/test_content_loader.gd:219)
       [4] _collect (res://tests/suite.gd:69)
       [5] run (res://tests/suite.gd:45)
       [6] _initialize (res://tests/run.gd:18)
SCRIPT ERROR: Invalid call. Nonexistent function 'has' in base 'String'.
   at: _check_texts (res://content/validator.gd:1052)
   GDScript backtrace (most recent call first):
       [0] _check_texts (res://content/validator.gd:1052)
       [1] validate (res://content/validator.gd:132)
       [2] load_mission (res://content/loader.gd:41)
       [3] load_text (res://content/loader.gd:30)
       [4] run (res://tests/cases/test_content_loader.gd:229)
       [5] _collect (res://tests/suite.gd:69)
       [6] run (res://tests/suite.gd:45)
       [7] _initialize (res://tests/run.gd:18)
tests: 727, failed: 0
EXIT=0
```

**Ни одного именованного провала.** Семь `SCRIPT ERROR … Nonexistent function 'has'` в stderr
поведение изменили (сверка начала вызываться), но вердикт — код возврата — остался нулевым:
ровно дефект §6.1.1 из брифа. Это и есть доказательство, что прежний набор мутацию E не видел.

## 3. Мутация E. Дословный вывод ПОСЛЕ правки

Та же мутация (байт-в-байт тот же диф `validator.gd`), но в копии уже лежат правленые тесты
(цикл валидатора 875, загрузчика 235). Команда та же:

```
ERROR: Failed to open 'user://logs/godot2026-09-27T12.33.20.log'.
   at: copy (core/io/dir_access.cpp:429)
ERROR: Failed to open log file for writing: user://logs/godot.log
   at: rotate_file (core/io/logger.cpp:169)
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

ERROR: Resource file not found: res:// (expected type: unknown)
   at: _load (core/io/resource_loader.cpp:325)
ERROR: Failed to instantiate an autoload, can't load from path: .
   at: start (main/main.cpp:4533)
ERROR: Failed to read the root certificate store.
   at: get_system_ca_certificates (platform/windows/os_windows.cpp:2582)
SCRIPT ERROR: Invalid call. Nonexistent function 'has' in base 'String'.
   at: _check_texts (res://content/validator.gd:1052)
   GDScript backtrace (most recent call first):
       [0] _check_texts (res://content/validator.gd:1052)
       [1] validate (res://content/validator.gd:132)
       [2] run (res://tests/cases/test_content_validator.gd:875)
       [3] _collect (res://tests/suite.gd:69)
       [4] run (res://tests/suite.gd:45)
       [5] _initialize (res://tests/run.gd:18)
SCRIPT ERROR: Invalid call. Nonexistent function 'has' in base 'int'.
   at: _check_texts (res://content/validator.gd:1052)
   GDScript backtrace (most recent call first):
       [0] _check_texts (res://content/validator.gd:1052)
       [1] validate (res://content/validator.gd:132)
       [2] run (res://tests/cases/test_content_validator.gd:875)
       [3] _collect (res://tests/suite.gd:69)
       [4] run (res://tests/suite.gd:45)
       [5] _initialize (res://tests/run.gd:18)
SCRIPT ERROR: Invalid call. Nonexistent function 'has' in base 'bool'.
   at: _check_texts (res://content/validator.gd:1052)
   GDScript backtrace (most recent call first):
       [0] _check_texts (res://content/validator.gd:1052)
       [1] validate (res://content/validator.gd:132)
       [2] run (res://tests/cases/test_content_validator.gd:875)
       [3] _collect (res://tests/suite.gd:69)
       [4] run (res://tests/suite.gd:45)
       [5] _initialize (res://tests/run.gd:18)
SCRIPT ERROR: Invalid call. Nonexistent function 'has' in base 'String'.
   at: _check_texts (res://content/validator.gd:1052)
   GDScript backtrace (most recent call first):
       [0] _check_texts (res://content/validator.gd:1052)
       [1] validate (res://content/validator.gd:132)
       [2] load_mission (res://content/loader.gd:47)
       [3] run (res://tests/cases/test_content_loader.gd:235)
       [4] _collect (res://tests/suite.gd:69)
       [5] run (res://tests/suite.gd:45)
       [6] _initialize (res://tests/run.gd:18)
SCRIPT ERROR: Invalid call. Nonexistent function 'has' in base 'int'.
   at: _check_texts (res://content/validator.gd:1052)
   GDScript backtrace (most recent call first):
       [0] _check_texts (res://content/validator.gd:1052)
       [1] validate (res://content/validator.gd:132)
       [2] load_mission (res://content/loader.gd:47)
       [3] run (res://tests/cases/test_content_loader.gd:235)
       [4] _collect (res://tests/suite.gd:69)
       [5] run (res://tests/suite.gd:45)
       [6] _initialize (res://tests/run.gd:18)
SCRIPT ERROR: Invalid call. Nonexistent function 'has' in base 'bool'.
   at: _check_texts (res://content/validator.gd:1052)
   GDScript backtrace (most recent call first):
       [0] _check_texts (res://content/validator.gd:1052)
       [1] validate (res://content/validator.gd:132)
       [2] load_mission (res://content/loader.gd:47)
       [3] run (res://tests/cases/test_content_loader.gd:235)
       [4] _collect (res://tests/suite.gd:69)
       [5] run (res://tests/suite.gd:45)
       [6] _initialize (res://tests/run.gd:18)
SCRIPT ERROR: Invalid call. Nonexistent function 'has' in base 'String'.
   at: _check_texts (res://content/validator.gd:1052)
   GDScript backtrace (most recent call first):
       [0] _check_texts (res://content/validator.gd:1052)
       [1] validate (res://content/validator.gd:132)
       [2] load_mission (res://content/loader.gd:47)
       [3] load_text (res://content/loader.gd:30)
       [4] run (res://tests/cases/test_content_loader.gd:248)
       [5] _collect (res://tests/suite.gd:69)
       [6] run (res://tests/suite.gd:45)
       [7] _initialize (res://tests/run.gd:18)
FAIL  test_content_validator.gd :: texts = [] — ровно WRONG_TYPE, без сверки
      ожидалось: ["WRONG_TYPE"]
      получено:  ["WRONG_TYPE", "MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT"]
FAIL  test_content_loader.gd :: texts = [] — ровно [WRONG_TYPE], без сверки
      ожидалось: ["WRONG_TYPE"]
      получено:  ["WRONG_TYPE", "MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT"]
tests: 728, failed: 2
EXIT=1
```

Названы ровно два ассерта — те, что и должны:

1. `test_content_validator.gd :: texts = [] — ровно WRONG_TYPE, без сверки` —
   `["WRONG_TYPE"]` против `["WRONG_TYPE", MISSING_TEXT×6]` (`_good()` использует шесть ключей);
2. `test_content_loader.gd :: texts = [] — ровно [WRONG_TYPE], без сверки` —
   `["WRONG_TYPE"]` против `["WRONG_TYPE", MISSING_TEXT×5]` (фикстура загрузчика использует пять).

Код возврата `1`. Мутация E больше не проходит: дефект «ассерт зелен на сломанном коде» закрыт
именно ассертом, а не комментарием.

### Проба E′ (побочная, для полноты картины)

Мой первый заход на мутацию был неточен: я снял `else`, но оставил вызов с отступом — получилось
«сверка ТОЛЬКО на неверном типе» (обратная поломка: у законного словаря сверка пропадает). Набор
покраснел, но не тем: `tests: 728, failed: 8` (шесть кейсов `MISSING_TEXT`/`DANGLING_TEXT`
валидатора и скелета плюс два `load_text`), код 1. Это не мутация E и в зачёт не идёт, но
показывает полезное: **вторая сторона** (`else`-ветка со словарём) охраняется плотно, дыра была
именно в варианте «сверка вызывается всегда». Транскрипт полного прогона не привожу (семь блоков
`SCRIPT ERROR` те же), список провалов — из того прогона:

```
FAIL  test_content_validator.gd :: нет ключа текста окна — MISSING_TEXT
FAIL  test_content_validator.gd :: висячий ключ текста — DANGLING_TEXT
FAIL  test_content_validator.gd :: texts = {} — MISSING_TEXT на каждый ключ данных (6)
FAIL  test_handoff_skeleton.gd :: пустой словарь текстов — MISSING_TEXT на каждый ключ данных
FAIL  test_handoff_skeleton.gd :: удалён один ключ фикстуры — ровно MISSING_TEXT
FAIL  test_handoff_skeleton.gd :: удалён один ключ фикстуры — путь на поле *_key ((проблем нет))
FAIL  test_handoff_skeleton.gd :: лишний ключ текстов — DANGLING_TEXT
FAIL  test_handoff_skeleton.gd :: лишний ключ текстов — ровно один диагноз
tests: 728, failed: 8
EXIT=1
```

---

## 4. Гейт (дословно, финальное дерево)

Копия `%TEMP%\fixer8` синхронизирована с рабочей областью (`robocopy /MIR`, исключены
`.godot`, `.git`, `tools`; `docs/` на месте), SHA четырёх файлов в копии и в рабочей области
совпали. Мутация E откачена (`Copy-Item` из рабочей области), после отката — финальный прогон:

```powershell
tools\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path %TEMP%\fixer8\game --script res://tests/preflight.gd
tools\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path %TEMP%\fixer8\game --script res://tests/run.gd
tools\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path %TEMP%\fixer8\game --script res://tests/run_red.gd
```

```
=== res://tests/preflight.gd ===
ERROR: Failed to open 'user://logs/godot2026-09-27T12.33.32.log'.
   at: copy (core/io/dir_access.cpp:429)
ERROR: Failed to open log file for writing: user://logs/godot.log
   at: rotate_file (core/io/logger.cpp:169)
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

ERROR: Resource file not found: res:// (expected type: unknown)
   at: _load (core/io/resource_loader.cpp:325)
ERROR: Failed to instantiate an autoload, can't load from path: .
   at: start (main/main.cpp:4533)
ERROR: Failed to read the root certificate store.
   at: get_system_ca_certificates (platform/windows/os_windows.cpp:2582)
preflight: scripts: 30, failed: 0
EXIT=0
=== res://tests/run.gd ===
ERROR: Failed to open 'user://logs/godot2026-09-27T12.33.33.log'.
   at: copy (core/io/dir_access.cpp:429)
ERROR: Failed to open log file for writing: user://logs/godot.log
   at: rotate_file (core/io/logger.cpp:169)
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

ERROR: Resource file not found: res:// (expected type: unknown)
   at: _load (core/io/resource_loader.cpp:325)
ERROR: Failed to instantiate an autoload, can't load from path: .
   at: start (main/main.cpp:4533)
ERROR: Failed to read the root certificate store.
   at: get_system_ca_certificates (platform/windows/os_windows.cpp:2582)
tests: 728, failed: 0
EXIT=0
=== res://tests/run_red.gd ===
ERROR: Failed to open 'user://logs/godot2026-09-27T12.33.33.log'.
   at: copy (core/io/dir_access.cpp:429)
ERROR: Failed to open log file for writing: user://logs/godot.log
   at: rotate_file (core/io/logger.cpp:169)
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

ERROR: Resource file not found: res:// (expected type: unknown)
   at: _load (core/io/resource_loader.cpp:325)
ERROR: Failed to instantiate an autoload, can't load from path: .
   at: start (main/main.cpp:4533)
ERROR: Failed to read the root certificate store.
   at: get_system_ca_certificates (platform/windows/os_windows.cpp:2582)
FAIL  red_path.gd :: нарочно неверный ассерт
      ожидалось: 2
      получено:  1
red-path: tests: 2, failed: 1 (ожидаем failed > 0)
tests: 728, failed: 0
EXIT=0
```

Вердикт — коды возврата: **preflight 0, run 0, run_red 0**. Числа: `30/0`, `728/0` (было 727),
красный путь `2/1` как задумано. Прогоны завершились сами, сторож не срабатывал, каждый — секунды.

**Baseline до правок** (та же копия, те же команды): `preflight: scripts: 30, failed: 0`;
`tests: 727, failed: 0`; `run_red` — код 0. Совпал с числами брифа, то есть правка не «починила»
уже красный набор.

**Про три `ERROR` в выводе** (autoload `res://`, `user://logs`, сертификаты) — среда копии, а не
набор: в свежем `%TEMP%` нет кэша `.godot`, автозагрузка `McpRuntimeProbe` ссылается на
`uid://…`, а `user://` в песочнице недоступна для записи. Те же строки были и в baseline до
правок, и в отчёте шестого захода.

SHA-256 файлов, на которых снят финальный гейт (рабочая область = копия):

| Файл | SHA-256 |
|---|---|
| `game/content/validator.gd` | `5DA472DEB2278AA7AEB7986A15728EF2E4DD887E476D7EFDE1EA6B91F7C3AA89` (НЕ менялся) |
| `game/content/loader.gd` | `AEB370CBE5A1C754C586590B23296D841C7E104207613B930955AAD385B00D6B` |
| `game/tests/cases/test_content_validator.gd` | `09BC802AF4BD7A9805BA71A9FEB8D2E8854268BCE0FCF82AE6D5D93FE2AE2D5B` |
| `game/tests/cases/test_content_loader.gd` | `5A9B002525FDEF846D6D31C8D2E9972419E81308FC7EE7C115A09A1AFB56F101` |

Все три правленых файла — с LF (CRLF-байт нет: правка не смешала окончания строк).

---

## 5. Как делались пробы и что осталось в стороне

- Копия: `git worktree add --detach %TEMP%\fixer8 HEAD` + `robocopy /MIR` из рабочей области
  с исключением `.godot`, `.git`, `tools` (и `/XF .git`, чтобы `/MIR` не снёс `.git`-файл
  worktree). `docs/` в копии есть — кейс скелета читает `../docs/...`. Редактор не запускался.
- Правки в копии делались с ЯВНОЙ кодировкой UTF-8 (`UTF8Encoding($false)`): Windows PowerShell
  5.1 в этой среде читает файл как ANSI, и первый заход на мутацию дал двойную перекодировку
  кириллицы (`"(тексты)"` превратился в мусор) — файл был откачен и перезаписан из рабочей
  области, сверено по SHA. В самом отчёте это важно как грабли для следующего: в этой среде
  `Get-Content -Raw`/`Set-Content` для `.gd` с кириллицей использовать нельзя.
- **Замечено, не стал делать (второй ассерт того же класса — прошу решения ведущего).**
  Ассерт `test_content_validator.gd:881-882` («ожидание названо») проверяет только половину
  сообщения — что в нём есть «словарь» (это ожидаемый тип). Фактический тип в сообщении не
  проверяется, поэтому мутация «подставить в `wrong_type` чужой фактический тип» остаётся
  зелёной. Проверено пробой F: `Problems.wrong_type("(тексты)", TYPE_DICTIONARY, TYPE_ARRAY)`
  (фактический тип зашит как «массив», хотя входы — строка/число/логическое) даёт
  `tests: 728, failed: 0`, `EXIT=0`, то есть диагноз для строки читается «получено: массив».
  Гипотетическая правка (одна строка, НЕ применял):
  `_message_at(...).contains("получено: %s" % Problems.type_name(typeof(wrong_texts)))`
  вместо `contains("словарь")` — она называла бы и ожидание, и факт. Сюда же относится, что
  `load_text`-ассерты (`test_content_loader.gd:248-252`) сверяют только размер и `mission == null`,
  а не код: подмена кода проблемы на другой прошла бы там незамеченной (в пути `validate` её
  ловит сверка кодов, поэтому практического риска не вижу — отмечаю как факт).
- Мутация E применена к копии ДВА раза (до правки и после), плюс один неточный заход E′ и проба F;
  все правки копии откатывались `Copy-Item` из рабочей области, финальное состояние копии
  сверено с рабочей областью по SHA четырёх файлов (совпали) — финальный гейт снят на нём.
- Коммит не делался, `.uid` не создавались, `docs/**`, `game/sim/**` и постановка не тронуты.

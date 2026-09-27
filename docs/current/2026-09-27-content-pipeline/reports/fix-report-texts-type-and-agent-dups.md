# Отчёт: седьмой заход — тип второго аргумента `texts` и дубли `id` агентов

Исполнитель: субагент по брифу `fix-brief-texts-type-and-agents.md`.
Коммит не делался, `.uid` не создавались, редактор (`--editor`) не запускался.
`docs/**` и `game/sim/**` не тронуты. Прогоны — в копии дерева в `%TEMP%` (`git worktree`
от `HEAD` + наложение рабочего дерева), чтобы не писать в общий `.godot/` рабочей области.

## Итог

| Ворота | До захода | После захода | Код возврата |
|---|---|---|---|
| `preflight.gd` | `scripts: 30, failed: 0` | `preflight: scripts: 30, failed: 0` | 0 |
| `run.gd` | `tests: 707, failed: 0` | `tests: 727, failed: 0` | 0 |
| `run_red.gd` | код 0 | код 0 | 0 |

Рост на 20 проверок: +6 в кейсе 12в валидатора (три не-словаря × 2 ассерта), +11 в кейсе
загрузчика (три не-словаря × 3 ассерта + два ассерта на `load_text`), +3 в пятом случае
состава (`test_content_loader.gd`). 707 + 20 = 727.

## Изменённые файлы

| Файл | Место | Что |
|---|---|---|
| `game/content/validator.gd` | `:90-99` | контракт `validate`: названо ТРЕТЬЕ состояние второго аргумента |
| `game/content/validator.gd` | `:125-134` | проверка формы аргумента: не `null` и не словарь → `WRONG_TYPE` на `(тексты)`, сверка не выполняется |
| `game/content/validator.gd` | `:1045-1050` | док `_check_texts`: предусловие «только `null` или словарь», проверка формы живёт в одном месте |
| `game/content/loader.gd` | `:110-115` | политика `agents`: дубль `id` отбраковывается, как и пустой `id` |
| `game/content/loader.gd` | `:153-158` | док `_plan_agents`: правило «остаётся ПЕРВАЯ запись» и почему не «последний победил» |
| `game/content/loader.gd` | `:172-183` | `seen: Dictionary` — множество принятых id, дубль отбрасывается целиком |
| `game/tests/cases/test_content_validator.gd` | `:843-864` | новый кейс 12в (строка, число, логическое; ровно `WRONG_TYPE`, без сверки) |
| `game/tests/cases/test_content_validator.gd` | `:983-985` | проблемы 12в добавлены в корпус нормы имён типов |
| `game/tests/cases/test_content_loader.gd` | `:210-233` | новый кейс 7a: `load_mission` со строкой/числом/логическим + `load_text` со строкой вместо словаря |
| `game/tests/cases/test_content_loader.gd` | `:264-284` | п.3 брифа: ложное обоснование заменено правдой о `{} == []` и о дублировании |
| `game/tests/cases/test_content_loader.gd` | `:383` | «ЧЕТЫРЕ случая состава» → «ПЯТЬ» |
| `game/tests/cases/test_content_loader.gd` | `:421-446` | пятый случай: дубль `id` + дубль в середине списка, сверка ТОЧНОГО содержимого |
| `.superpowers/.../fix-report-texts-and-agents.md` | `:247-255`, `:368-373`, `:377`, `:2a/2c`, проба 3 | п.4 брифа: «5 мест» → «6 мест» (+ строка 141) и происхождение чисел проб |

---

## 1. Второй аргумент неверного типа

### 1.1. Что изменено

`validator.gd:125-134`:

```gdscript
	if texts != null and typeof(texts) != TYPE_DICTIONARY:
		problems.append(Problems.wrong_type("(тексты)", TYPE_DICTIONARY, typeof(texts)))
	else:
		_check_texts(data, texts, problems)
```

Проверка стоит в `validate` (как и требует бриф) по той же причине, по которой там стоит
проверка `(корень)`: это форма АРГУМЕНТА, а `_check_texts` отвечает на вопрос «что в текстах
против данных». Третье состояние не доходит до `_check_texts` вовсе, и второй такой же
`typeof` внутри неё не заводится — иначе две копии одной проверки разошлись бы молча.
Предусловие записано в доке `_check_texts` (`validator.gd:1045-1050`); единственный её
вызывающий — `validate` (проверено grep'ом по `game/`).

Контракт назван в доке `validate` (`validator.gd:90-99`) третьим пунктом рядом с `null` и
словарём; там же прямо сказано, почему без аннотации типа компилятор ловит забывание, но не
подстановку не того.

### 1.2. Проба «до» — дефект воспроизведён на дереве до правки

Скрипт `game/tests/_probe_texts_wrong_type.gd` (жил только в копии в `%TEMP%`, в рабочей
области не создавался; фикстура берётся у кейса загрузчика, второй копии данных нет):

```
SCRIPT ERROR: Invalid call. Nonexistent function 'has' in base 'String'.
   at: _check_texts (res://content/validator.gd:1027)
   GDScript backtrace (most recent call first):
       [0] _check_texts (res://content/validator.gd:1027)
       [1] validate (res://content/validator.gd:111)
       [2] load_mission (res://content/loader.gd:41)
       [3] _initialize (res://tests/_probe_texts_wrong_type.gd:13)
load_mission(texts=мусор-строка): problems=0 mission_null=false
```

Дальше то же самое с `int`, `bool` (движок меняет только имя базового типа в сообщении):

```
SCRIPT ERROR: Invalid call. Nonexistent function 'has' in base 'int'.
   at: _check_texts (res://content/validator.gd:1027)
SCRIPT ERROR: Invalid call. Nonexistent function 'has' in base 'bool'.
   at: _check_texts (res://content/validator.gd:1027)
load_mission(texts=7): problems=0 mission_null=false
load_mission(texts=false): problems=0 mission_null=false
validate(texts=мусор-строка): problems=0
validate(texts=7): problems=0
validate(texts=false): problems=0
EXIT=0
```

То есть подтверждено дословно: **`problems = 0` и миссия СОБРАНА**, а единственный признак
дефекта — строка в stderr, которая вердиктом не является. Важная деталь механики: рантайм-ошибка
прерывает именно `_check_texts` (первую же строку сверки), а `validate` и `load_mission`
завершаются нормально — поэтому «проблем нет» и выходило.

### 1.3. Та же проба после правки

```
load_mission(texts=мусор-строка): problems=1 mission_null=true
validate(texts=мусор-строка): problems=1
load_mission(texts=7): problems=1 mission_null=true
validate(texts=7): problems=1
load_mission(texts=false): problems=1 mission_null=true
validate(texts=false): problems=1
EXIT=0
```

Ошибок в stderr нет вовсе: исчезла и ложная «успешность», и рантайм-сбой.

---

## 2. Дубли `id` агентов

### 2.1. Что изменено

`loader.gd:172-183`:

```gdscript
	## Множество уже принятых id — тот же словарь-множество, что `_known_ids` в валидаторе.
	## Отдельно от `out`, чтобы не искать по списку записей на каждом шаге.
	var seen: Dictionary = {}
	for a in (value as Array):
		...
		if seen.has(id):
			continue
		seen[id] = true
```

Правило названо в доке функции (`loader.gd:153-158`) и в политике `load_plan`
(`loader.gd:110-115`): остаётся ПЕРВАЯ запись — порядок записи задаёт приоритет, а не
«побеждает последний»; запись отбрасывается ЦЕЛИКОМ, как и запись с пустым `id`.

Обоснование в комментарии опирается на прочитанный (не тронутый) код ядра:
`sim.gd:93-102` кладёт КАЖДУЮ запись плана в `own`, а `sim.gd:183-189` (`_positions()`)
пишет `out[a.id] = a.node` — ключ один, вторая запись его перезаписывает. Боец при этом
остаётся в `own`, но исчезает из отчёта (`positions`, `sim.gd:179`) без единого сообщения.

### 2.2. Проверки (точный результат, не «не пусто»)

`test_content_loader.gd:421-446`, пятый случай блока состава:

* дубль `id` → `size == 1` **и** `t.eq(agents, [{kira, tactician, Понимание 3}])` — сверяется
  содержимое уцелевшей записи, поэтому видно, что отброшена именно ВТОРАЯ (у неё другой
  `role` и Понимание 5);
* три записи, две с одним `id` (двойник в СЕРЕДИНЕ) → `t.eq(agents, [kira, echo])` — соседи
  сохранены, порядок сохранён, отброшен третий (`scout`), то есть отбраковка идёт по
  встреченному id, а не «усечением хвоста».

---

## 3. `test_content_loader.gd:264-284` — правда о `{} == []` и решение по ассерту типа

### 3.1. Что проверено пробой на этой же версии движка (4.7.2)

| Проба | Результат |
|---|---|
| `var a: Dictionary = {}; var b: Array = []; a == b` (затипизированные операнды) | **ошибка разбора**: `Parse Error: Invalid operands "Dictionary" and "Array" for "==" operator.` (скрипт не загружается, код 1) |
| то же через нетипизированные переменные | **рантайм-ошибка**: `SCRIPT ERROR: Invalid operands 'Dictionary' and 'Array' in operator '=='.` — прерывает текущую функцию; в `_initialize` `SceneTree` `quit()` не достигается, и процесс зависает (проба снята по таймауту) |
| `Assert.eq("{} == []", {}, [])` | `ok=false`, ошибок нет: `_same` (`tests/assert.gd:26-32`) сравнивает `typeof` первым делом и на разных типах возвращает `false`, не выполняя `==` |
| `Assert.eq("словарь вместо массива", {"guard_1": {}}, [])` | `ok=false` |

Итог: **`{} == []` не истинно**; прежнее обоснование в комментарии было ложным, и на нём
охрану можно было снять, посчитав её основанной на несуществующем свойстве языка.

### 3.2. Решение: вариант (а) — ассерт оставлен

Выбран вариант (а) брифа: `typeof(...) == TYPE_ARRAY` остаётся, но обоснован честно.

Почему не (б) «убрать как дублирующий». Дублирование по обнаружению — факт, и он проверен
пробой: со сломанной охраной `_items` (`return data.get(section, [])`) краснеют ОБА ассерта,
то есть равенство ловит дефект и без проверки типа:

```
FAIL  test_content_loader.gd :: _items: словарь вместо массива — пустой массив, а не ключи
      ожидалось: []
      получено:  { "guard_1": { "route": [] } }
FAIL  test_content_loader.gd :: _items: строка вместо массива — пустой массив
      ожидалось: []
      получено:  guard_1
FAIL  test_content_loader.gd :: _items: словарь вместо массива — вернулся МАССИВ, не словарь
      ожидалось: 28
      получено:  27
tests: 727, failed: 3
EXIT=1
```

Но ассерт не вырожден (на снятой охране он краснеет) и держит то, чего равенство не даёт:
ИМЯ провала называет контракт («вернулся МАССИВ, не словарь»), тогда как `t.eq` печатает
расхождение словаря с массивом; и он не зависит от того, как `_same` сравнивает типы внутри
— если общий хелпер когда-нибудь ослабят, равенство замолчит, а этот ассерт останется.
В комментарии это записано прямо, вместе с фразой, что прежнее обоснование было ложным.

---

## 4. Отчёт шестого захода: две неточности (правка текста)

1. **§A.3**: «test_handoff_skeleton.gd — 5 мест» → **6 мест**, добавлен пропущенный
   `141` (`{}` — новый отрицательный контроль «пустой словарь текстов — MISSING_TEXT на
   каждый ключ данных»), то есть ровно тот контроль, ради которого заход и делался.
2. **Пробы 1/2a/2c/3**: числа приведены к факту указанием происхождения, а не переписыванием
   транскриптов. В преамбуле раздела проб (`:368-373`) сказано: пробы сняты на дереве ДО
   добавления трёх ассертов пути отказа, поэтому в них `tests: 704`, а не 707; у каждой из
   четырёх проб (`:377`, 2a, 2c, проба 3) стоит та же пометка. **Транскрипты `704` на `707`
   не заменены намеренно**: это была бы подделка вывода — исправлено происхождение чисел.

---

## Гейт (дословно, финальное дерево)

Прогон — в копии рабочего дерева:
`git worktree add --detach %TEMP%\fixer7 HEAD` + `robocopy /MIR` (исключены `.godot` и `.git`).
Команда та же, что в брифе, с `--path` на копию:

```powershell
tools\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path <temp>\game --script res://tests/preflight.gd
tools\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path <temp>\game --script res://tests/run.gd
tools\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path <temp>\game --script res://tests/run_red.gd
```

```
=== 1) PREFLIGHT ===
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

ERROR: Resource file not found: res:// (expected type: unknown)
   at: _load (core/io/resource_loader.cpp:325)
ERROR: Failed to instantiate an autoload, can't load from path: .
   at: start (main/main.cpp:4533)
ERROR: Failed to read the root certificate store.
   at: get_system_ca_certificates (platform/windows/os_windows.cpp:2582)
preflight: scripts: 30, failed: 0
EXIT=0
=== 2) RUN ===
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

ERROR: Resource file not found: res:// (expected type: unknown)
   at: _load (core/io/resource_loader.cpp:325)
ERROR: Failed to instantiate an autoload, can't load from path: .
   at: start (main/main.cpp:4533)
ERROR: Failed to read the root certificate store.
   at: get_system_ca_certificates (platform/windows/os_windows.cpp:2582)
tests: 727, failed: 0
EXIT=0
=== 3) RUN_RED ===
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
tests: 727, failed: 0
EXIT=0
```

Вердикт — код возврата: preflight 0, run 0, run_red 0. Прогоны завершились сами (сторож
вердикта не срабатывал), каждый — за секунды.

Гейт прогнан дважды на одном и том же содержимом `game/**`: второй раз — после повторного
`robocopy /MIR` из рабочей области, чтобы исключить гонку с параллельными правками `docs/**`
ведущего (в той же рабочей области он правит документы и создаёт `.uid`). Вывод второго
прогона тот же — те же числа и коды. SHA-256 правленых файлов, на которых снят этот вывод:

| Файл | SHA-256 |
|---|---|
| `game/content/validator.gd` | `5DA472DEB2278AA7AEB7986A15728EF2E4DD887E476D7EFDE1EA6B91F7C3AA89` |
| `game/content/loader.gd` | `8AB3BA387672D771F848ED624F8660E3841F752416D271C304DF1E335262A413` |
| `game/tests/cases/test_content_loader.gd` | `664DCC5486FAF374BE5580A9D2A17A5EDD0AE277DD14CCF4A0BCF5234693832E` |
| `game/tests/cases/test_content_validator.gd` | `D781627D9B781F8DEB2CB82237BEBDE66861BCD58056BC769A4AC830CF3B3771` |

**Про три `ERROR` в выводе.** Это среда копии, а не набор: в свежем `%TEMP%` нет кэша
`.godot`, поэтому автозагрузка `McpRuntimeProbe` (`game/project.godot:19`, ссылка по
`uid://…`) не разрешается, а `user://` в песочнице недоступен для записи (в прогонах номеров
2…N после перенаправления `APPDATA` в `%TEMP%` строки про `user://logs` уже нет). Те же три
строки были и в baseline-прогоне ДО правок (`preflight 30/0`, `tests: 707, failed: 0`, код 0) —
то есть к правкам они отношения не имеют. Рабочая область и её `.godot/` не затронуты:
редактор не запускался, копия лежит вне рабочей области.

**Один промежуточный прогон был красным — и это важная часть отчёта.** Первая версия правки
в `test_content_loader.gd` оставила в закрытии литерала `})` вместо `])`. Ворота разбора
назвали файл по имени, ровно как обещано в брифе:

```
SCRIPT ERROR: Parse Error: Closing "}" doesn't match the opening "(".
   at: GDScript::reload (res://tests/cases/test_content_loader.gd:419)
   GDScript backtrace (most recent call first):
       [0] _parses (res://tests/preflight.gd:68)
       [1] _initialize (res://tests/preflight.gd:56)
ERROR: Failed to load script "res://tests/cases/test_content_loader.gd" with error "Parse error".
LOAD FAIL  res://tests/cases/test_content_loader.gd
preflight: scripts: 30, failed: 1
EXIT=1
```

Дополнительно все четыре правленых файла прогнаны самодельным токенизатором скобок (строки и
комментарии пропускаются): расхождений нет, незакрытых скобок нет. Порядок соблюдён: сначала
preflight, потом набор; финальный гейт выше — уже на починенном дереве.

---

## Мутационные пробы (дословно)

Все пробы сделаны в копии дерева: правка, прогон, откат `Copy-Item` из рабочей области
(байтовая сверка не нужна — файлы копий сверялись по содержимому каталога при финальном
`robocopy /MIR`, после которого прогнан финальный гейт).

### Проба A. Убрана проверка типа `texts` (`validator.gd:130-134` → безусловный вызов `_check_texts`)

```
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

ERROR: Resource file not found: res:// (expected type: unknown)
   at: _load (core/io/resource_loader.cpp:325)
ERROR: Failed to instantiate an autoload, can't load from path: .
   at: start (main/main.cpp:4533)
ERROR: Failed to read the root certificate store.
   at: get_system_ca_certificates (platform/windows/os_windows.cpp:2582)
SCRIPT ERROR: Invalid call. Nonexistent function 'has' in base 'String'.
   at: _check_texts (res://content/validator.gd:1050)
   GDScript backtrace (most recent call first):
       [0] _check_texts (res://content/validator.gd:1050)
       [1] validate (res://content/validator.gd:130)
       [2] run (res://tests/cases/test_content_validator.gd:856)
       [3] _collect (res://tests/suite.gd:69)
       [4] run (res://tests/suite.gd:45)
       [5] _initialize (res://tests/run.gd:18)
SCRIPT ERROR: Invalid call. Nonexistent function 'has' in base 'int'.
   at: _check_texts (res://content/validator.gd:1050)
   GDScript backtrace (most recent call first):
       [0] _check_texts (res://content/validator.gd:1050)
       [1] validate (res://content/validator.gd:130)
       [2] run (res://tests/cases/test_content_validator.gd:856)
       [3] _collect (res://tests/suite.gd:69)
       [4] run (res://tests/suite.gd:45)
       [5] _initialize (res://tests/run.gd:18)
SCRIPT ERROR: Invalid call. Nonexistent function 'has' in base 'bool'.
   at: _check_texts (res://content/validator.gd:1050)
   GDScript backtrace (most recent call first):
       [0] _check_texts (res://content/validator.gd:1050)
       [1] validate (res://content/validator.gd:130)
       [2] run (res://tests/cases/test_content_validator.gd:856)
       [3] _collect (res://tests/suite.gd:69)
       [4] run (res://tests/suite.gd:45)
       [5] _initialize (res://tests/run.gd:18)
SCRIPT ERROR: Invalid call. Nonexistent function 'has' in base 'String'.
   at: _check_texts (res://content/validator.gd:1050)
   GDScript backtrace (most recent call first):
       [0] _check_texts (res://content/validator.gd:1050)
       [1] validate (res://content/validator.gd:130)
       [2] load_mission (res://content/loader.gd:41)
       [3] run (res://tests/cases/test_content_loader.gd:219)
       [4] _collect (res://tests/suite.gd:69)
       [5] run (res://tests/suite.gd:45)
       [6] _initialize (res://tests/run.gd:18)
SCRIPT ERROR: Invalid call. Nonexistent function 'has' in base 'int'.
   at: _check_texts (res://content/validator.gd:1050)
   GDScript backtrace (most recent call first):
       [0] _check_texts (res://content/validator.gd:1050)
       [1] validate (res://content/validator.gd:130)
       [2] load_mission (res://content/loader.gd:41)
       [3] run (res://tests/cases/test_content_loader.gd:219)
       [4] _collect (res://tests/suite.gd:69)
       [5] run (res://tests/suite.gd:45)
       [6] _initialize (res://tests/run.gd:18)
SCRIPT ERROR: Invalid call. Nonexistent function 'has' in base 'bool'.
   at: _check_texts (res://content/validator.gd:1050)
   GDScript backtrace (most recent call first):
       [0] _check_texts (res://content/validator.gd:1050)
       [1] validate (res://content/validator.gd:130)
       [2] load_mission (res://content/loader.gd:41)
       [3] run (res://tests/cases/test_content_loader.gd:219)
       [4] _collect (res://tests/suite.gd:69)
       [5] run (res://tests/suite.gd:45)
       [6] _initialize (res://tests/run.gd:18)
SCRIPT ERROR: Invalid call. Nonexistent function 'has' in base 'String'.
   at: _check_texts (res://content/validator.gd:1050)
   GDScript backtrace (most recent call first):
       [0] _check_texts (res://content/validator.gd:1050)
       [1] validate (res://content/validator.gd:130)
       [2] load_mission (res://content/loader.gd:41)
       [3] load_text (res://content/loader.gd:30)
       [4] run (res://tests/cases/test_content_loader.gd:229)
       [5] _collect (res://tests/suite.gd:69)
       [6] run (res://tests/suite.gd:45)
       [7] _initialize (res://tests/run.gd:18)
FAIL  test_content_validator.gd :: texts = мусор-строка — ровно WRONG_TYPE, без сверки
      ожидалось: ["WRONG_TYPE"]
      получено:  []
FAIL  test_content_validator.gd :: texts = мусор-строка — проблема на пути (тексты), ожидание названо
      ожидалось: true
      получено:  false
FAIL  test_content_validator.gd :: texts = 7 — ровно WRONG_TYPE, без сверки
      ожидалось: ["WRONG_TYPE"]
      получено:  []
FAIL  test_content_validator.gd :: texts = 7 — проблема на пути (тексты), ожидание названо
      ожидалось: true
      получено:  false
FAIL  test_content_validator.gd :: texts = false — ровно WRONG_TYPE, без сверки
      ожидалось: ["WRONG_TYPE"]
      получено:  []
FAIL  test_content_validator.gd :: texts = false — проблема на пути (тексты), ожидание названо
      ожидалось: true
      получено:  false
FAIL  test_content_loader.gd :: texts = мусор-строка — ровно одна проблема
      ожидалось: 1
      получено:  0
FAIL  test_content_loader.gd :: texts = мусор-строка — это WRONG_TYPE
      ожидалось: true
      получено:  false
FAIL  test_content_loader.gd :: texts = мусор-строка — миссия не собрана
      ожидалось: true
      получено:  false
FAIL  test_content_loader.gd :: texts = 7 — ровно одна проблема
      ожидалось: 1
      получено:  0
FAIL  test_content_loader.gd :: texts = 7 — это WRONG_TYPE
      ожидалось: true
      получено:  false
FAIL  test_content_loader.gd :: texts = 7 — миссия не собрана
      ожидалось: true
      получено:  false
FAIL  test_content_loader.gd :: texts = false — ровно одна проблема
      ожидалось: 1
      получено:  0
FAIL  test_content_loader.gd :: texts = false — это WRONG_TYPE
      ожидалось: true
      получено:  false
FAIL  test_content_loader.gd :: texts = false — миссия не собрана
      ожидалось: true
      получено:  false
FAIL  test_content_loader.gd :: load_text: строка вместо словаря текстов — миссии нет
      ожидалось: true
      получено:  false
FAIL  test_content_loader.gd :: load_text: строка вместо словаря текстов — ровно одна проблема
      ожидалось: 1
      получено:  0
tests: 727, failed: 17
EXIT=1
```

17 именованных провалов, код 1. В выводе видно и то, ради чего проверка заводилась: вместе с
красными ассертами идёт семь `SCRIPT ERROR … in base 'String'/'int'/'bool'` — на снятой
проверке «проблем нет» стоит на рантайм-ошибке.

### Проба B. Возвращён приём дублей `id` (из `_plan_agents` убраны `seen` и `if seen.has(id)`)

```
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

ERROR: Resource file not found: res:// (expected type: unknown)
   at: _load (core/io/resource_loader.cpp:325)
ERROR: Failed to instantiate an autoload, can't load from path: .
   at: start (main/main.cpp:4533)
ERROR: Failed to read the root certificate store.
   at: get_system_ca_certificates (platform/windows/os_windows.cpp:2582)
FAIL  test_content_loader.gd :: agents = [дубль id] — ровно одна запись
      ожидалось: 1
      получено:  2
FAIL  test_content_loader.gd :: agents = [дубль id] — осталась ПЕРВАЯ запись
      ожидалось: [{ "id": "kira", "role": "tactician", "understanding": 3 }]
      получено:  [{ "id": "kira", "role": "tactician", "understanding": 3 }, { "id": "kira", "role": "comms", "understanding": 5 }]
FAIL  test_content_loader.gd :: дубль id в середине — двойник отброшен, соседи сохранены
      ожидалось: [{ "id": "kira", "role": "tactician", "understanding": 3 }, { "id": "echo", "role": "comms", "understanding": 2 }]
      получено:  [{ "id": "kira", "role": "tactician", "understanding": 3 }, { "id": "echo", "role": "comms", "understanding": 2 }, { "id": "kira", "role": "scout", "understanding": 7 }]
tests: 727, failed: 3
EXIT=1
```

Три именованных провала, код 1. В выводе видно сам дефект: две записи с одним `id` уезжают
в `Plan.agents`, и в `positions` останется один ключ.

### Проба C (сверх брифа, для §3). Сломанная охрана `_items`

Приведена в §3.2: равенство с `[]` краснеет вместе с проверкой типа — этим и доказано, что
проверка типа дублирует равенство по обнаружению (и потому оставлена с честным обоснованием,
а не как «единственная защита»).

### Проба D (сверх брифа). Правда о `{} == []`

Приведена в §3.1 (ошибка разбора на затипизированных операндах, рантайм-ошибка с обрывом
функции на нетипизированных, `Assert.eq({}, []) == false`).

---

## Решения, которых в брифе не было (или против буквы брифа)

1. **Проверка формы `texts` оставлена в `validate`, в `_check_texts` не продублирована** — это
   ровно то, что просил бриф («в `validate` до `_check_texts`»). Отличие только в том, что
   вызов `_check_texts` стоит в `else`: при неверном типе сверка не запускается вовсе, и
   второго диагноза (`MISSING_TEXT` на каждый ключ) не возникает. Это и есть «одна ошибка —
   одно следствие».
2. **`load_text` покрыт отдельным ассертом, а не только `load_mission`.** Бриф допускал любой
   из двух входов; проверены оба, потому что у `load_text(json_text: String, texts)` описка
   правдоподобнее всего, а общий путь `validate` до конца не доказывает, что загрузчик не
   подменяет аргумент по дороге.
3. **Проблемы кейса 12в добавлены в корпус нормы имён типов** (`test_content_validator.gd:983-985`).
   Сообщение нового диагноза — тоже `WRONG_TYPE` с именами типов, и оно обязано подчиняться
   норме (`словарь`/`строка`/`целое`/`логическое`). Без этого новое сообщение держалось бы
   только одним `contains("словарь")`.
4. **Пятый случай состава сделан в двух вариантах** (хвостовой дубль и дубль в середине):
   бриф требовал «три записи, из которых две с одним `id`» — это второй вариант; первый
   добавлен, потому что он дешевле читается.
5. **§3: выбран вариант (а)** — ассерт типа оставлен, обоснование переписано (см. §3.2).
6. **§4: числа проб исправлены указанием происхождения, а не переписыванием транскриптов.**
   Заменить `tests: 704` на `707` в выводе, который был снят на другом дереве, значило бы
   подделать доказательство; исправлено то, что было ложью, — утверждение «с финального
   дерева».
7. **Прогоны — в копии дерева в `%TEMP%`** (`git worktree` + `robocopy /MIR`, без `.godot`),
   а не в рабочей области: живого редактора пользователя это не касается, `.godot/` рабочей
   области не переписывается. В копии пришлось направить `APPDATA` в `%TEMP%` — иначе движок
   на каждой команде печатает `Failed to open 'user://logs/…'` (в песочнице `user://` не
   пишется). На вердикт это не влияет. После прогонов копия удалена, регистрация снята
   (`git worktree remove` не справился с перезаписанным `.git`, поэтому каталог удалён вручную
   и `git worktree prune`): `git worktree list` снова показывает только рабочий каталог,
   следов прогонов в рабочей области нет.

## Что заметил и не стал делать

* **`game/sim/**` — не тронут.** Граница названа: `sim.gd:93-102` по-прежнему кладёт каждую
  запись плана в `own`, а `_positions()` (`sim.gd:183-189`) перезаписывает ключ. После правки
  **любая** запись из `Loader.load_plan` несёт уникальный непустой `id`, поэтому этот путь
  достижим только для плана, собранного руками (фаза планирования, тесты, задача об
  эквивалентности трёх путей) — там дубли по-прежнему никто не проверяет. Это второй слой,
  вне области захода.
* **`load_plan` по-прежнему не возвращает `problems`** (решение C1 прошлого захода), поэтому
  отброшенный дубль `id` — отказ МОЛЧАЛИВЫЙ для вызывающего: в `Plan.agents` его просто нет.
  Громкий сигнал потребовал бы `problems` у плана — это отдельный контракт, не этот заход.
  Записано здесь, чтобы «молчаливо отброшено» не выглядело недосмотром.
* **`docs/**` — не тронуты** (область ведущего). Замечу для контракта: в документах нигде не
  сказано, что `agents` с дублем `id` теряет вторую запись, и нигде не названо третье
  состояние `texts`. Если это надо закрепить в постановке — правка `docs/` ваша.
* **`Problems.wrong_type` с путём `(тексты)`** — путь выбран по образцу `(корень)`: у
  аргумента нет места в файле контента, и «путь» здесь называет сам аргумент.
* **`game/tests/cases/test_handoff_skeleton.gd` — не менялся**: ни один из трёх пунктов к нему
  не относится. Его комментарий про пробу «подменить `_check_texts` пустышкой» остаётся
  верным: проверка формы `texts` стоит в `validate` и при неверном типе до `_check_texts` не
  доходит, поэтому пустышка сверки новые ассерты 12в не задевает. (Проба A снимает проверку
  типа, а не сверку, — это другой сценарий, и она это только подтверждает: ассерты 12в
  краснеют, а ассерты скелета — нет.)
* **Лишние скобки после правок** — проверено: проба токенизатором по всем четырём файлам +
  preflight. Один `})` вместо `])` был пойман и исправлен (см. Гейт).

## Открытые вопросы к ведущему

1. Нужно ли закрепить в постановке (`docs/handoff/.../02-format.md`, `docs/current/...`):
   (а) третье состояние второго аргумента `validate` — не-словарь это ошибка вызова, а не
   «текстов нет»; (б) правило «дубль `id` в `agents` отбрасывается, остаётся первая запись».
2. Считать ли молчаливую отбраковку дубля `id` достаточной (сегодня так, сообщения нет) или
   нужен громкий сигнал — это уже `problems` у `load_plan`, то есть отдельный контракт.

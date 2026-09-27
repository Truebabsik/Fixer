# Task 4 — Понимание: сложность приказа против понимания

**Статус:** DONE
**Ветка:** `p1-sim-core`
**Коммит:** `84b8cd3` feat(sim): понимание как детерминированная проверка сложности приказа

## Что реализовано

Одно чистое правило: исполнит ли боец приказ так, как задумано, или буквально.
Кубика нет — сравнение детерминировано, поэтому дешёвая команда предсказуемо
плоха, а не «слаба по статам».

- `game/sim/understanding.gd` — `extends RefCounted`, статический метод
  `resolves_literally(complexity: int, understanding: int) -> bool`, тело —
  `return complexity > understanding`. Код взят из брифа дословно.
- `game/tests/cases/test_understanding.gd` — таблица 12 комбинаций
  (Понимание 3/2/1/0 × сложность 1/2/3), 12 ассертов. Код из брифа дословно.
- `game/tests/run.gd` — путь кейса добавлен в явный `const CASES`
  (после `test_radio.gd`); порядок прогона остаётся фиксированным.

`class_name` не используется, только `preload`. Отступы — табы. `sim/` не
касается `Node`, `SceneTree`, сцен и рендеринга. Идентификаторы английские,
комментарии и имена ассертов русские.

Консьюмера у правила в этом плане нет и не заведено: найм специалистов с низким
Пониманием придёт в следующей фазе. Параметров «на будущее» не добавлялось.

## TDD: RED

Порядок, зафиксированный предыдущими задачами: сначала пишем кейс **и
регистрируем его в `CASES`**, потом гоним — иначе падение невидимо.

Команда:

```powershell
& "F:\WORK\Fixer\tools\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path "F:\WORK\Fixer\game" --script res://tests/run.gd; "код: $LASTEXITCODE"
```

Фактический вывод:

```
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

LOAD FAIL  res://tests/cases/test_understanding.gd
tests: 25, failed: 1
код: 1
[stderr]
ERROR: Failed to open 'user://logs/godot2026-09-27T00.06.42.log'.
   at: copy (core/io/dir_access.cpp:429)
ERROR: Failed to open log file for writing: user://logs/godot.log
   at: rotate_file (core/io/logger.cpp:169)
ERROR: Failed to read the root certificate store.
   at: get_system_ca_certificates (platform/windows/os_windows.cpp:2582)
SCRIPT ERROR: Parse Error: Preload file "res://sim/understanding.gd" does not exist.
   at: GDScript::reload (res://tests/cases/test_understanding.gd:6)
   GDScript backtrace (most recent call first):
       [0] _initialize (res://tests/run.gd:28)
SCRIPT ERROR: Parse Error: Cannot infer the type of "Understanding" constant because the value doesn't have a set type.
   at: GDScript::reload (res://tests/cases/test_understanding.gd:6)
   GDScript backtrace (most recent call first):
       [0] _initialize (res://tests/run.gd:28)
ERROR: Failed to load script "res://tests/cases/test_understanding.gd" with error "Parse error".
   at: load (modules/gdscript/gdscript_resource_format.cpp:46)
   GDScript backtrace (most recent call first):
       [0] _initialize (res://tests/run.gd:28)
```

Совпало с ожиданием брифа дословно: `LOAD FAIL  res://tests/cases/test_understanding.gd`,
`код: 1`.

**Почему это падение ожидалось.** Модуль `game/sim/understanding.gd` ещё не
существовал, поэтому `preload("res://sim/understanding.gd")` в кейсе не
разрешается, скрипт кейса не парсится, `load()` возвращает `null`, и раннер
честно печатает `LOAD FAIL` и считает это провалом. Отказ именно на этапе
**загрузки**, а не на ассертах, — и это ровно то, что бриф предсказал: тест
написан раньше реализации. Число `tests: 25` — ассерты трёх прежних кейсов
(`test_runner`, `test_scales`, `test_radio`); до 37 не хватает как раз 12
ассертов нового кейса, что подтверждает: падение вызвано отсутствием модуля, а
не сломанной таблицей. Ошибки в `stderr` про `user://logs` и корневые
сертификаты — фоновая среда, а не сигнал (вердикт — только код возврата).

## TDD: GREEN

После создания `game/sim/understanding.gd` та же команда:

```
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

tests: 37, failed: 0
код: 0
[stderr]
ERROR: Failed to open 'user://logs/godot2026-09-27T00.06.46.log'.
   at: copy (core/io/dir_access.cpp:429)
ERROR: Failed to open log file for writing: user://logs/godot.log
   at: rotate_file (core/io/logger.cpp:169)
ERROR: Failed to read the root certificate store.
   at: get_system_ca_certificates (platform/windows/os_windows.cpp:2582)
```

`failed: 0`, `код: 0` — как и ожидал бриф. 25 → 37 ассертов: добавились ровно
12 клеток таблицы. Ни одного `FAIL` и ни одного `LOAD FAIL`.

## Изменённые файлы

| Файл | Действие |
|---|---|
| `game/sim/understanding.gd` | создан (12 строк) |
| `game/tests/cases/test_understanding.gd` | создан (24 строки) |
| `game/tests/run.gd` | изменён (+1 строка: путь кейса в `CASES`) |

`git show --stat` коммита: 3 files changed, 37 insertions(+). Рабочее дерево
после коммита чистое (`git status --porcelain` пуст).

## Самопроверка

- **Дословность кода.** Из брифа извлечены оба ` ```gdscript `-блока, сравнены с
  файлами после нормализации переводов строк: `тест совпадает с брифом: True`,
  `модуль совпадает с брифом: True`. Ничего не переименовано, логика не
  добавлена, имена тестов не переформулированы.
- **Таблица — это и есть правило.** Строки таблицы (3/2/1/0) против столбцов
  (1/2/3) дают ровно `complexity > understanding` во всех 12 клетках. Сверено с
  канонической таблицей `docs/spr/mercs.md` §1, строка за строкой: Понимание 3 —
  «точно» везде; 2 — ошибка только на сложном; 1 — на среднем и сложном; 0 —
  везде. «Ошибка» в справочнике — это и есть буквальность, то есть `true`
  теста. Расхождений нет.
- **Порядок аргументов.** Тест зовёт `resolves_literally(complexity, understanding)`
  — совпадает с сигнатурой интерфейса из брифа (`complexity` первым). Перепутай
  я порядок, таблица была бы транспонирована и прогон бы покраснел; зелёный
  прогон это исключает.
- **Ссылки на решения.** Бриф в комментарии теста ссылается на D31, справочник —
  на D9. Проверено в `docs/desions.md`: обе записи существуют и говорят об
  одном и том же — D9 «"Понимание" — ключевая механика найма», D31 «Понимание —
  детерминированная проверка сложности приказа». Противоречия нет, комментарий
  брифа оставлен дословно.
- **Дисциплина слоя.** В `game/sim/understanding.gd` нет `Node`, `SceneTree`,
  сцен, рендеринга, `class_name`; тип — `RefCounted`.
- **Регистрация кейса.** Проверено, что добавленный путь синтаксически корректен и
  что кейс предъявляет непустой `Array` — иначе раннер счёл бы его провалом;
  фактически 12 ассертов.
- **Гигиена коммита.** Закоммичены ровно три файла, названные брифом; новый
  модуль использует `:=`-формы только там, где требует стиль (`var t := Assert.new()`),
  унарных `=` для объектов не появилось.

## Замечания и риски

1. **Правило не вызывается ниоткуда — это по замыслу.** У `resolves_literally`
   нет консьюмера в плане П1; найм специалистов с низким Пониманием приходит в
   следующей фазе. Риск не в коде, а в восприятии: мёртвого кода в проекте
   прибавилось, и следующий ревьюер может принять это за незавершённость.
   Это явное указание брифа, а не недоделка.
2. **Домен аргументов не валидируется.** `complexity` и `understanding` — любые
   `int`; значения вне 1..3 и 0..3 дают результат по тому же неравенству
   (например, отрицательная сложность — всегда «точно»). Бриф задаёт ровно одно
   выражение и запрещает добавлять логику, поэтому проверок диапазона нет.
   Если инвариант понадобится, его место — на стороне консьюмера, а не здесь.
3. **Число ассертов в прогоне выросло до 37.** Если в предыдущих задачах
   зафиксировано ожидание `25`, его надо обновить; сам раннер число не
   фиксирует и по-прежнему судит только по `failed`.
4. **Отчёт не входит в коммит задачи.** Бриф называет для коммита ровно три
   файла, и это соблюдено; сам этот отчёт оставлен незакоммиченным, чтобы не
   раздувать diff задачи.

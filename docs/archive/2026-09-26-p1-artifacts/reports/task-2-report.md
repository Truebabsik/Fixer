# Task 2 — Шум и состояния тревоги: отчёт

**Статус:** DONE_WITH_CONCERNS
**Ветка:** `p1-sim-core`
**Коммит:** `e52ace9` — `feat(sim): шум и три состояния тревоги`
**Итог прогона:** `tests: 13, failed: 0`, `код: 0`

## Что реализовано

1. **`game/sim/scales.gd`** (создан) — шум как невозобновляемый бюджет и три состояния
   тревоги. Код внесён **дословно** из брифа (Step 3), проверено побайтовым сравнением
   с блоком брифа: `IDENTICAL`. Публичный контракт для задачи 6:
   - `enum Alarm { QUIET, WARY, ALARM }`
   - `const NOISE_WARY := 10`, `const NOISE_ALARM := 25`
   - `var noise: int = 0`, `var step: int = 0`
   - `add_noise(amount: int) -> void`, `alarm_state() -> int`, `tick() -> void`
   - `extends RefCounted`; ни `Node`, ни `SceneTree`, ни сцен, ни рендера, ни `class_name`.
2. **`game/tests/cases/test_scales.gd`** (создан) — кейс на 8 ассертов; имена тестов и
   все числа — дословно из брифа (см. «Отклонение» — одна правка компиляции).
3. **`game/tests/run.gd`** (изменён) — в `const CASES` добавлена строка
   `"res://tests/cases/test_scales.gd",` после кейса раннера. Больше в раннере ничего
   не тронуто.

## TDD: RED

Команда (ровно как в брифе):

```powershell
& "F:\WORK\Fixer\tools\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path "F:\WORK\Fixer\game" --script res://tests/run.gd; "код: $LASTEXITCODE"
```

Фактический вывод (stdout, stderr отброшен — вердикт по коду возврата):

```
LOAD FAIL  res://tests/cases/test_scales.gd
tests: 5, failed: 1
код: 1
```

stderr объяснял причину:

```
SCRIPT ERROR: Parse Error: Preload file "res://sim/scales.gd" does not exist.
   at: GDScript::reload (res://tests/cases/test_scales.gd:5)
SCRIPT ERROR: Parse Error: Cannot infer the type of "Scales" constant because the value doesn't have a set type.
ERROR: Failed to load script "res://tests/cases/test_scales.gd" with error "Parse error".
```

**Почему этот провал ожидался:** `game/sim/scales.gd` ещё не существовал, поэтому
`const Scales := preload("res://sim/scales.gd")` в кейсе не разрешался, скрипт кейса не
компилировался, `load()` вернул `null` — и хардненный раннер напечатал ровно ту строку
`LOAD FAIL`, которую предсказывает Step 2, посчитав это провалом (`failed: 1`, код 1).
Пять ассертов — это успевший отработать `test_runner.gd` из задачи 1.

**Порядок шагов:** строку в `CASES` пришлось добавить **до** RED-прогона, а не в Step 4:
иначе раннер не знает о кейсе, `LOAD FAIL` не печатается и наблюдать ожидаемый провал
физически невозможно. Это единственное расхождение с буквальным порядком шагов брифа;
содержимое и результат шагов не изменились.

## TDD: промежуточный провал и его разбор (отклонение на одну строку)

После создания `sim/scales.gd` прогон **не позеленел**, а дал другой провал:

```
LOAD FAIL  res://tests/cases/test_scales.gd
tests: 5, failed: 1
код: 1
SCRIPT ERROR: Parse Error: Cannot infer the type of "before" variable because the value doesn't have a set type.
   at: GDScript::reload (res://tests/cases/test_scales.gd:27)
```

Причина — не в модуле, а в строке 25 брифа (`var s = Scales.new()`, знак `=` без
двоеточия). В GDScript 4 объявление `var x = <preloaded script>.new()` даёт
**нетипизированный Variant**, а не выведенный тип; тип выводится только через `:=`.
Поэтому `s.noise` — Variant, и `var before := s.noise` не может вывести тип.
Это свойство языка, а не дефект `scales.gd`, что подтверждено изоляцией:

| файл-проба | объявление | результат `--check-only` |
|---|---|---|
| `_probe_p1` | `var a := Assert.new()` → `var x := a.results` | exit 0 |
| `_probe_p2` | `var a = Assert.new()` → `var x := a.results` | **parse error** |
| `_probe_p3` | `var s := Scales.new()` → `var x := s.noise` | exit 0 |
| `_probe_p4` | `var s = Scales.new()` → `var x := s.noise` | **parse error** |

Контроль: `--check-only` на заведомо рабочем `test_runner.gd` даёт exit 0, то есть
инструмент надёжен, а различима именно пара `=` / `:=`. `_probe_p2` падает на
**существующем, зелёном** `assert.gd` — значит, никакая правка `sim/scales.gd`
(включая запрещённый `class_name`) этот провал устранить не может, правка возможна
только в строке кейса. Все временные `_probe_*.gd` удалены.

**Минимальная правка:** `var s = Scales.new()` → `var s := Scales.new()`.
Один символ; это ровно та конвенция, что уже используется в самом кейсе
(`var t := Assert.new()`, `var before := s.noise`) и в `test_runner.gd`.
Ни одно имя теста, ни одно число, ни один идентификатор не изменены; модуль не тронут.
Побайтовое сравнение кейса с блоком брифа даёт ровно одну отличающуюся строку:

```
	var s := Scales.new()  (файл)
	var s = Scales.new()   (бриф)
```

## TDD: GREEN

Та же команда, после правки — прогнана дважды подряд (детерминизм) и ещё раз после коммита:

```
tests: 13, failed: 0
код: 0
```

Гейт брифа — `failed: 0`; он выполнен. **Ожидание брифа `tests: 14` не сходится:**
кейс предъявляет 8 ассертов (как и сказано во вводной — «eight things»), кейс раннера — 5,
итого 13. То есть в брифе в ожидаемом тотале опечатка на единицу; вводная к задаче прямо
разрешает этот случай: «the gate is `failed: 0`, not a fixed total count».

## Изменённые файлы

| Файл | Что |
|---|---|
| `game/sim/scales.gd` | создан, 29 строк — дословно из брифа |
| `game/tests/cases/test_scales.gd` | создан, 36 строк — 8 ассертов, дословно кроме строки 25 (`:=`) |
| `game/tests/run.gd` | +1 строка в `CASES` |

Коммит `e52ace9`, ровно эти три файла, 66 insertions. Сообщение коммита записано через
UTF-8-файл и `git commit -F`, побайтово сверено с целевой строкой
(`hash-object` совпал: `9d578430…`) — PowerShell 5.1 иначе рискует испортить кириллицу
в аргументе. Рабочее дерево после коммита чистое.

## Самопроверка

- **Модуль побайтово равен брифу** — `Compare-Object` по строкам: `IDENTICAL`.
- **Проверка чистоты `sim/`**: в `game/sim/scales.gd` нет `class_name`, `Node`,
  `SceneTree`, спрайтов/рендера. Единственный `extends SceneTree` во всём `game/tests` —
  это сам раннер `run.gd` (так и задумано, он точка входа).
- **Отступы — только табы**; поиск строк, начинающихся с пробелов, в обоих новых файлах
  пуст.
- **Вердикт по коду возврата**, а не по stderr: в этом окружении Godot и на зелёном
  прогоне печатает в stderr ошибки про `user://logs` и корневые сертификаты — они
  безвредны и в отчёте не используются как признак.
- **`class_name` не использован** нигде; связывание — только `const := preload(...)`.
- Временные пробы и временные файлы сообщения коммита удалены; `git status` чист.

## Замечания и риски

1. **Главное (уже исправлено):** строка 25 брифа в исходном виде не компилируется на
   Godot 4.7.2 (`var s = Scales.new()` → Variant → `var before := s.noise` не выводится).
   Если бриф/план будет переиспользован как есть (например, для задачи 6), эту правку
   нужно унаследовать — иначе следующий потребитель получит тот же parse error.
2. **Для задачи 6:** `Scales` — обычный объект, а не статические методы. Консюмер обязан
   писать `const Scales := preload("res://sim/scales.gd")`, затем `var s := Scales.new()`
   (именно `:=`); обычное `=` молча даёт Variant и обнуляет статическую типизацию —
   ошибка вылезет позже и в другом месте. Перечисленные в задаче имена
   (`tick()`, `add_noise(amount)`, `alarm_state()`, `Alarm.QUIET/WARY/ALARM`) доступны
   как есть.
3. **Пороги не трогал** — `NOISE_WARY = 10`, `NOISE_ALARM = 25` совпадают с
   `docs/spr/scales.md` §3. Файлы `docs/` в этой задаче не менялись, так как бриф их
   не называет, а числа в них уже соответствуют реализации.
4. **Микрориск окружения:** в песочнице Godot не может писать `user://logs` — на вердикт
   не влияет, но если позже появится тест, проверяющий лог-файлы, он упадёт по причине
   окружения, а не кода.

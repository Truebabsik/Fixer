# Отчёт 14: правки по ревью 4 (четыре Minor)

Статус: **DONE**. Бриф — `docs/current/2026-09-27-mission-01-accept/briefs/14-review4-fixes.md`.
Источник находок — `reports/review-04.md` §8. Общая часть — `docs/agents/constraints.md`,
перечень классов дефектов — `docs/agents/review-checklist.md` (по нему проверял свой код сам, до отчёта).

Область работы соблюдена: изменены **четыре** файла — `game/content/validator.gd`,
`game/tests/cases/test_content_validator.gd`, `docs/handoff/2026-09-27-mission-01-v2/01-format.md`
(только §11.2), `docs/handoff/2026-09-27-mission-01-v2/07-self-check.md` (только строка 33).
`game/content/mission-01.json`, `game/content/texts.ru.json`, `kit/verifier/**`, `reports/**`,
остальные документы пакета, `docs/design.md`, `docs/architecture.md`, `docs/desions.md`, `README.md`
не открывались на запись. Редактор Godot не запускался, `.uid` не создавались, коммит не делался.
Файлов вне названных путей не создано; временные пробы жили в `%TEMP%` и удалены.

---

## 1. Что изменено

| Файл | Место | Что |
|---|---|---|
| `game/content/validator.gd` | 484–498 | комментарий-обоснование условия, `nodes_known`, `route_judgeable`; флаг снимается на `BAD_REF` узла маршрута |
| `game/content/validator.gd` | 509 | флаг снимается на разрыве соседней пары (`BAD_VALUE`) |
| `game/content/validator.gd` | 524–529 | комментарий о границе правила; условие замыкания стало `if route_judgeable and size >= 3 …` |
| `game/tests/cases/test_content_validator.gd` | 447–460 | кейс I6в: опечатка в узле трёхточечного маршрута — замыкание не судится |
| `game/tests/cases/test_content_validator.gd` | 462–474 | кейс I6в-2: узел не существует, но рёбра его «соединяют» — узловая половина флага |
| `game/tests/cases/test_content_validator.gd` | 476–493 | кейс I6г: сломанный раздел `edges` — `PATROL_ROUTE_OPEN` не выдан ни на одном из двух патрулей |
| `game/tests/cases/test_content_validator.gd` | 495–510 | кейс I6д: пустой раздел `nodes` — о маршруте не сказано ничего, диагноз ровно один |
| `game/tests/cases/test_content_validator.gd` | 1765–1788 | кейс 15з: ассерт фиксирует **всю** картину `floors = []`/`"этажи"`/`7`, а не только путь `floors` |
| `docs/handoff/2026-09-27-mission-01-v2/01-format.md` | 820–836 | §11.2: путь `MISSING_TEXT` — индексный; разведены индекс (сырой файл) и id (разобранная форма) |
| `docs/handoff/2026-09-27-mission-01-v2/07-self-check.md` | 33 | §2.3а: обоснование замыкания — «цикл в графе», охранник **телепортируется**, а не «не вернётся в начало» |

Числа диагностик в ожиданиях нигде не зафиксированы (ворота — `failed: 0`), число проверок выросло
само: 1251 → **1265** (+14 новых ассертов).

---

## 2. Как устроено решение

### 2.1 Условие, при котором судится замыкание

Замыкание судится тогда и только тогда, когда **о маршруте можно судить**:

1. раздел `nodes` — **непустой словарь** (`nodes_known`): если раздела нет, пуст или он не словарь,
   о существовании узлов маршрута судить нечем (ссылки `BAD_REF` в валидаторе гасятся ровно по этой
   причине, `not nodes.is_empty()` стоит во всех ссылочных проверках);
2. **каждый узел маршрута существует** — иначе на нём уже назван `BAD_REF`;
3. **каждая соседняя пара соединена ребром** — иначе на паре уже назван `BAD_VALUE`, и в том числе
   тогда, когда сам раздел `edges` не массив (тогда `_connected` не может ответить «да» ни на один
   вопрос, и о замыкании спрашивать нечего).

Почему именно оно: все три пункта — это ровно те входные данные, из которых правило замыкания
делает вывод. Пока хоть один из них недостоверен, вывод «разомкнута замыкающая пара» опирается на уже
названный дефект и становится **вторым следствием одной ошибки** — прямого запрета шапки
`validator.gd:9–11` и §15 спецификации. Формы, где корень уже назван, и что было раньше:

| Проба (боевой валидатор, фикстура `_good()`) | Было (условие прежнее) | Стало |
|---|---|---|
| C0: маршрут из трёх точек, замыкающее ребро **добавлено** | 0 диагнозов | 0 диагнозов |
| **C1: здоровый маршрут из трёх точек, замыкающего ребра нет** | **1** (`PATROL_ROUTE_OPEN patrols[0].route`) | **1** (`PATROL_ROUTE_OPEN patrols[0].route`) |
| C2: `route = entry, hall, нет_такого` (одна опечатка) | **3**: `BAD_REF` + `BAD_VALUE` + `PATROL_ROUTE_OPEN` | **2**: `BAD_REF` + `BAD_VALUE` |
| C3: то же на двухточечном маршруте (контроль неизменности) | 2: `BAD_REF` + `BAD_VALUE` | 2: `BAD_REF` + `BAD_VALUE` |
| C4: раздел `edges` не массив (`{}`), **два** патруля по три точки | **7**: `WRONG_TYPE edges` + по 2 `BAD_VALUE` **и по `PATROL_ROUTE_OPEN` на каждом патруле** | **5**: `WRONG_TYPE edges` + 4 `BAD_VALUE`, `PATROL_ROUTE_OPEN` — ни одного |
| C5: раздел `nodes` пуст (`{}`), маршрут разомкнут | **2**: `EMPTY_SECTION nodes` + `PATROL_ROUTE_OPEN` | **1**: `EMPTY_SECTION nodes` |
| C6: узел не существует, но рёбра его «соединяют» (опечатка и в рёбрах) | **3**: `BAD_REF edges[2].b` + `BAD_REF patrols[0].route` + `PATROL_ROUTE_OPEN` | **2**: `BAD_REF edges[2].b` + `BAD_REF patrols[0].route` |

Числа сняты дословно пробой `probe_14_cascade.gd` в копии дерева, дважды: на боевом валидаторе
(столбец «стало») и на валидаторе с прежним условием (`if size >= 3 …`, столбец «было»). Строки вывода:

```
########## AFTER (боевой валидатор с гейтом) ##########
SCENARIO C0_CLOSED_CONTROL problems=0
  ALL=[]
SCENARIO C1_OPEN_HEALTHY problems=1
  ALL=["PATROL_ROUTE_OPEN patrols[0].route"]
SCENARIO C2_BAD_REF_TRIPLE problems=2
  ALL=["BAD_REF patrols[0].route", "BAD_VALUE patrols[0].route"]
SCENARIO C3_BAD_REF_PAIR problems=2
  ALL=["BAD_REF patrols[0].route", "BAD_VALUE patrols[0].route"]
SCENARIO C4_EDGES_BROKEN problems=5
  ALL=["WRONG_TYPE edges", "BAD_VALUE patrols[0].route", "BAD_VALUE patrols[0].route", "BAD_VALUE patrols[1].route", "BAD_VALUE patrols[1].route"]
SCENARIO C5_NODES_EMPTY problems=1
  ALL=["EMPTY_SECTION nodes"]
SCENARIO C6_GHOST_NODE_CONNECTED problems=2
  ALL=["BAD_REF edges[2].b", "BAD_REF patrols[0].route"]
########## BEFORE (гейт снят: прежнее условие замыкания) ##########
SCENARIO C2_BAD_REF_TRIPLE problems=3
  ALL=["BAD_REF patrols[0].route", "BAD_VALUE patrols[0].route", "PATROL_ROUTE_OPEN patrols[0].route"]
SCENARIO C4_EDGES_BROKEN problems=7
  ALL=["WRONG_TYPE edges", "BAD_VALUE patrols[0].route", "BAD_VALUE patrols[0].route", "PATROL_ROUTE_OPEN patrols[0].route", "BAD_VALUE patrols[1].route", "BAD_VALUE patrols[1].route", "PATROL_ROUTE_OPEN patrols[1].route"]
SCENARIO C5_NODES_EMPTY problems=2
  ALL=["EMPTY_SECTION nodes", "PATROL_ROUTE_OPEN patrols[0].route"]
SCENARIO C6_GHOST_NODE_CONNECTED problems=3
  ALL=["BAD_REF edges[2].b", "BAD_REF patrols[0].route", "PATROL_ROUTE_OPEN patrols[0].route"]
```

Числа «было» для C2 и C4 совпали с пробой ревью (`review-04` §8, Minor 3: три диагноза на опечатку;
`PATROL_ROUTE_OPEN` на каждом патруле при сломанном `edges`), а C1 — с доказанным задачей 12: здоровый
маршрут с одним разрывом в цикле даёт **ровно один** `PATROL_ROUTE_OPEN` и до, и после правки.

**То же на реальном образце пакета** (кольцо `guard_3` из семи точек, `kit/example/`, проба
`probe_14_kit_open.gd`; это проба P4 из README §5 пакета):

```
--- intact validator ---
OK    probe_kit_open.gd :: образец без замыкающего ребра e_stair_2_0 — ровно один PATROL_ROUTE_OPEN
PROBE_KIT_OPEN problems=1 codes=["PATROL_ROUTE_OPEN patrols[2].route"]
OK    probe_kit_open.gd :: образец с ребром на месте — диагнозов нет
PROBE_KIT_INTACT problems=0 codes=[]
--- mutation: closure rule disabled (size >= 99) ---
FAIL  probe_kit_open.gd :: образец без замыкающего ребра e_stair_2_0 — ровно один PATROL_ROUTE_OPEN
      ожидалось: ["PATROL_ROUTE_OPEN patrols[2].route"]
      получено:  []
PROBE_KIT_OPEN problems=0 codes=[]
```

### 2.2 Правила-соседи задачи 12 (пункт A.4 брифа): каскада нет

Проверял пробой `probe_14_other_rules.gd` (боевой валидатор) — правок не потребовалось:

```
SCENARIO U1_UNLOCK_NODE_ENTERED problems=5 codes=["BAD_VALUE windows.w_door.options[0].effects", "BAD_VALUE windows.w_door.silence.good", "BAD_VALUE windows.w_door.silence.neutral", "BAD_VALUE windows.w_door.silence.bad", "BAD_VALUE windows.w_door.silence.safe"]
SCENARIO U2_UNLOCK_BROKEN_TRIGGER problems=1 codes=["BAD_VALUE windows.w_door.trigger.type"]
SCENARIO U3_UNLOCK_MISSING_TRIGGER problems=1 codes=["MISSING_FIELD windows.w_door.trigger"]
SCENARIO U4_UNKNOWN_CHANNEL problems=1 codes=["BAD_VALUE intel[0].channel"]
SCENARIO U5_CHANNEL_WRONG_TYPE problems=1 codes=["WRONG_TYPE intel[0].channel"]
SCENARIO U6_CHANNEL_MISSING problems=1 codes=["MISSING_FIELD intel[0].channel"]
SCENARIO U7_LIE_NOT_BOOL problems=1 codes=["WRONG_TYPE intel[0].entries[0].false"]
SCENARIO U8_AGENTS_ZERO_LIES problems=1 codes=["INTEL_LIE_COUNT intel.agents"]
```

* U2/U3: у испорченного (или отсутствующего) триггера диагноз **один** — про сам триггер; правило
  `unlock` вне молчания гасится сторожем `trigger_type == ""` (`_check_unlock_needs_door:898`).
  Сторож несущий, а не «проверка, которая не может сработать»: со снятым сторожем та же проба даёт
  **6** диагнозов — `BAD_VALUE` про сам триггер **плюс** пять следствий про `unlock`:
  `U2_UNLOCK_BROKEN_TRIGGER problems=6`, `U3_UNLOCK_MISSING_TRIGGER problems=6`.
* U4–U7: у канала ровно один диагноз на свой дефект; `INTEL_LIE_COUNT` судится только по известному
  каналу с честными пометками (`validator.gd:1155`, `1169`, `1234`). U8 — обратный контроль:
  у честного `agents` с нулём подброшенных счёт **срабатывает** (`INTEL_LIE_COUNT intel.agents`), то
  есть правило живо, а не заглушено.
* U1 — не каскад, а пять **разных** мест одного окна (вариант и четыре исхода молчания), в каждом
  свой `unlock`; путь диагноза у каждого свой.

### 2.3 Решение по `floors` (Minor 4): выбран исход (а) — ассерт фиксирует **все** диагнозы

**Решение:** не гасить `DANGLING_TEXT`, а закрепить полную картину ассертом.

**Почему не (б).** Каскад «испорченное поле-ключ → осиротевший текст» в проекте уже **осознанно
оставлен** и записан словами: §15 спецификации («Но не все следствия гасятся… Это не вторая ошибка:
чинить надо поле, а висячий ключ исчезнет сам») и комментарий `_check_text_key` (`validator.gd:1466–1477`:
«каскад здесь не гасится — гашение было бы отдельным правилом „одна ошибка — одно следствие“»).
`floors = []` — тот же класс: тексты **действительно** осиротели (ревью это и пишет: «Это не дефект
правила (тексты действительно осиротели)»), а не выдуманы проверкой. Гашение потребовало бы
**нового** правила и разошлось бы с уже принятым поведением у `name_key`/`facility_key`/`trace_key`,
закреплённым ассертами (15е, 15ж, 15и). Кроме того, гасить пришлось бы **выборочно по разделам**, а
форма той же болезни есть и у `nodes`: замер на сдаточном файле —

```
DELIVERY_FLOORS_ARRAY problems=8 dangling=7 floor_keys_in_texts=7
DELIVERY_NODES_ARRAY problems=29 room_dangling=28
```

то есть «какой раздел гасит свои подписи, а какой нет» — это отдельное решение по дизайну
диагностики, а не правка Minor 4 (названо ниже, в §6).

Дефект, который нашло ревью, был в **ассерте** («фиксирует половину картины»), поэтому и закрыт он
ассертом: для каждого из трёх не-словарей теперь проверяются **все** диагнозы — путь `floors`
(`WRONG_TYPE`), каждая подпись этажа (`DANGLING_TEXT` на `texts.floor.*`) и общее число
`1 + по одной подписи на этаж`. Ожидание посчитано руками (в фикстуре `_good_presented()` два этажа —
`-1` и `1`, значит 3), а не взято у валидатора: производное ожидание не поймало бы ни потерю, ни лишний
диагноз (`review-checklist.md` §2).

### 2.4 Формулировки в пакете (Minor 1 и Minor 2)

**`01-format.md` §11.2 (строки 820–836).** Пример пути `MISSING_TEXT` приведён к фактическому
(`windows[0].silence.bad_key` вместо `windows.w_archivist.silence.bad_key`) и добавлено объяснение
разницы: сверку ведёт обход **сырых данных**, поэтому по словарям путь идёт по ключу
(`nodes.hall1.name_key`, `floors.1.name_key`), а по массивам — по индексу
(`windows[0].silence.bad_key`, `access_points[0].text_key`); по id окна адресуют диагнозы, которые
идут по разобранной форме (`MISSING_FIELD`, `WRONG_TYPE`, правила окна: `windows.<id>.<поле>`).
Сказано прямо, что искать надо **тот** путь, который назван. Обе половины утверждения уже держатся
машинно: `test_content_validator.gd:993–995` (индексный путь `windows[0].silence.good_key`),
`:1569` (индексный `windows[0].text_key`), `:1001` (id-путь `windows.w_door.text_key`),
`:673` («путь проблемы окна — по id»), плюс `test_handoff_skeleton.gd` («удалён один ключ фикстуры —
путь на поле `*_key` (`windows.0.text_key`)»); доказательство — §4, пробы F и G.

**`07-self-check.md:33` (§2.3а).** Ложное обоснование «иначе охранник **не вернётся в начало**»
заменено на фактическое, совпадающее с §4.1/§16 спецификации и §14 леджера: маршрут охраны — цикл
**в графе**, рёбер охрана не смотрит вовсе, на разрыве не застревает, а телепортируется между
несоединёнными помещениями (позиция врёт сенсорам, окну `guard_in_sensor` и карте). Требование
самого пункта («последний узел соединён ребром с первым — да») не изменилось; изменилась причина.
Проверено пробой на ядре — §4, проба H.

---

## 3. Дословный вывод гейта (боевое дерево, финальная версия)

```
--- res://tests/preflight.gd EXIT=0 SCRIPT_ERROR=0
preflight: scripts: 33, failed: 0
--- res://tests/run.gd EXIT=0 SCRIPT_ERROR=0
tests: 1265, failed: 0
--- res://tests/run_red.gd EXIT=0 SCRIPT_ERROR=0
FAIL  red_path.gd :: нарочно неверный ассерт
red-path: tests: 2, failed: 1 (ожидаем failed > 0)
tests: 1265, failed: 0
```

Порядок команд — `preflight`, `run.gd`, `run_red.gd` (`constraints.md` §2). Вердикт — код возврата:
0/0/0. `SCRIPT ERROR` в stderr — **ноль** во всех трёх прогонах (считалось регуляркой по объединённому
потоку, а не на глаз). Шум stderr — четыре известные строки окружения (`user://logs/…`,
`Failed to read the root certificate store`), к вердикту отношения не имеет.

Приёмка брифа, остальные пункты:

| Пункт | Прогон | Итог |
|---|---|---|
| 2. `Validator` на `game/content/mission-01.json` — 0 проблем | `DELIVERY_VALIDATOR problems=0 codes=[]`; `DELIVERY_LOADER assembled=true load_problems=[]` | ✅ 0 проблем, миссия собирается |
| 3. Комплект пакета на своём образце | `ПРОБЛЕМ: 0` / `СОБРАНО: миссия «mission-example», помещений 14, рёбер 15, патрулей 3, сенсоров 3, окон 5, разведка 3, точек доступа 2` / `ВЕРДИКТ: проблем нет, миссия собрана (код 0)`; `KIT_EXIT=0 SCRIPT_ERROR=0` | ✅ код 0 |
| 3 (расхождение комплекта) | `game/content/validator.gd` = `1FCA76E4…`, `kit/verifier/content/validator.gd` = `6E3F894D…` — **DIFFER** | ожидаемо: боевой валидатор правлен, копию синхронизирует ведущий |
| 3 (образец через **боевой** валидатор) | `KIT_EXAMPLE_LIVE_VALIDATOR problems=0 codes=[]`, `KIT_EXAMPLE_LIVE_ASSEMBLED=true` | ✅ обещание README §2 истинно и для копии, и для боевого валидатора |
| `floors = []` на сдаточном файле (замер Minor 4) | `DELIVERY_FLOORS_ARRAY problems=8 dangling=7`; коды: `WRONG_TYPE floors` + `DANGLING_TEXT texts.floor.-1 … texts.floor.6` | 1 + 7 подписей — рост линейный по данным, все 7 — настоящие осиротевшие ключи |

`git status --porcelain` после работы: изменены только четыре файла этого задания
(`game/content/validator.gd`, `game/tests/cases/test_content_validator.gd`,
`docs/handoff/2026-09-27-mission-01-v2/01-format.md`,
`docs/handoff/2026-09-27-mission-01-v2/07-self-check.md`); новых файлов нет, `.uid` нет. Изменение
`docs/current/2026-09-27-mission-01-accept/summary.md` — **не моё** (его правил ведущий).

---

## 4. Доказательства: мутационные пробы

Копия дерева: `%TEMP%\fixer-14\tree` (`robocopy /E` без `.git`, `.superpowers`, `tools`, `.godot`;
`docs/` в копии есть — комплект пакета читает свои файлы). Базовая линия копии: `preflight 33/0` код 0,
`tests: 1265, failed: 0` код 0, `SCRIPT ERROR` ноль. Боевые `game/**` на запись не открывались:
после каждой пробы файл восстановлен из слепка, SHA сверен.

### Проба A1 — снят гейт замыкания (`if route_judgeable and size >= 3` → `if size >= 3`)

Одно место, `validator.gd:529`. Код 1, `SCRIPT_ERROR=0`, `tests: 1265, failed: 8`:

```
FAIL  test_content_validator.gd :: опечатка в узле маршрута — только BAD_REF и BAD_VALUE, замыкание не судится
FAIL  test_content_validator.gd :: узел маршрута не существует, хотя рёбра его «соединяют» — замыкание не судится
FAIL  test_content_validator.gd :: раздел edges не массив — PATROL_ROUTE_OPEN не выдан ни на одном патруле
FAIL  test_content_validator.gd :: раздел edges не массив — разрывы пар первого патруля названы по одному на пару
FAIL  test_content_validator.gd :: раздел edges не массив — разрывы пар второго патруля названы так же
FAIL  test_content_validator.gd :: раздел nodes пуст — PATROL_ROUTE_OPEN не выдан
FAIL  test_content_validator.gd :: раздел nodes пуст — о маршруте не сказано ничего
FAIL  test_content_validator.gd :: раздел nodes пуст — диагноз один, и он про сам раздел
```

### Проба A2 — снят флаг на узле (`route_judgeable = false` после `BAD_REF` удалён)

Одно место, `validator.gd:498`. Код 1, `SCRIPT_ERROR=0`, `tests: 1265, failed: 1`:

```
FAIL  test_content_validator.gd :: узел маршрута не существует, хотя рёбра его «соединяют» — замыкание не судится
```

Первая попытка этой пробы (на кейсе I6в) **не покраснела** — и это была ошибка пробы, а не кода:
в I6в несуществующий узел разрывает и соседнюю пару, поэтому флаг снимался вторым присваиванием.
Записываю прямо (`review-checklist.md` §2): кейс I6в-2 (узел, «соединённый» рёбрами) добавлен именно
затем, чтобы узловая половина условия имела свой краснеющий ассерт.

### Проба A3 — снят флаг на соседней паре (`route_judgeable = false` после `BAD_VALUE` удалён)

Одно место, `validator.gd:509`. Код 1, `SCRIPT_ERROR=0`, `tests: 1265, failed: 3`:

```
FAIL  test_content_validator.gd :: раздел edges не массив — PATROL_ROUTE_OPEN не выдан ни на одном патруле
FAIL  test_content_validator.gd :: раздел edges не массив — разрывы пар первого патруля названы по одному на пару
FAIL  test_content_validator.gd :: раздел edges не массив — разрывы пар второго патруля названы так же
```

### Проба A4 — узловая половина игнорируется (`var route_judgeable := nodes_known` → `:= true`)

Одно место, `validator.gd:494`. Код 1, `SCRIPT_ERROR=0`, `tests: 1265, failed: 3`:

```
FAIL  test_content_validator.gd :: раздел nodes пуст — PATROL_ROUTE_OPEN не выдан
FAIL  test_content_validator.gd :: раздел nodes пуст — о маршруте не сказано ничего
FAIL  test_content_validator.gd :: раздел nodes пуст — диагноз один, и он про сам раздел
```

### Проба B — правило замыкания **живо** (не сломано правкой)

Одно место, `validator.gd:529`: `size >= 3` → `size >= 99`. Код 1, `SCRIPT_ERROR=0`,
`tests: 1265, failed: 3`:

```
FAIL  test_content_validator.gd :: разомкнутый маршрут патруля — PATROL_ROUTE_OPEN на patrols[0].route
FAIL  test_content_validator.gd :: разомкнутый маршрут патруля — одна проблема на маршрут
FAIL  test_content_validator.gd :: разомкнутый маршрут — названы последняя и первая точки
```

Это те самые три ассерта задачи 12 (в том числе «ровно один `PATROL_ROUTE_OPEN` на здоровом маршруте»),
и они краснеют поимённо: правка не сделала правило недостижимым.

### Проба D — каскад `floors` погашен (альтернатива (б), которую я НЕ выбрал)

Одно место, `_check_texts`: перед `Problems.dangling_text` добавлено гашение ключей `floor.` при
не-словаре в `floors`. Код 1, `SCRIPT_ERROR=0`, `tests: 1265, failed: 6`:

```
FAIL  test_content_validator.gd :: floors = [] — каждая подпись этажа осталась без ссылки
FAIL  test_content_validator.gd :: floors = [] — диагнозов ровно 1 + по одному на подпись этажа
FAIL  test_content_validator.gd :: floors = этажи — каждая подпись этажа осталась без ссылки
FAIL  test_content_validator.gd :: floors = этажи — диагнозов ровно 1 + по одному на подпись этажа
FAIL  test_content_validator.gd :: floors = 7 — каждая подпись этажа осталась без ссылки
FAIL  test_content_validator.gd :: floors = 7 — диагнозов ровно 1 + по одному на подпись этажа
```

То есть новый ассерт ловит **обе** половины: и потерю диагноза, и «половину картины».

### Проба F — путь `MISSING_TEXT` индексный (утверждение §11.2 после правки)

Одно место, `_walk_text_keys`: `"%s[%d]"` → `"%s.%d"`. Код 1, `SCRIPT_ERROR=0`, `tests: 1265, failed: 4`:

```
FAIL  test_content_validator.gd :: нет текста у ключа качества — MISSING_TEXT на пути поля
FAIL  test_content_validator.gd :: нет window.w_door.text — путь на поле данных
FAIL  test_content_validator.gd :: нет window.w_door.text — сообщение называет ключ
FAIL  test_handoff_skeleton.gd :: удалён один ключ фикстуры — путь на поле *_key (windows.0.text_key)
```

То есть «индексный путь» — не описание в документе, а свойство, закреплённое тремя ассертами в двух
кейсах (включая кейс пакета наружу).

### Проба G — путь диагнозов окна по id (вторая половина §11.2)

Одно место, `_check_windows`: `var path := index_path if wid == index_path else "windows.%s" % wid`
→ `var path := index_path`. Код 1, `SCRIPT_ERROR=0`, `tests: 1265, failed: 4`:

```
FAIL  test_content_validator.gd :: неизвестный kind окна — одна проблема на поле
FAIL  test_content_validator.gd :: kind разошёлся с trigger.type — BAD_VALUE на kind
FAIL  test_content_validator.gd :: путь проблемы окна — по id
FAIL  test_content_validator.gd :: windows[].text_key числом — WRONG_TYPE на своём пути
```

### Проба H — «охранник телепортируется», а не «не вернётся в начало» (Minor 2)

Проба `probe_guard_cycle.gd` гоняет ядро на маршруте `a, b, c` с периодом 1, где ребра `c–a` в графе
**нет**. На целом ядре:

```
PROBE_GUARD_NODES=["a", "b", "c", "a"]
PROBE_EDGE_C_A_MISSING=true
PROBE_PATROL_LAST=c
probe: 1, failed: 0
```

Охранник возвращается к первой точке, хотя ребра между `c` и `a` не существует, — то есть «не вернётся
в начало» ложно, а «телепортируется между несоединёнными помещениями» истинно. Проба не вырождена:
одно место в `sim.gd` (`g.patrol_index = (g.patrol_index + 1) % g.patrol_route.size()` → «залипание»
на последнем узле) — и она краснеет **именованным** ассертом:

```
FAIL  probe_guard_cycle.gd :: охранник вернулся к первой точке, хотя ребра c-a нет: ядро рёбер не смотрит
      ожидалось: ["a", "b", "c", "a"]
      получено:  ["a", "b", "c", "c"]
```

`sim.gd` восстановлен, SHA `6139A9F8CB426589E5952632A163AA999F6A7530B740E1949AA1E1E34E159745`
(совпадает с SHA файла до проб). Вторую половину утверждения — «комплект назовёт `PATROL_ROUTE_OPEN`» —
держит проба B (со снятым правилом краснеет именованный ассерт) и проба `probe_14_kit_open.gd` на
реальном образце.

### Сводка проб

| # | Сломано (одно место) | Код | `tests: N, failed: M` | `SCRIPT ERROR` | Названные ассерты |
|---|---|---|---|---|---|
| A1 | `validator.gd:529` гейт снят | 1 | 1265 / 8 | 0 | 8 новых (I6в, I6в-2, I6г ×3, I6д ×3) |
| A2 | `validator.gd:498` флаг на узле снят | 1 | 1265 / 1 | 0 | I6в-2 |
| A3 | `validator.gd:509` флаг на паре снят | 1 | 1265 / 3 | 0 | I6г ×3 |
| A4 | `validator.gd:494` `route_judgeable := true` | 1 | 1265 / 3 | 0 | I6д ×3 |
| B | `validator.gd:529` `size >= 99` | 1 | 1265 / 3 | 0 | 3 ассерта замыкания задачи 12 |
| D | `_check_texts` гасит `floor.*` | 1 | 1265 / 6 | 0 | новые ассерты 15з ×6 |
| F | `_walk_text_keys` `[i]` → `.i` | 1 | 1265 / 4 | 0 | индексный путь ×3 + кейс скелета |
| G | `_check_windows` путь по id → индекс | 1 | 1265 / 4 | 0 | id-путь ×4 |
| H | `sim.gd` залипание охраны | 1 | проба: 1 / 1 | 0 | «охранник вернулся к первой точке…» |
| — | `_check_unlock_needs_door:898` сторож снят (`в наборе не гонялось`, только проба соседей) | — | проба U2/U3: 1 → 6 | 0 | проба `probe_14_other_rules.gd` (сторож несущий) |

Все 14 новых ассертов входят минимум в один список покрасневших по имени (A1 — 8, A2 — 1, A3 — 3,
A4 — 3, D — 6). Широких мутаций, теряющих ассерты, в этой волне нет: число проверок остаётся 1265,
`LOAD FAIL` не появлялся ни разу. Все пробы из этой таблицы, кроме H, сняты **на финальной версии**
боевого кода и теста (`tests: 1265`), а не на промежуточной. После каждой пробы файл восстановлен из
слепка, SHA совпал:
`validator.gd` `1FCA76E4CF6314DC83D37B4511A2DC3E49A7D3A40EBD8EF762E0DBFA55511759`,
`sim.gd` `6139A9F8…`, `test_content_validator.gd` `DABD7A93…`.

---

## 5. Решения вопреки брифу

Нет. Все четыре пункта выполнены буквально; в пункте D бриф прямо оставлял выбор из двух законных
исходов — выбран (а), обоснование в §2.3.

---

## 6. Что заметил и не стал делать

1. **§4.1 спецификации пакета не говорит про гейт замыкания.** После правки `PATROL_ROUTE_OPEN` не
   выдаётся, если маршрут уже назван дефектным (нет узла / разрыв пары / сломанный `edges`). Норма
   §4.1 («последняя точка обязана быть соединена ребром с первой») от этого не изменилась, и общий
   принцип §15 («проверки, зависящие от уже испорченного поля, пропускаются») это покрывает, — но
   прямой строки «замыкание судится только на целом маршруте» в §4.1 нет. Бриф ограничил меня §11.2,
   поэтому не правил; если ведущий захочет, это одна фраза рядом с §4.1:258–260.
2. **Один и тот же класс у `nodes` не закрыт ничем.** Замер на сдаточном файле: `nodes = []` даёт
   **29** диагнозов (`WRONG_TYPE nodes` + 28 `DANGLING_TEXT texts.room.*`). По той же логике, что
   Minor 4, это либо честная полная картина (тогда её стоило бы закрепить ассертом в кейсе доставки),
   либо каскад, пропорциональный числу помещений. Решение по `floors` я принял как (а) — «оставить
   как есть и закрепить», — и для `nodes` это означало бы то же самое; но закрепление на сдаточном
   файле живёт в `test_mission01_delivery.gd`, которого нет в моей области. Называю как открытый
   пункт для ведущего.
3. **Ассерт 15з закрепляет полную картину на фикстуре (3 диагноза), но не на сдаточном файле (8).**
   Число на поставке измерено (`DELIVERY_FLOORS_ARRAY problems=8 dangling=7`) и приведено в §3, однако
   автоматической проверки у него нет — по той же причине (файл вне области).
4. **`INTEL_LIE_COUNT` печатает путь `intel.agents`** — это пространство имён текстов, а не `intel[0]`,
   в отличие от соседних диагнозов канала (`BAD_VALUE intel[0].channel`). Проверял пробой U8; правило
   задачи 12, в область этой правки не входит, но внешний исполнитель может искать не там — тот же
   класс, что Minor 1.
5. **Копии комплекта `kit/verifier/**` теперь расходятся с боевыми** (`1FCA76E4…` против `6E3F894D…`) —
   синхронизирует ведущий. Прогон комплекта при этом зелёный (код 0, «ПРОБЛЕМ: 0, миссия собрана»), и
   образец проходит **боевой** валидатор без проблем: расхождение вердикта не даёт, но после
   пересинхронизации копия получит и гейт замыкания.

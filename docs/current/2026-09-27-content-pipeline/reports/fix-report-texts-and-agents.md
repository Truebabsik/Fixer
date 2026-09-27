# Отчёт: шестой заход — «молчаливый пропуск» в сверке текстов и в составе агентов

Исполнитель: субагент-исполнитель по брифу `fix-brief-texts-and-agents.md`.
Коммит не делался, `.uid` не создавались, `docs/**` не трогались,
`game/sim/sim.gd`, `game/sim/window.gd`, `game/sim/mission.gd`, `game/sim/plan.gd` не трогались.

## Итог

| Ворота | До захода | После захода | Код возврата |
|---|---|---|---|
| `preflight.gd` | `scripts: 30, failed: 0` | `preflight: scripts: 30, failed: 0` | 0 |
| `run.gd` | `tests: 696, failed: 0` | `tests: 707, failed: 0` | 0 |
| `run_red.gd` | код 0 | код 0 | 0 |

Рост на 11 проверок: +3 в новом кейсе семантики текстов (`test_content_validator.gd`),
+2 отрицательных контроля скелета (`test_handoff_skeleton.gd`), +6 в кейсе загрузчика
(+3 в четырёх случаях состава, +3 на пути отказа). Один вырожденный ассерт при этом снят
и заменён на точный (см. §B.3); 696 + 11 = 707.

Изменённые файлы:

| Файл | Что |
|---|---|
| `game/content/validator.gd` | `validate(data, texts)` — обязательный аргумент; `_check_texts` — семантика `null`/словарь |
| `game/content/loader.gd` | `load_text`/`load_mission` — обязательный `texts`; выбор прокидывается без подмены, включая путь отказа; `load_plan` — четыре случая состава |
| `game/tests/cases/test_content_validator.gd` | 108 мест вызова получили явный второй аргумент; положительные ассерты усилены словарём; новый кейс 12б |
| `game/tests/cases/test_content_loader.gd` | 8 мест вызова; четыре случая состава с точным результатом; путь отказа |
| `game/tests/cases/test_handoff_skeleton.gd` | комментарий фикстуры; два отрицательных контроля в 2a |

---

## A. `Validator.validate(data, texts)` — забыть тексты больше нельзя

### A.1. Что изменено

**`game/content/validator.gd`**

| Место | Было | Стало |
|---|---|---|
| `validator.gd:77-93` | шапка `problems = validate(mission_dict, texts ?= {})` | контракт: аргумент обязателен, `null` — отказ от сверки, словарь (в том числе пустой) — сверка |
| `validator.gd:94` | `static func validate(data, texts: Dictionary = {}) -> Array:` | `static func validate(data, texts) -> Array:` |
| `validator.gd:1022-1034` | `_check_texts(data, texts: Dictionary, ...)`; `if not texts.is_empty() and not texts.has(...)` | `_check_texts(data, texts, ...)`; `if texts == null: return`, дальше `if not texts.has(...)` |

Аннотация типа у `texts` снята (и у `validate`, и у `_check_texts`) **намеренно**: `null` —
законное значение, а `texts: Dictionary` отверг бы его на входе. Это записано в комментарии
рядом с подписью, чтобы следующий автор не «починил» аннотацию и не сломал семантику.

Нового кода проблемы «тексты не переданы» не заведено — как и требовал бриф: защита в том,
что вызов без второго аргумента не компилируется.

**`game/content/loader.gd`**

| Место | Было | Стало |
|---|---|---|
| `loader.gd:25` | `load_text(json_text: String, texts: Dictionary = {})` | `load_text(json_text: String, texts)` |
| `loader.gd:40` | `load_mission(data, texts: Dictionary = {})` | `load_mission(data, texts)` |
| `loader.gd:41` | `Validator.validate(data, texts)` | без изменений (прокид) |
| `loader.gd:43` | `{"mission": null, "texts": {}, ...}` при проблемах | `{"mission": null, "texts": _deep(texts), ...}` |
| `loader.gd:67`, `loader.gd:72` | `texts.duplicate(true)` в payload и в ответе | `_deep(texts)` — `duplicate()` на `null` уронил бы вызов рантаймом |
| `loader.gd:231-232` | `_fail(problem)` → `"texts": {}` | `_fail(problem, texts)` → `"texts": _deep(texts)` |

`_deep` (существующий хелпер: глубокая копия контейнера, иначе значение как есть) выбран
вместо нового кода — второй функции копирования в файле не появилось.

Пункт брифа «проверь, что `load_mission` прокидывает выбор дальше без искажения» дал две
находки, обе закрыты: (1) `duplicate(true)` на `null` — рантайм-сбой, замена на `_deep`;
(2) на **пути отказа** возвращался `{}`, то есть вызывающему, сказавшему «сверку не делаю»,
ответ сообщал «текстов нет» — та же тихая подмена, только на отказе.

### A.2. Семантика второго аргумента (проверено кейсом 12б)

| `texts` | Сверка ключей данных | `DANGLING_TEXT` |
|---|---|---|
| `null` | не выполняется | не выполняется |
| `{}` | выполняется: **каждый** ключ данных → `MISSING_TEXT` | нет ключей — нет висячих |
| полный словарь | выполняется | выполняется |

### A.3. Полный список обновлённых мест вызова

Аргумент проставлен **явно везде**; таблица ниже — все вызовы
`Validator.validate(...)` в `game/tests/cases/test_content_validator.gd` (112 вызовов;
108 получили второй аргумент в этом заходе, 4 уже были со словарём: строки 802, 806, 811, 816).

| строка | данные | texts | ассерт |
|---|---|---|---|
| 159 | `_good()` | `_texts_for(...)` | корректная миссия валидна |
| 162 | `[]` | `null` | корень не словарь |
| 170 | `m` | `null` | нет %s — MISSING_FIELD |
| 180 | `empty_section` | `null` | пустой %s допустим |
| 184 | `blank_title` | `null` | пустой title_key — BAD_VALUE |
| 192 | `bad_section` | `null` | раздел %s словарём — WRONG_TYPE |
| 196 | `empty` | `null` | пустой nodes — EMPTY_SECTION |
| 201 | `bad_nodes` | `null` | nodes не словарь — WRONG_TYPE |
| 205 | `bad_steps` | `null` | steps строкой — WRONG_TYPE |
| 209 | `bad_floor` | `null` | floor дробный — WRONG_TYPE |
| 214 | `unknown` | `null` | неизвестный ключ ребра |
| 218 | `noted` | `_texts_for(...)` | note разрешён |
| 225 | `noted_bad` | `null` | note %s — WRONG_TYPE |
| 230 | `dup` | `null` | дубль id патруля |
| 235 | `reserved` | `null` | patrols |
| 242 | `bad_kind` | `null` | неизвестный kind — BAD_VALUE |
| 246 | `zero_steps` | `null` | steps = 0 — BAD_VALUE |
| 250 | `neg_noise` | `null` | шум отрицательный — BAD_VALUE |
| 254 | `zero_period` | `null` | period = 0 — BAD_VALUE |
| 258 | `short_route` | `null` | патруль из одной точки — BAD_VALUE |
| 262 | `empty_sensor` | `null` | сенсор без помещений — BAD_VALUE |
| 266 | `loop_edge` | `null` | петля ребра — BAD_VALUE |
| 273 | `twin` | `null` | второе ребро между парой — BAD_VALUE |
| 280 | `twin_reversed` | `null` | второе ребро обратным порядком — BAD_VALUE |
| 285 | `broken_route` | `null` | patrols |
| 292 | `bad_edge` | `null` | ребро в пустоту — BAD_REF |
| 296 | `bad_objective` | `null` | цель в пустоту — BAD_REF |
| 300 | `bad_patrol` | `null` | патруль в пустоту — BAD_REF |
| 305 | `bad_window` | `null` | окно на несуществующее ребро — BAD_REF |
| 310 | `bad_point` | `null` | точка доступа в пустоту — BAD_REF |
| 317 | `bad_node_trigger` | `null` | windows.w_door.trigger.node |
| 324 | `bad_unlock_option` | `null` | windows.w_door.options[0].effects[0].edge |
| 331 | `bad_unlock_silence` | `null` | unlock в молчании «%s» на несуществующее ребро — BAD_REF |
| 340 | `bad_fallback` | `null` | windows.w_door.options[0].effects[0].fallback[0].edge |
| 346 | `cut` | `null` | цель недостижима — UNREACHABLE |
| 350 | `no_entry` | `null` | нет ни одного входа — UNREACHABLE |
| 364 | `reverse_cut` | `null` | objective |
| 371 | `no_silence` | `null` | окно без молчания — MISSING_SILENCE |
| 377 | `silence_option` | `null` | молчание как вариант — SILENCE_AS_OPTION |
| 383 | `partial` | `null` | молчание без %s — MISSING_SILENCE |
| 388 | `bad_complexity` | `null` | сложность вне 1–3 — BAD_VALUE |
| 393 | `dup_option` | `null` | дубль варианта — DUPLICATE_ID |
| 402 | `twin_options` | `null` | windows.w_door.options[1] |
| 414 | `reordered` | `_texts_for(...)` | разный порядок эффектов проходит |
| 416 | `reordered2` | `_texts_for(...)` | разный порядок эффектов проходит (зеркало) |
| 422 | `no_kind` | `null` | окно без kind — MISSING_FIELD |
| 427 | `bad_window_kind` | `null` | неизвестный kind окна — BAD_VALUE |
| 429 | `bad_window_kind` | `null` | windows.w_door.kind |
| 436 | `kind_mismatch` | `null` | windows |
| 456 | `bad_trigger` | `null` | неизвестный триггер — BAD_VALUE |
| 462 | `unlock_in_node_window` | `null` | unlock в молчании окна не про дверь — BAD_VALUE |
| 471 | `no_unlock_silence` | `null` | windows.w_door.silence |
| 476 | `no_unlock_silence` | `null` | запертое ребро без unlock в молчании — ровно одна проблема |
| 484 | `open_edge_window` | `null` | windows.w_door.trigger.edge |
| 487 | `open_edge_window` | `null` | окно на незапертом ребре — не UNWINNABLE_EDGE |
| 498 | `non_bool_locked` | `null` | edges |
| 508 | `honest_unlocked` | `null` | locked = false — WINDOW_ON_OPEN_EDGE, без WRONG_TYPE |
| 515 | `broken_edge_window` | `null` | битая ссылка окна на ребро — ровно одна проблема |
| 525 | `silence_missing_quality` | `null` | молчание без исхода safe и без unlock — только MISSING_SILENCE |
| 534 | `silence_single_object` | `null` | одиночный объект в молчании — только WRONG_TYPE, без UNWINNABLE |
| 542 | `unlock_only_in_safe` | `null` | unlock только в safe — миссия выполнима |
| 551 | `unlock_via_fallback` | `null` | unlock через fallback — миссия выполнима |
| 561 | `fallback_other_edge` | `null` | fallback на другое ребро — UNWINNABLE_EDGE |
| 569 | `one_message` | `null` | windows.w_door.silence |
| 574 | `node_window_without_unlock` | `null` | окно не про дверь без unlock проходит |
| 580 | `no_actions` | `null` | точка доступа без действий — EMPTY_SECTION |
| 585 | `no_actions_field` | `null` | access_points[0].actions |
| 591 | `no_steps` | `null` | access_points[0].actions[0].cost.steps |
| 596 | `neg_steps` | `null` | access_points[0].actions[0].cost.steps |
| 601 | `str_steps` | `null` | access_points[0].actions[0].cost.steps |
| 608 | `no_cost_field` | `null` | windows.w_door.options[0].cost.%s |
| 614 | `no_effects` | `null` | windows.w_door.options[0].effects |
| 619 | `empty_effects` | `_texts_for(...)` | пустой effects допустим |
| 626 | `no_effects_field` | `null` | windows |
| 640 | `no_option_cost` | `null` | windows.w_door.options[0].cost |
| 645 | `no_action_cost` | `null` | access_points[0].actions[0].cost |
| 650 | `no_action_complexity` | `null` | нет actions[].complexity — обещано целое |
| 659 | `no_fallback` | `null` | type |
| 675 | `empty_fallback` | `null` | fallback |
| 693 | `garbage_fallback` | `null` | windows.w_door.silence.good[0].fallback |
| 699 | `dict_type_effect` | `null` | windows.w_door.silence.good[0].type |
| 709 | `agents_ok` | `_texts_for(...)` | агентура с одной ложью проходит |
| 717 | `agents_none` | `null` | агентура без лжи — INTEL_LIE_COUNT |
| 728 | `agents_two` | `null` | агентура с двумя ложьями — INTEL_LIE_COUNT |
| 737 | `bad_patrol_ref` | `null` | разведка ссылается на несуществующий патруль — BAD_REF |
| 746 | `intel_bad_route` | `null` | intel[0].entries[0].route |
| 751 | `intel_bad_false` | `null` | intel[0].entries[0].false |
| 762 | `agents_bad_false` | `null` | не-bool `false` у агентуры — только WRONG_TYPE, без INTEL_LIE_COUNT |
| 768 | `intel_bad_count` | `null` | intel[0].entries[0].count |
| 777 | `ghost_route_unknown_node` | `_texts_for(...)` | маршрут призрака не сверяется с графом |
| 784 | `no_age` | `null` | intel[0].entries[0].age_hours |
| 790 | `neg_age` | `null` | intel[0].entries[0].age_hours |
| 795 | `neg_observed` | `null` | intel[0].observed_at |
| 802 | `_good()` | `intel_texts` | ключ intel.<канал>.<пометка> не висячий |
| 806 | `_good()` | `texts` | полный набор текстов проходит |
| 811 | `_good()` | `texts_missing` | нет ключа текста окна — MISSING_TEXT |
| 816 | `_good()` | `texts_extra` | висячий ключ текста — DANGLING_TEXT |
| 833 | `_good()` | `null` | texts = null — проблем про тексты нет |
| 841 | `_good()` | `{}` | texts = {} — MISSING_TEXT на каждый ключ данных (%d) |
| 859 | `empty_options` | `null` | windows.w_door.options |
| 871 | `dup_option_id` | `null` | повтор id варианта внутри окна — DUPLICATE_ID ровно одна |
| 881 | `neg_cost` | `null` | windows.w_door.options[0].cost.%s |
| 890 | `neg_value` | `null` | windows.w_door.silence.bad[0].value |
| 899 | `bad_effect_type` | `null` | windows.w_door.options[0].effects[0].type |
| 907 | `bad_trigger_type` | `null` | windows.w_door.trigger.type |
| 914 | `self_loop` | `null` | edges[0] |
| 922 | `route_gap` | `null` | patrols[0].route |
| 929 | `bad_intel_kind` | `null` | intel[0].entries[0].kind |
| 937 | `neg_observed_at` | `null` | intel[0].observed_at |
| 945 | `dup_window` | `null` | windows |
| 954 | `broken` | `null` | nodes |
| 959 | `norm_other` | `null` | windows |

**Почему `null` (99 мест; строки 162…959, кроме 833):** предмет каждого кейса — своё правило
(тип, ссылка, диапазон, каскад), а не тексты. Дикт здесь не «усилил» бы проверку, а сломал её:
`_good()` несёт шесть `*_key`, и словарь добавил бы `MISSING_TEXT` в списки, которые
сверяются **точно** (`t.eq(..., [Problems.WRONG_TYPE])`, `_codes_at(...) == [Problems.X]`).
Проба 4 (§Пробы) это доказывает: подмена `null` на «пустой словарь» краснит 14 кейсов
лишними `MISSING_TEXT` — то есть выбор `null` там не инерция, а условие точности ассертов.

**Почему словарь (7 мест):** положительные ассерты `is_empty()` — в них «проблем нет»
обязано включать и сверку ключей, иначе они ровно того класса, который закрывает заход:

| Строка | Данные | Предмет |
|---|---|---|
| 159 | `_good()` | «корректная миссия валидна» |
| 218 | `noted` | «note разрешён» |
| 414, 416 | `reordered`, `reordered2` | «разный порядок эффектов проходит» |
| 619 | `empty_effects` | «пустой effects допустим» |
| 709 | `agents_ok` | «агентура с одной ложью проходит» |
| 777 | `ghost_route_unknown_node` | «маршрут призрака не сверяется с графом» |

**Исключение — `null` в положительном ассерте (единственное, строки 180):** кейс
«пустой `patrols`/`sensors`/`windows`/`intel`/`access_points` допустим» опустошает раздел,
а опустошённый раздел **уносит с собой свои `*_key`**. Рукописная фикстура `_texts_for` там
стала бы висячей, и кейс краснел бы на `DANGLING_TEXT` про фикстуру, а не про пустой раздел
(проверено: первая редакция дала ровно два таких провала — «пустой windows допустим»,
«пустой access_points допустим»). Подставить туда словарь, собранный **из тех же данных**,
я не стал сознательно: он совпал бы по построению, то есть сверка выглядела бы включённой,
не умея ничего поймать, — это тот же дефект «выглядит успешным, ничего не проверив».
Обратное направление держит кейс 12.

**Адресные кейсы текстов (уже были со словарём):** 802 (`intel_texts`), 806 (`texts`,
полный набор — чисто), 811 (`texts_missing` — `MISSING_TEXT`), 816 (`texts_extra` —
`DANGLING_TEXT`). Новый кейс 12б (833 `null`, 841 `{}`) закрывает (а) и (б) брифа.

**`game/tests/cases/test_content_loader.gd` — 11 вызовов (все обновлены явно):**

| Строка | Данные | Передано | Почему |
|---|---|---|---|
| 97 | `fixture_data` | `_texts_for(...)` | эквивалентность фикстуре; словарь — часть груза миссии |
| 139 | `from_json` | `_texts_for(...)` | то же для JSON-чисел |
| 157 | строка JSON | `{"mission.j.title": …}` | у данных есть `title_key`; положительный ассерт «разобрана» не должен ничего пропускать |
| 163 | битый JSON | `null` | до валидатора вызов не доходит; сверять нечего — отказ назван в коде |
| 183 | `no_route` | `_texts_for(...)` | кейс проверяет «кроме объявленного дефекта чисто» |
| 191 | `no_route` | `null` | на пути отказа проверяется, что выбор не подменён |
| 196 | `no_objective` | `_texts_for(...)` | то же |
| 203, 208 | `bad_steps` | `_texts_for(...)` | то же |
| 218 | `bad_section` (5 разделов) | `_texts_for(bad_section)` | словарь берётся от **испорченного** словаря: подменённый раздел уносит свои ключи, иначе к дефекту добавился бы `DANGLING_TEXT` |
| 226 | `text_section` | `_texts_for(text_section)` | то же |

**`game/tests/cases/test_handoff_skeleton.gd` — 6 мест, все со словарём** (и были такими):
121 (`SKELETON_TEXTS` — положительный ассерт), 141 (`{}` — НОВЫЙ отрицательный контроль
«пустой словарь текстов — MISSING_TEXT на каждый ключ данных»), 151 (`gapped_texts` —
«удалён один ключ»), 170 и 172 (`extra_texts` — висячий ключ), 175 —
`Loader.load_mission(data, SKELETON_TEXTS)`.
Изменений подписи здесь не потребовалось, но добавлены два отрицательных контроля (строки
135-143) — §A.4 и проба 1. Прежняя редакция абзаца называла «5 мест» и пропускала 141, то
есть ровно тот новый контроль, ради которого заход и делался: числа приведены к факту
(седьмой заход).

### A.4. Невырожденность положительного ассерта скелета

Кейс 2a переписан. Прежний текст («`validate(data)` без текстов возвращает ровно `[]`»)
описывал умолчание, которого больше нет, а сам положительный ассерт
`t.eq("скелет без проблем валидатора", problems, [])` **не может** покраснеть от отключённой
сверки: отключение проверки умеет только убирать проблемы. Поэтому невырожденность сделана
парой: рядом стоят два отрицательных контроля, и оба краснеют на отключённой сверке.

1. `data_text_keys := Validator._collect_text_keys(data)`, затем
   `t.is_true("у скелета есть ключи текстов (найдено: %d)", size > 0)` (защита от вырождения
   самой проверки) и `t.eq("пустой словарь текстов — MISSING_TEXT на каждый ключ данных",
   _codes_of(Validator.validate(data, {})), [MISSING_TEXT × N])` — N берётся у валидатора,
   а не вписано константой (вписанное разошлось бы со скелетом при первом новом окне).
2. Старый контроль «из фикстуры убран один ключ → ровно `MISSING_TEXT` на путь `*_key`».

Приватная `_collect_text_keys` в тесте вызвана осознанно, как `Loader._items` в кейсе
загрузчика: публичную обёртку держали бы только ради теста. Это записано в комментарии.

---

## B. `load_plan`: `{"agents": []}` — «бойцов нет», а не состав по умолчанию

### B.1. Что изменено

| Место | Было | Стало |
|---|---|---|
| `loader.gd:138-141` | `var parsed_agents := _plan_agents(data.get("agents", [])); if not parsed_agents.is_empty(): plan.agents = parsed_agents` | `if data.has("agents") and typeof(data["agents"]) == TYPE_ARRAY: plan.agents = _plan_agents(data["agents"])` |
| `loader.gd:101-119` | политика «мусор в поле игнорируется» одной фразой | три различаемых случая (ниже) + названная цена |
| `loader.gd:145-157` | `_plan_agents`: «запись без id отбрасывается» | «отбрасывается **целиком**; подставить `""` нельзя — `Sim` пишет бойцов в один словарь `positions`»; и «пустой результат функция НЕ трактует — решение принимает `load_plan`» |

### B.2. Четыре случая — разбор

| Вход | Результат | Почему так |
|---|---|---|
| поля `agents` нет | умолчание `Plan` (kira+echo) | отсутствие утверждения про состав — не утверждение «бойцов нет» |
| `{"agents": "не массив"}` | умолчание `Plan` | мусор **в поле**: форма сломана, автор не сказал «вот бойцы». Это решение C1, и оно сохранено |
| `{"agents": []}` | `[]` | явный пустой список — **осмысленное значение** «бойцов нет»; прежний `if not parsed_agents.is_empty()` подменял его боевым составом |
| `{"agents": [{"role":"comms"}]}` (элемент без `id`) | `[]` | запись без строкового непустого `id` отбрасывается целиком (подстановка `""` недопустима: `Sim` пишет агентов в один словарь `positions`, пустой id столкнулся бы с другим таким же). Список объявлен явно, поэтому ответ — пустой состав, **а не умолчание**: иначе явный список молча подменялся бы боевым составом — та же тихая подмена, что и с `[]`, только на уровень глубже |
| `{"agents": [{...годная...}, {"role":"comms"}, ...]}` | только годные записи, порядок сохранён | поштучная отбраковка (проверено: `plan_junk_agents` → ровно `kira`) |

Решение по п.3 брифа («элемент без `id` — реши и обоснуй»): выбрана **поштучная отбраковка
записи**, а не отбраковка всего списка. Причина: годные соседи не должны теряться из-за
одного кривого элемента (терять бойца за чужую опечатку — та же тихая подмена, только
в другую сторону). Побочное следствие названо прямо: список из одних негодных записей даёт
пустой состав, о котором `Sim.setup` сегодня молчит (цикл по пустому списку не выполняется
ни разу) — это цена, и она записана в комментарии `load_plan`, а не замолчана.

### B.3. Проверки (точный результат, не «не пусто»)

`test_content_loader.gd:345-380`: (1) `t.eq(plan_empty_agents.agents, [])`;
(2) `t.eq(plan_no_agents.agents, Plan.new().agents)` + сверка id `["echo","kira"]` —
«два бойца» сравниваются с **умолчанием `Plan`**, а не с числом из кейса;
(3) `t.eq(plan_no_id_agent.agents, [])` и `t.eq(plan_no_valid_agents.agents, [])`;
(4) `t.eq(plan_full_agents.agents, [ {kira…}, {echo…} ])` — обе записи целиком.

Снят один вырожденный ассерт `t.is_true("состав по умолчанию — из умолчания Plan",
plan_no_agents.agents == Plan.new().agents)` — он заменён на `t.eq` по значению (та же
проверка, но с печатью расхождения). Итого в блоке состава пять ассертов стали восемью;
ещё +3 дал путь отказа (§A.1, п.2) — суммарно кейс загрузчика вырос на 6 проверок.

### B.4. Граница, которую надо записать (п. B.4 брифа)

`game/sim/sim.gd:93-98` (`for a in plan.agents: agent.id = String(a["id"]); … int(a.get(...))`)
**не тронут** — чужая область, проверенный код окон/ядра. После правок **любая** запись,
пришедшая из `Loader.load_plan`, гарантированно несёт непустой строковый `id` (без него запись
отбрасывается) и либо честное целое `understanding`, либо не несёт его вовсе (тогда умолчание
берёт ядро). Значит, путь `String(a["id"])` / `int(a.get(...))` достижим только для плана,
собранного **руками** (фаза планирования, тесты, задача об эквивалентности трёх путей), —
и там `[]`-подобные записи по-прежнему не проверяются никем. Это граница названа, а не
замолчана: она вне области захода.

---

## Гейт (дословно)

```
=== 1) PREFLIGHT ===
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

preflight: scripts: 30, failed: 0
EXIT=0
=== 2) RUN ===
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

tests: 707, failed: 0
EXIT=0
=== 3) RUN_RED ===
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

FAIL  red_path.gd :: нарочно неверный ассерт
      ожидалось: 2
      получено:  1
red-path: tests: 2, failed: 1 (ожидаем failed > 0)
tests: 707, failed: 0
EXIT=0
```

Вердикт — код возврата: preflight 0, run 0, run_red 0. Прогоны завершились сами
(сторож вердикта не срабатывал), каждый — за секунды.

Порядок соблюдён: массовая замена вызовов → **сначала preflight**, потом набор. Preflight
после замены: `scripts: 30, failed: 0`, код 0 (набор после неё тоже зелёный).

---

## Мутационные пробы (дословно)

Все пробы сделаны на зелёном дереве, каждая — с последующим откатом; после отката
`validator.gd` и `loader.gd` побайтово совпали с состоянием до проб (сверка SHA-256 с копией
в `%TEMP%`), финальный гейт прогнан заново и приведён выше.

**Числа проб приведены к факту (правка седьмого захода).** Пробы 1, 2a, 2c и 3 сняты на
дереве ДО добавления трёх ассертов пути отказа (§A.1, п.2), поэтому в них `tests: 704`, а не
707. Финальное дерево — 707 проверок; названы эти прогоны «с финального дерева» были
ошибочно. На выводы разница не влияет: красные ассерты те же (набор к тому моменту отличался
ровно тремя ассертами, которые эти пробы не задевают), но транскрипты 704 переписывать на 707
нельзя — это была бы подделка вывода. Ниже у каждой из четырёх проб это отмечено.

### Проба 1. `_check_texts` — пустышка (`return` первой строкой)

Дерево пробы: без +3 ассертов пути отказа → `tests: 704` (финальный гейт — 707).

Ожидание: краснеет кейс скелета, потому что его фикстура больше не сверяется.

```
FAIL  test_content_validator.gd :: нет ключа текста окна — MISSING_TEXT
      ожидалось: true
      получено:  false
FAIL  test_content_validator.gd :: висячий ключ текста — DANGLING_TEXT
      ожидалось: true
      получено:  false
FAIL  test_content_validator.gd :: texts = {} — MISSING_TEXT на каждый ключ данных (6)
      ожидалось: ["MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT"]
      получено:  []
FAIL  test_handoff_skeleton.gd :: пустой словарь текстов — MISSING_TEXT на каждый ключ данных
      ожидалось: ["MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT", "MISSING_TEXT"]
      получено:  []
FAIL  test_handoff_skeleton.gd :: удалён один ключ фикстуры — ровно MISSING_TEXT
      ожидалось: ["MISSING_TEXT"]
      получено:  []
FAIL  test_handoff_skeleton.gd :: удалён один ключ фикстуры — путь на поле *_key ((проблем нет))
      ожидалось: true
      получено:  false
FAIL  test_handoff_skeleton.gd :: лишний ключ текстов — DANGLING_TEXT
      ожидалось: true
      получено:  false
FAIL  test_handoff_skeleton.gd :: лишний ключ текстов — ровно один диагноз
      ожидалось: true
      получено:  false
tests: 704, failed: 8
EXIT=1
```

Важное наблюдение из этой же пробы: **положительный ассерт скелета
(`скелет без проблем валидатора`) в списке провалов ОТСУТСТВУЕТ** — он и на пустышке
зелёный. Это и есть прямое доказательство его вырожденности и того, что невырожденность
держит именно новый отрицательный контроль (строка `пустой словарь текстов — MISSING_TEXT
на каждый ключ данных`).

### Проба 2. Вернуть значение по умолчанию у `texts` (три шага)

**2a. `static func validate(data, texts = {})` — компилируется, набор зелёный:**
(дерево пробы: без +3 ассертов пути отказа → `tests: 704`; финальный гейт — 707)

```
preflight: scripts: 30, failed: 0
PREFLIGHT_EXIT=0
tests: 704, failed: 0
RUN_EXIT=0
```

Это ожидаемо и **не краснит**: все места вызова уже передают аргумент явно, а `{}` по новой
семантике означает «текстов нет», а не «пропустить». То есть опасным было не умолчание само
по себе, а его сочетание со старой семантикой `{}`.

**2c. При наличии умолчания убрать аргумент в одном месте (`Validator.validate([])`) —
снова зелено:** (дерево пробы: без +3 ассертов пути отказа → `tests: 704`; финальный гейт — 707)

```
preflight: scripts: 30, failed: 0
PREFLIGHT_EXIT=0
tests: 704, failed: 0
RUN_EXIT=0
```

Вот это — собственно дефект: **с умолчанием забытый аргумент не виден вообще**.

**2d. Умолчание убрано, забытый аргумент на месте — ворота разбора называют файл:**

```
SCRIPT ERROR: Parse Error: Too few arguments for "validate()" call. Expected at least 2 but received 1.
ERROR: Failed to load script "res://tests/cases/test_content_validator.gd" with error "Parse error".
LOAD FAIL  res://tests/cases/test_content_validator.gd
preflight: scripts: 30, failed: 1
PREFLIGHT_EXIT=1
```

Вывод: «забыть» стало невозможно — и это ловится **до** прогона, воротами, которые называют
файл. Умолчание снято именно ради этого шага.

### Проба 3. `{"agents": []}` снова даёт состав по умолчанию

Дерево пробы: без +3 ассертов пути отказа → `tests: 704` (финальный гейт — 707).

Возвращена прежняя логика `var parsed := …; if not parsed.is_empty(): plan.agents = parsed`.

```
FAIL  test_content_loader.gd :: agents = [] — ровно пустой состав
      ожидалось: []
      получено:  [{ "id": "kira", "role": "tactician", "understanding": 3 }, { "id": "echo", "role": "comms", "understanding": 3 }]
FAIL  test_content_loader.gd :: agents = [элемент без id] — запись отброшена, состав пуст
      ожидалось: []
      получено:  [{ "id": "kira", "role": "tactician", "understanding": 3 }, { "id": "echo", "role": "comms", "understanding": 3 }]
FAIL  test_content_loader.gd :: agents = [мусор, элемент без id] — годных нет, состав пуст (не умолчание)
      ожидалось: []
      получено:  [{ "id": "kira", "role": "tactician", "understanding": 3 }, { "id": "echo", "role": "comms", "understanding": 3 }]
tests: 704, failed: 3
RUN_EXIT=1
```

Краснеют ровно три именованных ассерта, и в выводе видно исходный дефект: «бойцов нет»
превращается в `kira`+`echo`.

### Проба 4. `null` перестаёт быть отказом (`texts == null` → `texts = {}`)

```
FAIL  test_content_validator.gd :: пустой patrols допустим
FAIL  test_content_validator.gd :: пустой sensors допустим
FAIL  test_content_validator.gd :: пустой windows допустим
FAIL  test_content_validator.gd :: пустой intel допустим
FAIL  test_content_validator.gd :: пустой access_points допустим
FAIL  test_content_validator.gd :: запертое ребро без unlock в молчании — ровно одна проблема
      ожидалось: ["UNWINNABLE_EDGE"]
      получено:  ["UNWINNABLE_EDGE", "MISSING_TEXT" × 6]
FAIL  test_content_validator.gd :: locked = да — ровно WRONG_TYPE, без каскада
      ожидалось: ["WRONG_TYPE"]
      получено:  ["WRONG_TYPE", "MISSING_TEXT" × 6]
FAIL  test_content_validator.gd :: locked = 1 — ровно WRONG_TYPE, без каскада
      ожидалось: ["WRONG_TYPE"]
      получено:  ["WRONG_TYPE", "MISSING_TEXT" × 6]
FAIL  test_content_validator.gd :: locked = false — WINDOW_ON_OPEN_EDGE, без WRONG_TYPE
      ожидалось: ["WINDOW_ON_OPEN_EDGE"]
      получено:  ["WINDOW_ON_OPEN_EDGE", "MISSING_TEXT" × 6]
FAIL  test_content_validator.gd :: битая ссылка окна на ребро — ровно одна проблема
      ожидалось: ["BAD_REF"]
      получено:  ["BAD_REF", "MISSING_TEXT" × 6]
FAIL  test_content_validator.gd :: молчание без исхода safe и без unlock — только MISSING_SILENCE
      ожидалось: ["MISSING_SILENCE"]
      получено:  ["MISSING_SILENCE", "MISSING_TEXT" × 6]
FAIL  test_content_validator.gd :: одиночный объект в молчании — только WRONG_TYPE, без UNWINNABLE
      ожидалось: ["WRONG_TYPE"]
      получено:  ["WRONG_TYPE", "MISSING_TEXT" × 6]
FAIL  test_content_validator.gd :: не-bool `false` у агентуры — только WRONG_TYPE, без INTEL_LIE_COUNT
      ожидалось: ["WRONG_TYPE"]
      получено:  ["WRONG_TYPE", "MISSING_TEXT" × 6]
FAIL  test_content_validator.gd :: texts = null — проблем про тексты нет
      ожидалось: []
      получено:  ["MISSING_TEXT" × 6]
FAIL  test_content_validator.gd :: повтор id окна — DUPLICATE_ID
      ожидалось: ["DUPLICATE_ID"]
      получено:  ["DUPLICATE_ID", "MISSING_TEXT" × 6]
tests: 704, failed: 15
RUN_EXIT=1
```

(В выводе движка каждый `MISSING_TEXT` напечатан отдельным элементом массива; здесь они
свёрнуты в `× 6` для читаемости, дословный вывод — в прогоне.)

Две вещи, которые эта проба доказывает: (1) `null`-ветка действительно проверяется —
ассерт `texts = null — проблем про тексты нет` краснеет; (2) все 99 `null`-мест стоят
по решению: преврати их в словарь — и 14 кейсов с точными списками кодов сломаются
о лишние `MISSING_TEXT`.

### Проба 5. Путь отказа снова возвращает `{}`

Возврат `{"mission": null, "texts": {}, ...}` в `load_mission`:

```
FAIL  test_content_loader.gd :: отказ валидатора: переданный словарь вернулся тем же
      ожидалось: { "mission.small.title": "ТЕКСТ", "window.w_locked_door.text": "ТЕКСТ", "window.w_locked_door.breach": "ТЕКСТ", "window.w_locked_door.pick": "ТЕКСТ", "window.w_locked_door.silence": "ТЕКСТ" }
      получено:  {  }
FAIL  test_content_loader.gd :: отказ валидатора: texts = null остался null
      ожидалось: <null>
      получено:  {  }
tests: 707, failed: 2
EXIT=1
```

---

## Решения, которых в брифе не было (и почему так)

1. **Снято умолчание и у `load_text`, не только у `load_mission`.** Бриф назвал
   `load_mission`; оставить `load_text(json_text, texts: Dictionary = {})` было нельзя:
   по новой семантике умолчание `{}` означало бы не «пропустить сверку», а «текстов нет»,
   и `load_text(json)` с любым `*_key` начал бы падать — то есть умолчание превратилось бы
   в ловушку. Все вызовы `load_text` (2) обновлены явно.
2. **Путь отказа `load_mission`/`_fail` тоже возвращает выбор вызывающего** (`_deep(texts)`
   вместо `{}`). Это прямое следствие пункта брифа «прокидывает выбор дальше без искажения»
   и той же дисциплины «ответ не подменяет выбор». Покрыто двумя ассертами (проба 5).
3. **Положительные ассерты `test_content_validator.gd` получили словарь (7 мест), а не `null`.**
   Формально бриф делил места на «тексты не проверяются → `null`» и «проверяются → словарь»,
   и эти 7 мест — про другие правила. Но ассерт «проблем нет» — это утверждение про **весь**
   список проблем, и без сверки ключей он вырожден ровно как ассерт скелета. Выбор `null`
   там был бы честным, но слабым; словарь делает проверку сильнее без потери предмета
   (мутации этих кейсов не трогают `*_key` — проверено прогоном).
4. **Исключение из п.3 — пустые разделы (строка 180).** Единственное место, где `null`
   стоит в положительном ассерте: мутация уносит `*_key` из данных. Обоснование — в §A.3.
5. **Невырожденность положительного ассерта скелета сделана парой с отрицательным
   контролем, а не изменением самого ассерта.** Ассерт `problems == []` физически не может
   покраснеть от отключённой проверки (отключение только убирает проблемы) — поэтому
   требование брифа «он обязан краснеть, если сверку отключить» выполнено так: рядом стоит
   `t.eq`, который на пустышке краснеет (проба 1 показывает оба факта сразу: контроль
   красный, положительный ассерт в провалах отсутствует).
6. **Приватная `Validator._collect_text_keys` вызвана из двух тестов** — вместо копии обхода
   `*_key` в тестовом файле (DRY) и вместо вписанного числа (оно разошлось бы с данными).
   Прецедент — `Loader._items` в кейсе загрузчика, там это уже записано.
7. **Поштучная отбраковка записи агента вынесена в `_plan_agents`, а решение «список объявлен
   явно ⇒ он и есть ответ» оставлено в `load_plan`.** Так `_plan_agents` не знает про умолчание
   и не может молча вернуть боевой состав; если решение перенести внутрь — разница между `[]`
   и мусором в поле сотрётся. Записано в доке обеих функций.

## Что заметил и не стал делать

- **`game/sim/sim.gd:93-98`** — не тронут (область ядра окон/`Sim`); граница названа в §B.4.
- **`game/sim/plan.gd`** — не тронут: бриф разрешал правку «только если указано», а правка
  не нужна. Умолчание `Plan.agents` (kira+echo) остаётся законным источником «утверждения
  о составе нет»; политика четырёх случаев живёт в `load_plan`, где решение и принимается.
  Комментарий в `plan.gd` был бы вторым местом описания одного правила.
- **`docs/**`** — не тронуты (область ведущего). Проверил: старое умолчание `texts ?= {}` и
  семантика пустого словаря в документации нигде не зафиксированы (grep по `docs/`:
  `validate(...texts)`, `Dictionary = {}`, «пустом словаре» — совпадений по существу нет),
  поэтому расхождения «док ↔ код» этот заход не создал. Если контракт `null` / `{}` надо
  закрепить в постановке — это правка `docs/`, то есть ваша.
- **`score`/`problems` у плана** — `load_plan` по-прежнему не возвращает `problems`
  (решено ранее, C1); цена названа в доке (`мусор в route`/`exit_node`/`agents` молчит).
  Менять контракт `load_plan` в этом заходе не стал: это отдельная задача об эквивалентности
  трёх путей, и она упомянута в брифе как второй слой.
- **`understanding` в записи агента** — поведение не менялось (негодное значение не доезжает,
  остаётся умолчание `Plan`); заметил, что соседний абзац доки `_plan_agents` раньше
  противоречил коду (запись без `id` уже отбрасывалась), — док приведён в согласие с кодом.
- **Лишние `)` после массовой замены** — проверено специально (прошлый заход на этом
  попадался): preflight назвал бы файл; `scripts: 30, failed: 0`. Массовая замена делалась
  только по вызовам `Validator.validate(...)` с явным шаблоном, не по скобкам.

## Открытые вопросы к ведущему

1. Нужно ли закрепить контракт «`null` — отказ, `{}` — текстов нет» в постановке
   (`docs/handoff/.../02-format.md` §3, `docs/current/...`) — область `docs/`.
2. Считать ли `{"agents": [одни негодные записи]}` пустым составом **без сообщения**
   (сегодня так) или требовать громкого сигнала — второй слой (`problems` у плана) не в этом
   заходе.

extends RefCounted
## Прогон сценариев и детерминизм: один вход — один исход.

const Assert := preload("res://tests/assert.gd")
const Fixture := preload("res://tests/fixtures/small_mission.gd")
const Plan := preload("res://sim/plan.gd")
const Harness := preload("res://sim/harness.gd")
const Sim := preload("res://sim/sim.gd")


func _plan(route: Array):
	var p := Plan.new()
	p.route = route
	p.exit_node = "dock"
	p.agents = [
		{"id": "kira", "role": "tactician", "understanding": 3},
		{"id": "echo", "role": "comms", "understanding": 3},
	]
	return p


func run() -> Array:
	var t := Assert.new()
	var route := ["dock", "hall", "office2", "vault"]

	# ВАЖНО: миссию можно строить один раз на много прогонов. Состояние открытых
	# дверей живёт в Sim (`unlocked`), а Mission — неизменяемые данные: `_unlock`
	# больше НЕ пишет в `mission.edge(...)`. Пока он писал, переиспользованный
	# объект миссии был другим входом, и подбор гипотез по одной миссии врал.

	# 1. Прогон даёт полный отчёт.
	var r: Dictionary = Harness.run_scenario(Fixture.build(), _plan(route), ["breach"], {"seed": 5})
	for key in ["outcome", "steps", "objective_done", "orders_left", "noise", "radio", "imprint", "alarm", "injured", "dead", "positions", "digest"]:
		t.is_true("в отчёте есть %s" % key, r.has(key))
	t.eq("приказ потрачен", r["orders_left"], 2)
	# Эфир затухает: к концу миссии он успевает остыть. Несмываемое свидетельство
	# передачи — отпечаток (D33), по нему и сверяем факт передачи.
	t.eq("передача была одна", r["imprint"], 1)
	t.is_true("эфир успел остыть", int(r["radio"]) < 8)

	# 2. Детерминизм: тот же вход — тот же отпечаток.
	var again: Dictionary = Harness.run_scenario(Fixture.build(), _plan(route), ["breach"], {"seed": 5})
	t.eq("повтор совпал", again["digest"], r["digest"])

	# 2б. Проводка seed закреплена ПОЛНЫМ отпечатком, а не только равенством
	# двух прогонов: раньше ни одна проверка не связывала seed с исходом, и ключ
	# `seed` можно было игнорировать, оставшись зелёным. Отпечаток снят с рабочего
	# кода; меняться он может только вместе с изменением баланса.
	var pinned: Dictionary = Harness.run_scenario(Fixture.build(), _plan(route), ["breach"], {"seed": 5})
	t.eq(
		"отпечаток seed=5 закреплён",
		String(pinned["digest"]),
		"outcome=caught|steps=17|objective_done=false|orders_left=2|noise=44|radio=0|imprint=1|alarm=2|injured=[\"kira\", \"echo\"]|dead=[]|positions={ \"kira\": \"vault\", \"echo\": \"vault\", \"guard_1\": \"hall\" }"
	)

	# 2в. Сам seed виден в исходе: кубик импровизации обязан читать именно его.
	# Молчание со связистом — единственное место с кубиком (D7); на seed 4 выпало
	# «плохо» (импровизация стоила 5 шума), на seed 7 — «нейтрально». Разные seed
	# обязаны давать разные отпечатки, иначе ключ не подключён.
	var seed4: Dictionary = Harness.run_scenario(Fixture.build(), _plan(route), ["silence"], {"seed": 4})
	var seed7: Dictionary = Harness.run_scenario(Fixture.build(), _plan(route), ["silence"], {"seed": 7})
	t.is_true("разные seed — разные исходы", seed4["digest"] != seed7["digest"])
	t.eq("seed 4 — дорогая импровизация", int(seed4["noise"]) - int(seed7["noise"]), 5)

	# 3. Другой сценарий — другой исход (иначе сценарий ни на что не влияет).
	var silent: Dictionary = Harness.run_scenario(Fixture.build(), _plan(route), ["silence"], {"seed": 5})
	t.is_true("молчание отличается от приказа", silent["digest"] != r["digest"])
	t.eq("молчание не тратит приказы", silent["orders_left"], 3)
	t.eq("молчание не шумит в эфире", silent["radio"], 0)
	t.eq("молчание не оставляет отпечатка", silent["imprint"], 0)

	# 4. Короткий сценарий: кончились ответы — дальше игрок молчит.
	# Маршрут намеренно упирается в запертую дверь: иначе окно не открылось бы
	# ни разу, и главное поведение модуля («сценарий кончился — игрок молчит»)
	# не выполнилось бы ни разу во всём наборе. Проверяем и сам факт молчания,
	# и то, что оно действительно открыло дверь.
	var short_mission = Fixture.build()
	var short_box := RefCounted.new()
	var short: Dictionary = Harness.run_scenario(short_mission, _plan(route), [], {"seed": 5}, short_box)
	var short_sim = short_box.get_meta("sim")
	t.is_true("исход есть", String(short["outcome"]) != "")
	t.is_true("молчание сработало на окне", bool(short_sim.unlocked.get("e_office_vault", false)))
	t.is_true("миссия не тронута молчанием", bool(short_mission.edge("e_office_vault")["locked"]))
	# Молчание — и есть поведение по умолчанию: явный `silence` в сценарии даёт
	# тот же отпечаток, что и кончившийся сценарий.
	var explicit_silence: Dictionary = Harness.run_scenario(Fixture.build(), _plan(route), ["silence"], {"seed": 5})
	t.eq("пустой сценарий равен явному молчанию", short["digest"], explicit_silence["digest"])

	# 5. Тревога и уход из подвала воспроизводятся через харнесс.
	var run_away: Dictionary = Harness.run_scenario(
		Fixture.build(), _plan(["dock", "archive0"]), [], {"seed": 5, "noise_start": 25}
	)
	t.eq("ушли из подвала", String(run_away["outcome"]), "extracted")
	t.is_true("цель взята", run_away["objective_done"])

	# 6. Импровизация связиста тоже детерминирована через харнесс.
	var crew := ["dock", "hall", "office2", "vault"]
	var i1: Dictionary = Harness.run_scenario(Fixture.build(), _plan(crew), ["silence"], {"seed": 99})
	var i2: Dictionary = Harness.run_scenario(Fixture.build(), _plan(crew), ["silence"], {"seed": 99})
	t.eq("импровизация воспроизводима", i1["digest"], i2["digest"])

	# 7. Два прогона по ОДНОМУ И ТОМУ ЖЕ объекту миссии дают один отпечаток.
	# Это и есть проверка иммутабельности входа: раньше первый прогон открывал
	# дверь прямо в миссии, второй шёл через уже открытую дверь и получал другой
	# исход. Балансировочный приём «загрузить миссию один раз и гонять по ней
	# гипотезы» на такой модели молча врал.
	var shared = Fixture.build()
	var shared_1: Dictionary = Harness.run_scenario(shared, _plan(route), ["breach"], {"seed": 5})
	var shared_2: Dictionary = Harness.run_scenario(shared, _plan(route), ["breach"], {"seed": 5})
	t.eq("повтор по той же миссии совпал", shared_2["digest"], shared_1["digest"])
	t.is_true("дверь в миссии осталась заперта", bool(shared.edge("e_office_vault")["locked"]))

	# 8. Неверный вход падает громко, а не притворяется caught/timeout.
	# Разорванный маршрут — самая частая опечатка в данных плана.
	# Здесь Sim собирается напрямую: событие invalid_mission видно только в
	# списке событий, а харнесс отдаёт отчёт без него.
	var broken_mission = Fixture.build()
	var broken_sim := Sim.new()
	broken_sim.setup(broken_mission, _plan(["dock", "it4"]), {"seed": 5})
	t.is_true("неверный вход — миссия сразу окончена", broken_sim.finished)
	t.eq("неверный вход — исход invalid_mission", broken_sim.outcome, "invalid_mission")
	t.is_true("проверка назвала разрыв маршрута", _has_invalid(broken_sim, "между dock и it4 нет ребра"))
	t.eq("неверный вход не выдаёт отчёт как прогон", broken_sim.advance().size(), 0)

	# ...и то же с неверной миссией: цели нет в графе.
	var goal_mission = Fixture.build()
	goal_mission.objective = "nope"
	var bad_goal: Dictionary = Harness.run_scenario(goal_mission, _plan(route), [], {"seed": 5})
	t.eq("битая миссия — invalid_mission", String(bad_goal["outcome"]), "invalid_mission")

	# ...и третий вход: пустой маршрут — тоже неверный вход, а не тихий исход.
	var empty_route: Dictionary = Harness.run_scenario(Fixture.build(), _plan([]), [], {"seed": 5})
	t.eq("пустой маршрут — invalid_mission", String(empty_route["outcome"]), "invalid_mission")

	return t.results


## Есть ли среди событий `invalid_mission`, называющее именно эту проблему.
func _has_invalid(sim, needle: String) -> bool:
	for e in sim.events:
		if String(e["type"]) != "invalid_mission":
			continue
		for p in e["data"]["problems"]:
			if String(p).contains(needle):
				return true
	return false

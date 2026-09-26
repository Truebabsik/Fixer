extends RefCounted
## Прогон сценариев и детерминизм: один вход — один исход.

const Assert := preload("res://tests/assert.gd")
const Fixture := preload("res://tests/fixtures/small_mission.gd")
const Plan := preload("res://sim/plan.gd")
const Harness := preload("res://sim/harness.gd")


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

	# ВАЖНО: миссию строим заново на каждый прогон. `_unlock` правит миссию
	# НА МЕСТЕ, поэтому переиспользованный объект — это уже другой вход: второй
	# прогон увидел бы дверь открытой, не дошёл бы до окна и получил бы другой исход.

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

	# 3. Другой сценарий — другой исход (иначе сценарий ни на что не влияет).
	var silent: Dictionary = Harness.run_scenario(Fixture.build(), _plan(route), ["silence"], {"seed": 5})
	t.is_true("молчание отличается от приказа", silent["digest"] != r["digest"])
	t.eq("молчание не тратит приказы", silent["orders_left"], 3)
	t.eq("молчание не шумит в эфире", silent["radio"], 0)
	t.eq("молчание не оставляет отпечатка", silent["imprint"], 0)

	# 4. Короткий сценарий: кончились ответы — дальше игрок молчит.
	var short: Dictionary = Harness.run_scenario(Fixture.build(), _plan(["dock"]), [], {"seed": 5})
	t.is_true("исход есть", String(short["outcome"]) != "")

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

	return t.results

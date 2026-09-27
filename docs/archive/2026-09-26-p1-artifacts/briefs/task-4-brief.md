### Task 4: Понимание — сложность приказа против понимания

**Files:**
- Create: `game/sim/understanding.gd`
- Create: `game/tests/cases/test_understanding.gd`
- Modify: `game/tests/run.gd`

**Interfaces:**
- Consumes: ничего.
- Produces: `Understanding` — статический метод `resolves_literally(complexity: int, understanding: int) -> bool`.

- [ ] **Step 1: Написать падающий тест `game/tests/cases/test_understanding.gd`**

```gdscript
extends RefCounted
## Понимание — детерминированная проверка, без кубика (D31).
## Таблица — docs/spr/mercs.md §1.

const Assert := preload("res://tests/assert.gd")
const Understanding := preload("res://sim/understanding.gd")


func run() -> Array:
	var t := Assert.new()
	# Строки — Понимание 3/2/1/0, столбцы — сложность 1/2/3.
	var table := [
		[false, false, false],  # понимание 3: всё точно
		[false, false, true],   # понимание 2: сложный приказ — буквально
		[false, true, true],    # понимание 1: средний и сложный — буквально
		[true, true, true],     # понимание 0: даже простой — буквально
	]
	for u in 4:
		var understanding := 3 - u
		for c in 3:
			var complexity := c + 1
			var name := "понимание %d, сложность %d" % [understanding, complexity]
			t.eq(name, Understanding.resolves_literally(complexity, understanding), table[u][c])
	return t.results
```

- [ ] **Step 2: Прогнать — ожидаем провал**

Expected: `LOAD FAIL  res://tests/cases/test_understanding.gd`, `код: 1`.

- [ ] **Step 3: Написать `game/sim/understanding.gd`**

```gdscript
extends RefCounted
## Понимание: исполнит ли боец приказ так, как задумано, или буквально.
##
## Буквальность — это НЕ провал, а окно: исполнил ровно сказанное и создал
## новую проблему. Кубика здесь нет — сравнение детерминировано (D31),
## поэтому дешёвая команда предсказуемо плоха, а не «слаба по статам».
## Таблица — docs/spr/mercs.md §1.


## complexity 1..3 — число условий в приказе, understanding 0..3 — качество бойца.
static func resolves_literally(complexity: int, understanding: int) -> bool:
	return complexity > understanding
```

- [ ] **Step 4: Прогнать — ожидаем зелёный**

Expected: `failed: 0`, `код: 0`.

- [ ] **Step 5: Закоммитить**

```powershell
git add game/sim/understanding.gd game/tests/cases/test_understanding.gd game/tests/run.gd
git commit -m "feat(sim): понимание как детерминированная проверка сложности приказа"
```


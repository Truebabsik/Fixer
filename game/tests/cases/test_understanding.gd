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

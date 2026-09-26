extends RefCounted
## Самопроверка раннера: ассерты работают, результаты копятся.

const Assert := preload("res://tests/assert.gd")


func run() -> Array:
	var t := Assert.new()
	t.eq("целые равны", 2, 1 + 1)
	t.eq("int и float по значению", 1, 1.0)
	t.eq("строки равны", "ab", "a" + "b")
	t.is_true("истина", 1 == 1)
	t.is_false("ложь", 1 == 2)
	return t.results

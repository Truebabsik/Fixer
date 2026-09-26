extends RefCounted
## Мини-ассерты. Никаких зависимостей и никакой печати: только список результатов.
## Печатает раннер — так один и тот же кейс годится и для прогона, и для отчёта.

var results: Array = []


func eq(name: String, actual, expected) -> void:
	results.append({
		"name": name,
		"ok": _same(actual, expected),
		"actual": actual,
		"expected": expected,
	})


func is_true(name: String, actual) -> void:
	eq(name, bool(actual), true)


func is_false(name: String, actual) -> void:
	eq(name, bool(actual), false)


## int и float сравниваем по значению, всё остальное — строго.
func _same(a, b) -> bool:
	if typeof(a) != typeof(b):
		var a_num := typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT
		var b_num := typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT
		if a_num and b_num:
			return is_equal_approx(float(a), float(b))
		return false
	return a == b

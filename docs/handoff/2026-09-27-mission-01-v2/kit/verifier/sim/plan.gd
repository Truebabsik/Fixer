extends RefCounted
## План игрока: маршрут, отход и состав.
## Пока это данные, которые кто-то задал снаружи. Фаза планирования (П2) будет
## их собирать; ядру важно лишь то, что маршрут задан явно и проверяем.

var route: Array = []              # id помещений по порядку
var exit_node: String = ""         # куда выходим
var exit_backup_node: String = ""  # запасной выход (D32): есть всегда
var cargo_heavy: bool = false      # планируем вынос носителей (нужен Л2)
var agents: Array = [
	{"id": "kira", "role": "tactician", "understanding": 3},
	{"id": "echo", "role": "comms", "understanding": 3},
]

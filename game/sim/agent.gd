extends RefCounted
## Агент: свой боец или охранник. Состояние растёт только через накопленные
## триггеры — один промах убить не может ни при каких настройках.

enum Kind { OWN, GUARD }
enum State { OK, WOUNDED, CRITICAL, DEAD }

const TRIGGERS_DEAD := 3

var id: String = ""
var kind: int = Kind.OWN
var role: String = "tactician"
var understanding: int = 3
var node: String = ""
var state: int = State.OK
var triggers: int = 0
var progress: int = 0
var delay: int = 0

# свои
var waypoints: Array = []
var waypoint_index: int = 1
## Пройденный путь: узлы, в которых агент побывал, по порядку. `setup` кладёт узел старта,
## `_advance_own` дописывает каждый достигнутый, поэтому последний элемент — текущий узел.
## Нужен для отхода: после взятой цели группа идёт к выходу ОБРАТНЫМ ПУТЁМ, а не одним
## ребром «цель → выход» (`sim.gd:_withdraw_route`) — иначе выход, не смежный цели,
## недостижим без поиска пути, которого в ядре нет.
## Цена — один массив на своего бойца (их двое), длиной по числу сделанных переходов;
## на охрану он не заводится.
var path: Array = []

# охрана
var patrol_route: Array = []
var patrol_index: int = 0
var patrol_period: int = 4


func speed_penalty() -> int:
	match state:
		State.WOUNDED:
			return 1
		State.CRITICAL:
			return 2
		_:
			return 0


func add_trigger() -> void:
	triggers += 1
	state = mini(triggers, TRIGGERS_DEAD)


func is_dead() -> bool:
	return state == State.DEAD


func is_own() -> bool:
	return kind == Kind.OWN

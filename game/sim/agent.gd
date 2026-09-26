extends RefCounted
## Агент: свой боец или охранник. Состояние растёт только через накопленные
## триггеры — один промах убить не может ни при каких настройках (design.md §13.5).

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

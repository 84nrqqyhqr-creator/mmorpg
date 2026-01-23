extends Object
class_name NetProtocol

const PROTOCOL_VERSION := 1

# Types
const C_HELLO := "hello"
const S_WELCOME := "welcome"
const S_ERROR := "error"
const C_INPUT := "input"
const S_SNAPSHOT := "snapshot"
const C_MOVE_TO := "move_to"
const C_STOP := "stop"

static func encode(msg: Dictionary) -> String:
	return JSON.stringify(msg)

static func decode(text: String) -> Dictionary:
	var v = JSON.parse_string(text)
	return v if typeof(v) == TYPE_DICTIONARY else {}
	
	
static func hello(token: String) -> Dictionary:
	return {
		"type": C_HELLO,
		"protocol": PROTOCOL_VERSION,
		"token": token,
	}

static func welcome(player_id: int) -> Dictionary:
	return {
		"type": S_WELCOME,
		"player_id": player_id,
		"protocol": PROTOCOL_VERSION,
	}

static func error(message: String) -> Dictionary:
	return {
		"type": S_ERROR,
		"message": message,
	}
	
static func input(dx: float, dy: float) -> Dictionary:
	return {
		"type": C_INPUT,
		"dx": dx,
		"dy": dy,
		"protocol": PROTOCOL_VERSION,
	}
	
static func snapshot(you: Dictionary, others: Array) -> Dictionary:
	return {
		"type": S_SNAPSHOT,
		"you": you,
		"others": others,
		"protocol": PROTOCOL_VERSION,
	}
	
static func move_to(x: float, y: float) -> Dictionary:
	return {
		"type": C_MOVE_TO,
		"x": x,
		"y": y,
		"protocol": PROTOCOL_VERSION,
	}
	
static func stop() -> Dictionary:
	return {
		"type": C_STOP,
		"protocol": PROTOCOL_VERSION,
	}

extends Node

var dot := ColorRect.new() # You
var other_dots: Dictionary = {} # other players: player_id -> ColorRect
var click_marker := ColorRect.new() # Mouse Click Marker

const SERVER_URL: String = "ws://64.225.2.31:8080"

var status_label: Label
var ws: WebSocketPeer = WebSocketPeer.new()

var sent_hello: bool = false
var player_id: int = -1

# --------------------------------------- Interpolation (snapshot smoothing) ---
const SNAPSHOT_INTERVAL_S: float = 0.10 # matches server ~10 snapshots/sec

# other player interpolation state:
# oid -> { "from":Vector2, "to":Vector2, "t":float, "render":Vector2 }
var other_interp: Dictionary = {}

# ----------------------------------------------- Client input send (10/sec) ---
var input_accum: float = 0.0
var last_sent_dx: float = 0.0
var last_sent_dy: float = 0.0

var render_pos: Vector2 = Vector2.ZERO      # what you display
var interp_from: Vector2 = Vector2.ZERO
var interp_to: Vector2 = Vector2.ZERO
var interp_t: float = 0.0
var have_pos: bool = false

# ------------------------------ Input (client -> server) ----------------------
var input_dx: float = 0.0
var input_dy: float = 0.0

var last_input_ms: int = 0
const INPUT_INTERVAL_MS: int = 50 # 20 inputs/sec
var input_seq: int = 0

#----------------------------------------------------------- reconnect state ---
var reconnect_delay: float = 1.0
var reconnect_max_delay: float = 10.0
var reconnect_at_ms: int = 0

var last_rx_ms: int = 0
const RX_TIMEOUT_MS: int = 3000

#------------------------------------------------- Capture mouse click state ---
var has_target: bool = false
var target_pos: Vector2 = Vector2.ZERO





# -------------------------------------------------------------------- INPUT ---
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton

		# LEFT click = set target (your existing code)
		if mb.button_index == MOUSE_BUTTON_LEFT:
			target_pos = mb.position
			has_target = true

			click_marker.position = target_pos - click_marker.size * 0.5
			click_marker.visible = true

			if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
				var msg := NetProtocol.move_to(target_pos.x, target_pos.y)
				ws.send_text(NetProtocol.encode(msg))

		# RIGHT click = cancel target
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_mouse_target(true)  # true = tell server
				

				
				
				
				




func _cancel_mouse_target(send_to_server: bool) -> void:
	if not has_target:
		return

	has_target = false
	click_marker.visible = false

	# Tell server to stop movement (important so the char doesn't keep walking)
	if send_to_server and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(NetProtocol.encode(NetProtocol.stop()))
		
		
		

# -------------------------------------------------------------------- READY ---
func _ready() -> void:
	
	# Player Marker
	dot.color = Color.GREEN
	dot.size = Vector2(16, 16)
	add_child(dot)
	
	# Mouse Click Marker
	click_marker.color = Color.YELLOW
	click_marker.size = Vector2(8, 8)
	click_marker.visible = false
	add_child(click_marker)
	
	
	status_label = get_node_or_null("CanvasLayer/StatusLabel") as Label
	if status_label == null:
		push_error("Missing node: CanvasLayer/StatusLabel")
		return
		
	_connect_now("Connecting…")
	
func _connect_now(reason: String) -> void:
	# reset per-connection state
	ws = WebSocketPeer.new()
	sent_hello = false
	player_id = -1
	
	status_label.text = "Status: %s" % reason
	var err: int = ws.connect_to_url(SERVER_URL)
	last_rx_ms = Time.get_ticks_msec()
	if err != OK:
		status_label.text = "Status: Connect failed (%d). Retrying…" % err
		_schedule_reconnect()
	
func _schedule_reconnect() -> void:
	var now: int = Time.get_ticks_msec()
	reconnect_at_ms = now + int(reconnect_delay * 1000.0)
	reconnect_delay = min(reconnect_delay * 2.0, reconnect_max_delay)
	
func _on_connected() -> void:
	reconnect_delay = 1.0
	reconnect_at_ms = 0
	
func _read_move_input() -> Vector2:
	var dx: float = 0.0
	var dy: float = 0.0

	if Input.is_action_pressed("ui_right"):
		dx += 1.0
	if Input.is_action_pressed("ui_left"):
		dx -= 1.0
	if Input.is_action_pressed("ui_down"):
		dy += 1.0
	if Input.is_action_pressed("ui_up"):
		dy -= 1.0

	# optional: normalize diagonal so speed is consistent
	var v := Vector2(dx, dy)
	if v.length() > 1.0:
		v = v.normalized()
	return v
	
	
	
	
	
# ------------------------------------------------------------------ PROCESS ---
func _process(_dt: float) -> void:
	var st: int = ws.get_ready_state()
	
	# If we're not connected, handle timed reconnect
	if st == WebSocketPeer.STATE_CLOSED:
		var now: int = Time.get_ticks_msec()
		if reconnect_at_ms == 0:
			_schedule_reconnect()
		
		var remaining_ms: int = max(0, reconnect_at_ms - now)
		status_label.text = "Status: Disconnected. Reconnecting in %.1fs" % (float(remaining_ms) / 1000.0)
		
		if now >= reconnect_at_ms:
			_connect_now("Reconnecting…")
		return
		
	# Normal websocket polling
	ws.poll()
	st = ws.get_ready_state()
	
	match st:
		WebSocketPeer.STATE_CONNECTING:
			pass
			
		WebSocketPeer.STATE_OPEN:
			# --- Gather input (WASD / Arrows) ---
			input_dx = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
			input_dy = Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")
			
			# --- CANCEL click-to-move if keyboard is used ---
			if has_target and (input_dx != 0.0 or input_dy != 0.0):
				_cancel_mouse_target(true) # tells server STOP too
			
			if reconnect_at_ms != 0:
				_on_connected()
				
			if not sent_hello:
				sent_hello = true
				status_label.text = "Status: Connected (handshaking…)"
				var hello: Dictionary = NetProtocol.hello("") # token reserved for later
				ws.send_text(NetProtocol.encode(hello))
				
				# -------------------------- Send input at fixed rate (10/sec) -----------------
				#input_accum += _dt
				#if input_accum >= SNAPSHOT_INTERVAL_S:
				#	input_accum = 0.0

				#	var v := _read_move_input()
				#	var dx := float(v.x)
				#	var dy := float(v.y)

					# Only send if changed (reduces spam)
				#	if dx != last_sent_dx or dy != last_sent_dy:
				#		last_sent_dx = dx
				#		last_sent_dy = dy
				#		ws.send_text(NetProtocol.encode(NetProtocol.input(dx, dy)))
			
			# --- Send input (rate-limited) ---
			var now_i: int = Time.get_ticks_msec()
			if now_i - last_input_ms >= INPUT_INTERVAL_MS:
				last_input_ms = now_i
				input_seq += 1
				
				if not has_target:
					var imsg: Dictionary = NetProtocol.input(input_dx, input_dy)
					ws.send_text(NetProtocol.encode(imsg))
		
			while ws.get_available_packet_count() > 0:
				last_rx_ms = Time.get_ticks_msec()
				var text: String = ws.get_packet().get_string_from_utf8()
				var msg: Dictionary = NetProtocol.decode(text)
				
				# Ignore keepalive ticks so they don't spam the UI
				if msg.get("type") == "tick":
					continue
					
				if msg.get("type") == NetProtocol.S_WELCOME:
					player_id = int(msg.get("player_id", -1))
					status_label.text = "Connected as Player #%d" % player_id
					
				elif msg.get("type") == NetProtocol.S_ERROR:
					status_label.text = "Error: %s" % String(msg.get("message", "unknown"))
				
				elif msg.get("type") == NetProtocol.S_SNAPSHOT:
					var you: Dictionary = msg.get("you", {})
					var sx: float = float(you.get("x", 0.0))
					var sy: float = float(you.get("y", 0.0))
					var new_target: Vector2 = Vector2(sx, sy)
					
					
					
					# --------------------------- Render other players ----------------------------
					var others_arr: Array = msg.get("others", [])
					#if others_arr.size() > 0:
					#	print("OTHERS RAW:", others_arr)

					var seen: Dictionary = {} # player_id -> true

					for o in others_arr:
						if typeof(o) != TYPE_DICTIONARY:
							continue

						var oid: int = int(o.get("id", -1))
						if oid == -1:
							continue

						seen[oid] = true

						var ox: float = float(o.get("x", 0.0))
						var oy: float = float(o.get("y", 0.0))

						# Create dot if needed
						if not other_dots.has(oid):
							var r := ColorRect.new()
							r.color = Color.RED
							r.size = Vector2(16, 16)
							add_child(r)
							other_dots[oid] = r

						var new_pos := Vector2(ox, oy)

						# Create interp state if needed
						if not other_interp.has(oid):
							other_interp[oid] = {
								"from": new_pos,
								"to": new_pos,
								"t": 0.0,
								"render": new_pos,
							}
						else:
							var s: Dictionary = other_interp[oid]
							s["from"] = Vector2(s["render"].x, s["render"].y) # current rendered pos
							s["to"] = new_pos
							s["t"] = 0.0
							other_interp[oid] = s

					# Remove dots for players no longer present
					for oid in other_dots.keys():
						if not seen.has(oid):
							var rd: ColorRect = other_dots[oid]
							rd.queue_free()
							other_dots.erase(oid)
							other_interp.erase(oid)
					
					
					
					
					
					if not have_pos:
						# First snapshot: snap immediately
						render_pos = new_target
						interp_from = new_target
						interp_to = new_target
						interp_t = 0.0
						have_pos = true
					else:
						# Smooth interpolation
						interp_from = render_pos
						interp_to = new_target
						interp_t = 0.0
						
				else:
					status_label.text = "Server: %s" % text
					
					
			# ------------------------------ Apply interpolation ---------------------------
			if have_pos:
				interp_t += _dt
				var a: float = clamp(interp_t / SNAPSHOT_INTERVAL_S, 0.0, 1.0)
				render_pos = interp_from.lerp(interp_to, a)
				dot.position = render_pos
				
				# Smooth other players too
				for oid in other_dots.keys():
					if not other_interp.has(oid):
						continue
					var s: Dictionary = other_interp[oid]
					s["t"] = float(s.get("t", 0.0)) + _dt
					var a2: float = clamp(float(s["t"]) / SNAPSHOT_INTERVAL_S, 0.0, 1.0)

					var from: Vector2 = s["from"]
					var to: Vector2 = s["to"]
					var rpos: Vector2 = from.lerp(to, a2)

					s["render"] = rpos
					other_interp[oid] = s

					var rd: ColorRect = other_dots[oid]
					rd.position = rpos
				
				# Show smoothed position (render_pos)
				status_label.text = "You (smooth): (%.0f, %.0f)  Player #%d" % [render_pos.x, render_pos.y, player_id]
				
			var now_ms: int = Time.get_ticks_msec()
			if now_ms - last_rx_ms > RX_TIMEOUT_MS:
				status_label.text = "Status: Connection lost. Reconnecting…"
				ws.close() # will push us into STATE_CLOSED next frames
				_schedule_reconnect()
				return
				

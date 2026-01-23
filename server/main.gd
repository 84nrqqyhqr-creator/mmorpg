extends Node

#------------------------------------------------------------ Timing / Rates ---
# Used to rate-limit server-to-client state snapshots
var last_snapshot_ms: int = 0

# Used to rate-limit keepalive ("tick") messages
var last_keepalive_ms: int = 0

# (DEPRECATED) Legacy tick timer — DO NOT USE
# Kept temporarily to avoid breaking references during refactor
var last_tick_ms: int = 0
const TICK_INTERVAL_MS: int = 1000


#---------------------------------------------------- Networking / Transport ---
const PORT := 8080

var tcp := TCPServer.new()

# Connected websocket peers: peer_id -> WebSocketPeer
var peers: Dictionary = {} # int -> WebSocketPeer

# Mapping: peer_id -> player_id
var connections: Dictionary = {} # int peer_id -> int player_id

# Incrementing IDs for new connections / new players
var next_peer_id := 1
var next_player_id := 1


# ------------------------------------------------- Simulation / World State ---
# Movement speed (units per second)
const SPEED := 200.0

# Player state: player_id -> {x, y, dx, dy}
var players := {} # pid -> {x, y, dx, dy}

const STOP_DIST := 4.0 # how close is "arrived"




# -------------------------------------------------------------------- READY ---
func _ready() -> void:
	var err := tcp.listen(PORT)
	if err != OK:
		push_error("TCP listen failed: %s" % err)
		get_tree().quit(1)
		return
		
	print("WS server listening on 0.0.0.0:%d" % PORT)
	set_process(true)
	
	
	
	
	
# ------------------------------------------------------------------ PROCESS ---
func _process(_dt: float) -> void:
	# Accept new TCP connections.
	while tcp.is_connection_available():
		var conn := tcp.take_connection()
		if conn == null:
			break
			
		var ws := WebSocketPeer.new()
		# IMPORTANT: server-side accept handshake
		ws.accept_stream(conn)
		
		var id := next_peer_id
		next_peer_id += 1
		peers[id] = ws
		print("Client connected:", id)
		
	# Poll peers and handle messages.
	var to_remove: Array[int] = []
	for id in peers.keys():
		var ws: WebSocketPeer = peers[id]
		ws.poll()
		
		var state := ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			while ws.get_available_packet_count() > 0:
				var pkt: PackedByteArray = ws.get_packet()
				var text := pkt.get_string_from_utf8()
				var msg := NetProtocol.decode(text)
				
				if msg.get("type") == NetProtocol.C_HELLO:
					var pid := next_player_id
					next_player_id += 1
					
					# link peer -> player
					connections[id] = pid
					
					# create player state (spawn anywhere for now)
					players[pid] = {
						"id": pid,
						"x": 0.0,
						"y": 0.0,
						"dx": 0.0,
						"dy": 0.0,
					}
					
					var reply := NetProtocol.welcome(pid)
					ws.send_text(NetProtocol.encode(reply))
						
				# Server: handle input messages
				elif msg.get("type") == NetProtocol.C_INPUT:
					if not connections.has(id):
						continue
					var pid := int(connections[id])
					
					if players.has(pid):
						var p: Dictionary = players[pid]
						p["dx"] = float(msg.get("dx", 0.0))
						p["dy"] = float(msg.get("dy", 0.0))
						p["has_target"] = false
						print("INPUT pid=%d dx=%.2f dy=%.2f" % [pid, p["dx"], p["dy"]])


				elif msg.get("type") == NetProtocol.C_MOVE_TO:
					if not connections.has(id):
						continue
					var pid := int(connections[id])

					if players.has(pid):
						var p: Dictionary = players[pid]
						p["tx"] = float(msg.get("x", p.get("x", 0.0)))
						p["ty"] = float(msg.get("y", p.get("y", 0.0)))
						p["has_target"] = true
						# optional: print("MOVE_TO pid=%d -> (%.1f, %.1f)" % [pid, p["tx"], p["ty"]])

						
				elif msg.get("type") == NetProtocol.C_STOP:
					if not connections.has(id):
						continue
					var pid := int(connections[id])

					if players.has(pid):
						var p: Dictionary = players[pid]
						p["dx"] = 0.0
						p["dy"] = 0.0
						p["has_target"] = false
						# future-proofing:
						# p.erase("tx")
						# p.erase("ty")
						# p["has_target"] = false
						
						
		elif state == WebSocketPeer.STATE_CLOSED:
			to_remove.append(id)
			
			
			
			
			
	# ---------------------------------------------------- Client Disconnect ---
	for id in to_remove:
		if connections.has(id):
			var pid := int(connections[id])
			players.erase(pid)
			connections.erase(id)
			
		peers.erase(id)
		print("Client disconnected:", id)
		
		
		
		
		
	# ------------------------------------------- Authoritative movement sim ---
	var dt := _dt
	for pid in players.keys():
		var p: Dictionary = players[pid]

		# If click-to-move target exists, server drives dx/dy
		if bool(p.get("has_target", false)):
			var x := float(p.get("x", 0.0))
			var y := float(p.get("y", 0.0))
			var tx := float(p.get("tx", x))
			var ty := float(p.get("ty", y))

			var to := Vector2(tx - x, ty - y)
			var dist := to.length()

			if dist <= STOP_DIST:
				p["dx"] = 0.0
				p["dy"] = 0.0
				p["has_target"] = false
			else:
				var dir := to / dist
				p["dx"] = dir.x
				p["dy"] = dir.y

		# Integrate movement
		p["x"] = float(p.get("x", 0.0)) + float(p.get("dx", 0.0)) * SPEED * dt
		p["y"] = float(p.get("y", 0.0)) + float(p.get("dy", 0.0)) * SPEED * dt
		
		
		
		
		
	# ------------------------------------------------ Snapshots (broadcast) ---
	var snap_ms := Time.get_ticks_msec()
	if snap_ms - last_snapshot_ms >= 100: # 10 snapshots/sec
		last_snapshot_ms = snap_ms
		# Send Snapshot
		
		for peer_id in peers.keys():
			var w: WebSocketPeer = peers[peer_id]
			if w.get_ready_state() != WebSocketPeer.STATE_OPEN:
				continue
			if not connections.has(peer_id):
				continue
				
			var pid := int(connections[peer_id])
			if not players.has(pid):
				continue
			
			# ---------------------------------------------------------- YOU ---
			var p: Dictionary = players[pid]
			var you := {
				"id": pid,
				"x": float(p.get("x", 0.0)),
				"y": float(p.get("y", 0.0)),
			}
			
			# ------------------------------------------------------- OTHERS ---
			var others: Array = []
			for opid in players.keys():
				if int(opid) == pid:
					continue
				var op: Dictionary = players[opid]
				others.append({
					"id": int(opid),
					"x": float(op.get("x", 0.0)),
					"y": float(op.get("y", 0.0)),
				})
				
			w.send_text(NetProtocol.encode(NetProtocol.snapshot(you, others)))
		
		
		
		
		
	# ---------------------------------------------- Server tick (keepalive) ---
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - last_keepalive_ms >= TICK_INTERVAL_MS:
		last_keepalive_ms = now_ms
		# Send Tick
		
		var tick_txt: String = JSON.stringify({"type":"tick","t": now_ms})
		
		for id in peers.keys():
			var w: WebSocketPeer = peers[id]
			if w.get_ready_state() == WebSocketPeer.STATE_OPEN:
				w.send_text(tick_txt)
				

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

A Godot 4 project (GDScript, `config/features` says 4.5; the developer uses 4.6) for a small client/server MMORPG prototype. One Godot project holds both the game client and the dedicated server. They talk over raw WebSockets using JSON messages. There are no tests, linters or build tools apart from Godot itself.

## Commands

There is no Godot binary in the cloud container, so none of these can run there. They are for the developer's machine (macOS; `deploy_server.sh` has the editor path).

- Run the client: open the project in the editor and press Play. `run/main_scene` points at `client/client.tscn`.
- Run the server locally (headless): `godot --headless --path . res://server/server.tscn`. It listens on `0.0.0.0:8080`.
- Test against a local server: change `SERVER_URL` in `client/client.gd` from the production IP to `ws://127.0.0.1:8080`.
- Export and deploy the server: `./deploy_server.sh`. It exports with the `ServerLinux` preset to `exports/server/build/latest/`, copies `server.x86_64`, `server.pck` and `server.sh` to `gamestudio@64.225.2.31`, swaps them into `/home/gamestudio/srv/game/bin`, restarts the `mmorpg-server.service` systemd unit, then checks that port 8080 is listening and that the unit's MainPID is `server.x86_64`. The remote user needs passwordless `sudo` for `systemctl`.

## Architecture

- `shared/net_protocol.gd`: `class_name NetProtocol`, a global static helper used by both sides. It holds the message type constants, `PROTOCOL_VERSION`, JSON `encode`/`decode`, and one constructor per message. **Add any new message type here first**, then handle it on both sides.
- `server/main.gd` (scene `server/server.tscn`): the authoritative server. Everything runs in `_process`:
  1. Accept TCP connections and upgrade them with `WebSocketPeer.accept_stream`.
  2. Poll each peer and dispatch on `msg.type`.
  3. Simulate movement.
  4. Broadcast snapshots at 10 Hz.
  5. Send a `{"type":"tick"}` keepalive once a second.

  It has no `SceneTree` or physics nodes: all state lives in dictionaries (`peers`: peer_id → WebSocketPeer; `connections`: peer_id → player_id; `players`: player_id → `{x, y, dx, dy, tx, ty, has_target}`).
- `client/client.gd` (scene `client/client.tscn`): builds its visuals in code with `ColorRect`s: a green dot for you, red dots for others, and a yellow click marker. It needs the `CanvasLayer/StatusLabel` node from the scene. Other logic:
  - Reconnects with exponential backoff (1s up to 10s).
  - Treats 3s without received data as a lost connection. The server's 1s `tick` keepalive is what stops this from firing while you stand still.
  - Sends `input` at 20 Hz.
  - Interpolates between snapshots over `SNAPSHOT_INTERVAL_S` (0.10s). This value must match the server's snapshot rate.

### Message flow
1. The client connects and sends `hello` (token reserved, currently `""`).
2. The server replies `welcome{player_id}` and spawns the player at (0, 0).
3. Movement uses two input modes, and the server simulates both at `SPEED` 200 units/s:
   - Keyboard (`ui_*` actions): the client sends `input{dx,dy}` continuously. This clears any click target.
   - Left click: `move_to{x,y}`. The server steers toward the target until within `STOP_DIST`.
   - Right click, or pressing a movement key while a target is active: `stop`.
4. `snapshot{you, others}` is sent per player. The client removes dots for player ids missing from `others`.

### Gotchas
- `PROTOCOL_VERSION` is sent with messages but never checked on either side.
- Players are identified by connection only. There is no auth or persistence, and a player's state is deleted on disconnect.
- Click coordinates are screen-space (`InputEventMouseButton.position`) and are used directly as world coordinates. There is no camera.
- `last_tick_ms` in `server/main.gd` is marked deprecated. Use `last_keepalive_ms`.
- `run/main_scene` is the client scene. The `ServerLinux` export preset sets no custom feature or scene override, so check how the server build picks `server.tscn` before changing the main scene or export settings.
- Godot 4.4+ keeps a `.uid` file beside each script and references scenes and scripts by `uid://`. Commit `.uid` files together with their scripts.

extends Control

@export var websocket_url: String = "ws://localhost:8787"
@export var player_name: String = "Player"
@export var auto_connect: bool = true

const WORLD_W: float = 720.0
const WORLD_H: float = 1280.0
const WORLD_SIZE: Vector2 = Vector2(WORLD_W, WORLD_H)
const SEND_RATE: float = 1.0 / 30.0
const SNAPSHOT_INTERPOLATION_DELAY: float = 0.04
const MOVE_BAR_Y: float = 1028.0
const WEAPON_ORDER: Array[String] = ["sniper"]
const WEAPON_LABELS: Dictionary = {
	"sniper": "Sniper"
}
const WEAPON_AMMO_MAX: Dictionary = {
	"sniper": 5
}
const WEAPON_RELOAD_TIME: Dictionary = {
	"sniper": 0.8
}
const ACTION_ORDER: Array[String] = ["rapid", "shield", "split"]
const ACTION_LABELS: Dictionary = {
	"rapid": "Rapid",
	"shield": "Shield",
	"split": "Split"
}

const TEX_ATLAS: Texture2D = preload("res://assets/samibrick_texture_atlas_v1.png")
const TEX_BUTTON_ATLAS: Texture2D = preload("res://assets/ui_button_ring_atlas_v1.png")
var tex_space_bg: Texture2D
var tex_fx_shield: Texture2D
var tex_fx_rapid: Texture2D
var tex_fx_split: Texture2D
const ATLAS_BRICK_BLUE: Rect2 = Rect2(816, 8, 64, 24)
const ATLAS_BRICK_RED: Rect2 = Rect2(608, 80, 64, 24)
const ATLAS_SHIELD_SEGMENT_BLUE: Rect2 = Rect2(672, 8, 64, 18)
const ATLAS_SHIELD_SEGMENT_RED: Rect2 = Rect2(464, 80, 64, 18)
const ATLAS_BALL_MAIN: Rect2 = Rect2(160, 152, 32, 32)
const ATLAS_SHIP_BLUE: Rect2 = Rect2(496, 8, 80, 64)
const ATLAS_SHIP_RED: Rect2 = Rect2(288, 80, 80, 64)
const ATLAS_TURRET_BLUE: Rect2 = Rect2(568, 8, 40, 40)
const ATLAS_TURRET_RED: Rect2 = Rect2(360, 80, 40, 40)
const ATLAS_SHIELD_BUBBLE_BLUE: Rect2 = Rect2(744, 8, 64, 64)
const ATLAS_SHIELD_BUBBLE_RED: Rect2 = Rect2(536, 80, 64, 64)
const ATLAS_BULLET_BLUE: Rect2 = Rect2(336, 152, 18, 36)
const ATLAS_BULLET_RED: Rect2 = Rect2(670, 152, 18, 36)
const ATLAS_HEAVY_BLUE: Rect2 = Rect2(378, 152, 18, 36)
const ATLAS_HEAVY_RED: Rect2 = Rect2(712, 152, 18, 36)
const ATLAS_POWER_SPLIT: Rect2 = Rect2(50, 208, 36, 36)
const ATLAS_POWER_SHIELD: Rect2 = Rect2(94, 208, 36, 36)
const ATLAS_POWER_RAPID: Rect2 = Rect2(138, 208, 36, 36)
const UI_FIRE_IDLE: Rect2 = Rect2(8, 8, 176, 176)
const UI_FIRE_PRESSED: Rect2 = Rect2(200, 8, 176, 176)
const UI_RING_FRAME_SIZE: float = 384.0
const UI_RING_FRAME_STEP: float = 400.0
const UI_RING_START: Vector2 = Vector2(8.0, 208.0)
const UI_WEAPON_INNER_RADIUS: float = 88.0
const UI_WEAPON_OUTER_RADIUS: float = 184.0
const ROOM_CODE_HOLD_SECONDS: float = 0.55

var socket := WebSocketPeer.new()
var has_joined := false
var reconnect_timer := 0.0
var last_socket_state := WebSocketPeer.STATE_CLOSED
var current_url := ""
var url_params: Dictionary = {}
var room_code := ""
var invite_path := ""
var invite_url := ""
var is_room_host := false
var room_rules: Dictionary = {}
var lobby_menu_visible := false
var lobby_join_code := ""
var lobby_join_focused := false
var lobby_paste_pending := false
var lobby_paste_timeout := 0.0
var room_launch_mode := ""
var room_code_hold_id := ""
var room_code_hold_elapsed := 0.0
var room_code_hold_copied := false
var room_code_copied_time := 0.0

var my_role := -1
var room_id := ""
var current_state: Dictionary = {}
var visual_state: Dictionary = {}
var state_buffer: Array[Dictionary] = []
var status_message := "Initialisation..."
var event_log: Array[String] = []

var send_accumulator := 0.0
var touch_target_x := -1.0
var move_touches: Dictionary = {}
var fire_touches: Dictionary = {}
var action_touches: Dictionary = {}
var pending_switch := ""
var pending_action := ""
var last_sent_fire := false
var draw_fit_offset := Vector2.ZERO
var draw_fit_scale := 1.0
var ui_font: Font
var sound_players: Dictionary = {}
var sound_streams: Dictionary = {}
var previous_projectile_ids: Dictionary = {}
var previous_alive_bricks := -1
var previous_room_status := ""
var previous_countdown_second := -1
var ammo_empty_feedback := false
var ammo_empty_pulse := 0.0
var ammo_empty_time := 0.0
var ammo_empty_weapon := ""
var fire_blocked_sound_cooldown := 0.0
var ping_timer := 0.0
var ping_seq := 0
var pending_pings: Dictionary = {}
var server_latency_ms := -1
var ball_visual_angle := 0.0

func _ready() -> void:
	set_process(true)
	ui_font = get_theme_default_font()
	_load_effect_assets()
	_setup_audio()
	url_params = _resolve_url_params()
	room_code = _room_code_from_params(url_params)
	if room_code != "":
		room_launch_mode = "join"
	elif _wants_bot_match():
		room_launch_mode = "bot"
	elif _wants_quick_match():
		room_launch_mode = "quick"
	else:
		room_launch_mode = "create"
		lobby_menu_visible = true
	current_url = _resolve_websocket_url()
	status_message = "Choisis un mode de jeu" if lobby_menu_visible else _initial_connection_message()
	if auto_connect and not lobby_menu_visible:
		_connect_to_server()

func _load_effect_assets() -> void:
	tex_space_bg = load("res://assets/space_starfield.png")
	tex_fx_shield = load("res://assets/fx_shield_ring.png")
	tex_fx_rapid = load("res://assets/fx_rapid_trail.png")
	tex_fx_split = load("res://assets/fx_split_ghost.png")

func _process(delta: float) -> void:
	_poll_socket()
	_update_reconnect(delta)
	_update_room_code_hold(delta)
	_update_lobby_clipboard_paste(delta)
	_update_ammo_empty_feedback(delta)
	ball_visual_angle = fposmod(ball_visual_angle - TAU * 0.55 * delta, TAU)
	fire_blocked_sound_cooldown = maxf(0.0, fire_blocked_sound_cooldown - delta)
	_update_server_ping(delta)
	room_code_copied_time = maxf(0.0, room_code_copied_time - delta)
	send_accumulator += delta
	if send_accumulator >= SEND_RATE:
		send_accumulator = 0.0
		_send_input()
	queue_redraw()

func _connect_to_server() -> void:
	socket = WebSocketPeer.new()
	has_joined = false
	state_buffer.clear()
	visual_state = {}
	previous_projectile_ids.clear()
	previous_alive_bricks = -1
	previous_room_status = ""
	previous_countdown_second = -1
	current_url = _resolve_websocket_url()
	var err := socket.connect_to_url(current_url)
	if err != OK:
		status_message = "Connexion impossible: %s" % current_url
		reconnect_timer = 2.0
	else:
		status_message = _initial_connection_message()

func _resolve_websocket_url() -> String:
	if OS.has_feature("web"):
		var protocol := str(JavaScriptBridge.eval("window.location.protocol", true))
		var host := str(JavaScriptBridge.eval("window.location.host", true))
		if host != "" and host != "null":
			var scheme := "wss://" if protocol == "https:" else "ws://"
			return scheme + host
	return websocket_url

func _resolve_url_params() -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var raw := str(JavaScriptBridge.eval("(function(){return JSON.stringify(Object.fromEntries(new URLSearchParams(window.location.search)));})()", true))
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}

func _room_code_from_params(params: Dictionary) -> String:
	for key in ["room", "code", "roomCode"]:
		var value := str(params.get(key, "")).strip_edges().to_upper()
		if value != "":
			return value
	return ""

func _url_param_bool(key: String) -> bool:
	var value := str(url_params.get(key, "")).strip_edges().to_lower()
	return ["1", "true", "yes", "on"].has(value)

func _wants_quick_match() -> bool:
	var mode := str(url_params.get("mode", "")).strip_edges().to_lower()
	return _url_param_bool("quick") or mode == "quick" or mode == "matchmaking"

func _wants_bot_match() -> bool:
	var mode := str(url_params.get("mode", "")).strip_edges().to_lower()
	return _url_param_bool("bot") or _url_param_bool("solo") or mode == "bot" or mode == "solo"

func _initial_connection_message() -> String:
	if room_code != "":
		return "Connexion room %s..." % room_code
	if room_launch_mode == "bot" or _wants_bot_match():
		return "Creation d'une partie solo..."
	if room_launch_mode == "quick" or _wants_quick_match():
		return "Connexion matchmaking rapide..."
	return "Creation d'une room privee..."

func _normalize_room_code(value: String) -> String:
	var output := ""
	for i in range(value.length()):
		var code := value.unicode_at(i)
		if code >= 97 and code <= 122:
			code -= 32
		if (code >= 65 and code <= 90) or (code >= 48 and code <= 57):
			output += char(code)
	return output.substr(0, 12)

func _poll_socket() -> void:
	socket.poll()
	var state := socket.get_ready_state()
	if state != last_socket_state:
		last_socket_state = state
		if state == WebSocketPeer.STATE_OPEN:
			status_message = "Connecté. Recherche d'un adversaire..."
		elif state == WebSocketPeer.STATE_CLOSED:
			var reason := socket.get_close_reason()
			if reason == "":
				reason = "fermé"
			status_message = "Déconnecté (%s). Reconnexion..." % reason
			reconnect_timer = 2.0

	if state == WebSocketPeer.STATE_OPEN:
		if not has_joined:
			_send_room_join()
			has_joined = true
		while socket.get_available_packet_count() > 0:
			var packet := socket.get_packet().get_string_from_utf8()
			_handle_packet(packet)

func _send_room_join() -> void:
	status_message = _initial_connection_message()
	var payload := {"name": player_name}
	if room_launch_mode == "join" or room_code != "":
		payload["type"] = "joinRoom"
		payload["roomCode"] = room_code
	elif room_launch_mode == "bot" or _wants_bot_match():
		payload["type"] = "botRoom"
	elif room_launch_mode == "quick" or _wants_quick_match():
		payload["type"] = "join"
	else:
		payload["type"] = "createRoom"
	_send_json(payload)

func _update_reconnect(delta: float) -> void:
	if not auto_connect or lobby_menu_visible:
		return
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN or socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		return
	if reconnect_timer > 0.0:
		reconnect_timer -= delta
		if reconnect_timer <= 0.0:
			_connect_to_server()

func _handle_packet(packet: String) -> void:
	var parsed = JSON.parse_string(packet)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	var msg_type := str(data.get("type", ""))
	match msg_type:
		"welcome":
			my_role = int(data.get("role", my_role))
			room_id = str(data.get("roomId", ""))
			status_message = "Salle %s - rôle %s" % [room_id, my_role]
		"roomInfo":
			_apply_room_info(data)
			status_message = _room_status_text()
		"state":
			data["_rx"] = Time.get_ticks_msec() * 0.001
			_update_sound_cues(data)
			current_state = data
			_record_state_snapshot(data)
			my_role = int(data.get("you", my_role))
			room_id = str(data.get("roomId", room_id))
			room_code = str(data.get("roomCode", room_code))
			invite_path = str(data.get("invitePath", invite_path))
			is_room_host = bool(data.get("host", is_room_host))
			if data.has("rules") and typeof(data.get("rules")) == TYPE_DICTIONARY:
				room_rules = data.get("rules")
			_refresh_invite_url()
			if current_state.has("message"):
				status_message = str(current_state.get("message"))
		"event":
			var message := str(data.get("message", ""))
			_add_event(message)
			_handle_event_sound(message)
		"pong":
			_handle_pong(data)
		"error":
			status_message = str(data.get("message", "Erreur serveur"))
		_:
			pass

func _start_create_room() -> void:
	lobby_menu_visible = false
	lobby_join_focused = false
	room_launch_mode = "create"
	room_code = ""
	status_message = _initial_connection_message()
	_connect_to_server()

func _start_quick_match() -> void:
	lobby_menu_visible = false
	lobby_join_focused = false
	room_launch_mode = "quick"
	room_code = ""
	status_message = _initial_connection_message()
	_connect_to_server()

func _start_bot_match() -> void:
	lobby_menu_visible = false
	lobby_join_focused = false
	room_launch_mode = "bot"
	room_code = ""
	status_message = _initial_connection_message()
	_connect_to_server()

func _start_join_room(code: String) -> void:
	var normalized := _normalize_room_code(code)
	if normalized == "":
		status_message = "Entre un code room"
		lobby_join_focused = true
		return
	lobby_menu_visible = false
	lobby_join_focused = false
	room_launch_mode = "join"
	room_code = normalized
	status_message = _initial_connection_message()
	_connect_to_server()

func _apply_room_info(data: Dictionary) -> void:
	my_role = int(data.get("role", my_role))
	room_id = str(data.get("roomId", room_id))
	room_code = str(data.get("roomCode", room_code))
	invite_path = str(data.get("invitePath", invite_path))
	is_room_host = bool(data.get("host", is_room_host))
	if data.has("rules") and typeof(data.get("rules")) == TYPE_DICTIONARY:
		room_rules = data.get("rules")
	_refresh_invite_url()

func _refresh_invite_url() -> void:
	if room_code == "":
		invite_url = ""
		return
	if OS.has_feature("web"):
		var origin := str(JavaScriptBridge.eval("window.location.origin", true))
		var pathname := str(JavaScriptBridge.eval("window.location.pathname", true))
		if pathname == "" or pathname == "null":
			pathname = "/"
		invite_url = "%s%s?room=%s" % [origin, pathname, room_code]
	else:
		invite_url = "room:%s" % room_code

func _room_status_text() -> String:
	if room_code == "":
		return "Room en cours de creation..."
	if room_launch_mode == "bot" or _wants_bot_match():
		return "Solo bot %s" % room_code
	if room_launch_mode == "quick" or _wants_quick_match():
		return "Room rapide %s" % room_code
	return "Room %s - partage le lien pour inviter" % room_code

func _send_json(payload: Dictionary) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	socket.send_text(JSON.stringify(payload))

func _update_server_ping(delta: float) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	ping_timer -= delta
	if ping_timer > 0.0:
		return
	ping_timer = 1.0
	ping_seq += 1
	pending_pings[ping_seq] = Time.get_ticks_msec()
	_send_json({"type": "ping", "seq": ping_seq})

func _handle_pong(data: Dictionary) -> void:
	var seq := int(data.get("seq", -1))
	if not pending_pings.has(seq):
		return
	var sent_ms := int(pending_pings.get(seq))
	pending_pings.erase(seq)
	server_latency_ms = max(0, Time.get_ticks_msec() - sent_ms)

func _send_input() -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN or not has_joined:
		return
	var axis := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		axis -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		axis += 1.0

	var key_fire := Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_ENTER)
	var fire := key_fire or fire_touches.size() > 0
	var target_value = null
	if touch_target_x >= 0.0:
		target_value = clampf(touch_target_x, 40.0, WORLD_W - 40.0)

	var payload := {
		"type": "input",
		"move": axis,
		"targetX": target_value,
		"fire": fire,
		"switch": pending_switch,
		"action": pending_action
	}
	pending_switch = ""
	pending_action = ""
	last_sent_fire = fire
	_send_json(payload)

func _input(event: InputEvent) -> void:
	if _handle_menu_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var pos := _screen_to_virtual(event.position)
		if event.pressed:
			_pointer_down("mouse", pos)
		else:
			_pointer_up("mouse")
	elif event is InputEventMouseMotion:
		if move_touches.has("mouse") or fire_touches.has("mouse") or (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			var pos := _screen_to_virtual(event.position)
			_pointer_move("mouse", pos)
	elif event is InputEventScreenTouch:
		var id := "touch_%s" % event.index
		var pos := _screen_to_virtual(event.position)
		if event.pressed:
			_pointer_down(id, pos)
		else:
			_pointer_up(id)
	elif event is InputEventScreenDrag:
		var id := "touch_%s" % event.index
		var pos := _screen_to_virtual(event.position)
		_pointer_move(id, pos)
	elif event is InputEventKey and event.pressed and not event.echo:
		if _handle_key_input(event):
			get_viewport().set_input_as_handled()

func _handle_menu_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var pos := _screen_to_virtual(event.position)
		if event.pressed:
			return _handle_menu_click(pos, "mouse")
		if room_code_hold_id == "mouse":
			_finish_room_code_hold()
			return true
	if event is InputEventMouseMotion and room_code_hold_id == "mouse":
		var pos := _screen_to_virtual(event.position)
		if not _room_code_copy_rect().has_point(pos):
			_cancel_room_code_hold()
		return true
	if event is InputEventScreenTouch:
		var id := "touch_%s" % event.index
		var pos := _screen_to_virtual(event.position)
		if event.pressed:
			return _handle_menu_click(pos, id)
		if room_code_hold_id == id:
			_finish_room_code_hold()
			return true
	if event is InputEventScreenDrag:
		var id := "touch_%s" % event.index
		if room_code_hold_id == id:
			var pos := _screen_to_virtual(event.position)
			if not _room_code_copy_rect().has_point(pos):
				_cancel_room_code_hold()
			return true
	if event is InputEventKey and event.pressed and not event.echo:
		if lobby_menu_visible:
			return _handle_lobby_key(event)
	return lobby_menu_visible

func _handle_menu_click(pos: Vector2, pointer_id: String) -> bool:
	if lobby_menu_visible:
		_handle_lobby_click(pos)
		return true
	if _rematch_button_visible() and _rematch_button_rect().has_point(pos):
		_request_rematch()
		return true
	if _room_code_copy_rect().has_point(pos) and room_code != "":
		_start_room_code_hold(pointer_id)
		return true
	return false

func _handle_lobby_click(pos: Vector2) -> void:
	lobby_join_focused = false
	if _lobby_create_rect().has_point(pos):
		_start_create_room()
	elif _lobby_quick_rect().has_point(pos):
		_start_quick_match()
	elif _lobby_bot_rect().has_point(pos):
		_start_bot_match()
	elif _lobby_join_paste_rect().has_point(pos):
		lobby_join_focused = true
		_paste_lobby_join_code()
	elif _lobby_join_input_rect().has_point(pos):
		lobby_join_focused = true
	elif _lobby_join_rect().has_point(pos):
		if lobby_join_code == "":
			var prompted := _prompt_join_code()
			if prompted != "":
				lobby_join_code = prompted
		_start_join_room(lobby_join_code)

func _handle_lobby_key(event: InputEventKey) -> bool:
	if event.keycode == KEY_ESCAPE:
		lobby_join_focused = false
		return true
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		if lobby_join_focused:
			_start_join_room(lobby_join_code)
		return true
	if event.keycode == KEY_BACKSPACE and lobby_join_focused:
		if lobby_join_code.length() > 0:
			lobby_join_code = lobby_join_code.substr(0, lobby_join_code.length() - 1)
		return true
	if event.keycode == KEY_V and lobby_join_focused and (event.ctrl_pressed or event.meta_pressed):
		_paste_lobby_join_code()
		return true
	if lobby_join_focused and event.unicode > 0:
		lobby_join_code = _normalize_room_code(lobby_join_code + char(event.unicode))
		return true
	if event.keycode == KEY_Q:
		_start_quick_match()
		return true
	if event.keycode == KEY_B:
		_start_bot_match()
		return true
	if event.keycode == KEY_C:
		_start_create_room()
		return true
	return lobby_menu_visible

func _prompt_join_code() -> String:
	if OS.has_feature("web"):
		var raw := str(JavaScriptBridge.eval("window.prompt('Code room') || ''", true))
		return _extract_room_code(raw)
	return ""

func _paste_lobby_join_code() -> void:
	var pasted := _extract_room_code(DisplayServer.clipboard_get())
	if pasted != "":
		lobby_join_code = pasted
		status_message = "Code colle"
		return
	if OS.has_feature("web"):
		lobby_paste_pending = true
		lobby_paste_timeout = 1.2
		status_message = "Lecture presse-papiers..."
		JavaScriptBridge.eval("(function(){ window.__brickDuelPasteReady=false; window.__brickDuelPaste=''; if (navigator.clipboard && navigator.clipboard.readText) { navigator.clipboard.readText().then(function(t){ window.__brickDuelPaste=String(t || ''); window.__brickDuelPasteReady=true; }).catch(function(){ window.__brickDuelPaste=''; window.__brickDuelPasteReady=true; }); } else { window.__brickDuelPasteReady=true; } })()", false)
	else:
		status_message = "Presse-papiers vide"

func _update_lobby_clipboard_paste(delta: float) -> void:
	if not lobby_paste_pending:
		return
	lobby_paste_timeout -= delta
	if OS.has_feature("web"):
		var ready_value = JavaScriptBridge.eval("window.__brickDuelPasteReady === true", true)
		var ready: bool = ready_value == true or str(ready_value).to_lower() == "true"
		if ready:
			lobby_paste_pending = false
			var pasted := _extract_room_code(str(JavaScriptBridge.eval("window.__brickDuelPaste || ''", true)))
			if pasted != "":
				lobby_join_code = pasted
				status_message = "Code colle"
			else:
				status_message = "Collage impossible"
			JavaScriptBridge.eval("window.__brickDuelPasteReady=false; window.__brickDuelPaste='';", false)
			return
	if lobby_paste_timeout <= 0.0:
		lobby_paste_pending = false
		status_message = "Collage impossible"

func _extract_room_code(text: String) -> String:
	var raw := text.strip_edges()
	if raw == "":
		return ""
	var lower := raw.to_lower()
	for marker in ["roomcode=", "room=", "code="]:
		var marker_text := str(marker)
		var idx := lower.find(marker_text)
		if idx >= 0:
			var start: int = idx + marker_text.length()
			var stop: int = raw.length()
			for delimiter in ["&", "#", "?", " ", "\n", "\r", "\t"]:
				var delimiter_idx := raw.find(str(delimiter), start)
				if delimiter_idx >= 0 and delimiter_idx < stop:
					stop = delimiter_idx
			return _normalize_room_code(raw.substr(start, stop - start))
	return _normalize_room_code(raw)

func _start_room_code_hold(pointer_id: String) -> void:
	room_code_hold_id = pointer_id
	room_code_hold_elapsed = 0.0
	room_code_hold_copied = false

func _cancel_room_code_hold() -> void:
	room_code_hold_id = ""
	room_code_hold_elapsed = 0.0
	room_code_hold_copied = false

func _finish_room_code_hold() -> void:
	if room_code_hold_id != "" and not room_code_hold_copied and room_code_hold_elapsed >= ROOM_CODE_HOLD_SECONDS:
		_copy_room_code()
	_cancel_room_code_hold()

func _update_room_code_hold(delta: float) -> void:
	if room_code_hold_id == "":
		return
	room_code_hold_elapsed += delta
	if not room_code_hold_copied and room_code_hold_elapsed >= ROOM_CODE_HOLD_SECONDS:
		_copy_room_code()
		room_code_hold_copied = true

func _copy_room_code() -> void:
	if room_code == "":
		return
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(function(){ if (navigator.clipboard) { navigator.clipboard.writeText('%s').catch(function(){}); } })()" % room_code, false)
	else:
		DisplayServer.clipboard_set(room_code)
	room_code_copied_time = 1.35
	status_message = "Code %s copie" % room_code

func _setup_audio() -> void:
	sound_streams["shoot"] = _make_tone(920.0, 520.0, 0.075, 0.24)
	sound_streams["brick"] = _make_tone(180.0, 82.0, 0.13, 0.30)
	sound_streams["bonus"] = _make_tone(540.0, 1040.0, 0.16, 0.22)
	sound_streams["empty"] = _make_tone(190.0, 150.0, 0.11, 0.20)
	sound_streams["blocked"] = _make_tone(250.0, 95.0, 0.16, 0.24)
	sound_streams["count"] = _make_tone(720.0, 720.0, 0.08, 0.18)
	sound_streams["start"] = _make_tone(520.0, 1180.0, 0.22, 0.24)
	for key in sound_streams.keys():
		var player := AudioStreamPlayer.new()
		player.stream = sound_streams[key]
		player.volume_db = -10.0
		add_child(player)
		sound_players[key] = player

func _make_tone(start_hz: float, end_hz: float, duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate := 44100
	var sample_count := int(duration * float(sample_rate))
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	var phase := 0.0
	for i in range(sample_count):
		var t := float(i) / maxf(1.0, float(sample_count - 1))
		var hz := lerpf(start_hz, end_hz, t)
		phase += TAU * hz / float(sample_rate)
		var envelope := pow(1.0 - t, 1.8)
		var sample := sin(phase) * envelope * volume
		if start_hz < 250.0:
			sample += sin(phase * 0.47) * envelope * volume * 0.55
		var pcm := int(clampf(sample, -1.0, 1.0) * 32767.0)
		if pcm < 0:
			pcm += 65536
		bytes[i * 2] = pcm & 0xff
		bytes[i * 2 + 1] = (pcm >> 8) & 0xff
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = bytes
	return stream

func _play_sound(kind: String) -> void:
	var player = sound_players.get(kind, null)
	if player is AudioStreamPlayer:
		player.stop()
		player.play()

func _update_sound_cues(data: Dictionary) -> void:
	var status := str(data.get("status", "waiting"))
	var countdown_second := -1
	if status == "countdown":
		countdown_second = max(1, int(ceil(float(data.get("countdown", 0.0)))))
		if countdown_second != previous_countdown_second:
			_play_sound("count")
	elif status == "playing" and previous_room_status == "countdown":
		_play_sound("start")
	previous_room_status = status
	previous_countdown_second = countdown_second

	var new_projectile_ids := {}
	var role := int(data.get("you", my_role))
	var has_new_local_projectile := false
	for proj in data.get("projectiles", []):
		if typeof(proj) != TYPE_DICTIONARY:
			continue
		var id := int(proj.get("id", -1))
		new_projectile_ids[id] = true
		if not previous_projectile_ids.has(id) and int(proj.get("owner", -1)) == role:
			has_new_local_projectile = true
	if has_new_local_projectile:
		_play_sound("shoot")
	var alive_bricks := 0
	for brick in data.get("bricks", []):
		if typeof(brick) == TYPE_DICTIONARY and bool(brick.get("alive", true)):
			alive_bricks += 1
	if previous_alive_bricks >= 0 and alive_bricks < previous_alive_bricks:
		_play_sound("brick")
	previous_alive_bricks = alive_bricks
	previous_projectile_ids = new_projectile_ids

func _handle_event_sound(message: String) -> void:
	var lower := message.to_lower()
	if lower.find("bonus") >= 0 or lower.find("+1 ") >= 0 or lower.find("rapid active") >= 0 or lower.find("shield actif") >= 0 or lower.find("split tir") >= 0:
		_play_sound("bonus")

func _handle_key_input(event: InputEventKey) -> bool:
	var keycodes: Array[int] = [event.keycode, event.physical_keycode]
	var unicode := int(event.unicode)
	if keycodes.has(KEY_F5):
		_reload_page()
		return true
	if keycodes.has(KEY_SPACE) or keycodes.has(KEY_ENTER) or keycodes.has(KEY_KP_ENTER):
		_play_fire_blocked_sound_if_needed()
		return false
	if keycodes.has(KEY_1) or keycodes.has(KEY_KP_1) or unicode == 49:
		_request_action("rapid")
		return true
	if keycodes.has(KEY_2) or keycodes.has(KEY_KP_2) or unicode == 50:
		_request_action("shield")
		return true
	if keycodes.has(KEY_3) or keycodes.has(KEY_KP_3) or unicode == 51:
		_request_action("split")
		return true
	if keycodes.has(KEY_R):
		_request_rematch()
		return true
	return false

func _request_rematch() -> void:
	_send_json({"type": "restart"})
	status_message = "Revanche demandee"

func _reload_page() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.reload()", false)
	else:
		_connect_to_server()

func _play_fire_blocked_sound_if_needed() -> void:
	if str(current_state.get("status", "")) != "playing":
		return
	if _active_weapon_can_fire():
		return
	if fire_blocked_sound_cooldown > 0.0:
		return
	_play_sound("blocked")
	fire_blocked_sound_cooldown = 0.16

func _active_weapon_can_fire() -> bool:
	var player := _local_player_from_state(current_state)
	if player.is_empty():
		return false
	var cooldown := float(player.get("cooldown", 0.0))
	if cooldown > 0.0:
		return false
	var active_weapon := str(player.get("active", ""))
	var reserves: Dictionary = player.get("ammoReserve", {})
	var reserve := int(reserves.get(active_weapon, player.get("ammo", 0)))
	return active_weapon != "" and reserve > 0

func _pointer_down(id, pos: Vector2) -> void:
	if not _virtual_rect().has_point(pos):
		return
	var action := _action_at_pos(pos)
	if action != "":
		if fire_touches.has(id):
			fire_touches.erase(id)
		action_touches[id] = action
		_request_action(action)
		return
	if not _is_move_zone(pos):
		_play_fire_blocked_sound_if_needed()
		fire_touches[id] = true
		_send_input()
		return
	move_touches[id] = true
	touch_target_x = clampf(pos.x, 40.0, WORLD_W - 40.0)
	_send_input()

func _pointer_move(id, pos: Vector2) -> void:
	var action := _action_at_pos(pos)
	if action != "":
		if move_touches.has(id):
			move_touches.erase(id)
			if move_touches.size() == 0:
				touch_target_x = -1.0
		if fire_touches.has(id):
			fire_touches.erase(id)
		if str(action_touches.get(id, "")) != action:
			action_touches[id] = action
			_request_action(action)
		else:
			_send_input()
		return
	if action_touches.has(id):
		action_touches.erase(id)
	if move_touches.has(id):
		if _is_move_zone(pos):
			touch_target_x = clampf(pos.x, 40.0, WORLD_W - 40.0)
		else:
			move_touches.erase(id)
			if move_touches.size() == 0:
				touch_target_x = -1.0
			_play_fire_blocked_sound_if_needed()
			fire_touches[id] = true
		_send_input()
	elif fire_touches.has(id):
		_send_input()
	elif not _is_move_zone(pos):
		_play_fire_blocked_sound_if_needed()
		fire_touches[id] = true
		_send_input()

func _pointer_up(id) -> void:
	var changed := false
	if move_touches.has(id):
		move_touches.erase(id)
		changed = true
		if move_touches.size() == 0:
			touch_target_x = -1.0
	if fire_touches.has(id):
		fire_touches.erase(id)
		changed = true
	if action_touches.has(id):
		action_touches.erase(id)
	if changed:
		_send_input()

func _request_switch(weapon: String) -> void:
	if WEAPON_ORDER.has(weapon):
		pending_switch = weapon
		_send_input()

func _request_action(action: String) -> void:
	if ACTION_ORDER.has(action):
		pending_action = action
		_send_input()

func _weapon_rules(weapon: String) -> Dictionary:
	var weapons = room_rules.get("weapons", {})
	if typeof(weapons) != TYPE_DICTIONARY:
		return {}
	var data = weapons.get(weapon, {})
	if typeof(data) == TYPE_DICTIONARY:
		return data
	return {}

func _weapon_label(weapon: String) -> String:
	var rules := _weapon_rules(weapon)
	return str(rules.get("label", WEAPON_LABELS.get(weapon, weapon)))

func _weapon_ammo_max(weapon: String) -> int:
	var rules := _weapon_rules(weapon)
	return max(1, int(round(float(rules.get("ammo", WEAPON_AMMO_MAX.get(weapon, 1))))))

func _weapon_reload_time(weapon: String) -> float:
	var rules := _weapon_rules(weapon)
	return maxf(0.01, float(rules.get("reload", WEAPON_RELOAD_TIME.get(weapon, 1.0))))

func _action_icon_source(action: String) -> Rect2:
	if action == "shield":
		return ATLAS_POWER_SHIELD
	if action == "rapid":
		return ATLAS_POWER_RAPID
	return ATLAS_POWER_SPLIT

func _add_event(message: String) -> void:
	if message == "":
		return
	event_log.append(message)
	while event_log.size() > 5:
		event_log.pop_front()

func _record_state_snapshot(data: Dictionary) -> void:
	state_buffer.append(data)
	while state_buffer.size() > 8:
		state_buffer.pop_front()

func _update_ammo_empty_feedback(delta: float) -> void:
	var player := _local_player_from_state(current_state)
	var is_empty := false
	var active_weapon := ""
	if not player.is_empty():
		active_weapon = str(player.get("active", ""))
		var reserves: Dictionary = player.get("ammoReserve", {})
		var reserve := int(reserves.get(active_weapon, player.get("ammo", 0)))
		is_empty = active_weapon != "" and reserve <= 0

	if is_empty:
		if not ammo_empty_feedback or active_weapon != ammo_empty_weapon:
			_play_sound("empty")
			ammo_empty_pulse = 0.0
			ammo_empty_time = 0.0
		ammo_empty_feedback = true
		ammo_empty_weapon = active_weapon
		ammo_empty_time += delta
	else:
		ammo_empty_feedback = false
		ammo_empty_weapon = ""
		ammo_empty_time = 0.0

	ammo_empty_pulse = 0.0

func _get_render_state() -> Dictionary:
	if state_buffer.is_empty():
		return current_state
	if state_buffer.size() == 1:
		return state_buffer[0]

	var target_time: float = Time.get_ticks_msec() * 0.001 - SNAPSHOT_INTERPOLATION_DELAY
	while state_buffer.size() >= 3 and float(state_buffer[1].get("_rx", 0.0)) <= target_time:
		state_buffer.pop_front()

	var from_state: Dictionary = state_buffer[0]
	var to_state: Dictionary = state_buffer[1]
	var from_time: float = float(from_state.get("_rx", target_time))
	var to_time: float = float(to_state.get("_rx", target_time))
	if to_time <= from_time:
		return to_state

	var alpha: float = clampf((target_time - from_time) / (to_time - from_time), 0.0, 1.0)
	return _interpolate_state(from_state, to_state, alpha)

func _interpolate_state(from_state: Dictionary, to_state: Dictionary, alpha: float) -> Dictionary:
	var output: Dictionary = to_state.duplicate(false)
	output["balls"] = _interpolate_object_array(from_state.get("balls", []), to_state.get("balls", []), alpha, "id")
	output["players"] = _interpolate_object_array(from_state.get("players", []), to_state.get("players", []), alpha, "role")
	output["projectiles"] = _interpolate_object_array(from_state.get("projectiles", []), to_state.get("projectiles", []), alpha, "id")
	output["powerups"] = _interpolate_object_array(from_state.get("powerups", []), to_state.get("powerups", []), alpha, "id")
	return output

func _interpolate_object_array(from_array: Array, to_array: Array, alpha: float, key_name: String) -> Array:
	var output: Array = []
	for item in to_array:
		if typeof(item) != TYPE_DICTIONARY:
			output.append(item)
			continue
		var to_object: Dictionary = item
		var from_object: Dictionary = _find_object_by_key(from_array, key_name, to_object.get(key_name, null))
		if from_object.is_empty():
			output.append(to_object)
		else:
			output.append(_interpolate_object(from_object, to_object, alpha))
	return output

func _find_object_by_key(objects: Array, key_name: String, key_value: Variant) -> Dictionary:
	if key_value == null:
		return {}
	for item in objects:
		if typeof(item) == TYPE_DICTIONARY and item.get(key_name, null) == key_value:
			return item
	return {}

func _interpolate_object(from_object: Dictionary, to_object: Dictionary, alpha: float) -> Dictionary:
	var output: Dictionary = to_object.duplicate(false)
	if from_object.has("x") and to_object.has("x"):
		output["x"] = lerpf(float(from_object.get("x", 0.0)), float(to_object.get("x", 0.0)), alpha)
	if from_object.has("y") and to_object.has("y"):
		output["y"] = lerpf(float(from_object.get("y", 0.0)), float(to_object.get("y", 0.0)), alpha)
	return output

func _draw() -> void:
	var fit := _fit_transform()
	draw_fit_offset = fit["offset"]
	draw_fit_scale = fit["scale"]
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.02, 0.025, 0.035, 1.0))
	draw_set_transform(draw_fit_offset, 0.0, Vector2(draw_fit_scale, draw_fit_scale))
	_draw_virtual()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_fps_overlay()

func _draw_virtual() -> void:
	_draw_background()
	if lobby_menu_visible:
		_draw_lobby_menu()
		return
	visual_state = _get_render_state()
	if visual_state.is_empty():
		_draw_waiting_screen()
		return
	_draw_bricks()
	_draw_powerups()
	_draw_projectiles()
	_draw_balls()
	_draw_players()
	var status := str(visual_state.get("status", "waiting"))
	if status == "waiting" or status == "countdown":
		_draw_room_ready_overlay()
		_draw_status_overlay()
		return
	_draw_hud()
	_draw_status_overlay()

func _draw_background() -> void:
	if tex_space_bg:
		draw_texture_rect(tex_space_bg, Rect2(0, 0, WORLD_W, WORLD_H), false, Color(1, 1, 1, 1))
	else:
		draw_rect(Rect2(0, 0, WORLD_W, WORLD_H), Color(0.02, 0.025, 0.045, 1.0))
	for i in range(0, int(WORLD_H), 128):
		draw_line(Vector2(0, i), Vector2(WORLD_W, i), Color(0.45, 0.85, 1.0, 0.035), 1.0)
	for x in range(0, int(WORLD_W), 128):
		draw_line(Vector2(x, 0), Vector2(x, WORLD_H), Color(0.45, 0.85, 1.0, 0.025), 1.0)
	draw_rect(Rect2(14, 14, WORLD_W - 28, WORLD_H - 28), Color(1, 1, 1, 0.30), false, 4.0)
	draw_line(Vector2(40, WORLD_H * 0.5), Vector2(WORLD_W - 40, WORLD_H * 0.5), Color(1, 1, 1, 0.22), 3.0)
	draw_circle(Vector2(WORLD_W * 0.5, WORLD_H * 0.5), 72.0, Color(1, 1, 1, 0.035))
	draw_arc(Vector2(WORLD_W * 0.5, WORLD_H * 0.5), 72.0, 0.0, TAU, 96, Color(1, 1, 1, 0.16), 3.0)

func _draw_lobby_menu() -> void:
	var panel := _lobby_panel_rect()
	draw_rect(panel, Color(0.025, 0.035, 0.05, 0.92), true)
	draw_rect(panel, Color(0.55, 0.82, 1.0, 0.24), false, 2.0)
	_draw_centered_text("BREAKSHOT", Vector2(WORLD_W * 0.5, panel.position.y + 68.0), 54, Color(1, 1, 1, 1))
	_draw_centered_text("ROOMS", Vector2(WORLD_W * 0.5, panel.position.y + 116.0), 22, Color(0.72, 0.9, 1.0, 0.92))
	_draw_menu_button(_lobby_create_rect(), "CREER UNE ROOM", Color(0.06, 0.42, 0.62, 0.92), true)
	_draw_menu_button(_lobby_quick_rect(), "QUICK MATCH", Color(0.10, 0.34, 0.22, 0.92), true)
	_draw_menu_button(_lobby_bot_rect(), "SOLO BOT", Color(0.34, 0.24, 0.08, 0.92), true)
	var input_rect := _lobby_join_input_rect()
	draw_rect(input_rect, Color(0, 0, 0, 0.38), true)
	draw_rect(input_rect, Color(0.7, 0.95, 1.0, 0.72 if lobby_join_focused else 0.28), false, 2.0)
	var code_text := lobby_join_code if lobby_join_code != "" else "CODE ROOM"
	_draw_centered_text(code_text, input_rect.get_center() + Vector2(0, 10), 28, Color(1, 1, 1, 0.96 if lobby_join_code != "" else 0.45))
	_draw_menu_button(_lobby_join_paste_rect(), "COLLER", Color(0.10, 0.20, 0.28, 0.92), false)
	_draw_menu_button(_lobby_join_rect(), "REJOINDRE", Color(0.48, 0.14, 0.34, 0.92), true)

func _draw_room_code_chip() -> void:
	if room_code == "":
		return
	var rect := _room_code_copy_rect()
	var progress := 0.0
	if room_code_hold_id != "":
		progress = clampf(room_code_hold_elapsed / ROOM_CODE_HOLD_SECONDS, 0.0, 1.0)
	var copied := room_code_copied_time > 0.0
	var fill := Color(0.04, 0.16, 0.22, 0.88)
	if copied:
		fill = Color(0.05, 0.34, 0.20, 0.92)
	draw_rect(rect, fill, true)
	draw_rect(rect, Color(0.75, 0.95, 1.0, 0.36), false, 2.0)
	if progress > 0.0 and not copied:
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * progress, rect.size.y)), Color(0.3, 0.82, 1.0, 0.24), true)
	var label := "COPIE" if copied else room_code
	_draw_centered_text(label, rect.get_center() + Vector2(0, 7), 18, Color(1, 1, 1, 0.96))

func _draw_room_ready_overlay() -> void:
	var status := str(visual_state.get("status", "waiting"))
	var player_count := int(visual_state.get("playerCount", _connected_players_from_state()))
	var capacity := int(visual_state.get("capacity", 2))
	var countdown := float(visual_state.get("countdown", 0.0))
	var rect := Rect2(WORLD_W * 0.5 - 142.0, WORLD_H * 0.5 - 78.0, 284.0, 156.0)
	draw_rect(rect, Color(0.02, 0.025, 0.033, 0.82), true)
	draw_rect(rect, Color(0.75, 0.95, 1.0, 0.30), false, 2.0)
	var fill_width := rect.size.x * clampf(float(player_count) / maxf(1.0, float(capacity)), 0.0, 1.0)
	draw_rect(Rect2(rect.position, Vector2(fill_width, rect.size.y)), Color(0.09, 0.34, 0.48, 0.25), true)
	if status == "countdown":
		var seconds: int = max(1, int(ceil(countdown)))
		_draw_centered_text("%d" % seconds, rect.get_center() + Vector2(0, 7), 74, Color(1, 1, 1, 0.98))
		_draw_centered_text("START", rect.get_center() + Vector2(0, 57), 18, Color(0.76, 0.92, 1.0, 0.88))
		return
	_draw_centered_text("%d/%d" % [player_count, capacity], rect.get_center() + Vector2(0, -2), 56, Color(1, 1, 1, 0.98))
	var sub := "EN ATTENTE"
	_draw_centered_text(sub, rect.get_center() + Vector2(0, 50), 18, Color(0.76, 0.92, 1.0, 0.88))

func _draw_menu_button(rect: Rect2, text: String, fill: Color, strong: bool) -> void:
	draw_rect(rect, fill, true)
	draw_rect(rect, Color(0.75, 0.95, 1.0, 0.42 if strong else 0.26), false, 2.0)
	_draw_centered_text(text, rect.get_center() + Vector2(0, 8), 22 if strong else 18, Color(1, 1, 1, 0.96))

func _draw_waiting_screen() -> void:
	var font := ui_font
	_draw_centered_text("BREAKSHOT", Vector2(WORLD_W * 0.5, 315), 54, Color(1, 1, 1, 1))
	_draw_centered_text("Pong + casse-briques + tirs", Vector2(WORLD_W * 0.5, 372), 22, Color(0.75, 0.85, 1.0, 1))
	_draw_room_code_chip()
	var box := Rect2(70, 465, WORLD_W - 140, 300)
	draw_rect(box, Color(0, 0, 0, 0.34), true)
	draw_rect(box, Color(1, 1, 1, 0.18), false, 2.0)
	var room_line := "Code room: %s" % room_code if room_code != "" else "Code room en creation..."
	var link_line := "Lien: %s" % invite_url if invite_url != "" and room_launch_mode != "quick" and not _wants_quick_match() else ""
	var lines := [
		status_message,
		room_line,
		link_line,
		"Lance le serveur: cd server && npm install && npm start",
		"Ouvre deux clients Godot ou deux onglets web.",
		"Mobile: glisse pour viser, bouton TIR pour shooter.",
		"Clavier: A/D ou flèches, Espace, touches 1-3."
	]
	var y := box.position.y + 48.0
	for line in lines:
		draw_string(font, Vector2(box.position.x + 26, y), line, HORIZONTAL_ALIGNMENT_LEFT, box.size.x - 52, 21, Color(0.93, 0.96, 1.0, 1))
		y += 38.0

func _draw_bricks() -> void:
	var bricks: Array = visual_state.get("bricks", [])
	for brick in bricks:
		if typeof(brick) != TYPE_DICTIONARY:
			continue
		if not bool(brick.get("alive", true)):
			continue
		var owner := int(brick.get("owner", -1))
		var rect := _world_rect_to_local(Rect2(float(brick.get("x", 0.0)), float(brick.get("y", 0.0)), float(brick.get("w", 80.0)), float(brick.get("h", 28.0))))
		var is_local := owner == my_role
		var protected := bool(brick.get("protected", false))
		var brick_src := ATLAS_BRICK_BLUE if is_local else ATLAS_BRICK_RED
		_draw_atlas_region(brick_src, rect, not is_local, Color(1, 1, 1, 1))
		if protected:
			var shield_src := ATLAS_SHIELD_SEGMENT_BLUE if is_local else ATLAS_SHIELD_SEGMENT_RED
			_draw_atlas_region(shield_src, rect.grow(2), not is_local, Color(1, 1, 1, 0.9))
			draw_rect(rect.grow(3), Color(0.45, 0.76, 1.0, 0.55), false, 3.0)

func _draw_powerups() -> void:
	var powerups: Array = visual_state.get("powerups", [])
	for power in powerups:
		if typeof(power) != TYPE_DICTIONARY:
			continue
		var pos := _world_to_local(Vector2(float(power.get("x", 0.0)), float(power.get("y", 0.0))))
		var ptype := str(power.get("kind", "ammo"))
		var source := _action_icon_source("split")
		if ptype == "shield":
			source = _action_icon_source("shield")
		elif ptype == "rapid":
			source = _action_icon_source("rapid")
		elif ptype == "split":
			source = _action_icon_source("split")
		var rect := Rect2(pos.x - 26.0, pos.y - 26.0, 52.0, 52.0)
		_draw_atlas_region(source, rect, false, Color(1, 1, 1, 0.95))
		var owner := int(power.get("owner", -1))
		if owner == my_role:
			draw_arc(pos, 33, 0, TAU, 40, Color(1, 1, 1, 0.45), 2)

func _draw_projectiles() -> void:
	var projectiles: Array = visual_state.get("projectiles", [])
	for proj in projectiles:
		if typeof(proj) != TYPE_DICTIONARY:
			continue
		var pos := _world_to_local(Vector2(float(proj.get("x", 0.0)), float(proj.get("y", 0.0))))
		var ptype := str(proj.get("kind", "sniper"))
		var owner := int(proj.get("owner", -1))
		var is_local := owner == my_role
		var source := ATLAS_HEAVY_BLUE if is_local else ATLAS_HEAVY_RED
		var rect := Rect2(pos.x - 9.0, pos.y - 18.0, 18.0, 36.0)
		var vx := float(proj.get("vx", 0.0))
		var vy := float(proj.get("vy", -1.0 if is_local else 1.0))
		var angle := atan2(vy, vx) + PI * 0.5
		_draw_atlas_region_rotated(source, rect, angle, Color(1, 1, 1, 0.98))

func _draw_balls() -> void:
	var balls: Array = visual_state.get("balls", [])
	if balls.is_empty():
		var single_ball: Dictionary = visual_state.get("ball", {})
		if not single_ball.is_empty():
			_draw_ball_object(single_ball)
		return
	for ball in balls:
		if typeof(ball) == TYPE_DICTIONARY:
			_draw_ball_object(ball)

func _draw_ball_object(ball: Dictionary) -> void:
	var pos := _world_to_local(Vector2(float(ball.get("x", WORLD_W * 0.5)), float(ball.get("y", WORLD_H * 0.5))))
	var r := float(ball.get("r", 16.0))
	var rect := Rect2(pos.x - r, pos.y - r, r * 2.0, r * 2.0)
	_draw_atlas_region_rotated(ATLAS_BALL_MAIN, rect, ball_visual_angle, Color(1, 1, 1, 1))

func _draw_players() -> void:
	var players: Array = visual_state.get("players", [])
	for player in players:
		if typeof(player) != TYPE_DICTIONARY:
			continue
		var role := int(player.get("role", -1))
		var pos := _world_to_local(Vector2(float(player.get("x", WORLD_W * 0.5)), float(player.get("y", WORLD_H * 0.5))))
		var is_local := role == my_role
		if is_local and touch_target_x >= 0.0:
			pos.x = touch_target_x
		var ship_src := ATLAS_SHIP_BLUE if is_local else ATLAS_SHIP_RED
		var rotate_180 := not is_local
		_draw_player_bonus_effects(player, pos, is_local)
		_draw_atlas_region(ship_src, Rect2(pos.x - 46.0, pos.y - 37.0, 92.0, 74.0), rotate_180, Color(1, 1, 1, 0.98))
		if bool(player.get("protected", false)):
			var bubble_src := ATLAS_SHIELD_BUBBLE_BLUE if is_local else ATLAS_SHIELD_BUBBLE_RED
			_draw_atlas_region(bubble_src, Rect2(pos.x - 76.0, pos.y - 76.0, 152.0, 152.0), false, Color(1, 1, 1, 0.7))
		if is_local and touch_target_x >= 0.0:
			var target := Vector2(touch_target_x, pos.y)
			draw_line(Vector2(touch_target_x, pos.y - 70.0), Vector2(touch_target_x, pos.y + 70.0), Color(1, 1, 1, 0.20), 2.0)
			draw_circle(target, 8.0, Color(1, 1, 1, 0.35))

func _draw_hud() -> void:
	var player := _local_player()
	var active := str(player.get("active", "sniper")) if not player.is_empty() else "sniper"
	var ammo := int(player.get("ammo", 0)) if not player.is_empty() else 0
	var cooldown := float(player.get("cooldown", 0.0)) if not player.is_empty() else 0.0
	var cooldown_max := float(player.get("cooldownMax", 1.0)) if not player.is_empty() else 1.0
	var reserves: Dictionary = player.get("ammoReserve", {}) if not player.is_empty() else {}
	var reloads: Dictionary = player.get("ammoReload", {}) if not player.is_empty() else {}
	var action_stacks: Dictionary = player.get("actionStacks", {}) if not player.is_empty() else {}

	for i in range(ACTION_ORDER.size()):
		var action: String = ACTION_ORDER[i]
		var ring_rect := _weapon_ring_rect()
		var stack := int(action_stacks.get(action, 0))
		var active_time := _action_active_remaining(player, action)
		var active_total := _action_active_total(player, action)
		var is_ready := stack > 0 and active_time <= 0.0
		var button_src := _weapon_segment_source(i, is_ready, false)
		_draw_button_region(button_src, ring_rect, Color(1, 1, 1, 0.98 if is_ready else 0.72))
		if active_time > 0.0 and active_total > 0.0:
			var active_pct := clampf(active_time / active_total, 0.0, 1.0)
			_draw_weapon_arc(i, UI_WEAPON_INNER_RADIUS + 10.0, active_pct, Color(0.35, 0.72, 1.0, 0.75), 7.0)
		var label_pos := _weapon_segment_label_pos(i)
		_draw_action_stack_icons(action, stack, label_pos, is_ready or active_time > 0.0)

	var fire_rect := _fire_button_rect()
	var firing := fire_touches.size() > 0 or Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_ENTER)
	var fire_src := UI_FIRE_PRESSED if firing else UI_FIRE_IDLE
	_draw_button_region(fire_src, fire_rect, Color(1, 1, 1, 0.9))
	_draw_centered_text("TIR", fire_rect.get_center() + Vector2(0, 9), 26, Color(1, 1, 1, 1))
	if cooldown > 0.0:
		var pct := clampf(cooldown / maxf(cooldown_max, 0.01), 0.0, 1.0)
		draw_arc(fire_rect.get_center(), fire_rect.size.x * 0.5 + 9, -PI * 0.5, -PI * 0.5 + TAU * pct, 64, Color(1.0, 0.93, 0.28, 0.9), 6.0)
	var sniper_max := _weapon_ammo_max(active)
	var sniper_reserve := int(reserves.get(active, ammo))
	var sniper_reload := float(reloads.get(active, 0.0))
	_draw_ammo_bar(fire_rect, sniper_reserve, sniper_max, sniper_reload, _weapon_reload_time(active))

func _draw_move_limit_bar() -> void:
	draw_rect(Rect2(0, MOVE_BAR_Y, WORLD_W, WORLD_H - MOVE_BAR_Y), Color(0.06, 0.10, 0.13, 0.16), true)
	draw_line(Vector2(36.0, MOVE_BAR_Y), Vector2(WORLD_W - 36.0, MOVE_BAR_Y), Color(0.72, 0.92, 1.0, 0.72), 5.0)
	draw_line(Vector2(36.0, MOVE_BAR_Y + 9.0), Vector2(WORLD_W - 36.0, MOVE_BAR_Y + 9.0), Color(0.14, 0.24, 0.32, 0.66), 2.0)
	draw_circle(Vector2(36.0, MOVE_BAR_Y), 8.0, Color(0.72, 0.92, 1.0, 0.72))
	draw_circle(Vector2(WORLD_W - 36.0, MOVE_BAR_Y), 8.0, Color(0.72, 0.92, 1.0, 0.72))

func _draw_status_overlay() -> void:
	var font := ui_font
	var status := str(visual_state.get("status", "waiting"))
	var winner := int(visual_state.get("winner", -1))
	_draw_room_code_chip()
	if status == "ended":
		draw_rect(Rect2(60, 455, WORLD_W - 120, 180), Color(0, 0, 0, 0.68), true)
		draw_rect(Rect2(60, 455, WORLD_W - 120, 180), Color(1, 1, 1, 0.24), false, 2.0)
		var result_text := "VICTOIRE" if winner == my_role else "DEFAITE"
		_draw_centered_text(result_text, Vector2(WORLD_W * 0.5, 530), 48, Color(1, 1, 1, 1))
		_draw_menu_button(_rematch_button_rect(), "REVANCHE", Color(0.38, 0.08, 0.14, 0.95), true)
	return

func _draw_fps_overlay() -> void:
	var font := ui_font
	var latency_text := "--" if server_latency_ms < 0 else str(server_latency_ms)
	var fps_text := "FPS %d  %sms" % [Engine.get_frames_per_second(), latency_text]
	var rect := Rect2(10, 10, 142, 28)
	draw_rect(rect, Color(0, 0, 0, 0.58), true)
	draw_rect(rect, Color(1, 1, 1, 0.18), false, 1.0)
	draw_string(font, Vector2(rect.position.x + 9, rect.position.y + 20), fps_text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 18, 15, Color(0.90, 1.0, 0.82, 0.96))

func _draw_atlas_region(source: Rect2, rect: Rect2, rotate_180: bool, color: Color) -> void:
	if rotate_180:
		_draw_atlas_region_rotated(source, rect, PI, color)
		return
	draw_texture_rect_region(TEX_ATLAS, rect, source, color)

func _draw_atlas_region_rotated(source: Rect2, rect: Rect2, angle: float, color: Color) -> void:
	var center := draw_fit_offset + rect.get_center() * draw_fit_scale
	draw_set_transform(center, angle, Vector2(draw_fit_scale, draw_fit_scale))
	draw_texture_rect_region(TEX_ATLAS, Rect2(-rect.size * 0.5, rect.size), source, color)
	draw_set_transform(draw_fit_offset, 0.0, Vector2(draw_fit_scale, draw_fit_scale))

func _draw_button_region(source: Rect2, rect: Rect2, color: Color) -> void:
	draw_texture_rect_region(TEX_BUTTON_ATLAS, rect, source, color)

func _draw_player_bonus_effects(player: Dictionary, pos: Vector2, is_local: bool) -> void:
	var rapid_time := float(player.get("rapid", 0.0))
	var split_time := float(player.get("split", 0.0))
	var shield_time := float(player.get("shield", 0.0))
	var facing := -1.0 if is_local else 1.0
	var back := -facing
	var phase := Time.get_ticks_msec() * 0.006
	if rapid_time > 0.0:
		for i in range(3):
			var offset := sin(phase + float(i) * 1.7) * 6.0
			var trail_center := pos + Vector2(-36.0 + float(i) * 36.0 + offset, back * 50.0)
			var rect := Rect2(trail_center.x - 24.0, trail_center.y - 32.0, 48.0, 64.0)
			if tex_fx_rapid:
				draw_texture_rect(tex_fx_rapid, rect, false, Color(1, 1, 1, 0.65), false)
	if split_time > 0.0:
		var ghost_alpha := 0.22 + 0.06 * sin(phase * 1.4)
		if tex_fx_split:
			draw_texture_rect(tex_fx_split, Rect2(pos.x - 82.0, pos.y - 32.0, 116.0, 64.0), false, Color(1, 1, 1, ghost_alpha), false)
			draw_texture_rect(tex_fx_split, Rect2(pos.x - 34.0, pos.y - 32.0, 116.0, 64.0), false, Color(1, 1, 1, ghost_alpha), false)
		var split_start := 205.0 if is_local else 25.0
		var split_end := 335.0 if is_local else 155.0
		draw_arc(pos, 70.0, deg_to_rad(split_start), deg_to_rad(split_end), 32, Color(0.68, 0.36, 1.0, 0.56), 4.0)
	if shield_time > 0.0:
		if tex_fx_shield:
			draw_texture_rect(tex_fx_shield, Rect2(pos.x - 82.0, pos.y - 82.0, 164.0, 164.0), false, Color(1, 1, 1, 0.72), false)
		var spin := phase if is_local else -phase
		draw_arc(pos, 86.0, spin, spin + TAU * 0.72, 48, Color(0.24, 1.0, 0.56, 0.68), 5.0)
		draw_arc(pos, 94.0, -spin * 0.7, -spin * 0.7 + TAU * 0.42, 36, Color(0.76, 1.0, 0.86, 0.42), 3.0)

func _fit_transform() -> Dictionary:
	var screen: Vector2 = get_viewport_rect().size
	var scale: float = minf(screen.x / WORLD_W, screen.y / WORLD_H)
	var size: Vector2 = WORLD_SIZE * scale
	var offset: Vector2 = (screen - size) * 0.5
	return {"scale": scale, "offset": offset}

func _screen_to_virtual(screen_pos: Vector2) -> Vector2:
	var fit := _fit_transform()
	return (screen_pos - fit["offset"]) / fit["scale"]

func _virtual_rect() -> Rect2:
	return Rect2(0, 0, WORLD_W, WORLD_H)

func _is_move_zone(pos: Vector2) -> bool:
	return pos.y >= MOVE_BAR_Y

func _world_to_local(p: Vector2) -> Vector2:
	if my_role == 1:
		return Vector2(p.x, WORLD_H - p.y)
	return p

func _world_rect_to_local(r: Rect2) -> Rect2:
	if my_role == 1:
		return Rect2(r.position.x, WORLD_H - r.position.y - r.size.y, r.size.x, r.size.y)
	return r

func _weapon_ring_rect() -> Rect2:
	var size := Vector2(UI_RING_FRAME_SIZE, UI_RING_FRAME_SIZE)
	return Rect2(_fire_button_rect().get_center() - size * 0.5, size)

func _weapon_segment_source(index: int, is_active: bool, _is_empty: bool) -> Rect2:
	var state_col := 0
	if is_active:
		state_col = 1
	return Rect2(UI_RING_START + Vector2(float(state_col) * UI_RING_FRAME_STEP, float(index) * UI_RING_FRAME_STEP), Vector2(UI_RING_FRAME_SIZE, UI_RING_FRAME_SIZE))

func _weapon_angle_range(index: int) -> Vector2:
	if index == 0:
		return Vector2(-86.0, -34.0)
	if index == 1:
		return Vector2(-27.0, 27.0)
	return Vector2(34.0, 86.0)

func _weapon_angle_center(index: int) -> float:
	var angle_range := _weapon_angle_range(index)
	return (angle_range.x + angle_range.y) * 0.5

func _weapon_segment_label_pos(index: int) -> Vector2:
	var angle := deg_to_rad(_weapon_angle_center(index))
	return _fire_button_rect().get_center() + Vector2(cos(angle), sin(angle)) * 138.0

func _draw_weapon_arc(index: int, radius: float, pct: float, color: Color, width: float) -> void:
	if pct <= 0.0:
		return
	var angle_range := _weapon_angle_range(index)
	var start_angle := deg_to_rad(angle_range.x)
	var end_angle := deg_to_rad(lerpf(angle_range.x, angle_range.y, clampf(pct, 0.0, 1.0)))
	draw_arc(_fire_button_rect().get_center(), radius, start_angle, end_angle, 24, color, width)

func _action_active_remaining(player: Dictionary, action: String) -> float:
	if action == "rapid":
		return float(player.get("rapid", 0.0))
	if action == "shield":
		return float(player.get("shield", 0.0))
	if action == "split":
		return float(player.get("split", 0.0))
	return 0.0

func _action_active_total(player: Dictionary, action: String) -> float:
	if action == "rapid":
		return maxf(0.01, float(player.get("rapidMax", 5.0)))
	if action == "shield":
		return maxf(0.01, float(player.get("shieldMax", 1.0)))
	if action == "split":
		return maxf(0.01, float(player.get("splitMax", 3.0)))
	return 1.0

func _draw_action_stack_icons(action: String, stack: int, center: Vector2, highlighted: bool) -> void:
	var icon := _action_icon_source(action)
	var visible_count: int = mini(maxi(stack, 1), 9)
	var points := _stack_points(visible_count)
	var size := _stack_icon_size(visible_count)
	var alpha := 0.98 if highlighted else 0.48
	for point in points:
		var p := center + point
		_draw_atlas_region(icon, Rect2(p.x - size * 0.5, p.y - size * 0.5, size, size), false, Color(1, 1, 1, alpha))

func _stack_icon_size(count: int) -> float:
	if count <= 1:
		return 48.0
	if count == 2:
		return 32.0
	if count == 3:
		return 27.0
	if count == 4:
		return 25.0
	return 20.0

func _stack_points(count: int) -> Array[Vector2]:
	if count <= 1:
		return [Vector2.ZERO]
	if count == 2:
		return [Vector2(-8, 0), Vector2(8, 0)]
	if count == 3:
		return [Vector2(0, -8), Vector2(-9, 7), Vector2(9, 7)]
	if count == 4:
		return [Vector2(-8, -8), Vector2(8, -8), Vector2(-8, 8), Vector2(8, 8)]
	var cols: int = 3
	var rows: int = int(ceil(float(count) / float(cols)))
	var output: Array[Vector2] = []
	for i in range(count):
		var col: int = i % cols
		var row: int = int(i / cols)
		output.append(Vector2((float(col) - 1.0) * 12.0, (float(row) - float(rows - 1) * 0.5) * 12.0))
	return output

func _draw_ammo_bar(fire_rect: Rect2, reserve: int, max_ammo: int, reload_remaining: float, reload_total: float) -> void:
	var cells: int = maxi(1, max_ammo)
	var bar_h: float = 214.0
	var bar: Rect2 = Rect2(WORLD_W - 70.0, WORLD_H * 0.5 - bar_h * 0.5, 30.0, bar_h)
	draw_rect(bar.grow(4.0), Color(0.0, 0.0, 0.0, 0.42), true)
	draw_rect(bar.grow(4.0), Color(1, 1, 1, 0.18), false, 2.0)
	var gap: float = 4.0
	var cell_h: float = (bar.size.y - gap * float(cells - 1)) / float(cells)
	var reload_pct: float = 0.0
	if reload_remaining > 0.0:
		reload_pct = 1.0 - clampf(reload_remaining / maxf(reload_total, 0.01), 0.0, 1.0)
	for i in range(cells):
		var slot: int = cells - 1 - i
		var y: float = bar.position.y + float(slot) * (cell_h + gap)
		var rect: Rect2 = Rect2(bar.position.x, y, bar.size.x, cell_h)
		draw_rect(rect, Color(0.04, 0.07, 0.09, 0.74), true)
		draw_rect(rect, Color(1, 1, 1, 0.22), false, 1.0)
		if i < reserve:
			draw_rect(rect.grow(-3.0), Color(0.30, 0.80, 1.0, 0.94), true)
		elif i == reserve and reserve < cells and reload_pct > 0.0:
			var fill_h: float = maxf(0.0, (rect.size.y - 6.0) * reload_pct)
			var fill: Rect2 = Rect2(rect.position.x + 3.0, rect.position.y + rect.size.y - 3.0 - fill_h, rect.size.x - 6.0, fill_h)
			draw_rect(fill, Color(0.30, 0.80, 1.0, 0.72), true)

func _lobby_panel_rect() -> Rect2:
	return Rect2(64.0, 180.0, WORLD_W - 128.0, 820.0)

func _lobby_create_rect() -> Rect2:
	return Rect2(116.0, 338.0, WORLD_W - 232.0, 72.0)

func _lobby_quick_rect() -> Rect2:
	return Rect2(116.0, 426.0, WORLD_W - 232.0, 72.0)

func _lobby_bot_rect() -> Rect2:
	return Rect2(116.0, 514.0, WORLD_W - 232.0, 72.0)

func _lobby_join_input_rect() -> Rect2:
	return Rect2(116.0, 620.0, WORLD_W - 368.0, 66.0)

func _lobby_join_paste_rect() -> Rect2:
	return Rect2(WORLD_W - 240.0, 620.0, 124.0, 66.0)

func _lobby_join_rect() -> Rect2:
	return Rect2(116.0, 700.0, WORLD_W - 232.0, 72.0)

func _room_code_copy_rect() -> Rect2:
	return Rect2(24.0, 26.0, 140.0, 42.0)

func _rematch_button_rect() -> Rect2:
	return Rect2(WORLD_W * 0.5 - 150.0, 565.0, 300.0, 64.0)

func _rematch_button_visible() -> bool:
	return str(current_state.get("status", "")) == "ended"

func _fire_button_rect() -> Rect2:
	return Rect2(18.0, WORLD_H * 0.5 - 74.0, 148.0, 148.0)

func _action_at_pos(pos: Vector2) -> String:
	var delta := pos - _fire_button_rect().get_center()
	var distance := delta.length()
	if distance < UI_WEAPON_INNER_RADIUS or distance > UI_WEAPON_OUTER_RADIUS:
		return ""
	var angle := rad_to_deg(atan2(delta.y, delta.x))
	for i in range(ACTION_ORDER.size()):
		var angle_range := _weapon_angle_range(i)
		if angle >= angle_range.x and angle <= angle_range.y:
			return ACTION_ORDER[i]
	return ""

func _local_player() -> Dictionary:
	var players: Array = visual_state.get("players", [])
	for player in players:
		if typeof(player) == TYPE_DICTIONARY and int(player.get("role", -1)) == my_role:
			return player
	return {}

func _local_player_from_state(state: Dictionary) -> Dictionary:
	var players: Array = state.get("players", [])
	var role := int(state.get("you", my_role))
	for player in players:
		if typeof(player) == TYPE_DICTIONARY and int(player.get("role", -1)) == role:
			return player
	return {}

func _connected_players_from_state() -> int:
	var count := 0
	for player in visual_state.get("players", []):
		if typeof(player) == TYPE_DICTIONARY and str(player.get("name", "")).strip_edges() != "":
			count += 1
	return max(1, count)

func _draw_centered_text(text: String, pos: Vector2, font_size: int, color: Color) -> void:
	var font := ui_font
	var width := WORLD_W
	draw_string(font, Vector2(pos.x - width * 0.5, pos.y), text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, color)

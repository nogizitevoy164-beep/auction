class_name ServerClient
extends Node
## Минимальный HTTP-клиент первого серверного этапа.
## При недоступном сервере клиент может продолжить локальную игру.

const SESSION_PATH := "user://auction_server_session.json"
## Production server. For local development this can be changed to
## http://127.0.0.1:8080 in the Godot editor or in a derived client.
var base_url: String = "https://www.arh.seaetr.online"
var token: String = ""
var _socket: WebSocketPeer

signal server_event(event_type: String, payload: Variant)


func connect_guest() -> Dictionary:
	var health := await _request_json("/health")
	if not health.get("ok", false):
		return {}
	var saved_session := _load_session()
	if not String(saved_session.get("token", "")).is_empty():
		token = String(saved_session["token"])
		var existing_profile := await _request_json("/api/v1/me")
		if existing_profile.get("ok", false):
			return existing_profile["data"]
	var login := _load_guest_login()
	var registered := await _request_json("/api/v1/auth/register", HTTPClient.METHOD_POST,
		{"login": login})
	if registered.get("ok", false):
		token = String(registered["data"].get("token", ""))
	else:
		var logged := await _request_json("/api/v1/auth/login", HTTPClient.METHOD_POST,
			{"login": login})
		if not logged.get("ok", false):
			return {}
		token = String(logged["data"].get("token", ""))
	_save_session(login, token)
	var profile := await _request_json("/api/v1/me")
	return profile["data"] if profile.get("ok", false) else {}


func get_profile() -> Dictionary:
	var response := await _request_json("/api/v1/me")
	return response["data"] if response.get("ok", false) else {}


func get_policies() -> Dictionary:
	var response := await _request_json("/api/v1/policies")
	return response["data"] if response.get("ok", false) else {}


func login_account(login: String, password: String) -> Dictionary:
	var response := await _request_json("/api/v1/auth/login", HTTPClient.METHOD_POST, {
		"login": login, "password": password})
	if not response.get("ok", false):
		return response
	token = String(response["data"].get("token", ""))
	_save_session(login, token)
	return {"ok": true, "data": response["data"].get("player", {})}


func register_account(login: String, email: String, display_name: String, password: String,
		age_confirmed: bool, policy_acceptances: Dictionary) -> Dictionary:
	var response := await _request_json("/api/v1/auth/register", HTTPClient.METHOD_POST, {
		"login": login, "email": email, "displayName": display_name,
		"password": password, "ageConfirmed": age_confirmed,
		"policyAcceptances": policy_acceptances,
		"guestLogin": String(_load_session().get("login", ""))})
	if not response.get("ok", false):
		return response
	token = String(response["data"].get("token", ""))
	_save_session(login, token)
	return {"ok": true, "data": response["data"].get("player", {})}


func get_catalog_items() -> Dictionary:
	return await _request_json("/api/v1/catalog/items")


func sell_to_server(instance_id: String) -> Dictionary:
	return await _request_json("/api/v1/inventory/sell", HTTPClient.METHOD_POST,
		{"instanceId": instance_id})


func sell_all_simple_items() -> Dictionary:
	return await _request_json("/api/v1/inventory/sell-all-simple", HTTPClient.METHOD_POST, {})


func claim_field_item(item: Dictionary) -> Dictionary:
	return await _request_json("/api/v1/inventory/claim-field-item", HTTPClient.METHOD_POST, item)


func equip_item(instance_id: String, slot: String) -> Dictionary:
	return await _request_json("/api/v1/equipment/equip", HTTPClient.METHOD_POST,
		{"instanceId": instance_id, "slot": slot})


func create_market_listing(instance_id: String, price: int) -> Dictionary:
	return await _request_json("/api/v1/market/listings", HTTPClient.METHOD_POST,
		{"instanceId": instance_id, "price": price})


func get_market_listings() -> Dictionary:
	return await _request_json("/api/v1/market/listings")


func buy_market_listing(listing_id: int) -> Dictionary:
	return await _request_json("/api/v1/market/listings/%d/buy" % listing_id,
		HTTPClient.METHOD_POST, {})


func cancel_market_listing(listing_id: int) -> Dictionary:
	return await _request_json("/api/v1/market/listings/%d/cancel" % listing_id,
		HTTPClient.METHOD_POST, {})


func get_castle() -> Dictionary:
	return await _request_json("/api/v1/castle")


func collect_castle_income() -> Dictionary:
	return await _request_json("/api/v1/castle/collect", HTTPClient.METHOD_POST, {})


func upgrade_coin_tower() -> Dictionary:
	return await _request_json("/api/v1/castle/upgrade", HTTPClient.METHOD_POST, {})


func upgrade_alchemy_tower() -> Dictionary:
	return await _request_json("/api/v1/castle/upgrade-alchemy", HTTPClient.METHOD_POST, {})


func craft_potion() -> Dictionary:
	return await _request_json("/api/v1/potions/craft", HTTPClient.METHOD_POST, {})


func use_potion(instance_id: String) -> Dictionary:
	return await _request_json("/api/v1/potions/use", HTTPClient.METHOD_POST, {"instanceId": instance_id})


func start_realtime() -> void:
	if _socket != null:
		return
	_socket = WebSocketPeer.new()
	_socket.connect_to_url(_websocket_url() + "/ws")
	set_process(true)


func _websocket_url() -> String:
	if base_url.begins_with("https://"):
		return "wss://" + base_url.trim_prefix("https://")
	if base_url.begins_with("http://"):
		return "ws://" + base_url.trim_prefix("http://")
	return base_url


func _process(_delta: float) -> void:
	if _socket == null:
		return
	_socket.poll()
	while _socket.get_available_packet_count() > 0:
		var raw := (_socket.get_packet() as PackedByteArray).get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			server_event.emit(String(parsed.get("type", "")), parsed.get("payload", {}))


func get_legendary_auctions() -> Dictionary:
	return await _request_json("/api/v1/legendary-auctions")


func create_legendary_auction(instance_id: String, start_price: int, duration_hours: int) -> Dictionary:
	return await _request_json("/api/v1/legendary-auctions", HTTPClient.METHOD_POST, {
		"instanceId": instance_id, "startPrice": start_price, "durationHours": duration_hours})


func bid_legendary_auction(auction_id: String, amount: int) -> Dictionary:
	return await _request_json("/api/v1/legendary-auctions/%s/bid" % auction_id,
		HTTPClient.METHOD_POST, {"amount": amount})


func finish_legendary_auction(auction_id: String) -> Dictionary:
	return await _request_json("/api/v1/legendary-auctions/%s/finish" % auction_id,
		HTTPClient.METHOD_POST, {})


func join_matchmaking(tier: int) -> Dictionary:
	return await _request_json("/api/v1/matchmaking/join", HTTPClient.METHOD_POST,
		{"tier": tier})


func get_matchmaking_status(tier: int) -> Dictionary:
	return await _request_json("/api/v1/matchmaking/status?tier=%d" % tier)


func skip_matchmaking(tier: int) -> Dictionary:
	return await _request_json("/api/v1/matchmaking/skip", HTTPClient.METHOD_POST,
		{"tier": tier})


func leave_matchmaking(tier: int) -> Dictionary:
	return await _request_json("/api/v1/matchmaking/leave", HTTPClient.METHOD_POST,
		{"tier": tier})


func get_auction_room(room_id: String) -> Dictionary:
	return await _request_json("/api/v1/auction/rooms/%s" % room_id)


func submit_auction_bid(room_id: String, amount: int) -> Dictionary:
	return await _request_json("/api/v1/auction/rooms/%s/bid" % room_id,
		HTTPClient.METHOD_POST, {"amount": amount})


func _request_json(path: String, method: HTTPClient.Method = HTTPClient.METHOD_GET,
		payload: Dictionary = {}) -> Dictionary:
	var request := HTTPRequest.new()
	add_child(request)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not token.is_empty():
		headers.append("Authorization: Bearer %s" % token)
	var data := "" if payload.is_empty() else JSON.stringify(payload)
	var err := request.request(base_url + path, headers, method, data)
	if err != OK:
		request.queue_free()
		return {"ok": false, "status": 0}
	var response: Array = await request.request_completed
	request.queue_free()
	var response_code: int = int(response[1])
	var response_body: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	return {"ok": response_code >= 200 and response_code < 300,
		"status": response_code, "data": response_body if response_body is Dictionary else {}}


func _load_guest_login() -> String:
	var saved := _load_session()
	if not String(saved.get("login", "")).is_empty() and String(saved.get("token", "")).is_empty():
		return String(saved["login"])
	var login := "guest_%d" % int(Time.get_unix_time_from_system())
	_save_session(login, "")
	return login


func _load_session() -> Dictionary:
	if not FileAccess.file_exists(SESSION_PATH):
		return {}
	var file := FileAccess.open(SESSION_PATH, FileAccess.READ)
	var saved: Variant = JSON.parse_string(file.get_as_text())
	return saved if saved is Dictionary else {}


func _save_session(login: String, session_token: String = "") -> void:
	var file := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"login": login, "token": session_token}))

class_name ServerClient
extends Node
## Минимальный HTTP-клиент первого серверного этапа.
## При недоступном сервере клиент может продолжить локальную игру.

const SESSION_PATH := "user://auction_server_session.json"
var base_url: String = "http://127.0.0.1:8080"
var token: String = ""


func connect_guest() -> Dictionary:
	var health := await _request_json("/health")
	if not health.get("ok", false):
		return {}
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
	_save_session(login)
	var profile := await _request_json("/api/v1/me")
	return profile["data"] if profile.get("ok", false) else {}


func get_profile() -> Dictionary:
	var response := await _request_json("/api/v1/me")
	return response["data"] if response.get("ok", false) else {}


func sell_to_server(instance_id: String) -> Dictionary:
	return await _request_json("/api/v1/inventory/sell", HTTPClient.METHOD_POST,
		{"instanceId": instance_id})


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
	if FileAccess.file_exists(SESSION_PATH):
		var file := FileAccess.open(SESSION_PATH, FileAccess.READ)
		var saved: Variant = JSON.parse_string(file.get_as_text())
		if saved is Dictionary and not String(saved.get("login", "")).is_empty():
			return String(saved["login"])
	var login := "guest_%d" % int(Time.get_unix_time_from_system())
	_save_session(login)
	return login


func _save_session(login: String) -> void:
	var file := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"login": login}))

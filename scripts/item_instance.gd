class_name ItemInstance
extends RefCounted
## Конкретный экземпляр предмета игрока. Позже это соответствует записи
## item_instances на сервере, а не только описанию ItemData/WeaponData.

var instance_id: String = ""
var definition_id: String = ""
var item_name: String = ""
var quality: int = 1
var state: String = "inventory"
var acquired_at: int = 0

static func create(p_definition_id: String, p_name: String, p_quality: int = 1):
	var item = load("res://scripts/item_instance.gd").new()
	item.instance_id = "%s-%s" % [p_definition_id, Time.get_unix_time_from_system()]
	item.definition_id = p_definition_id
	item.item_name = p_name
	item.quality = clampi(p_quality, 1, 5)
	item.acquired_at = int(Time.get_unix_time_from_system())
	return item


func to_dict() -> Dictionary:
	return {
		"instance_id": instance_id,
		"definition_id": definition_id,
		"item_name": item_name,
		"quality": quality,
		"state": state,
		"acquired_at": acquired_at,
	}


static func from_dict(data: Dictionary):
	var item = load("res://scripts/item_instance.gd").new()
	item.instance_id = String(data.get("instance_id", ""))
	item.definition_id = String(data.get("definition_id", ""))
	item.item_name = String(data.get("item_name", ""))
	item.quality = clampi(int(data.get("quality", 1)), 1, 5)
	item.state = String(data.get("state", "inventory"))
	item.acquired_at = int(data.get("acquired_at", 0))
	return item

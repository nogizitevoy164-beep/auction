class_name SaveData
extends RefCounted
## Простое локальное сохранение прогресса игрока.
## Файл находится в user:// и не попадает в репозиторий.

const SAVE_PATH := "user://auction_save.json"
const SELL_RATE := 0.70

static func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {"gold": 1000, "inventory": []}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return {
			"gold": maxi(int(parsed.get("gold", 1000)), 0),
			"inventory": parsed.get("inventory", []) if parsed.get("inventory", []) is Array else [],
		}
	return {"gold": 1000, "inventory": []}


static func save_game(gold: int, inventory: Array) -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"gold": maxi(gold, 0), "inventory": inventory}))


static func sell_price(item: Dictionary) -> int:
	return maxi(1, int(floor(float(item.get("cost", 0)) * SELL_RATE)))

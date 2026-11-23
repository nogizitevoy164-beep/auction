class_name ItemData
extends Resource
## Предмет игрового поля (лот аукциона).
## Это ресурс Godot: предметы можно сохранять в .tres-файлы,
## они видны в панели «Файловая система» и редактируются в Инспекторе.

## Локальная ссылка на ядро данных (не зависит от глобального кэша классов).
const GameData = preload("res://scripts/game_data.gd")

## Название предмета.
@export var item_name: String = ""
## Стоимость в золоте (границы: GameData.COST_MIN..GameData.COST_MAX).
@export var cost: int = 100:
	set(value):
		cost = clampi(value, GameData.COST_MIN, GameData.COST_MAX)
## Клетки по оси X.
@export var size_x: int = 1
## Клетки по оси Y.
@export var size_y: int = 1
## Редкость: GameData.Rarity 1..5 (Обычный..Легендарный).
@export var rarity: int = 1
## Тип: GameData.ItemType (см. ядро данных).
@export var type: int = 0

## Уникальный номер (назначается фабрикой, в редакторе не нужен).
var id: int = 0


static func create(p_name: String, p_cost: int, p_size_x: int, p_size_y: int,
		p_rarity: int, p_type: int) -> ItemData:
	var item := ItemData.new()
	item.item_name = p_name
	item.cost = p_cost
	item.size_x = maxi(p_size_x, 1)
	item.size_y = maxi(p_size_y, 1)
	item.rarity = p_rarity
	item.type = p_type
	return item


## Создаёт предмет для продажи по идентификатору каталога
## GameData.SELLABLE_ITEMS (например "copper_coin").
static func create_sellable(id: String) -> ItemData:
	var info: Dictionary = GameData.SELLABLE_ITEMS[id]
	var item := ItemData.new()
	item.item_name = info["title"]
	item.cost = int(info["cost"])
	item.size_x = (info["size"] as Vector2i).x
	item.size_y = (info["size"] as Vector2i).y
	item.rarity = int(info["quality"])
	item.type = GameData.ItemType.SELLABLE
	return item


func cell_count() -> int:
	return size_x * size_y


func rarity_color() -> Color:
	return GameData.QUALITY_COLORS[rarity]


func rarity_name() -> String:
	return GameData.RARITY_NAMES[rarity]


func type_name() -> String:
	return GameData.ITEM_TYPE_NAMES[type]


func to_display_string() -> String:
	return "%s [%d×%d, %s, %s] — %d зол." % [
		item_name, size_x, size_y, rarity_name(), type_name(), cost]

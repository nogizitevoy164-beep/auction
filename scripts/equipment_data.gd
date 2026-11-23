class_name EquipmentData
extends "res://scripts/item_data.gd"
## Снаряжение игрока: ресурс Godot (.tres) — виден в файловой системе
## редактора, свойства редактируются в Инспекторе.
## GameData наследуется от ItemData (preload ядра данных).
##
## Готовые экземпляры лежат в res://resources/equipment/*.tres.
## Экземпляры в коде создаются через EquipmentData.make("hood_assassin", качество).

## Класс снаряжения (ключ GameData.GEAR_CLASSES).
@export var gear_class_id: String = ""
## Качество: 1..5 (GameData.Quality).
@export var quality: int = 1:
	set(value):
		quality = clampi(value, 1, 5)
## Иконка снаряжения.
@export var icon: Texture2D


static func make(class_id: String, p_quality: int) -> EquipmentData:
	var info: Dictionary = GameData.GEAR_CLASSES[class_id]
	var equip := EquipmentData.new()
	equip.gear_class_id = class_id
	equip.item_name = info["title"]
	equip.size_x = (info["size"] as Vector2i).x
	equip.size_y = (info["size"] as Vector2i).y
	equip.type = GameData.ItemType.SELLABLE
	equip.quality = clampi(p_quality, 1, 5)
	equip.rarity = equip.quality # качество и редкость идут одной шкалой
	equip.cost = int(info.get("base_cost", 1000))
	if info.has("icon_path"):
		equip.icon = load(info["icon_path"])
	return equip


func quality_name() -> String:
	return GameData.QUALITY_NAMES[quality]


## Цвет рамки предмета — по качеству снаряжения.
func quality_color() -> Color:
	return GameData.QUALITY_COLORS[quality]


func slot() -> int:
	return GameData.GEAR_CLASSES[gear_class_id]["slot"]


func abilities() -> Array:
	return GameData.GEAR_CLASSES[gear_class_id]["abilities"]


func has_ability(ability: int) -> bool:
	return abilities().has(ability)


# ============================================================
#  СПОСОБНОСТИ, ЗАВИСЯЩИЕ ОТ КАЧЕСТВА
# ============================================================

## Плащ скрытности: скрыть ставку в одном из раундов.
## Нагрудник защиты: защита от проигрыша (ставка ×2) в одном раунде.
## Роба волшебства: отменить способности, применённые соперниками
## (срабатывает только на носителе роби), в одном раунде.
func consumable_capacity() -> int:
	if not GameData.GEAR_CLASSES[gear_class_id].get("has_capacity", false):
		return 0
	return GameData.CONSUMABLE_CAPACITY[quality - 1]


## Сколько расходных материалов можно применять ЗА РАУНД
## (у легендарной брони — 2, у остальных — 1).
func consumables_per_round() -> int:
	if not GameData.GEAR_CLASSES[gear_class_id].get("has_capacity", false):
		return 1
	return 2 if quality == GameData.Quality.LEGENDARY else 1


## Верхняя граница качества предметов, которые снаряжение открывает
## на игровом поле (оружие / ингредиенты). Открывается «качество и ниже».
func unlock_quality_limit() -> int:
	return quality


## Тип предметов, открываемых на поле (ItemType), либо -1, если снаряжение
## ничего не открывает.
func unlock_branch() -> int:
	var info: Dictionary = GameData.GEAR_CLASSES[gear_class_id]
	if not info.has("unlock_branch"):
		return -1
	return info["unlock_branch"]


## Человекочитаемое описание способностей для карточки предмета.
func ability_description() -> String:
	var info: Dictionary = GameData.GEAR_CLASSES[gear_class_id]
	var parts: Array[String] = []
	if info.get("has_capacity", false):
		parts.append("Вмещает %d расходных материалов" % consumable_capacity())
		if consumables_per_round() > 1:
			parts.append("Можно применять %d расходных материала за раунд" % consumables_per_round())
	for ability: int in abilities():
		match ability:
			GameData.Ability.UNLOCK_WEAPON:
				parts.append("Открывает на поле: %s (качество до %s)" % [
					info["unlock_target"], GameData.QUALITY_NAMES[unlock_quality_limit()]])
			GameData.Ability.UNLOCK_INGREDIENTS:
				parts.append("Открывает на поле: %s (качество до %s)" % [
					info["unlock_target"], GameData.QUALITY_NAMES[unlock_quality_limit()]])
			GameData.Ability.STEALTH:
				parts.append("Скрывает вашу ставку в одном из раундов")
			GameData.Ability.DEFENSE:
				parts.append("Защита от проигрыша в одном раунде (ставка ×2)")
			GameData.Ability.CANCEL:
				parts.append("Отменяет способности, применённые соперниками (срабатывает только на носителе роби, 1 раунд)")
	return " • ".join(parts)

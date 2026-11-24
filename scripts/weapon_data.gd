class_name WeaponData
extends "res://scripts/equipment_data.gd"
## Описание оружия. Логика применения должна дублироваться и проверяться
## сервером после появления онлайн-режима.

enum WeaponKind { DAGGER, SWORD, STAFF }

@export var weapon_kind: WeaponKind = WeaponKind.DAGGER

static func make_weapon(kind: WeaponKind, p_quality: int):
	var weapon = load("res://scripts/weapon_data.gd").new()
	weapon.weapon_kind = kind
	weapon.quality = clampi(p_quality, GameData.Quality.COMMON, GameData.Quality.LEGENDARY)
	weapon.rarity = weapon.quality
	weapon.type = GameData.ItemType.WEAPON
	weapon.size_x = 1
	weapon.size_y = 1
	match kind:
		WeaponKind.DAGGER:
			weapon.item_name = "Кинжал ассасина"
			weapon.gear_class_id = "weapon_dagger_assassin"
			weapon.cost = 2500
		WeaponKind.SWORD:
			weapon.item_name = "Меч воина"
			weapon.gear_class_id = "weapon_sword_warrior"
			weapon.cost = 3000
		WeaponKind.STAFF:
			weapon.item_name = "Посох мага"
			weapon.gear_class_id = "weapon_staff_mage"
			weapon.cost = 3200
	return weapon


## Всегда 2 клетки для кинжала и 4 для меча/посоха.
func ability_cell_count() -> int:
	return 2 if weapon_kind == WeaponKind.DAGGER else 4


func ability_direction() -> String:
	match weapon_kind:
		WeaponKind.SWORD:
			return "horizontal"
		WeaponKind.STAFF:
			return "vertical"
	return "selected"


## Уровень информации зависит только от качества.
## 1 — тип, 2 — размер, 3 — качество, 4 — полная информация.
func reveal_level() -> int:
	return mini(quality, 4)


func max_uses_per_auction() -> int:
	return 2 if quality == GameData.Quality.LEGENDARY else 1


func can_use_in_round(used_rounds: Array, round_index: int) -> bool:
	if used_rounds.has(round_index):
		return false
	return used_rounds.size() < max_uses_per_auction()


func ability_description() -> String:
	var action := "выбранные 2 клетки" if weapon_kind == WeaponKind.DAGGER \
		else ("4 клетки по горизонтали" if weapon_kind == WeaponKind.SWORD \
		else "4 клетки по вертикали")
	var extra := " Можно применить дважды за аукцион." if max_uses_per_auction() == 2 else ""
	return "Открывает %s. Раскрытие информации: уровень %d.%s" % [action, reveal_level(), extra]

extends SceneTree

const WeaponDataS = preload("res://scripts/weapon_data.gd")
const GameDataS = preload("res://scripts/game_data.gd")
const ItemInstanceS = preload("res://scripts/item_instance.gd")

var failures := 0

func check(cond: bool, label: String) -> void:
	if cond:
		print("   OK   ", label)
	else:
		failures += 1
		printerr("   FAIL ", label)


func _initialize() -> void:
	print("=== Тесты оружия и экземпляров ===")
	var dagger = WeaponDataS.make_weapon(WeaponDataS.WeaponKind.DAGGER, GameDataS.Quality.RARE)
	var sword = WeaponDataS.make_weapon(WeaponDataS.WeaponKind.SWORD, GameDataS.Quality.EPIC)
	var staff = WeaponDataS.make_weapon(WeaponDataS.WeaponKind.STAFF, GameDataS.Quality.LEGENDARY)
	check(dagger.ability_cell_count() == 2, "кинжал всегда открывает 2 клетки")
	check(sword.ability_cell_count() == 4 and sword.ability_direction() == "horizontal", "меч открывает 4 клетки горизонтально")
	check(staff.ability_cell_count() == 4 and staff.ability_direction() == "vertical", "посох открывает 4 клетки вертикально")
	check(dagger.reveal_level() == 3, "редкое оружие раскрывает тип, размер и качество")
	check(sword.reveal_level() == 4, "эпическое оружие раскрывает всю информацию")
	check(staff.max_uses_per_auction() == 2, "легендарное оружие можно применить дважды")
	check(not staff.can_use_in_round([2], 2), "нельзя применить оружие дважды в одном раунде")
	check(staff.can_use_in_round([2], 3), "легендарное оружие можно применить в другом раунде")
	var instance = ItemInstanceS.create("weapon_staff_mage", "Посох мага", GameDataS.Quality.LEGENDARY)
	var restored = ItemInstanceS.from_dict(instance.to_dict())
	check(restored.definition_id == "weapon_staff_mage", "экземпляр сохраняет идентификатор описания")
	check(restored.state == "inventory" and restored.quality == GameDataS.Quality.LEGENDARY, "экземпляр сохраняет состояние и качество")
	if failures == 0:
		print("=== ИТОГ: ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ ===")
	else:
		printerr("=== ИТОГ: ОШИБОК: %d ===" % failures)
	quit(1 if failures > 0 else 0)

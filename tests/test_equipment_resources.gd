extends SceneTree
## Проверка: все ресурсы снаряжения из res://resources/equipment
## загружаются как EquipmentData с иконкой и корректными полями.

const EquipmentDataS = preload("res://scripts/equipment_data.gd")

const EXPECTED: Dictionary = {
	"hood_assassin": ["Капюшон ассасина", 2, 2, 1],
	"helm_warrior": ["Шлем воина", 2, 2, 3],
	"hat_mage": ["Шляпа мага", 2, 2, 4],
	"cloak_stealth": ["Плащ скрытности", 2, 3, 2],
	"chest_defense": ["Нагрудник защиты", 3, 3, 3],
	"robe_magic": ["Роба волшебства", 2, 4, 5],
	"gloves_assassin": ["Перчатки ассасина", 2, 1, 2],
	"mittens_warrior": ["Руковицы воина", 2, 2, 3],
	"gloves_mage": ["Перчатки мага", 2, 1, 2],
	"boots_assassin": ["Сапоги ассасина", 2, 2, 2],
	"boots_plate": ["Латные сапоги", 2, 2, 3],
	"boots_wizard": ["Сапоги волшебника", 2, 2, 4],
}

var failures: int = 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("   OK   ", label)
	else:
		failures += 1
		printerr("   FAIL ", label)


func _initialize() -> void:
	print("=== Проверка ресурсов снаряжения ===")
	for key: String in EXPECTED:
		var path := "res://resources/equipment/%s.tres" % key
		var res: Resource = load(path)
		var ok := res is EquipmentDataS
		if not ok:
			check(false, "%s: ресурс не загрузился или неверный класс" % path)
			continue
		var equip: EquipmentDataS = res
		var exp: Array = EXPECTED[key]
		var icon_ok := equip.icon != null
		var desc := equip.to_display_string()
		check(icon_ok, "%s: иконка загружена" % key)
		check(equip.item_name == exp[0] and equip.size_x == exp[1] \
				and equip.size_y == exp[2] and equip.quality == exp[3],
				"%s: поля совпадают (%s)" % [key, desc])
		check(equip.ability_description() != "", "%s: способности описаны" % key)
	if failures == 0:
		print("=== ИТОГ: ВСЕ 12 РЕСУРСОВ В ПОРЯДКЕ ===")
	else:
		printerr("=== ИТОГ: ОШИБОК: %d ===" % failures)
	quit(1 if failures > 0 else 0)

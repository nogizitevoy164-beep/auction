extends SceneTree
## Тест каталога предметов для продажи: 33 предмета, фабрика
## ItemData.create_sellable(), цвета качества, границы стоимости.

const GameDataS = preload("res://scripts/game_data.gd")
const ItemDataS = preload("res://scripts/item_data.gd")

var failures: int = 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("   OK   ", label)
	else:
		failures += 1
		printerr("   FAIL ", label)


func _initialize() -> void:
	print("=== Тест каталога предметов для продажи ===")
	var catalog: Dictionary = GameDataS.SELLABLE_ITEMS
	check(catalog.size() == 33, "в каталоге 33 предмета (фактически: %d)" % catalog.size())

	# Каждый предмет создаётся фабрикой с корректными полями.
	var quality_counts: Dictionary = {}
	var bad_ids: Array[String] = []
	for id: String in catalog:
		var info: Dictionary = catalog[id]
		var item: ItemDataS = ItemDataS.create_sellable(id)
		var ok: bool = item.item_name == info["title"] \
				and item.cost == int(info["cost"]) \
				and item.size_x == (info["size"] as Vector2i).x \
				and item.size_y == (info["size"] as Vector2i).y \
				and item.rarity == int(info["quality"]) \
				and item.type == GameDataS.ItemType.SELLABLE \
				and item.cell_count() >= 1 and item.cell_count() <= 16
		if not ok:
			bad_ids.append(id)
		var q: int = int(info["quality"])
		quality_counts[q] = int(quality_counts.get(q, 0)) + 1
	check(bad_ids.is_empty(), "все предметы создаются фабрикой create_sellable корректно")
	if not bad_ids.is_empty():
		printerr("      проблемные: %s" % ", ".join(bad_ids))

	check(int(quality_counts.get(1, 0)) == 7, "Обычное: 7 предметов (белый)")
	check(int(quality_counts.get(2, 0)) == 7, "Необычное: 7 предметов (зелёный)")
	check(int(quality_counts.get(3, 0)) == 7, "Редкое: 7 предметов (синий)")
	check(int(quality_counts.get(4, 0)) == 6, "Эпическое: 6 предметов (фиолетовый)")
	check(int(quality_counts.get(5, 0)) == 6, "Легендарное: 6 предметов (оранжевый)")

	# Стоимость в границах каталога 20..5500 — кламп не должен искажать.
	var coin: ItemDataS = ItemDataS.create_sellable("copper_coin")
	check(coin.cost == 20, "медная монета: стоимость 20 (не обрезана минимумом 100)")
	var ark: ItemDataS = ItemDataS.create_sellable("ancient_empire_ark")
	check(ark.cost == 5500, "золотой ковчег: стоимость 5500")

	# Цвет предмета = цвет его качества.
	check(coin.rarity_color() == GameDataS.QUALITY_COLORS[1], "обычный предмет — белый цвет")
	check(ark.rarity_color() == GameDataS.QUALITY_COLORS[5], "легендарный предмет — оранжевый цвет")

	# Итоговая стоимость лота считается по предметам каталога.
	var sample_total: int = ItemDataS.create_sellable("copper_coin").cost \
			+ ItemDataS.create_sellable("rune_north_axe").cost
	check(sample_total == 20 + 500, "сумма стоимостей предметов: 20 + 500 = 520")

	if failures == 0:
		print("=== ИТОГ: ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ ===")
	else:
		printerr("=== ИТОГ: ОШИБОК: %d ===" % failures)
	quit(1 if failures > 0 else 0)

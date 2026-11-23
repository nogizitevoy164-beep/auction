extends SceneTree
## Тест игровых полей: пороги входа, шансы лотов из CSV,
## взвешенная раскладка и экран выбора поля.

const GameDataS = preload("res://scripts/game_data.gd")

var failures: int = 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("   OK   ", label)
	else:
		failures += 1
		printerr("   FAIL ", label)


func _initialize() -> void:
	print("=== Тест игровых полей (начальный/средний/элитный) ===")

	var tiers: Dictionary = GameDataS.FIELD_TIERS
	check(tiers.size() == 3, "описаны три игровых поля")

	check(int(tiers[GameDataS.FieldTier.STARTER]["min_gold"]) == 1000,
			"вход на начальный: не менее 1000 монет")
	check(int(tiers[GameDataS.FieldTier.MID]["min_gold"]) == 10000,
			"вход на средний: не менее 10000 монет")
	check(int(tiers[GameDataS.FieldTier.ELITE]["min_gold"]) == 100000,
			"вход на элитный: не менее 100000 монет")

	# У каждого из 33 предметов есть шанс для каждого поля,
	# и колонки CSV в сумме дают ~100%.
	var catalog: Dictionary = GameDataS.SELLABLE_ITEMS
	check(catalog.size() == 33, "в каталоге 33 предмета")
	var chance_keys: Array = ["chance_starter", "chance_mid", "chance_elite"]
	var missing: int = 0
	for id in catalog:
		for key in chance_keys:
			if not catalog[id].has(key) or float(catalog[id][key]) <= 0.0:
				missing += 1
	check(missing == 0, "у всех предметов заданы шансы для всех полей")

	var ok_sum: bool = true
	for key in chance_keys:
		var total := 0.0
		for id in catalog:
			total += float(catalog[id][key])
		if absf(total - 100.0) > 0.5:
			ok_sum = false
			printerr("   сумма %s = %.2f%% (ожидалось ~100%%)" % [key, total])
	check(ok_sum, "сумма шансов каждой колонки ~100%")

	# Дорогие легендарные предметы чаще на элитном поле, дешёвое
	# обычное добро — на начальном (колонки CSV монотонны).
	check(float(catalog["ancient_empire_ark"]["chance_elite"]) >
			float(catalog["ancient_empire_ark"]["chance_starter"]),
			"Золотой ковчег: шанс на элитном выше, чем на начальном")
	check(float(catalog["copper_coin"]["chance_starter"]) >
			float(catalog["copper_coin"]["chance_elite"]),
			"Медная монета: шанс на начальном выше, чем на элитном")

	# Взвешенная раскладка в живом интерфейсе: экземпляр главной сцены.
	var ui = load("res://scenes/main_ui.tscn").instantiate()
	root.add_child(ui)
	await process_frame

	# До выбора поля оверлей выбора показан, игровое поле скрыто.
	check(ui.get_node("TierSelection").visible, "перед входом показан экран выбора поля")
	check(not ui.main_hbox.visible, "игровое поле скрыто до выбора")

	# Золота игрока не хватает на средний/элитный — кнопки недоступны.
	check(ui._tier_buttons[GameDataS.FieldTier.STARTER].disabled == false,
			"начальный доступен при 1000 монет")
	check(ui._tier_buttons[GameDataS.FieldTier.MID].disabled,
			"средний недоступен при 1000 монет")
	check(ui._tier_buttons[GameDataS.FieldTier.ELITE].disabled,
			"элитный недоступен при 1000 монет")

	# Вход на начальное поле: раскладка лотов, старт раунда 1.
	ui._on_tier_selected(GameDataS.FieldTier.STARTER)
	await process_frame
	check(ui.current_tier == GameDataS.FieldTier.STARTER, "выбрано начальное поле")
	check(not ui.get_node("TierSelection").visible, "экран выбора скрыт после входа")
	check(ui.main_hbox.visible, "игровое поле показано после входа")
	check(ui.field_items.size() == 6, "на начальном поле 6 лотов")
	check(ui.auction_field_name == "Начальный аукцион",
			"название поля в статусе: «Начальный аукцион»")
	check(ui._field_round == 1, "после входа начался раунд 1")

	# Все размещённые лоты берутся из каталога.
	var titles: Dictionary = {}
	for id in catalog:
		titles[String(catalog[id]["title"])] = true
	var all_known: bool = true
	for item in ui.field_items:
		if not titles.has(String(item["title"])):
			all_known = false
	check(all_known, "все лоты на поле из каталога продажи")

	# Вход на элитное поле (тестово поднимаем золото игрока).
	ui.players[0].gold = 150000
	ui._refresh_tier_buttons()
	check(ui._tier_buttons[GameDataS.FieldTier.ELITE].disabled == false,
			"элитный доступен при 150000 монет")
	ui._on_tier_selected(GameDataS.FieldTier.ELITE)
	await process_frame
	check(ui.current_tier == GameDataS.FieldTier.ELITE, "выбрано элитное поле")
	check(ui.field_items.size() == 10, "на элитном поле 10 лотов")
	check(ui.auction_field_name == "Элитный аукцион",
			"название поля в статусе: «Элитный аукцион»")

	# Среднее поле: 8 лотов.
	ui._on_tier_selected(GameDataS.FieldTier.MID)
	await process_frame
	check(ui.current_tier == GameDataS.FieldTier.MID, "выбрано среднее поле")
	check(ui.field_items.size() == 8, "на среднем поле 8 лотов")

	# Попытка входа без достаточного золота не меняет поле.
	ui.players[0].gold = 100
	ui._refresh_tier_buttons()
	var tier_before: int = ui.current_tier
	ui._on_tier_selected(GameDataS.FieldTier.ELITE)
	check(ui.current_tier == tier_before, "вход без золота отклонён — поле не сменилось")

	ui.queue_free()
	await process_frame

	if failures == 0:
		print("=== ИТОГ: ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ ===")
	else:
		printerr("=== ИТОГ: ОШИБОК: %d ===" % failures)
	quit(1 if failures > 0 else 0)

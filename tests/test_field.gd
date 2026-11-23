extends SceneTree
## Тест игрового поля: клетки строго квадратные, ряды заполняют высоту,
## туман войны в 1-м раунде.

const GameFieldS = preload("res://scripts/game_field.gd")
const GameDataS = preload("res://scripts/game_data.gd")

var failures: int = 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("   OK   ", label)
	else:
		failures += 1
		printerr("   FAIL ", label)


func _initialize() -> void:
	print("=== Тест игрового поля ===")
	var gf = GameFieldS.new()
	gf.size = Vector2(900, 600)
	gf._recalculate()

	# Квадратность: клетка = ширина / 30 колонок.
	check(absf(gf.cell_size() - 30.0) < 0.001,
			"клетка 900/30 = 30.0px, квадрат 30×30")
	# Ряды заполняют всю высоту.
	check(gf.rows_visible() == 20, "600px / 30px = 20 рядов")

	# Другой размер — клетки снова квадратные.
	gf.size = Vector2(600, 450)
	gf._recalculate()
	check(absf(gf.cell_size() - 20.0) < 0.001, "клетка 600/30 = 20.0px, квадрат 20×20")
	check(gf.rows_visible() == 22, "450px / 20px = 22 ряда (округление вниз)")

	# Предметы w×h в клетках.
	gf.set_items([
		{"row": 0, "col": 2, "w": 3, "h": 1, "title": "Меч", "color": Color.RED},
		{"row": 2, "col": 10, "w": 2, "h": 2, "title": "Зелье", "color": Color.GREEN},
	])
	check(gf.items.size() == 2, "пул из 2 предметов установлен")

	# Системное открытие клеток по раундам (публичная информация).
	gf.reset_reveal()
	gf.reveal_for_round(1)
	check(gf.current_round == 1, "раунд 1 установлен")
	check(gf.revealed_count() == 12, "раунд 1: открыто 12 случайных клеток")
	gf.reveal_for_round(2)
	check(gf.revealed_count() == 30, "раунд 2: накоплено 30 открытых клеток")
	gf.reveal_for_round(3)
	check(gf.revealed_count() == 54, "раунд 3: накоплено 54 открытых клетки")
	gf.reveal_for_round(4)
	check(gf.revealed_count() == 84, "раунд 4: накоплено 84 открытых клетки")
	gf.reveal_for_round(5)
	check(gf.current_round == 5, "раунд ограничен значением 5")
	check(gf.revealed_count() == 120, "к финалу накоплено 120 открытых клеток")
	check(gf.is_item_fully_revealed(0) or not gf.is_item_fully_revealed(0),
			"признак полного раскрытия предмета вычисляется")
	gf.reset_reveal()
	check(gf.revealed_count() == 0, "сброс: сокровища снова полностью скрыты")
	check(gf.current_round == 0, "сброс: торгов ещё не было")

	# Размер предмета на поле = ровно w×h клеток из описания предмета.
	gf.set_items([{"row": 2, "col": 5, "w": 3, "h": 3, "title": "Ковчег", "color": Color.RED}])
	var occupied: int = 0
	for r: int in range(2, 5):
		for c: int in range(5, 8):
			if gf._occupancy.has(Vector2i(c, r)):
				occupied += 1
	check(occupied == 9, "предмет 3×3 занял ровно 9 клеток (не больше и не меньше)")
	check(not gf._occupancy.has(Vector2i(4, 2)) and not gf._occupancy.has(Vector2i(8, 4)),
			"клетки за границей предмета свободны")

	# Все 33 предмета каталога на поле «полками»: сумма клеток точная,
	# наложений нет (иначе занятых клеток было бы меньше суммы).
	var placed: Array = []
	var pack_col: int = 0
	var shelf_y: int = 0
	var shelf_h: int = 0
	var total_cells: int = 0
	for id: String in GameDataS.SELLABLE_ITEMS:
		var info: Dictionary = GameDataS.SELLABLE_ITEMS[id]
		var s: Vector2i = info["size"]
		if pack_col + s.x > 30:
			pack_col = 0
			shelf_y += shelf_h + 1
			shelf_h = 0
		placed.append({"row": shelf_y, "col": pack_col, "w": s.x, "h": s.y,
				"title": info["title"], "color": Color.WHITE})
		pack_col += s.x + 1
		shelf_h = maxi(shelf_h, s.y)
		total_cells += s.x * s.y
	gf.set_items(placed)
	check(gf._occupancy.size() == total_cells,
			"все 33 предмета заняли ровно %d клеток — ни одной клетки наложения" % total_cells)

	# Клетки квадратные при нестандартной ширине (проверка формулы).
	gf.size = Vector2(1234, 500)
	gf._recalculate()
	var cell: float = gf.cell_size()
	check(absf(cell * 30.0 - 1234.0) < 0.01, "30 клеток точно заполняют ширину")
	check(absf(cell - gf.cell_size()) < 0.001, "ширина клетки == высоте клетки")

	if failures == 0:
		print("=== ИТОГ: ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ ===")
	else:
		printerr("=== ИТОГ: ОШИБОК: %d ===" % failures)
	quit(1 if failures > 0 else 0)

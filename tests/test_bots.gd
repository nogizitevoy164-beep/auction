extends SceneTree
## Тест ботов: оценка стоимости лота по открытым клеткам и ставки.

const BotsControllerS = preload("res://scripts/bots_controller.gd")

var failures: int = 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("   OK   ", label)
	else:
		failures += 1
		printerr("   FAIL ", label)


func _initialize() -> void:
	print("=== Тест ботов аукциона ===")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	# Оценка: предмет 2×2 стоимостью 100, открыты 2 из 4 клеток -> 50.
	var items: Array = [{"row": 0, "col": 0, "w": 2, "h": 2, "cost": 100, "title": "Ларец"}]
	var revealed: Dictionary = {Vector2i(0, 0): true, Vector2i(1, 1): true}
	check(BotsControllerS.estimate_lot_value(items, revealed) == 50,
			"предмет 2×2 за 100, открыты 2/4 клетки -> оценка 50")

	# Ничего не открыто -> оценка 0 (бот пасует).
	check(BotsControllerS.estimate_lot_value(items, {}) == 0,
			"нет открытых клеток -> оценка 0")

	# Предмет полностью открыт -> оценка = его стоимости.
	revealed = {Vector2i(0, 0): true, Vector2i(0, 1): true,
			Vector2i(1, 0): true, Vector2i(1, 1): true}
	check(BotsControllerS.estimate_lot_value(items, revealed) == 100,
			"все 4 клетки открыты -> оценка 100")

	# Несколько предметов: оценка = сумма долей.
	var two: Array = [
		{"row": 0, "col": 0, "w": 1, "h": 1, "cost": 200, "title": "A"},
		{"row": 0, "col": 1, "w": 1, "h": 1, "cost": 300, "title": "B"},
	]
	revealed = {Vector2i(0, 0): true}
	check(BotsControllerS.estimate_lot_value(two, revealed) == 200,
			"открыт только предмет A (200), предмет B скрыт -> оценка 200")

	# Ставка не превышает золото бота.
	var bid := BotsControllerS.bot_bid(100000, 1, 500, 0.9, rng)
	check(bid == 500, "оценка 100000 при золоте 500 -> ставка ровно 500")

	# Нулевая оценка -> пас.
	check(BotsControllerS.bot_bid(0, 3, 1000, 0.5, rng) == 0, "оценка 0 -> пас")

	# Ставка соответствует порогу раунда с разбросом (раунд 3 = ×1.3).
	var lo: int = 999999
	var hi: int = 0
	for i: int in 200:
		var b: int = BotsControllerS.bot_bid(1000, 3, 100000, 0.5, rng)
		lo = mini(lo, b)
		hi = maxi(hi, b)
	# 1000 × 1.3 × (1 ± 0.12) => диапазон примерно 1144..1456.
	check(lo >= 1144 - 1 and hi <= 1456 + 1,
			"200 ставок в раунде 3 уложились в коридор %d..%d (ожидается ~1144..1456)" % [lo, hi])

	# Характер бота влияет на среднюю ставку (агрессивный ставит выше).
	var sum_calm := 0
	var sum_fierce := 0
	for i: int in 200:
		sum_calm += BotsControllerS.bot_bid(1000, 2, 100000, 0.1, rng)
		sum_fierce += BotsControllerS.bot_bid(1000, 2, 100000, 0.9, rng)
	check(sum_fierce > sum_calm,
			"агрессивный бот ставит в среднем больше (fierce %d > calm %d)" % [sum_fierce, sum_calm])

	if failures == 0:
		print("=== ИТОГ: ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ ===")
	else:
		printerr("=== ИТОГ: ОШИБОК: %d ===" % failures)
	quit(1 if failures > 0 else 0)

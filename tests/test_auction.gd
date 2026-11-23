extends SceneTree
## Автотест «Магического аукциона»: запускается headless через
## godot --headless --script tests/test_auction.gd

const AuctionState = preload("res://scripts/auction_state.gd")
const ItemDataS = preload("res://scripts/item_data.gd")
const GameDataS = preload("res://scripts/game_data.gd")

var failures: int = 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("   OK   ", label)
	else:
		failures += 1
		printerr("   FAIL ", label)


func make_players(gold: int) -> Array:
	var players: Array = []
	for i: int in range(1, 5): # 4 игрока
		players.append({"id": i, "name": "Игрок %d" % i, "gold": gold})
	return players


## Три предмета: истинная стоимость лота = 500 + 300 + 200 = 1000.
func make_items() -> Array:
	var items: Array = []
	items.append(ItemDataS.create("Меч", 500, 2, 1, GameDataS.Rarity.RARE, GameDataS.ItemType.WEAPON))
	items.append(ItemDataS.create("Зелье", 300, 1, 1, GameDataS.Rarity.COMMON, GameDataS.ItemType.INGREDIENT_CONSUMABLE))
	items.append(ItemDataS.create("Кристалл", 200, 1, 1, GameDataS.Rarity.UNCOMMON, GameDataS.ItemType.SELLABLE))
	return items


func _test_reveal_and_estimate() -> void:
	print("--- Вскрытие свойств и оценка стоимости ---")
	var a = AuctionState.new()
	a.properties_per_round = 2
	a.setup(make_players(2000), make_items())
	a.start_auction()
	check(a.current_round == 1, "Аукцион стартует с 1-го раунда")
	check(a.get_visible_item(0).size() == 2, "За раунд вскрывается 2 свойства предмета")
	check(a.estimate_value() <= a.true_value(), "Оценка не превышает истинную стоимость")
	check(a.round_threshold() == 2000, "Порог раунда 1 = 1000 × 2.0 = 2000")
	check(a.round_multiplier() == 2.0, "Множитель раунда 1 = 2.0")


func _test_gold_limit() -> void:
	print("--- Ограничение по золоту ---")
	var a = AuctionState.new()
	a.setup(make_players(500), make_items())
	a.start_auction()
	check(a.place_bid(1, 600) != "", "Ставка больше золота отклонена")
	check(a.place_bid(1, 0) != "", "Нулевая ставка отклонена")
	check(a.place_bid(1, 500) == "", "Ставка в пределах золота принята")


func _test_stealth() -> void:
	print("--- Скрытая ставка (плащ скрытности) ---")
	var a = AuctionState.new()
	a.setup(make_players(2000), make_items())
	a.start_auction()
	check(a.place_bid(1, 700, true) == "", "Скрытая ставка принята")
	check(a.get_public_bids(2)[1]["amount"] == -1, "Игрок 2 не видит сумму ставки игрока 1")
	check(a.get_public_bids(1)[1]["amount"] == 700, "Игрок 1 видит свою ставку")
	check(a.place_bid(1, 100, true) != "", "Повторное применение плаща запрещено")


func _test_win_in_round3() -> void:
	print("--- Победа в 3-м раунде (пороги 2000/1500/1300) ---")
	var a = AuctionState.new()
	a.setup(make_players(2000), make_items()) # истинная стоимость 1000
	a.start_auction()
	a.place_bid(1, 500)
	a.place_bid(2, 600)
	a.resolve_round()
	check(not a.finished and a.winner_id == -1, "Раунд 1: победителя нет (порог 2000)")
	a.start_round()
	a.place_bid(1, 1000)
	a.place_bid(2, 1200)
	a.resolve_round()
	check(not a.finished and a.winner_id == -1, "Раунд 2: победителя нет (порог 1500)")
	a.start_round()
	check(a.place_bid(2, 1400) == "", "Раунд 3: ставка 1400 принята (порог 1300)")
	a.resolve_round()
	check(a.winner_id == 2 and a.winning_price == 1400, "Игрок 2 победил в раунде 3 и платит 1400")
	var gold2: int = 0
	for player: Dictionary in a.players:
		if int(player["id"]) == 2:
			gold2 = int(player["gold"])
	check(gold2 == 600, "Золото победителя уменьшилось: 2000 - 1400 = 600")


func _test_defense() -> void:
	print("--- Нагрудник защиты (ставка ×2 в раунде защиты) ---")
	var a = AuctionState.new()
	a.setup(make_players(2000), make_items())
	a.start_auction()
	for r: int in range(3): # раунды 1..3 — все ставят мало
		for pid: int in [1, 2, 3, 4]:
			a.place_bid(pid, 100)
		a.resolve_round()
		if not a.finished:
			a.start_round()
	check(a.current_round == 4, "Дошли до раунда 4 (порог 1100)")
	check(a.place_bid(4, 600, false, true) == "", "Нагрудник применён в раунде 4")
	a.resolve_round()
	check(a.winner_id == 4 and a.winning_price == 600,
			"Защита ×2 дала победу: 600 → 1200 ≥ 1100, платит реальные 600")
	check(a.place_bid(4, 100, false, true) != "", "Повторное применение нагрудника запрещено")


func _test_round5_tie_speed() -> void:
	print("--- Раунд 5: равные ставки, побеждает скорость ---")
	var a = AuctionState.new()
	a.setup(make_players(2000), make_items())
	a.start_auction()
	for r: int in range(4): # раунды 1..4 без qualifying-ставок
		for pid: int in [1, 2, 3, 4]:
			a.place_bid(pid, 100)
		a.resolve_round()
		if not a.finished:
			a.start_round()
	check(a.current_round == 5, "Дошли до раунда 5")
	a.place_bid(1, 900) # раньше по времени
	a.place_bid(2, 900)
	a.resolve_round()
	check(a.winner_id == 1 and a.winning_price == 900,
			"При равных ставках 900 побеждает игрок 1 (поставил быстрее)")


func _test_no_winner() -> void:
	print("--- Аукцион без победителя ---")
	var a = AuctionState.new()
	a.setup(make_players(2000), make_items())
	a.start_auction()
	for r: int in range(5):
		a.resolve_round()
		if not a.finished:
			a.start_round()
	check(a.finished and a.winner_id == -1 and a.winning_price == 0, "Лот не продан, никто ничего не потерял")


func _initialize() -> void:
	print("=== Тест машины состояний аукциона ===")
	_test_reveal_and_estimate()
	_test_gold_limit()
	_test_stealth()
	_test_win_in_round3()
	_test_defense()
	_test_round5_tie_speed()
	_test_no_winner()
	if failures == 0:
		print("=== ИТОГ: ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ ===")
	else:
		printerr("=== ИТОГ: ОШИБОК: %d ===" % failures)
	quit(1 if failures > 0 else 0)

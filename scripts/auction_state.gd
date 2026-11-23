class_name AuctionState
extends RefCounted
## Машина состояний «Магического аукциона».
##
## ПРАВИЛА (по описанию игрока):
##  • Аукцион длится 5 раундов, участвуют 4 игрока.
##  • В начале каждого раунда вскрываются случайные свойства предметов
##    на игровом поле — по ним игроки оценивают примерную стоимость лота.
##  • В каждом раунде игрок может сделать ОДНУ ставку (в золоте).
##    Ставки действуют только внутри своего раунда.
##  • Проигравшие раунды ничего не теряют; платит только победитель.
##  • Раунды 1–4: чтобы выиграть, ставка должна быть выше ставок остальных
##    игроков ЭТОГО раунда и не ниже порога:
##    истинная стоимость лота × множитель раунда (2.0 / 1.5 / 1.3 / 1.1).
##  • Раунд 5: побеждает наибольшая ставка (без порога); при равенстве
##    ставок побеждает тот, кто сделал ставку быстрее.
##  • Способности снаряжения (передаются при place_bid):
##    use_stealth  — скрыть свою ставку в этом раунде (плащ скрытности);
##    use_defense  — ставка считается ×2 при проверке порога (нагрудник).
##    Каждая способность — не более одного раза за аукцион.

signal round_started(round_index: int)
signal properties_revealed(round_index: int, revealed: Array)
signal bid_placed(round_index: int, player_id: int, hidden: bool)
signal round_resolved(round_index: int, winner_id: int)
signal auction_finished(winner_id: int, price: int)

## Число раундов аукциона.
const ROUNDS: int = 5
## Порог выигрыша по раундам: истинная стоимость × множитель.
## Раунд 5 — порога нет, побеждает наибольшая ставка.
const ROUND_MULTIPLIERS: Array[float] = [2.0, 1.5, 1.3, 1.1, 1.0]
## Свойства предмета, которые вскрываются по раундам.
const PROPERTIES: Array[String] = ["name", "cost", "rarity", "type", "size"]

## Сколько случайных свойств каждого предмета вскрывается за раунд.
var properties_per_round: int = 1

# ------------------ СОСТОЯНИЕ ------------------
var items: Array = []                 # предметы лота (ItemData)
var players: Array = []               # [{id, name, gold}]
var current_round: int = 0            # 0 — не начат, 1..5 — раунд, 6 — завершён
var revealed: Dictionary = {}         # индекс предмета -> {свойство: true}
var bids: Dictionary = {}             # player_id -> {amount, order}
var stealth_round: Dictionary = {}    # player_id -> раунд применения плаща
var defense_round: Dictionary = {}    # player_id -> раунд применения нагрудника
var finished: bool = false
var winner_id: int = -1
var winning_price: int = 0
var _order_counter: int = 0           # порядок ставок (кто быстрее)


## players: [{id: int, name: String, gold: int}], items: [ItemData].
func setup(p_players: Array, p_items: Array) -> void:
	players = p_players.duplicate(true)
	items = p_items.duplicate()
	_reset()


func _reset() -> void:
	current_round = 0
	revealed = {}
	bids = {}
	stealth_round = {}
	defense_round = {}
	finished = false
	winner_id = -1
	winning_price = 0
	_order_counter = 0


# ============================================================
#  ХОД АУКЦИОНА
# ============================================================
func start_auction() -> void:
	_reset()
	start_round()


## Начинает следующий раунд: вскрывает свойства, очищает ставки.
func start_round() -> void:
	if finished:
		return
	current_round += 1
	bids = {}
	_reveal_properties()
	round_started.emit(current_round)


func _reveal_properties() -> void:
	var revealed_now: Array = []
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for item_index: int in items.size():
		if not revealed.has(item_index):
			revealed[item_index] = {}
		var hidden: Array[String] = []
		for prop: String in PROPERTIES:
			if not revealed[item_index].has(prop):
				hidden.append(prop)
		hidden.shuffle()
		for i: int in mini(properties_per_round, hidden.size()):
			revealed[item_index][hidden[i]] = true
			revealed_now.append({"item": item_index, "property": hidden[i]})
	properties_revealed.emit(current_round, revealed_now)


## Ставка игрока. Возвращает "" при успехе, иначе текст ошибки.
## use_stealth/use_defense — способности плаща/нагрудника (1 раз за аукцион).
func place_bid(player_id: int, amount: int,
		use_stealth: bool = false, use_defense: bool = false) -> String:
	if finished:
		return "Аукцион завершён"
	if current_round < 1 or current_round > ROUNDS:
		return "Аукцион ещё не начат"
	var player: Dictionary = _get_player(player_id)
	if player.is_empty():
		return "Игрок не найден"
	if amount <= 0:
		return "Ставка должна быть положительной"
	if amount > int(player["gold"]):
		return "Недостаточно золота"
	if use_stealth and stealth_round.has(player_id):
		return "Плащ уже использован в этом аукционе"
	if use_defense and defense_round.has(player_id):
		return "Нагрудник уже использован в этом аукционе"

	# Повторная ставка в том же раунде заменяет предыдущую.
	_order_counter += 1
	bids[player_id] = {"amount": amount, "order": _order_counter}
	if use_stealth:
		stealth_round[player_id] = current_round
	if use_defense:
		defense_round[player_id] = current_round
	var hidden: bool = stealth_round.get(player_id, 0) == current_round
	bid_placed.emit(current_round, player_id, hidden)
	return ""


## Разрешает текущий раунд: определяет победителя или переходит дальше.
func resolve_round() -> void:
	if finished or current_round < 1:
		return
	var winner: int = -1
	if not bids.is_empty():
		var best_eff := -1
		var best_order := -1
		for pid: int in bids:
			var bid: Dictionary = bids[pid]
			var effective: int = _effective_bid(pid)
			# Раунды 1–4: ставка обязана преодолеть порог.
			if current_round < ROUNDS and effective < round_threshold():
				continue
			if effective > best_eff or (effective == best_eff and int(bid["order"]) < best_order):
				winner = pid
				best_eff = effective
				best_order = int(bid["order"])

	if winner >= 0:
		_finish(winner, int(bids[winner]["amount"]))
		round_resolved.emit(current_round, winner)
		return

	round_resolved.emit(current_round, -1)
	if current_round >= ROUNDS:
		# Никто не победил даже в пятом раунде — лот не продан.
		_finish(-1, 0)


func _finish(p_winner: int, p_price: int) -> void:
	finished = true
	current_round = ROUNDS + 1
	winner_id = p_winner
	winning_price = p_price
	if p_winner >= 0:
		var player: Dictionary = _get_player(p_winner)
		player["gold"] = int(player["gold"]) - p_price
	auction_finished.emit(p_winner, p_price)


# ============================================================
#  ЗАПРОСЫ (для UI и ИИ)
# ============================================================
func _get_player(player_id: int) -> Dictionary:
	for player: Dictionary in players:
		if int(player["id"]) == player_id:
			return player
	return {}


## Истинная стоимость лота — сумма стоимостей всех предметов поля.
## Для баланса/сервера; игрокам показывается только оценка.
func true_value() -> int:
	var total := 0
	for item in items:
		total += int(item.cost)
	return total


## Множитель порога текущего раунда.
func round_multiplier() -> float:
	if current_round < 1 or current_round > ROUNDS:
		return 0.0
	return ROUND_MULTIPLIERS[current_round - 1]


## Порог выигрыша текущего раунда (истинная стоимость × множитель).
func round_threshold() -> int:
	return int(roundf(true_value() * round_multiplier()))


## Эффективная ставка игрока: с нагрудником в его раунде — ×2.
func _effective_bid(player_id: int) -> int:
	if not bids.has(player_id):
		return -1
	var amount: int = int(bids[player_id]["amount"])
	if defense_round.get(player_id, 0) == current_round:
		return amount * 2
	return amount


## Вид, в котором ставки этого раунда видны игроку for_player_id:
## чужие скрытые ставки (плащ) приходят как {"amount": -1}.
func get_public_bids(for_player_id: int) -> Dictionary:
	var result: Dictionary = {}
	for pid: int in bids:
		var hidden: bool = stealth_round.get(pid, 0) == current_round and pid != for_player_id
		result[pid] = {"amount": -1 if hidden else int(bids[pid]["amount"]),
				"order": int(bids[pid]["order"])}
	return result


## Оценка стоимости лота по ВСКРЫТЫМ свойствам (видна всем игрокам).
func estimate_value() -> int:
	var total := 0
	for item_index: int in items.size():
		if revealed.get(item_index, {}).get("cost", false):
			total += int(items[item_index].cost)
	return total


## Предмет, каким его видят игроки: только вскрытые свойства.
func get_visible_item(item_index: int) -> Dictionary:
	var item = items[item_index]
	var visible: Dictionary = {}
	var item_props: Dictionary = {
		"name": item.item_name, "cost": item.cost,
		"rarity": item.rarity, "type": item.type,
		"size": Vector2i(item.size_x, item.size_y),
	}
	for prop: String in PROPERTIES:
		if revealed.get(item_index, {}).get(prop, false):
			visible[prop] = item_props[prop]
	return visible

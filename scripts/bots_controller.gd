class_name BotsController
extends RefCounted
## Мозг ботов аукциона.
##
## Боты оценивают стоимость лота по ОТКРЫТЫМ клеткам поля
## (публичная информация, как и у живых игроков): каждый предмет
## вносит в оценку долю своей стоимости, пропорциональную доле
## открытых клеток. Чем больше раундов прошло — тем точнее оценка.
##
## Ставка бота направлена на порог выигрыша текущего раунда
## (оценка × множитель раунда) с шумом, зависящим от характера бота,
## и не может превышать его золото.
## В будущем вместо ботов подключаются живые игроки по сети.

## Множители порога выигрыша по раундам (правила аукциона).
const ROUND_MULTIPLIERS: Array[float] = [2.0, 1.5, 1.3, 1.1, 1.0]


## Оценка стоимости лота по открытым клеткам.
## items — [{row, col, w, h, cost, ...}], revealed — открытые клетки.
static func estimate_lot_value(items: Array, revealed: Dictionary) -> int:
	var total := 0
	for item: Dictionary in items:
		var cells: int = int(item.w) * int(item.h)
		if cells <= 0:
			continue
		var seen := 0
		for r: int in range(int(item.row), int(item.row) + int(item.h)):
			for c: int in range(int(item.col), int(item.col) + int(item.w)):
				if revealed.has(Vector2i(c, r)):
					seen += 1
		total += int(roundf(int(item.cost) * float(seen) / float(cells)))
	return total


## Ставка бота в текущем раунде.
## Возвращает сумму ставки (0 допустимо), всегда в пределах gold.
static func bot_bid(estimate: int, round: int, gold: int,
		aggression: float, rng: RandomNumberGenerator) -> int:
	if estimate <= 0 or gold <= 0:
		return 0
	var mult: float = ROUND_MULTIPLIERS[clampi(round, 1, 5) - 1]
	# Шум оценки: базовый разброс ±12% + поправка характера бота.
	var noise: float = rng.randf_range(-0.12, 0.12) + (aggression - 0.5) * 0.3
	var desired := int(roundf(estimate * mult * (1.0 + noise)))
	return clampi(desired, 0, gold)

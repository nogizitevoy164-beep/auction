extends Control
## Главный игровой интерфейс «Магического аукциона».
## Сцена: scenes/main_ui.tscn (дерево Control-контейнеров).
## Скрипт заполняет блоки текстовыми заглушками, управляет игровым полем
## (сетка GameField: 30 строго квадратных клеток по X) и калькулятором.

## Локальные ссылки (не зависят от глобального кэша классов).
const PlayerDataS = preload("res://scripts/player_data.gd")
const BotsControllerS = preload("res://scripts/bots_controller.gd")

# ==================== ИГРОВОЕ ПОЛЕ ====================
## Сетка рисуется узлом GameField (scripts/game_field.gd):
## клетка = ширина поля / 30, поэтому клетки всегда квадратные;
## число рядов вычисляется из высоты поля.
## Предметы на поле: row/col — левый верхний угол, w×h — размер в клетках.
## Пул набирается случайно по шансам выбранного поля
## (GameData.FIELD_TIERS) функцией _place_tier_items().
var field_items: Array[Dictionary] = []

# ==================== ВЫБОР ИГРОВОГО ПОЛЯ ====================
## Выбранное поле аукциона (GameData.FieldTier); -1 — пока не выбрано.
var current_tier: int = -1
## ГСЧ раскладки лотов по шансам поля.
var _item_rng := RandomNumberGenerator.new()
## Оверлей выбора поля (создаётся в _setup_field_selection()).
var _tier_overlay: PanelContainer
## Подпись с золотом игрока на экране выбора.
var _tier_gold_label: Label
## Кнопки входа на поля: FieldTier -> Button.
var _tier_buttons: Dictionary = {}

# ==================== ТАЙМЕР РАУНДА ====================
const ROUND_TIME: float = 40.0    # длительность одного раунда, секунд

## Сигнал: время раунда истекло (round_index — номер завершившегося раунда).
signal round_time_expired(round_index: int)

## Название текущего аукционного поля (показывается в статусе раунда).
var auction_field_name: String = "Волшебный лот"
## Текущий раунд аукциона (1..5); в 1-м раунде поле скрыто туманом.
var _field_round: int = 1
## Остаток времени текущего раунда, секунд.
var round_time_left: float = ROUND_TIME
## Секундный таймер раунда (создаётся в _ready).
var _round_timer: Timer

# ==================== ЭКИПИРОВКА ====================
## Слоты экипировки: имя узла в сцене -> название слота.
const EQUIP_SLOT_LABELS: Dictionary = {
	"SlotHead":   "Головной убор",
	"SlotArmor":  "Броня",
	"SlotGloves": "Перчатки",
	"SlotBoots":  "Обувь",
	"SlotWeapon": "Оружие",
	"SlotRing1":  "Кольцо 1",
	"SlotRing2":  "Кольцо 2",
	"SlotNeck":   "Ожерелье",
}

# ==================== ССЫЛКИ НА УЗЛЫ СЦЕНЫ ====================
@onready var character_name_label: Label = $MainHBox/LeftColumn/CharacterPanel/CharacterVBox/CharacterName
@onready var character_portrait: TextureRect = $MainHBox/LeftColumn/CharacterPanel/CharacterVBox/CharacterPortrait
@onready var equipment_list: VBoxContainer = $MainHBox/LeftColumn/EquipmentPanel/EquipmentList
@onready var news_label: Label = $MainHBox/CenterColumn/NewsPanel/NewsLabel
@onready var round_field_label: Label = $MainHBox/CenterColumn/RoundInfoPanel/RoundInfoHBox/FieldNameLabel
@onready var round_label: Label = $MainHBox/CenterColumn/RoundInfoPanel/RoundInfoHBox/RoundLabel
@onready var round_timer_label: Label = $MainHBox/CenterColumn/RoundInfoPanel/RoundInfoHBox/RoundTimerLabel
@onready var round_defense_label: Label = $MainHBox/CenterColumn/RoundInfoPanel/RoundInfoHBox/DefenseLabel
@onready var game_field = $MainHBox/CenterColumn/FieldHBox/GameFieldPanel/GameField
@onready var players_column: VBoxContainer = $MainHBox/CenterColumn/FieldHBox/PlayersColumn
@onready var log_scroll: ScrollContainer = $MainHBox/RightColumn/LogPanel/LogVBox/LogScroll
@onready var log_list: VBoxContainer = $MainHBox/RightColumn/LogPanel/LogVBox/LogScroll/LogList
@onready var calc_display: LineEdit = $MainHBox/RightColumn/CalcPanel/CalcVBox/CalcDisplay
@onready var calc_grid: GridContainer = $MainHBox/RightColumn/CalcPanel/CalcVBox/CalcGrid
@onready var calc_gold_label: Label = $MainHBox/RightColumn/CalcPanel/CalcVBox/CalcGoldLabel
@onready var bid_button: Button = $MainHBox/RightColumn/CalcPanel/CalcVBox/BidButton
@onready var main_hbox: HBoxContainer = $MainHBox

## Текущее выражение калькулятора (набирается кнопками).
var calc_expression: String = ""

# ==================== ИГРОКИ И БОТЫ ====================
## Имена ботов (текущий игрок — «Вы», всегда верхняя иконка).
const BOT_NAMES: Array[String] = ["Бот Айра", "Бот Дорн", "Бот Кира"]

## Игроки аукциона: индекс 0 — текущий игрок (верхняя иконка),
## далее три бота (в будущем — живые игроки по сети).
var players: Array[PlayerDataS] = []
## ГСЧ ботов (задержки ставок, шум оценки).
var _bot_rng := RandomNumberGenerator.new()


func _ready() -> void:
	_item_rng.randomize()
	_setup_round_timer()
	_setup_players()
	_init_placeholders()
	_setup_field_selection()
	_setup_calc()


# ============================================================
#  ЗАГЛУШКИ
# ============================================================
func _init_placeholders() -> void:
	set_character_name("Аукционер Морган")
	for slot_node_name: String in EQUIP_SLOT_LABELS:
		set_equipment(slot_node_name, "—")
	_init_demo_equipment()
	set_news("Выберите аукционное поле, чтобы начать!")
	set_field_name("—")
	add_log("[Игра] Добро пожаловать на магический аукцион!")
	add_log("[Игра] Выберите игровое поле для входа.")


# ============================================================
#  ВЫБОР ИГРОВОГО ПОЛЯ (начальный / средний / элитный)
# ============================================================
## В начале игры вместо игрового поля показывается экран выбора:
## три поля с порогом входа по золоту (1000 / 10 000 / 100 000).
func _setup_field_selection() -> void:
	main_hbox.visible = false
	_tier_overlay = PanelContainer.new()
	_tier_overlay.name = "TierSelection"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.08, 0.12)
	_tier_overlay.add_theme_stylebox_override("panel", sb)
	_tier_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_tier_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tier_overlay.add_child(center)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)
	var title := Label.new()
	title.text = "Выберите аукционное поле"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	_tier_gold_label = Label.new()
	_tier_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_tier_gold_label)
	for tier: int in [GameData.FieldTier.STARTER, GameData.FieldTier.MID, GameData.FieldTier.ELITE]:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(520, 72)
		btn.pressed.connect(_on_tier_selected.bind(tier))
		vbox.add_child(btn)
		_tier_buttons[tier] = btn
	_refresh_tier_buttons()


## Обновляет доступность кнопок полей по текущему золоту игрока.
func _refresh_tier_buttons() -> void:
	var gold: int = players[0].gold if players.size() > 0 else 0
	if _tier_gold_label != null:
		_tier_gold_label.text = "Ваше золото: %d" % gold
	for tier in _tier_buttons:
		var info: Dictionary = GameData.FIELD_TIERS[tier]
		var btn: Button = _tier_buttons[tier]
		var ok: bool = gold >= int(info["min_gold"])
		btn.disabled = not ok
		var hint: String = "" if ok else "  —  не хватает золота"
		btn.text = "%s\nвход: от %d монет%s" % [info["title"], int(info["min_gold"]), hint]


## Вход на выбранное поле: проверка золота, вход ботов,
## раскладка лотов по шансам поля и старт 1-го раунда.
func _on_tier_selected(tier: int) -> void:
	var info: Dictionary = GameData.FIELD_TIERS[tier]
	var min_gold: int = int(info["min_gold"])
	if players[0].gold < min_gold:
		add_log("[Игра] Не хватает золота для «%s»: нужно %d, у вас %d." % [
			info["title"], min_gold, players[0].gold])
		return
	current_tier = tier
	_tier_overlay.visible = false
	main_hbox.visible = true
	# Боты тоже вошли на это поле — их золото не ниже порога входа.
	for i: int in range(1, players.size()):
		players[i].gold = maxi(players[i].gold, min_gold)
	auction_field_name = String(info["title"])
	add_log("[Игра] Вы вошли на «%s» (вход от %d монет)." % [auction_field_name, min_gold])
	_place_tier_items(int(info["lot_count"]))
	set_field_round(1)
	add_log("[Игра] Раунд 1: местоположение предметов скрыто...")
	add_log("[Игра] Стартовое золото: %d" % players[0].gold)
	_update_player_labels()


func set_character_name(value: String) -> void:
	character_name_label.text = value


func set_news(value: String) -> void:
	news_label.text = "Новости:  " + value


## Обновляет строку статуса раунда: название аукционного поля,
## номер текущего раунда и коэффициент срабатывания защиты ставки.
func update_round_info(field_name: String, current_round: int, multiplier: float) -> void:
	round_field_label.text = "Аукционное поле: %s" % field_name
	round_label.text = "Раунд: %d" % current_round
	# Множитель защиты ставки: ×2.0 в 1-м раунде, ×1.5 во 2-м,
	# ×1.3 в 3-м, ×1.1 в 4-м; в 5-м раунде защиты нет (×1.0).
	round_defense_label.text = "Защита ставки: ×%s" % ("—" if multiplier <= 0.0 else "%.1f" % multiplier)


## Удобная обёртка: вычисляет коэффициент защиты по номеру раунда
## (правила аукциона: 2.0 / 1.5 / 1.3 / 1.1 / без защиты).
func update_round_info_from_state(field_name: String, current_round: int) -> void:
	var multipliers: Array[float] = [2.0, 1.5, 1.3, 1.1, 1.0]
	var multiplier: float = 0.0
	if current_round >= 1 and current_round <= multipliers.size():
		multiplier = multipliers[current_round - 1]
	update_round_info(field_name, current_round, multiplier)


## slot_node_name — один из ключей EQUIP_SLOT_LABELS (например "SlotWeapon").
## Ставит строку-заглушку (имя слота + текст).
func set_equipment(slot_node_name: String, item: String) -> void:
	var label: Label = equipment_list.get_node(NodePath(slot_node_name + "/Text"))
	label.text = "%s: %s" % [EQUIP_SLOT_LABELS[slot_node_name], item]
	label.modulate = Color.WHITE


## Ставит предмет снаряжения в слот: иконка + название + цвет качества.
func set_equipment_item(slot_node_name: String, equip: EquipmentData) -> void:
	var slot: HBoxContainer = equipment_list.get_node(NodePath(slot_node_name))
	var icon: TextureRect = slot.get_node(NodePath("Icon"))
	var label: Label = slot.get_node(NodePath("Text"))
	icon.texture = equip.icon
	label.text = "%s: %s (%s)" % [
		EQUIP_SLOT_LABELS[slot_node_name], equip.item_name, equip.quality_name()]
	label.modulate = equip.quality_color()


## Демо: заполняет панель экипировки из ресурсов .tres
## (res://resources/equipment/*.tres — редактируются в Инспекторе).
func _init_demo_equipment() -> void:
	var demo: Dictionary = {
		"SlotHead":   "hood_assassin",
		"SlotArmor":  "chest_defense",
		"SlotGloves": "mittens_warrior",
		"SlotBoots":  "boots_plate",
	}
	for slot_node_name: String in demo:
		var path := "res://resources/equipment/%s.tres" % demo[slot_node_name]
		var equip: EquipmentData = load(path)
		if equip is EquipmentData:
			set_equipment_item(slot_node_name, equip)


func set_portrait_texture(texture: Texture2D) -> void:
	character_portrait.texture = texture


# ============================================================
#  ЛОГ
# ============================================================
func add_log(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_list.add_child(label)
	# Автопрокрутка вниз после добавления строки.
	await get_tree().process_frame
	log_scroll.scroll_vertical = int(log_scroll.get_v_scroll_bar().max_value)


# ============================================================
#  ИГРОВОЕ ПОЛЕ (строго квадратные клетки, 30 колонок)
# ============================================================
## Сетку рисует узел GameField (scripts/game_field.gd):
## клетка = ширина поля / 30, поэтому клетки всегда квадратные;
## число рядов вычисляется из высоты и заполняет всё место.
## Сокровища скрыты: каждый раунд система вскрывает несколько
## случайных клеток (больше — в более поздних раундах).

## Отправляет пул предметов на поле и перерисовывает сетку.
func rebuild_field() -> void:
	game_field.set_items(field_items)


## Набирает случайные предметы из каталога продажи
## (GameData.SELLABLE_ITEMS) по шансам текущего поля и раскладывает
## их по верхним рядам поля «полками» — без наложений,
## цвет клетки = цвет качества.
## Шанс предмета = chance_starter / chance_mid / chance_elite
## (колонки CSV res://data/magic_auction_items.csv).
func _place_tier_items(count: int) -> void:
	field_items.clear()
	# Колонка шансов выбранного поля (по умолчанию — начальное).
	var chance_key: String = "chance_starter"
	if current_tier >= 0:
		chance_key = String(GameData.FIELD_TIERS[current_tier]["chance_key"])
	# Взвешенный выбор без повторений: чем выше шанс — тем чаще лот.
	var pool: Array = GameData.SELLABLE_ITEMS.keys()
	var picked: Array[Dictionary] = []
	for i: int in mini(count, pool.size()):
		var total_weight := 0.0
		for id in pool:
			total_weight += float(GameData.SELLABLE_ITEMS[id][chance_key])
		var roll := _item_rng.randf() * total_weight
		var chosen: String = String(pool[pool.size() - 1])
		for id in pool:
			roll -= float(GameData.SELLABLE_ITEMS[id][chance_key])
			if roll <= 0.0:
				chosen = String(id)
				break
		picked.append(GameData.SELLABLE_ITEMS[chosen])
		pool.erase(chosen)
	# Раскладка «полками».
	var col: int = 0
	var shelf_y: int = 0
	var shelf_h: int = 0
	for info: Dictionary in picked:
		var item_size: Vector2i = info["size"]
		# Предмет не влезает по ширине — переносим на новую полку.
		if col + item_size.x > 30:
			col = 0
			shelf_y += shelf_h + 1
			shelf_h = 0
		field_items.append({
			"row": shelf_y, "col": col,
			"w": item_size.x, "h": item_size.y,
			"title": info["title"],
			"cost": int(info["cost"]),
			"color": GameData.QUALITY_COLORS[info["quality"]],
		})
		col += item_size.x + 1
		shelf_h = maxi(shelf_h, item_size.y)
	rebuild_field()
	var titles: Array[String] = []
	for placed: Dictionary in field_items:
		titles.append(String(placed["title"]))
	add_log("[Игра] Лоты на поле: %s" % ", ".join(titles))


## Добавляет предмет в пул: размер w × h клеток, угол — (row, col).
func add_field_item(row: int, col: int, w: int, h: int, title: String,
		color: Color = Color(0.60, 0.60, 0.70)) -> void:
	w = clampi(w, 1, 30)
	h = maxi(h, 1)
	col = clampi(col, 0, 30 - w)
	field_items.append({"row": row, "col": col, "w": w, "h": h, "title": title, "color": color})
	rebuild_field()


## Устанавливает название аукционного поля (в статусе раунда).
func set_field_name(value: String) -> void:
	auction_field_name = value
	update_round_info_from_state(auction_field_name, _field_round)


## Устанавливает текущий раунд: система вскрывает порцию случайных
## клеток поля (больше — в более поздних раундах), строка статуса
## показывает коэффициент защиты ставки. Таймер раунда перезапускается.
func set_field_round(value: int) -> void:
	_field_round = clampi(value, 1, 5)
	game_field.reveal_for_round(_field_round)
	update_round_info_from_state(auction_field_name, _field_round)
	set_news("Раунд %d — смотрите на поле и делайте ставки!" % _field_round)
	start_round_timer()
	# Калькулятор помнит предыдущую ставку игрока: подставляем её в поле,
	# а ставки всех игроков на новый раунд обнуляются.
	var prev_bid: int = players[0].last_bid
	for p: PlayerDataS in players:
		p.last_bid = 0
	_prefill_calc(prev_bid)
	_schedule_bot_bids()


## Новый аукцион: сокровища снова полностью скрыты (сетка лота закрыта).
func reset_field_reveal() -> void:
	game_field.reset_reveal()


# ============================================================
#  ТАЙМЕР РАУНДА (40 секунд, тик каждую секунду)
# ============================================================
## Создаёт секундный таймер и подключает тик.
func _setup_round_timer() -> void:
	_round_timer = Timer.new()
	_round_timer.wait_time = 1.0
	_round_timer.one_shot = false
	_round_timer.timeout.connect(_on_round_timer_tick)
	add_child(_round_timer)


## Перезапускает отсчёт текущего раунда: время = ROUND_TIME (40 с).
func start_round_timer() -> void:
	round_time_left = ROUND_TIME
	_update_round_timer_label()
	_round_timer.start()


## Тик таймера (раз в секунду): уменьшаем остаток и обновляем надпись.
func _on_round_timer_tick() -> void:
	round_time_left -= 1.0
	_update_round_timer_label()
	if round_time_left <= 0.0:
		_on_round_time_expired()


## Время вышло — запускается следующий раунд (после 5-го аукцион завершён).
func _on_round_time_expired() -> void:
	round_time_expired.emit(_field_round)
	add_log("[Игра] Время раунда %d вышло!" % _field_round)
	_advance_round()


## Завершает текущий раунд: досрочно (все сделали ставки) или по таймеру.
## После 5-го раунда аукцион завершается.
func _advance_round() -> void:
	if _field_round >= 5:
		_round_timer.stop()
		set_news("Аукцион завершён! Итоги подведены.")
		add_log("[Игра] Раунд 5 завершён — аукцион окончен!")
		return
	set_field_round(_field_round + 1)


## Все игроки поставили — новый раунд начинается, не дожидаясь таймера.
func _check_all_bid() -> void:
	for p: PlayerDataS in players:
		if p.last_bid <= 0:
			return
	add_log("[Игра] Все игроки сделали ставки — начинается раунд %d!" % [
		_field_round + 1])
	_advance_round()


## Подставляет предыдущую ставку игрока в калькулятор.
func _prefill_calc(prev_bid: int) -> void:
	calc_expression = str(maxi(prev_bid, 0))
	calc_display.text = calc_expression


## Обновляет надпись таймера в формате "0:40", "0:39", ...
func _update_round_timer_label() -> void:
	var seconds := maxi(int(round_time_left), 0)
	round_timer_label.text = "%d:%02d" % [int(seconds / 60.0), seconds % 60]


# ============================================================
#  ИГРОКИ И БОТЫ
# ============================================================
## Создаёт 4 игроков: «Вы» (верхняя иконка) и три бота.
func _setup_players() -> void:
	players.clear()
	_bot_rng.randomize()
	var human := PlayerDataS.new()
	human.id = 1
	human.player_name = "Вы"
	human.is_bot = false
	human.gold = 1000
	human.avatar_path = "res://icons/player_1.svg"
	players.append(human)
	var bot_gold: Array[int] = [900, 1100, 1000]
	for i: int in 3:
		var bot := PlayerDataS.new()
		bot.id = i + 2
		bot.player_name = BOT_NAMES[i]
		bot.is_bot = true
		bot.gold = bot_gold[i]
		bot.aggression = 0.3 + 0.2 * i # осторожный / средний / агрессивный
		bot.avatar_path = "res://icons/player_%d.svg" % (i + 2)
		players.append(bot)
	for i: int in players.size():
		var row: HBoxContainer = players_column.get_node(NodePath("PlayerRow%d" % i))
		var avatar: TextureRect = row.get_node(NodePath("Avatar"))
		avatar.texture = load(players[i].avatar_path)
		var name_label: Label = row.get_node(NodePath("Info/NameLabel"))
		name_label.text = players[i].player_name
	_update_player_labels()


## Обновляет подписи текущих ставок рядом с иконками игроков
## (короткий текст — колонка игроков не расширяется и не толкает поле).
func _update_player_labels() -> void:
	for i: int in players.size():
		var row: HBoxContainer = players_column.get_node(NodePath("PlayerRow%d" % i))
		var bid_label: Label = row.get_node(NodePath("Info/BidLabel"))
		var p: PlayerDataS = players[i]
		bid_label.text = str(p.last_bid) if p.last_bid > 0 else "—"
	calc_gold_label.text = "Ваше золото: %d" % players[0].gold


## Боты делают ставки в течение раунда: оценивают лот по открытым
## клеткам поля (публичная информация) и назначают каждому боту
## случайный момент ставки. В будущем вместо ботов — игроки по сети.
func _schedule_bot_bids() -> void:
	var estimate := BotsControllerS.estimate_lot_value(field_items, game_field.revealed)
	for p: PlayerDataS in players:
		if not p.is_bot:
			continue
		p.last_bid = 0
		p.last_estimate = estimate
		var delay: float = _bot_rng.randf_range(3.0, 35.0)
		get_tree().create_timer(delay).timeout.connect(_bot_place_bid.bind(p, _field_round))
	_update_player_labels()


## Ставка конкретного бота (если раунд к моменту тика не сменился).
func _bot_place_bid(bot: PlayerDataS, round_at_schedule: int) -> void:
	if round_at_schedule != _field_round or bot.last_bid > 0:
		return
	bot.last_bid = BotsControllerS.bot_bid(
			bot.last_estimate, _field_round, bot.gold, bot.aggression, _bot_rng)
	if bot.last_bid > 0:
		add_log("[%s] ставка: %d монет (оценка лота %d)" % [
			bot.player_name, bot.last_bid, bot.last_estimate])
	else:
		add_log("[%s] пасует в этом раунде" % bot.player_name)
	_update_player_labels()
	_check_all_bid()


# ============================================================
#  КАЛЬКУЛЯТОР СТОИМОСТИ
# ============================================================
func _setup_calc() -> void:
	for child in calc_grid.get_children():
		if child is Button:
			child.pressed.connect(_on_calc_button_pressed.bind(child.text))
	bid_button.pressed.connect(_on_bid_button_pressed)


func _on_calc_button_pressed(symbol: String) -> void:
	match symbol:
		"C":
			calc_expression = ""
			calc_display.text = "0"
		"=":
			_calc_evaluate()
		_:
			calc_expression += symbol
			calc_display.text = calc_expression


func _calc_evaluate() -> void:
	if calc_expression.is_empty():
		return
	var expression := Expression.new()
	if expression.parse(calc_expression) != OK:
		_calc_show_error()
		return
	var result: Variant = expression.execute()
	if expression.has_execute_failed():
		_calc_show_error()
		return
	calc_expression = str(result)
	calc_display.text = calc_expression


func _calc_show_error() -> void:
	calc_expression = ""
	calc_display.text = "Ошибка"


## Вычисляет текущее выражение калькулятора. Возвращает целое (>=0)
## или -1, если выражение пустое или некорректное.
func _calc_result() -> int:
	if calc_expression.is_empty():
		return -1
	var expression := Expression.new()
	if expression.parse(calc_expression) != OK:
		return -1
	var result: Variant = expression.execute()
	if expression.has_execute_failed():
		return -1
	if not (result is int or result is float):
		return -1
	return int(roundf(float(result)))


## Кнопка «Сделать ставку»: текущее выражение калькулятора становится
## ставкой текущего игрока. Повторная ставка в раунде запрещена.
func _on_bid_button_pressed() -> void:
	var player: PlayerDataS = players[0]
	if player.last_bid > 0:
		add_log("[Игра] Вы уже сделали ставку в этом раунде")
		return
	var value := _calc_result()
	if value <= 0:
		add_log("[Игра] Наберите сумму ставки в калькуляторе (например 150)")
		return
	var amount: int = clampi(value, 1, player.gold)
	if amount < value:
		add_log("[Игра] Ставка урезана до вашего золота: %d" % amount)
	player.last_bid = amount
	add_log("[Вы] ставка: %d монет" % amount)
	_update_player_labels()
	_check_all_bid()

extends Control
## Главный игровой интерфейс «Магического аукциона».
## Сцена: scenes/main_ui.tscn (дерево Control-контейнеров).
## Скрипт заполняет блоки текстовыми заглушками, управляет игровым полем
## (сетка GameField: 30 строго квадратных клеток по X) и калькулятором.

## Локальные ссылки (не зависят от глобального кэша классов).
const PlayerDataS = preload("res://scripts/player_data.gd")
const BotsControllerS = preload("res://scripts/bots_controller.gd")
const SaveDataS = preload("res://scripts/save_data.gd")
const GameFieldS = preload("res://scripts/game_field.gd")
const ServerClientS = preload("res://scripts/server_client.gd")

const ROLE_DATA: Dictionary = {
	"mage": {"title": "Маг", "portrait": "res://icons/silhouette_mage.svg"},
	"warrior": {"title": "Воин", "portrait": "res://icons/silhouette_warrior.svg"},
	"assassin": {"title": "Ассасин", "portrait": "res://icons/silhouette_assassin.svg"},
}

# ==================== ИГРОВОЕ ПОЛЕ ====================
## Сетка рисуется узлом GameField (scripts/game_field.gd):
## клетка = ширина поля / 30, поэтому клетки всегда квадратные;
## число рядов вычисляется из высоты поля.
## Предметы на поле: row/col — левый верхний угол, w×h — размер в клетках.
## Пул набирается случайно по шансам выбранного поля
## (GameData.FIELD_TIERS) функцией _place_tier_items().
var field_items: Array[Dictionary] = []
var inventory: Array[Dictionary] = []
var _save_state: Dictionary = {}
var _inventory_list: VBoxContainer
var _inventory_gold_label: Label
var _role_selector: HBoxContainer
var _selected_role: String = "warrior"
var _equipped_items: Dictionary = {}
var _auction_settled: bool = false
## Ставки предыдущего завершённого раунда, доступные для отображения.
var _revealed_round_bids: Dictionary = {}
var _round_bids_visible: bool = false
var _round_finished: bool = false
var _auction_finished: bool = false
const ROUND_PROTECTION: Array[float] = [2.0, 1.5, 1.3, 1.1, 1.0]

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
@onready var game_field_panel: PanelContainer = $MainHBox/CenterColumn/FieldHBox/GameFieldPanel
@onready var field_hbox: HBoxContainer = $MainHBox/CenterColumn/FieldHBox
@onready var players_column: VBoxContainer = $MainHBox/CenterColumn/FieldHBox/PlayersColumn
@onready var log_scroll: ScrollContainer = $MainHBox/RightColumn/LogPanel/LogVBox/LogScroll
@onready var log_list: VBoxContainer = $MainHBox/RightColumn/LogPanel/LogVBox/LogScroll/LogList
@onready var calc_display: LineEdit = $MainHBox/RightColumn/CalcPanel/CalcVBox/CalcDisplay
@onready var calc_grid: GridContainer = $MainHBox/RightColumn/CalcPanel/CalcVBox/CalcGrid
@onready var calc_gold_label: Label = $MainHBox/RightColumn/CalcPanel/CalcVBox/CalcGoldLabel
@onready var bid_button: Button = $MainHBox/RightColumn/CalcPanel/CalcVBox/BidButton
@onready var main_hbox: HBoxContainer = $MainHBox
@onready var center_column: VBoxContainer = $MainHBox/CenterColumn
@onready var round_info_panel: PanelContainer = $MainHBox/CenterColumn/RoundInfoPanel

## Текущее выражение калькулятора (набирается кнопками).
var calc_expression: String = ""
var _calc_prefilled: bool = false
var _central_view_host: PanelContainer
var _active_central_view: String = "auction"
var _server_client: Node
var _server_connected: bool = false

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
	_save_state = SaveDataS.load_game()
	_setup_players()
	_setup_role_selector()
	_init_placeholders()
	_setup_inventory_panel()
	_setup_central_navigation()
	_setup_field_selection()
	_setup_calc()
	_server_client = ServerClientS.new()
	add_child(_server_client)
	call_deferred("_sync_with_server")


func _sync_with_server() -> void:
	var profile = await _server_client.connect_guest()
	if profile.is_empty():
		add_log("[Сервер] Сервер недоступен — используется локальный режим.")
		return
	_server_connected = true
	_apply_server_profile(profile)
	_server_client.server_event.connect(_on_server_event)
	_server_client.start_realtime()
	add_log("[Сервер] Подключено: %s." % String(profile.get("login", "игрок")))


func _apply_server_profile(profile: Dictionary) -> void:
	players[0].gold = maxi(int(profile.get("coins", players[0].gold)), 0)
	inventory.clear()
	_equipped_items.clear()
	for server_item: Variant in profile.get("inventory", []):
		if server_item is Dictionary:
			var item := {
				"id": String(server_item.get("id", "")),
				"title": String(server_item.get("name", server_item.get("title", "Предмет"))),
				"cost": int(server_item.get("baseCost", server_item.get("cost", 0))),
				"quality": int(server_item.get("quality", 1)),
				"gear_class_id": String(server_item.get("gearClassId", server_item.get("gear_class_id", ""))),
				"type": String(server_item.get("type", "")),
				"weaponKind": String(server_item.get("weaponKind", "")),
				"description": String(server_item.get("description", "")),
				"state": String(server_item.get("state", "inventory")),
			}
			if item["state"] == "equipped":
				var server_slot := String(server_item.get("slot", ""))
				if server_slot.is_empty():
					server_slot = String(profile.get("equipment", {}).find_key(String(server_item.get("id", ""))))
				if not server_slot.is_empty():
					_equipped_items[server_slot] = item
			else:
				inventory.append(item)
	SaveDataS.save_game(players[0].gold, inventory)
	_update_player_labels()
	_refresh_equipment_slots()
	_refresh_inventory()


func _on_server_event(event_type: String, payload: Variant) -> void:
	if event_type == "news_created" and payload is Dictionary:
		set_news(String(payload.get("message", "Новое серверное событие")))
		add_log("[Новости] %s" % String(payload.get("title", "Новость сервера")))
	elif event_type == "catalog_updated":
		add_log("[Сервер] Каталог предметов обновлён администратором.")


# ============================================================
#  ЗАГЛУШКИ
# ============================================================
func _init_placeholders() -> void:
	set_character_name("Аукционер Морган")
	for slot_node_name: String in EQUIP_SLOT_LABELS:
		set_equipment(slot_node_name, "—")
	_update_role_portrait()
	set_news("Выберите аукционное поле, чтобы начать!")
	set_field_name("—")
	add_log("[Игра] Добро пожаловать на магический аукцион!")
	add_log("[Игра] Выберите игровое поле для входа.")
	_refresh_inventory()


func _setup_inventory_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "InventoryPanel"
	panel.custom_minimum_size = Vector2(280, 0)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var header := Label.new()
	header.text = "Склад выигранных предметов"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 18)
	box.add_child(header)
	_inventory_gold_label = Label.new()
	_inventory_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_inventory_gold_label)
	_inventory_list = VBoxContainer.new()
	box.add_child(_inventory_list)
	$MainHBox/LeftColumn.add_child(panel)
	_refresh_inventory()


func _setup_role_selector() -> void:
	# Селектор роли вынесен в отдельную панель, чтобы не менять высоту
	# растягиваемой панели персонажа и не ломать расчёт контейнеров.
	var selector_panel := PanelContainer.new()
	selector_panel.name = "RoleSelectorPanel"
	selector_panel.custom_minimum_size = Vector2(0, 36)
	_role_selector = HBoxContainer.new()
	_role_selector.name = "RoleSelector"
	_role_selector.alignment = BoxContainer.ALIGNMENT_CENTER
	_role_selector.add_theme_constant_override("separation", 4)
	selector_panel.add_child(_role_selector)
	$MainHBox/LeftColumn.add_child(selector_panel)
	$MainHBox/LeftColumn.move_child(selector_panel, 0)
	for role_id: String in ROLE_DATA:
		var role_button := Button.new()
		role_button.text = String(ROLE_DATA[role_id]["title"])
		role_button.tooltip_text = "Выбрать роль: %s" % role_button.text
		role_button.toggle_mode = true
		role_button.button_pressed = role_id == _selected_role
		role_button.pressed.connect(_select_role.bind(role_id))
		_role_selector.add_child(role_button)


func _select_role(role_id: String) -> void:
	if not ROLE_DATA.has(role_id):
		return
	_selected_role = role_id
	for button: Button in _role_selector.get_children():
		button.button_pressed = button.text == String(ROLE_DATA[role_id]["title"])
	_update_role_portrait()
	add_log("[Персонаж] Выбрана роль: %s." % ROLE_DATA[role_id]["title"])


func _update_role_portrait() -> void:
	if character_portrait == null:
		return
	character_portrait.texture = load(String(ROLE_DATA[_selected_role]["portrait"]))
	character_portrait.tooltip_text = "Роль: %s" % ROLE_DATA[_selected_role]["title"]


func _gear_id_for_item(item: Dictionary) -> String:
	var explicit_id := String(item.get("gear_class_id", item.get("gearClassId", "")))
	if GameData.GEAR_CLASSES.has(explicit_id):
		return explicit_id
	var weapon_kind := String(item.get("weaponKind", item.get("weapon_kind", "")))
	var weapon_gear: Dictionary = {
		"dagger": "weapon_dagger_assassin",
		"sword": "weapon_sword_warrior",
		"staff": "weapon_staff_mage",
	}
	if weapon_gear.has(weapon_kind) and GameData.GEAR_CLASSES.has(weapon_gear[weapon_kind]):
		return String(weapon_gear[weapon_kind])
	var title := String(item.get("title", item.get("name", "")))
	for gear_id: String in GameData.GEAR_CLASSES:
		if String(GameData.GEAR_CLASSES[gear_id]["title"]) == title:
			return gear_id
	return ""


func _is_equipment_item(item: Dictionary) -> bool:
	return not _gear_id_for_item(item).is_empty()


func _equipment_for_item(item: Dictionary) -> EquipmentData:
	var gear_id := _gear_id_for_item(item)
	if gear_id.is_empty():
		return null
	var equip := EquipmentData.make(gear_id, clampi(int(item.get("quality", GameData.Quality.COMMON)), 1, 5))
	equip.item_name = String(item.get("title", item.get("name", equip.item_name)))
	equip.cost = int(item.get("cost", item.get("baseCost", equip.cost)))
	return equip


func _slot_node_for_equipment(equip: EquipmentData) -> String:
	var slot := equip.slot()
	for node_name: String in EQUIP_SLOT_LABELS:
		var slot_name := EQUIP_SLOT_LABELS[node_name]
		if slot_name == String(GameData.SLOT_NAMES[slot]):
			return node_name
	return ""


func _equipment_description(item: Dictionary) -> String:
	var equip := _equipment_for_item(item)
	if equip == null:
		return ""
	return "%s\nКачество: %s\nСлот: %s\nСтоимость: %d монет\n%s" % [
		equip.item_name, equip.quality_name(), GameData.SLOT_NAMES[equip.slot()], equip.cost,
		equip.ability_description() if not equip.ability_description().is_empty() else "Особых свойств нет"]


func _equip_inventory_item(index: int) -> void:
	if index < 0 or index >= inventory.size():
		return
	var item: Dictionary = inventory[index]
	var equip := _equipment_for_item(item)
	if equip == null:
		return
	var slot_node := _slot_node_for_equipment(equip)
	if slot_node.is_empty():
		return
	if _server_connected and not String(item.get("id", "")).is_empty():
		var response := await _server_client.equip_item(String(item["id"]), slot_node)
		if not response.get("ok", false):
			add_log("[Экипировка] Не удалось надеть предмет.")
			return
		_apply_server_profile(response.get("data", {}))
		add_log("[Экипировка] Надет предмет «%s»." % equip.item_name)
		return
	var previous: Variant = _equipped_items.get(slot_node, null)
	if previous is Dictionary:
		inventory.append(previous.duplicate(true))
	inventory.remove_at(index)
	_equipped_items[slot_node] = item.duplicate(true)
	SaveDataS.save_game(players[0].gold, inventory)
	_refresh_equipment_slots()
	_refresh_inventory()
	add_log("[Экипировка] Надет предмет «%s»." % equip.item_name)


func _refresh_equipment_slots() -> void:
	for slot_node: String in EQUIP_SLOT_LABELS:
		var item: Variant = _equipped_items.get(slot_node, null)
		if item is Dictionary:
			var equip := _equipment_for_item(item)
			if equip != null:
				set_equipment_item(slot_node, equip)
				continue
		set_equipment(slot_node, "—")


func _setup_central_navigation() -> void:
	var navigation := PanelContainer.new()
	navigation.name = "CentralNavigation"
	var nav_row := HBoxContainer.new()
	navigation.add_child(nav_row)
	for view: Dictionary in [
		{"id": "castle", "title": "Замок"},
		{"id": "auction", "title": "Аукцион"},
		{"id": "market", "title": "Рынок"},
		{"id": "legendary", "title": "Легендарные"},
		{"id": "potions", "title": "Зелья"},
	]:
		var button := Button.new()
		button.text = String(view["title"])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_show_central_view.bind(String(view["id"])))
		nav_row.add_child(button)
	center_column.add_child(navigation)
	center_column.move_child(navigation, 0)

	_central_view_host = PanelContainer.new()
	_central_view_host.name = "CentralViewHost"
	_central_view_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.name = "ViewLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	_central_view_host.add_child(label)
	center_column.add_child(_central_view_host)
	_central_view_host.visible = false


func _show_central_view(view_id: String) -> void:
	_active_central_view = view_id
	var is_auction := view_id == "auction"
	round_info_panel.visible = is_auction
	field_hbox.visible = is_auction
	_central_view_host.visible = not is_auction
	if not is_auction:
		for child in _central_view_host.get_children():
			child.queue_free()
		var view_label := Label.new()
		view_label.name = "ViewLabel"
		view_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		view_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		view_label.add_theme_font_size_override("font_size", 28)
		_central_view_host.add_child(view_label)
		var titles := {
			"castle": "Замок\n\nЗдесь будут башни, улучшения и пассивный доход.",
			"market": "Рынок игроков\n\nЗдесь будут обычные объявления и легендарные аукционы.",
			"potions": "Башня зелий\n\nЗдесь будут рецепты и производство зелий.",
		}
		view_label.text = String(titles.get(view_id, "Раздел в разработке"))
		if view_id == "market":
			_load_market_view()
		elif view_id == "castle":
			_load_castle_view()
		elif view_id == "potions":
			_load_potions_view()
		elif view_id == "legendary":
			_load_legendary_view()


func _replace_central_box() -> VBoxContainer:
	for child in _central_view_host.get_children():
		child.queue_free()
	var box := VBoxContainer.new()
	_central_view_host.add_child(box)
	return box


func _load_castle_view() -> void:
	if not _server_connected:
		return
	var box := _replace_central_box()
	var title := Label.new()
	title.text = "Замок игрока"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	var status := Label.new()
	status.text = "Загрузка состояния башен..."
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status)
	var response: Dictionary = await _server_client.get_castle()
	if not is_instance_valid(status):
		return
	status.queue_free()
	if not response.get("ok", false):
		var failed := Label.new()
		failed.text = "Не удалось загрузить замок"
		box.add_child(failed)
		return
	var castle: Dictionary = response.get("data", {})
	var tower: Dictionary = castle.get("buildings", {}).get("coin_tower", {})
	var info := Label.new()
	info.text = "Башня монет — уровень %d\nНакоплено: %d монет\nДоход: %d монет/час" % [
		int(tower.get("level", 1)), int(tower.get("storedCoins", 0)), int(tower.get("level", 1)) * 100]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(info)
	var collect := Button.new()
	collect.text = "Забрать доход"
	collect.pressed.connect(_collect_castle_income)
	box.add_child(collect)
	var upgrade := Button.new()
	upgrade.text = "Улучшить башню"
	upgrade.pressed.connect(_upgrade_coin_tower)
	box.add_child(upgrade)


func _collect_castle_income() -> void:
	var result: Dictionary = await _server_client.collect_castle_income()
	if not result.get("ok", false):
		add_log("[Замок] Не удалось забрать доход.")
		return
	_apply_server_profile(result.get("data", {}).get("player", {}))
	add_log("[Замок] Доход забран.")
	_load_castle_view()


func _upgrade_coin_tower() -> void:
	var result: Dictionary = await _server_client.upgrade_coin_tower()
	if not result.get("ok", false):
		add_log("[Замок] Недостаточно монет для улучшения.")
		return
	_apply_server_profile(result.get("data", {}).get("player", {}))
	add_log("[Замок] Башня монет улучшена.")
	_load_castle_view()


func _load_potions_view() -> void:
	if not _server_connected:
		return
	var box := _replace_central_box()
	var title := Label.new()
	title.text = "Башня зелий"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	var description := Label.new()
	description.text = "Создание зелья через сервер"
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(description)
	var craft := Button.new()
	craft.text = "Создать зелье"
	craft.pressed.connect(_craft_potion)
	box.add_child(craft)


func _craft_potion() -> void:
	var result: Dictionary = await _server_client.craft_potion()
	if not result.get("ok", false):
		add_log("[Зелья] Не удалось создать зелье.")
		return
	add_log("[Зелья] Зелье создано и сохранено на сервере.")


func _load_market_view() -> void:
	if not _server_connected:
		return
	for child in _central_view_host.get_children():
		child.queue_free()
	var box := VBoxContainer.new()
	_central_view_host.add_child(box)
	var header := Label.new()
	header.text = "Рынок игроков"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 24)
	box.add_child(header)
	var status := Label.new()
	status.text = "Загрузка лотов..."
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status)
	var response: Dictionary = await _server_client.get_market_listings()
	if not is_instance_valid(status):
		return
	status.queue_free()
	if not response.get("ok", false):
		var failed := Label.new()
		failed.text = "Не удалось загрузить рынок"
		box.add_child(failed)
		return
	var listings: Array = response.get("data", {}).get("listings", [])
	if listings.is_empty():
		var empty := Label.new()
		empty.text = "Активных лотов пока нет"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(empty)
		return
	for listing: Dictionary in listings:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s — %d монет" % [listing.get("name", "Предмет"), int(listing.get("price", 0))]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var buy := Button.new()
		buy.text = "Купить"
		buy.pressed.connect(_buy_market_listing.bind(int(listing.get("id", 0))))
		row.add_child(buy)
		box.add_child(row)


func _buy_market_listing(listing_id: int) -> void:
	var result: Dictionary = await _server_client.buy_market_listing(listing_id)
	if not result.get("ok", false):
		add_log("[Рынок] Покупка недоступна.")
		return
	var profile: Dictionary = result.get("data", {}).get("player", {})
	_apply_server_profile(profile)
	add_log("[Рынок] Предмет куплен и добавлен в инвентарь.")
	_load_market_view()


func _load_legendary_view() -> void:
	if not _server_connected:
		return
	var box := _replace_central_box()
	var title := Label.new()
	title.text = "Легендарные аукционы"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	var response: Dictionary = await _server_client.get_legendary_auctions()
	if not response.get("ok", false):
		var failed := Label.new()
		failed.text = "Не удалось загрузить легендарные аукционы"
		box.add_child(failed)
		return
	var auctions: Array = response.get("data", {}).get("auctions", [])
	if auctions.is_empty():
		var empty := Label.new()
		empty.text = "Активных легендарных аукционов нет"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(empty)
		return
	for auction: Dictionary in auctions:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s — текущая ставка: %d" % [auction.get("name", "Предмет"), int(auction.get("currentPrice", 0))]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var amount := LineEdit.new()
		amount.custom_minimum_size = Vector2(90, 0)
		amount.text = str(int(auction.get("currentPrice", 0)) + 1000)
		row.add_child(amount)
		var bid := Button.new()
		bid.text = "Сделать ставку"
		bid.pressed.connect(_bid_legendary.bind(String(auction.get("id", "")), amount))
		row.add_child(bid)
		box.add_child(row)


func _bid_legendary(auction_id: String, amount_input: LineEdit) -> void:
	var result: Dictionary = await _server_client.bid_legendary_auction(auction_id, int(amount_input.text))
	if not result.get("ok", false):
		add_log("[Легендарный аукцион] Ставка отклонена.")
		return
	add_log("[Легендарный аукцион] Ставка принята.")
	_load_legendary_view()


func _refresh_inventory() -> void:
	if _inventory_list == null:
		return
	for child in _inventory_list.get_children():
		child.queue_free()
	_inventory_gold_label.text = "Монеты: %d" % players[0].gold
	if inventory.is_empty():
		var empty := Label.new()
		empty.text = "Пока пусто"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_inventory_list.add_child(empty)
		return
	for index: int in inventory.size():
		var item: Dictionary = inventory[index]
		var row := HBoxContainer.new()
		var label := Label.new()
		var is_gear := _is_equipment_item(item)
		label.text = "%s — %d%s" % [item.get("title", "Предмет"), int(item.get("cost", item.get("baseCost", 0))), " (снаряжение)" if is_gear else ""]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		row.tooltip_text = _equipment_description(item) if is_gear else "Предмет для продажи\nСтоимость: %d монет" % int(item.get("cost", item.get("baseCost", 0)))
		if is_gear:
			var equip_button := Button.new()
			equip_button.text = "Одеть"
			equip_button.tooltip_text = "Надеть предмет в слот: %s" % GameData.SLOT_NAMES[_equipment_for_item(item).slot()]
			equip_button.pressed.connect(_equip_inventory_item.bind(index))
			row.add_child(equip_button)
		var sell := Button.new()
		sell.text = "Продать %d" % SaveDataS.sell_price(item)
		sell.pressed.connect(_sell_inventory_item.bind(index))
		row.add_child(sell)
		if _server_connected and not String(item.get("id", "")).is_empty():
			var market_price := LineEdit.new()
			market_price.custom_minimum_size = Vector2(70, 0)
			market_price.text = str(maxi(int(item.get("cost", 1)), 1))
			market_price.placeholder_text = "Цена"
			row.add_child(market_price)
			var market_button := Button.new()
			market_button.text = "На рынок"
			market_button.pressed.connect(_list_inventory_item_on_server.bind(index, market_price))
			row.add_child(market_button)
		_inventory_list.add_child(row)


func _sell_inventory_item(index: int) -> void:
	if index < 0 or index >= inventory.size():
		return
	var item: Dictionary = inventory[index]
	if _server_connected and not String(item.get("id", "")).is_empty():
		_sell_inventory_item_on_server(index, String(item["id"]))
		return
	var price := SaveDataS.sell_price(item)
	players[0].gold += price
	inventory.remove_at(index)
	SaveDataS.save_game(players[0].gold, inventory)
	add_log("[Склад] Продан предмет «%s» за %d монет." % [item.get("title", "Предмет"), price])
	_update_player_labels()
	_refresh_tier_buttons()
	_refresh_inventory()


func _sell_inventory_item_on_server(index: int, instance_id: String) -> void:
	var result: Dictionary = await _server_client.sell_to_server(instance_id)
	if not result.get("ok", false):
		add_log("[Сервер] Не удалось продать предмет.")
		return
	var profile: Dictionary = result.get("data", {}).get("player", {})
	_apply_server_profile(profile)
	add_log("[Склад] Предмет продан через сервер.")


func _list_inventory_item_on_server(index: int, price_input: LineEdit) -> void:
	if index < 0 or index >= inventory.size():
		return
	var price := int(price_input.text)
	if price <= 0:
		add_log("[Рынок] Укажите положительную цену.")
		return
	var item_id := String(inventory[index].get("id", ""))
	var result: Dictionary = await _server_client.create_market_listing(item_id, price)
	if not result.get("ok", false):
		add_log("[Рынок] Не удалось выставить предмет.")
		return
	var profile: Dictionary = await _server_client.get_profile()
	_apply_server_profile(profile)
	add_log("[Рынок] Предмет выставлен на 24 часа.")
	if _active_central_view == "market":
		_load_market_view()


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
	game_field_panel.visible = true
	_show_central_view("auction")
	# Боты тоже вошли на это поле — их золото не ниже порога входа.
	for i: int in range(1, players.size()):
		players[i].gold = maxi(players[i].gold, min_gold)
	auction_field_name = String(info["title"])
	add_log("[Игра] Вы вошли на «%s» (вход от %d монет)." % [auction_field_name, min_gold])
	_place_tier_items(int(info["lot_count"]))
	_auction_settled = false
	_auction_finished = false
	_revealed_round_bids = {}
	_round_bids_visible = false
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
	var slot: HBoxContainer = equipment_list.get_node(NodePath(slot_node_name))
	var icon: TextureRect = slot.get_node(NodePath("Icon"))
	icon.texture = null
	var label: Label = slot.get_node(NodePath("Text"))
	label.text = "%s: %s" % [EQUIP_SLOT_LABELS[slot_node_name], item]
	label.modulate = Color.WHITE
	slot.tooltip_text = "Пустой слот: %s" % EQUIP_SLOT_LABELS[slot_node_name]


## Ставит предмет снаряжения в слот: иконка + название + цвет качества.
func set_equipment_item(slot_node_name: String, equip: EquipmentData) -> void:
	var slot: HBoxContainer = equipment_list.get_node(NodePath(slot_node_name))
	var icon: TextureRect = slot.get_node(NodePath("Icon"))
	var label: Label = slot.get_node(NodePath("Text"))
	icon.texture = equip.icon
	label.text = "%s: %s (%s)" % [
		EQUIP_SLOT_LABELS[slot_node_name], equip.item_name, equip.quality_name()]
	label.modulate = equip.quality_color()
	slot.tooltip_text = "%s\nКачество: %s\nСлот: %s\nСтоимость: %d монет\n%s" % [
		equip.item_name, equip.quality_name(), GameData.SLOT_NAMES[equip.slot()], equip.cost,
		equip.ability_description() if not equip.ability_description().is_empty() else "Особых свойств нет"]


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
		if col + item_size.x > GameFieldS.FIELD_COLS:
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
	w = clampi(w, 1, GameFieldS.FIELD_COLS)
	h = maxi(h, 1)
	col = clampi(col, 0, GameFieldS.FIELD_COLS - w)
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
	_round_finished = false
	game_field.reveal_for_round(_field_round)
	update_round_info_from_state(auction_field_name, _field_round)
	set_news("Раунд %d — смотрите на поле и делайте ставки!" % _field_round)
	start_round_timer()
	# Калькулятор помнит предыдущую ставку игрока: подставляем её в поле,
	# а ставки всех игроков на новый раунд обнуляются.
	var prev_bid: int = players[0].last_bid
	for p: PlayerDataS in players:
		p.last_bid = 0
		p.has_acted = false
	_prefill_calc(prev_bid)
	_update_player_labels()
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
	if _round_finished or _auction_finished:
		return
	_round_finished = true
	_reveal_round_bids()
	if _field_round >= 5:
		_round_timer.stop()
		_settle_auction()
		set_news("Аукцион завершён! Итоги подведены.")
		add_log("[Игра] Раунд 5 завершён — аукцион окончен!")
		_show_field_selection_in_game_area()
		return
	set_field_round(_field_round + 1)


func _reveal_round_bids() -> void:
	_revealed_round_bids = {}
	for p: PlayerDataS in players:
		_revealed_round_bids[p.id] = p.last_bid
	_round_bids_visible = true
	_update_player_labels()


func _settle_auction() -> void:
	if _auction_settled:
		return
	_auction_settled = true
	_auction_finished = true
	var winner := -1
	var winning_bid := 0
	for p: PlayerDataS in players:
		if p.last_bid > winning_bid:
			winner = p.id
			winning_bid = p.last_bid
	if winner != 1 or winning_bid <= 0:
		add_log("[Игра] Лот выиграл %s. Ваши предметы не изменились." % _player_name(winner))
		return
	players[0].gold = maxi(players[0].gold - winning_bid, 0)
	for item: Dictionary in field_items:
		inventory.append({
			"title": String(item.get("title", "Предмет")),
			"cost": int(item.get("cost", 0)),
			"size": "%dx%d" % [int(item.get("w", 1)), int(item.get("h", 1))],
		})
	SaveDataS.save_game(players[0].gold, inventory)
	add_log("[Победа] Вы выиграли %d предмет(ов)." % field_items.size())
	_update_player_labels()
	_refresh_inventory()


func _show_field_selection_in_game_area() -> void:
	_round_timer.stop()
	game_field_panel.visible = false
	main_hbox.visible = true
	if _tier_overlay.get_parent() != field_hbox:
		_tier_overlay.get_parent().remove_child(_tier_overlay)
		field_hbox.add_child(_tier_overlay)
	_tier_overlay.layout_mode = 2
	_tier_overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tier_overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tier_overlay.custom_minimum_size = Vector2.ZERO
	_tier_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tier_overlay.visible = true
	_refresh_tier_buttons()


func _player_name(player_id: int) -> String:
	for p: PlayerDataS in players:
		if p.id == player_id:
			return p.player_name
	return "никто"


## Все игроки поставили — новый раунд начинается, не дожидаясь таймера.
func _check_all_bid() -> void:
	for p: PlayerDataS in players:
		if not p.has_acted:
			return
	add_log("[Игра] Все игроки сделали ставки — начинается раунд %d!" % [
		_field_round + 1])
	_advance_round()


## Подставляет предыдущую ставку игрока в калькулятор.
func _prefill_calc(prev_bid: int) -> void:
	calc_expression = str(maxi(prev_bid, 0))
	_calc_prefilled = true
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
	human.gold = int(_save_state.get("gold", 1000))
	inventory.clear()
	for saved_item: Variant in _save_state.get("inventory", []):
		if saved_item is Dictionary:
			inventory.append(saved_item.duplicate(true))
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
		var avatar: PanelContainer = row.get_node(NodePath("Avatar"))
		var avatar_icon: TextureRect = avatar.get_node(NodePath("Icon"))
		avatar_icon.texture = load(players[i].avatar_path)
		var name_label: Label = row.get_node(NodePath("Info/NameLabel"))
		name_label.text = players[i].player_name
	_update_player_labels()


## Обновляет подписи текущих ставок рядом с иконками игроков
## (короткий текст — колонка игроков не расширяется и не толкает поле).
func _update_player_labels() -> void:
	for i: int in players.size():
		var row: HBoxContainer = players_column.get_node(NodePath("PlayerRow%d" % i))
		var bid_label: Label = row.get_node(NodePath("Info/BidLabel"))
		var avatar: PanelContainer = row.get_node(NodePath("Avatar"))
		var p: PlayerDataS = players[i]
		if _round_bids_visible:
			var previous_bid: int = int(_revealed_round_bids.get(p.id, 0))
			bid_label.text = "Ставка: %d" % previous_bid if previous_bid > 0 else "Пас"
		else:
			if p.last_bid > 0:
				bid_label.text = "Готов"
			else:
				bid_label.text = "Пас" if p.has_acted else "Ожидание"
		_set_bid_frame(avatar, p.last_bid > 0)
	calc_gold_label.text = "Ваше золото: %d" % players[0].gold


func _set_bid_frame(avatar: PanelContainer, active: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.18, 0.14, 1.0)
	style.border_width_left = 3 if active else 0
	style.border_width_top = 3 if active else 0
	style.border_width_right = 3 if active else 0
	style.border_width_bottom = 3 if active else 0
	style.border_color = Color(0.20, 0.95, 0.35, 1.0)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	avatar.add_theme_stylebox_override("panel", style)


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
		var delay: float = _bot_rng.randf_range(0.5, 5.0)
		get_tree().create_timer(delay).timeout.connect(_bot_place_bid.bind(p, _field_round))
	_update_player_labels()


## Ставка конкретного бота (если раунд к моменту тика не сменился).
func _bot_place_bid(bot: PlayerDataS, round_at_schedule: int) -> void:
	if _auction_finished or round_at_schedule != _field_round or bot.has_acted:
		return
	bot.last_bid = BotsControllerS.bot_bid(
			bot.last_estimate, _field_round, bot.gold, bot.aggression, _bot_rng)
	bot.has_acted = true
	if bot.last_bid > 0:
		add_log("[%s] сделал ставку." % bot.player_name)
	else:
		add_log("[%s] пасует в этом раунде" % bot.player_name)
	_update_player_labels()
	if _check_early_victory(bot.id):
		return
	_check_all_bid()


func _check_early_victory(player_id: int) -> bool:
	if _auction_finished or _field_round < 1 or _field_round > ROUND_PROTECTION.size():
		return false
	var player_bid := 0
	var highest_other := 0
	for p: PlayerDataS in players:
		if p.id == player_id:
			player_bid = p.last_bid
		elif p.last_bid > highest_other:
			highest_other = p.last_bid
	if player_bid <= 0 or highest_other <= 0:
		return false
	var threshold := int(ceil(float(highest_other) * ROUND_PROTECTION[_field_round - 1]))
	if player_bid <= threshold:
		return false
	_round_finished = true
	_reveal_round_bids()
	_round_timer.stop()
	_auction_finished = true
	set_news("Досрочная победа — ставка превысила защитный порог!")
	add_log("[Игра] %s досрочно выиграл аукцион." % _player_name(player_id))
	_settle_auction()
	_show_field_selection_in_game_area()
	return true


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
			_calc_prefilled = false
			calc_display.text = "0"
		"=":
			_calc_evaluate()
		_:
			if _calc_prefilled:
				calc_expression = ""
				_calc_prefilled = false
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
	if _auction_finished:
		add_log("[Игра] Аукцион уже завершён")
		return
	if player.last_bid > 0:
		add_log("[Игра] Вы уже сделали ставку в этом раунде")
		return
	var value := _calc_result()
	if value < 0:
		add_log("[Игра] Введите ставку или оставьте 0 для паса")
		return
	if value == 0:
		player.last_bid = 0
		player.has_acted = true
		add_log("[Вы] пас в этом раунде")
		_update_player_labels()
		_check_all_bid()
		return
	var amount: int = clampi(value, 1, player.gold)
	if amount < value:
		add_log("[Игра] Ставка ограничена доступным балансом.")
	player.last_bid = amount
	player.has_acted = true
	add_log("[Вы] сделал ставку.")
	_update_player_labels()
	if _check_early_victory(player.id):
		return
	_check_all_bid()

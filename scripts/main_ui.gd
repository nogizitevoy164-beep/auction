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
const POLICY_VERSIONS: Dictionary = {"terms": "1.0", "privacy": "1.0", "rules": "1.0", "age": "1.0"}

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
var _role_locked: bool = false
var _equipped_items: Dictionary = {}
var _field_rules: Dictionary = {"registeredPlayers": 1, "legendaryCounts": {}}
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
var _auction_result_label: Label
var _sell_simple_after_win_button: Button
var _last_auction_summary: String = ""
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
var _account_form_host: VBoxContainer
var _active_central_view: String = "auction"
var _server_client: Node
var _server_connected: bool = false
var _server_player_id: int = 0
var _matchmaking_timer: Timer
var _matchmaking_tier: int = -1
var _matchmaking_status_label: Label
var _matchmaking_active: bool = false
var _online_room_id: String = ""
var _online_sync_timer: Timer
var _online_last_round: int = -1

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
	_matchmaking_timer = Timer.new()
	_matchmaking_timer.wait_time = 2.0
	_matchmaking_timer.one_shot = false
	_matchmaking_timer.timeout.connect(_poll_matchmaking)
	add_child(_matchmaking_timer)
	_online_sync_timer = Timer.new()
	_online_sync_timer.wait_time = 1.0
	_online_sync_timer.one_shot = false
	_online_sync_timer.timeout.connect(_poll_online_room)
	add_child(_online_sync_timer)
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
	_server_player_id = int(profile.get("id", _server_player_id))
	players[0].gold = maxi(int(profile.get("coins", players[0].gold)), 0)
	if profile.has("fieldRules") and profile["fieldRules"] is Dictionary:
		_field_rules = profile["fieldRules"]
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
			elif item["state"] == "inventory":
				inventory.append(item)
	SaveDataS.save_game(players[0].gold, inventory)
	_update_player_labels()
	_refresh_tier_buttons()
	if calc_gold_label != null:
		calc_gold_label.text = "Ваше золото: %d" % players[0].gold
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
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	var inventory_scroll := ScrollContainer.new()
	inventory_scroll.name = "InventoryScroll"
	inventory_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(inventory_scroll)
	_inventory_list = VBoxContainer.new()
	_inventory_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_scroll.add_child(_inventory_list)
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
	if _role_locked or not ROLE_DATA.has(role_id):
		return
	_selected_role = role_id
	for button: Button in _role_selector.get_children():
		button.button_pressed = button.text == String(ROLE_DATA[role_id]["title"])
	_update_role_portrait()
	add_log("[Персонаж] Выбрана роль: %s." % ROLE_DATA[role_id]["title"])


func _set_role_locked(locked: bool) -> void:
	_role_locked = locked
	if _role_selector == null:
		return
	for button: Button in _role_selector.get_children():
		button.disabled = locked


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
		var slot_name: String = String(EQUIP_SLOT_LABELS[node_name])
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
		var response: Dictionary = await _server_client.equip_item(String(item["id"]), slot_node)
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
		{"id": "catalog", "title": "Каталог"},
		{"id": "account", "title": "Аккаунт"},
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
		elif view_id == "catalog":
			_load_catalog_view()
		elif view_id == "account":
			_load_account_view()


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
	var definitions: Dictionary = castle.get("towerDefinitions", {})
	var coin_definition: Dictionary = definitions.get("coin_tower", {})
	var info := Label.new()
	var coin_level := int(tower.get("level", 1))
	var coin_cost := int(coin_definition.get("upgradeCosts", [])[mini(coin_level - 1, 3)]) if coin_level < int(coin_definition.get("maxLevel", 5)) else 0
	info.text = "%s — уровень %d/%d\n%s\nНакоплено: %d монет\nДоход: %d монет/час\nУлучшение: %d монет" % [
		String(coin_definition.get("title", "Башня монет")), coin_level, int(coin_definition.get("maxLevel", 5)), String(coin_definition.get("description", "")), int(tower.get("storedCoins", 0)), int(coin_definition.get("incomePerHour", [100])[mini(coin_level - 1, 4)]), coin_cost]
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
	var alchemy: Dictionary = castle.get("buildings", {}).get("alchemy_tower", {})
	var alchemy_definition: Dictionary = definitions.get("alchemy_tower", {})
	var alchemy_level := int(alchemy.get("level", 1))
	var alchemy_cost := int(alchemy_definition.get("upgradeCosts", [])[mini(alchemy_level - 1, 3)]) if alchemy_level < int(alchemy_definition.get("maxLevel", 5)) else 0
	var alchemy_info := Label.new()
	alchemy_info.text = "%s — уровень %d/%d\n%s\nДоступно качество зелий: %d\nУлучшение: %d монет" % [
		String(alchemy_definition.get("title", "Башня алхимии")), alchemy_level, int(alchemy_definition.get("maxLevel", 5)), String(alchemy_definition.get("description", "")), alchemy_level, alchemy_cost]
	alchemy_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	alchemy_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(alchemy_info)
	var upgrade_alchemy := Button.new()
	upgrade_alchemy.text = "Улучшить башню алхимии"
	upgrade_alchemy.disabled = alchemy_level >= int(alchemy_definition.get("maxLevel", 5))
	upgrade_alchemy.pressed.connect(_upgrade_alchemy_tower)
	box.add_child(upgrade_alchemy)


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


func _upgrade_alchemy_tower() -> void:
	var result: Dictionary = await _server_client.upgrade_alchemy_tower()
	if not result.get("ok", false):
		add_log("[Замок] Не удалось улучшить башню алхимии.")
		return
	_apply_server_profile(result.get("data", {}).get("player", {}))
	add_log("[Замок] Башня алхимии улучшена.")
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
	description.text = "Зелье откровения открывает информацию об одном предмете на игровом поле. Для создания нужен ингредиент из инвентаря."
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
		var listing_id := int(listing.get("id", 0))
		if int(listing.get("sellerId", 0)) == _server_player_id:
			var cancel := Button.new()
			cancel.text = "Снять с продажи"
			cancel.pressed.connect(_cancel_market_listing.bind(listing_id))
			row.add_child(cancel)
		else:
			var buy := Button.new()
			buy.text = "Купить"
			buy.pressed.connect(_buy_market_listing.bind(listing_id))
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


func _cancel_market_listing(listing_id: int) -> void:
	var result: Dictionary = await _server_client.cancel_market_listing(listing_id)
	if not result.get("ok", false):
		var error_data: Dictionary = result.get("data", {})
		add_log("[Рынок] Не удалось снять лот: %s" % String(error_data.get("error", "сервер отклонил запрос")))
		return
	_apply_server_profile(result.get("data", {}).get("player", {}))
	add_log("[Рынок] Лот снят с продажи, предмет возвращён в инвентарь.")
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


func _load_catalog_view() -> void:
	var box := _replace_central_box()
	var title := Label.new()
	title.text = "Каталог предметов"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	var status := Label.new()
	status.text = "Загрузка каталога..."
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status)
	var items: Array = _local_catalog_items()
	if _server_connected:
		var response: Dictionary = await _server_client.get_catalog_items()
		if response.get("ok", false):
			items = _merge_catalog_items(items, response.get("data", {}).get("items", []))
	if not is_instance_valid(status):
		return
	status.queue_free()
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	for item: Variant in items:
		if item is Dictionary:
			grid.add_child(_catalog_card(item))


func _local_catalog_items() -> Array:
	var result: Array = []
	for item_id: String in GameData.SELLABLE_ITEMS:
		var item: Dictionary = GameData.SELLABLE_ITEMS[item_id].duplicate(true)
		item["id"] = item_id
		item["type"] = "sellable"
		item["rarity"] = int(item.get("quality", 1))
		item["baseCost"] = int(item.get("cost", 0))
		result.append(item)
	for gear_id: String in GameData.GEAR_CLASSES:
		for quality: int in range(1, 6):
			var gear: Dictionary = GameData.GEAR_CLASSES[gear_id].duplicate(true)
			var equip: EquipmentData = EquipmentData.make(gear_id, quality)
			gear["id"] = "%s_q%d" % [gear_id, quality]
			gear["baseId"] = gear_id
			gear["type"] = "equipment"
			gear["quality"] = quality
			gear["rarity"] = quality
			gear["baseCost"] = int(gear.get("base_cost", 0))
			gear["iconPath"] = String(gear.get("icon_path", ""))
			gear["description"] = equip.ability_description()
			gear["properties"] = "Слот: %s" % GameData.SLOT_NAMES[equip.slot()]
			result.append(gear)
	for ingredient_id: String in GameData.ALCHEMY_INGREDIENTS:
		var ingredient: Dictionary = GameData.ALCHEMY_INGREDIENTS[ingredient_id].duplicate(true)
		ingredient["id"] = ingredient_id
		ingredient["type"] = "ingredient"
		ingredient["baseCost"] = int(ingredient.get("cost", 0))
		ingredient["description"] = "Ингредиент для Башни алхимии."
		result.append(ingredient)
	return result


func _merge_catalog_items(local_items: Array, server_items: Variant) -> Array:
	var merged: Array = local_items.duplicate(true)
	var indexes: Dictionary = {}
	for index: int in merged.size():
		indexes[String(merged[index].get("id", ""))] = index
	if server_items is Array:
		for server_item: Variant in server_items:
			if not server_item is Dictionary:
				continue
			var server_id := String(server_item.get("id", ""))
			# Серверные базовые записи экипировки заменяются локальными
			# вариантами q1..q5, чтобы в каталоге были все качества.
			if GameData.GEAR_CLASSES.has(server_id):
				continue
			if indexes.has(server_id):
				merged[int(indexes[server_id])] = server_item
			else:
				indexes[server_id] = merged.size()
				merged.append(server_item)
	return merged


func _catalog_card(item: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 108)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var quality := clampi(int(item.get("quality", item.get("rarity", 1))), 1, 5)
	var quality_color: Color = GameData.QUALITY_COLORS[quality]
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.10, 0.09, 0.14, 0.96)
	card_style.border_width_left = 2
	card_style.border_width_top = 2
	card_style.border_width_right = 2
	card_style.border_width_bottom = 2
	card_style.border_color = quality_color
	var shadow_color := quality_color
	shadow_color.a = 0.72
	card_style.shadow_color = shadow_color
	card_style.shadow_size = 6
	card.add_theme_stylebox_override("panel", card_style)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 5)
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	margin.add_child(row)
	var icon := _catalog_icon(item)
	row.add_child(icon)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var name_label := Label.new()
	name_label.text = String(item.get("name", item.get("title", "Предмет")))
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(name_label)
	var meta := Label.new()
	meta.text = "%s • %s • %d монет" % [
		String(item.get("type", "предмет")), _catalog_rarity_name(quality),
		int(item.get("baseCost", item.get("cost", 0)))]
	meta.add_theme_font_size_override("font_size", 11)
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(meta)
	var size_label := Label.new()
	size_label.text = _catalog_size_text(item)
	size_label.add_theme_font_size_override("font_size", 11)
	info.add_child(size_label)
	var properties_text := _catalog_properties(item)
	if not properties_text.is_empty():
		var properties := Label.new()
		properties.text = properties_text
		properties.add_theme_font_size_override("font_size", 11)
		properties.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(properties)
	var description_text := String(item.get("description", "")).strip_edges()
	if not description_text.is_empty():
		var description := Label.new()
		description.text = description_text
		description.add_theme_font_size_override("font_size", 11)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(description)
	return card


func _catalog_rarity_name(value: int) -> String:
	var names: Array[String] = ["", "Обычное", "Необычное", "Редкое", "Эпическое", "Легендарное"]
	return names[clampi(value, 1, 5)]


func _catalog_properties(item: Dictionary) -> String:
	var properties: Variant = item.get("properties", "")
	if properties is Dictionary or properties is Array:
		return JSON.stringify(properties)
	if not String(properties).is_empty():
		return String(properties)
	var weapon_kind := String(item.get("weaponKind", ""))
	return "Оружие: %s" % weapon_kind if not weapon_kind.is_empty() else ""


func _catalog_size_text(item: Dictionary) -> String:
	var size_value: Variant = item.get("size", null)
	var width := int(item.get("sizeX", item.get("width", 0)))
	var height := int(item.get("sizeY", item.get("height", 0)))
	if size_value is Vector2i:
		width = size_value.x
		height = size_value.y
	elif size_value is Dictionary:
		width = int(size_value.get("x", size_value.get("width", width)))
		height = int(size_value.get("y", size_value.get("height", height)))
	var item_id := String(item.get("baseId", item.get("id", "")))
	if width <= 0 or height <= 0:
		if GameData.SELLABLE_ITEMS.has(item_id):
			var sellable_size: Vector2i = GameData.SELLABLE_ITEMS[item_id]["size"]
			width = sellable_size.x
			height = sellable_size.y
		elif GameData.GEAR_CLASSES.has(item_id):
			var gear_size: Vector2i = GameData.GEAR_CLASSES[item_id]["size"]
			width = gear_size.x
			height = gear_size.y
	if width <= 0 or height <= 0:
		width = 1
		height = 1
	return "Размер: %d×%d клетки" % [width, height]


func _catalog_icon(item: Dictionary) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(38, 38)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var icon_value := String(item.get("icon", item.get("iconPath", "")))
	if icon_value.begins_with("res://"):
		icon.texture = load(icon_value)
	elif icon_value.begins_with("data:image/"):
		var parts := icon_value.split(",", false, 1)
		if parts.size() == 2:
			var image := Image.new()
			var raw := Marshalls.base64_to_raw(parts[1])
			var loaded: Error = image.load_from_buffer(raw)
			if loaded == OK:
				icon.texture = ImageTexture.create_from_image(image)
	return icon


func _load_account_view() -> void:
	var box := _replace_central_box()
	var title := Label.new()
	title.text = "Аккаунт"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	var switcher := HBoxContainer.new()
	switcher.alignment = BoxContainer.ALIGNMENT_CENTER
	var login_button := Button.new()
	login_button.text = "Войти"
	login_button.pressed.connect(_render_account_form.bind(false))
	switcher.add_child(login_button)
	var register_button := Button.new()
	register_button.text = "Регистрация"
	register_button.pressed.connect(_render_account_form.bind(true))
	switcher.add_child(register_button)
	box.add_child(switcher)
	_account_form_host = VBoxContainer.new()
	_account_form_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_account_form_host)
	_render_account_form(false)


func _render_account_form(register_mode: bool) -> void:
	if _account_form_host == null:
		return
	for child in _account_form_host.get_children():
		child.queue_free()
	var current := Label.new()
	current.text = "Текущий аккаунт: %s" % String(players[0].player_name) if players.size() > 0 else ""
	current.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_account_form_host.add_child(current)
	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_account_form_host.add_child(status)
	var login_input := LineEdit.new()
	login_input.placeholder_text = "Логин или email"
	_account_form_host.add_child(login_input)
	var email_input: LineEdit
	var display_input: LineEdit
	if register_mode:
		email_input = LineEdit.new()
		email_input.placeholder_text = "Email"
		_account_form_host.add_child(email_input)
		display_input = LineEdit.new()
		display_input.placeholder_text = "Имя игрока"
		_account_form_host.add_child(display_input)
	var password_input := LineEdit.new()
	password_input.placeholder_text = "Пароль (минимум 8 символов)"
	password_input.secret = true
	_account_form_host.add_child(password_input)
	if register_mode:
		var age := CheckButton.new()
		age.text = "Мне есть 13 лет"
		_account_form_host.add_child(age)
		var terms := CheckButton.new()
		terms.text = "Принимаю Пользовательское соглашение v1.0"
		_account_form_host.add_child(terms)
		var privacy := CheckButton.new()
		privacy.text = "Принимаю Политику конфиденциальности v1.0"
		_account_form_host.add_child(privacy)
		var rules := CheckButton.new()
		rules.text = "Принимаю Правила игры v1.0"
		_account_form_host.add_child(rules)
		var note := Label.new()
		note.text = "Регистрация нужна для сохранения прогресса и доступа к рынку. Роль выбирается перед входом на поле."
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_account_form_host.add_child(note)
		var submit := Button.new()
		submit.text = "Зарегистрироваться"
		submit.pressed.connect(_submit_registration.bind(login_input, email_input, display_input, password_input, age, terms, privacy, rules, status))
		_account_form_host.add_child(submit)
	else:
		var submit_login := Button.new()
		submit_login.text = "Войти"
		submit_login.pressed.connect(_submit_login.bind(login_input, password_input, status))
		_account_form_host.add_child(submit_login)


func _submit_login(login_input: LineEdit, password_input: LineEdit, status: Label) -> void:
	status.text = "Выполняется вход..."
	var result: Dictionary = await _server_client.login_account(login_input.text.strip_edges(), password_input.text)
	if not result.get("ok", false):
		status.text = String(result.get("data", {}).get("error", "Не удалось войти"))
		return
	_apply_server_profile(result.get("data", {}))
	status.text = "Вход выполнен. Прогресс сохранён на сервере."
	add_log("[Аккаунт] Выполнен вход: %s." % login_input.text.strip_edges())


func _submit_registration(login_input: LineEdit, email_input: LineEdit, display_input: LineEdit,
		password_input: LineEdit, age: CheckButton, terms: CheckButton, privacy: CheckButton,
		rules: CheckButton, status: Label) -> void:
	status.text = "Выполняется регистрация..."
	var acceptances := {"terms": POLICY_VERSIONS["terms"], "privacy": POLICY_VERSIONS["privacy"], "rules": POLICY_VERSIONS["rules"], "age": POLICY_VERSIONS["age"]}
	if not age.button_pressed or not terms.button_pressed or not privacy.button_pressed or not rules.button_pressed:
		status.text = "Подтвердите возраст и принятие всех обязательных политик."
		return
	var result: Dictionary = await _server_client.register_account(
		login_input.text.strip_edges(), email_input.text.strip_edges(), display_input.text.strip_edges(),
		password_input.text, age.button_pressed, acceptances)
	if not result.get("ok", false):
		status.text = String(result.get("data", {}).get("error", "Не удалось зарегистрироваться"))
		return
	_apply_server_profile(result.get("data", {}))
	status.text = "Регистрация выполнена. Email пока не подтверждён."
	add_log("[Аккаунт] Регистрация завершена. Роль выбирается перед входом на поле.")


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
		var row := VBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 2)
		var label := Label.new()
		var is_gear := _is_equipment_item(item)
		label.text = "%s — %d%s" % [item.get("title", "Предмет"), int(item.get("cost", item.get("baseCost", 0))), " (снаряжение)" if is_gear else ""]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		row.tooltip_text = _equipment_description(item) if is_gear else "Предмет для продажи\nСтоимость: %d монет" % int(item.get("cost", item.get("baseCost", 0)))
		var actions := HBoxContainer.new()
		actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_theme_constant_override("separation", 3)
		row.add_child(actions)
		if is_gear:
			var equip_button := Button.new()
			equip_button.text = "Одеть"
			equip_button.tooltip_text = "Надеть предмет в слот: %s" % GameData.SLOT_NAMES[_equipment_for_item(item).slot()]
			equip_button.pressed.connect(_equip_inventory_item.bind(index))
			actions.add_child(equip_button)
		var sell := Button.new()
		sell.text = "Продать %d" % SaveDataS.sell_price(item)
		sell.pressed.connect(_sell_inventory_item.bind(index))
		actions.add_child(sell)
		if _server_connected and _is_market_item(item) and not String(item.get("id", "")).is_empty():
			var market_price := LineEdit.new()
			market_price.custom_minimum_size = Vector2(58, 0)
			market_price.text = str(maxi(int(item.get("cost", 1)), 1))
			market_price.placeholder_text = "Цена"
			actions.add_child(market_price)
			var market_button := Button.new()
			market_button.text = "Рынок"
			market_button.pressed.connect(_list_inventory_item_on_server.bind(index, market_price))
			actions.add_child(market_button)
		_inventory_list.add_child(row)


func _is_market_item(item: Dictionary) -> bool:
	if not String(item.get("gear_class_id", item.get("gearClassId", ""))).is_empty():
		return true
	var item_type := String(item.get("type", "")).to_lower()
	return item_type in ["equipment", "weapon", "potion"]


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
	if item_id.is_empty():
		add_log("[Рынок] Предмет ещё синхронизируется с сервером. Повторите через секунду.")
		return
	var item_title := String(inventory[index].get("title", "Предмет"))
	var result: Dictionary = await _server_client.create_market_listing(item_id, price)
	if not result.get("ok", false):
		var error_data: Dictionary = result.get("data", {})
		add_log("[Рынок] Не удалось выставить предмет: %s" % String(error_data.get("error", "сервер отклонил запрос")))
		return
	var profile: Dictionary = await _server_client.get_profile()
	_apply_server_profile(profile)
	add_log("[Рынок] Предмет «%s» выставлен на 24 часа за %d монет." % [
		item_title, price])
	if _active_central_view == "market":
		_load_market_view()


# ============================================================
#  ВЫБОР ИГРОВОГО ПОЛЯ (начальный / средний / элитный)
# ============================================================
## В начале игры в центральной области вместо игрового поля показывается экран выбора:
## три поля с порогом входа по золоту (1000 / 10 000 / 100 000).
func _setup_field_selection() -> void:
	_tier_overlay = PanelContainer.new()
	_tier_overlay.name = "TierSelection"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.08, 0.12)
	_tier_overlay.add_theme_stylebox_override("panel", sb)
	_tier_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_field.add_child(_tier_overlay)
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
	_auction_result_label = Label.new()
	_auction_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_auction_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_auction_result_label.visible = false
	vbox.add_child(_auction_result_label)
	_sell_simple_after_win_button = Button.new()
	_sell_simple_after_win_button.text = "Продать все простые предметы"
	_sell_simple_after_win_button.visible = false
	_sell_simple_after_win_button.pressed.connect(_sell_all_simple_after_win)
	vbox.add_child(_sell_simple_after_win_button)
	_tier_gold_label = Label.new()
	_tier_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_tier_gold_label)
	for tier: int in [GameData.FieldTier.STARTER, GameData.FieldTier.MID, GameData.FieldTier.ELITE]:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(420, 68)
		btn.pressed.connect(_on_tier_selected.bind(tier))
		vbox.add_child(btn)
		_tier_buttons[tier] = btn
	_refresh_tier_buttons()
	main_hbox.visible = true
	round_info_panel.visible = true
	field_hbox.visible = true
	game_field_panel.visible = true
	_show_central_view("auction")


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
	_set_role_locked(true)
	_tier_overlay.visible = false
	main_hbox.visible = true
	game_field.visible = true
	game_field_panel.visible = true
	_matchmaking_tier = tier
	_matchmaking_active = true
	_show_matchmaking_view(info)


func _show_matchmaking_view(info: Dictionary) -> void:
	_round_timer.stop()
	round_info_panel.visible = false
	field_hbox.visible = false
	_central_view_host.visible = true
	var box := _replace_central_box()
	var title := Label.new()
	title.text = "Поиск игроков"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	var field_label := Label.new()
	field_label.text = String(info.get("title", "Аукцион"))
	field_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(field_label)
	_matchmaking_status_label = Label.new()
	_matchmaking_status_label.text = "Подключение к очереди игроков..."
	_matchmaking_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_matchmaking_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_matchmaking_status_label)
	var skip := Button.new()
	skip.text = "Начать с ботами"
	skip.custom_minimum_size = Vector2(300, 52)
	skip.pressed.connect(_skip_matchmaking)
	box.add_child(skip)
	var hint := Label.new()
	hint.text = "Ожидайте игроков или пропустите поиск — свободные места займут боты."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	if _server_connected:
		var result: Dictionary = await _server_client.join_matchmaking(_matchmaking_tier)
		if not _matchmaking_active:
			return
		if result.get("ok", false):
			_update_matchmaking_status(result.get("data", {}))
			if String(result.get("data", {}).get("status", "")) == "started":
				_online_room_id = String(result.get("data", {}).get("roomId", ""))
				_start_auction_after_matchmaking()
				return
		else:
			_matchmaking_status_label.text = "Не удалось войти в очередь. Можно начать с ботами."
		_matchmaking_timer.start()
	else:
		_matchmaking_status_label.text = "Сервер недоступен — можно продолжить локально с ботами."


func _update_matchmaking_status(data: Dictionary) -> void:
	if _matchmaking_status_label == null:
		return
	var waiting := int(data.get("waitingPlayers", data.get("humanPlayers", 1)))
	var capacity := int(data.get("capacity", 4))
	_matchmaking_status_label.text = "Готовы к игре: %d из %d\nДругие игроки могут присоединиться к этому полю." % [waiting, capacity]


func _poll_matchmaking() -> void:
	if not _matchmaking_active or not _server_connected:
		return
	var result: Dictionary = await _server_client.get_matchmaking_status(_matchmaking_tier)
	if not _matchmaking_active or not result.get("ok", false):
		return
	var data: Dictionary = result.get("data", {})
	_update_matchmaking_status(data)
	if bool(data.get("ready", false)) or String(data.get("status", "")) == "started":
		_online_room_id = String(data.get("roomId", ""))
		_start_auction_after_matchmaking()


func _skip_matchmaking() -> void:
	if not _matchmaking_active:
		return
	if _server_connected:
		var result: Dictionary = await _server_client.skip_matchmaking(_matchmaking_tier)
		if result.get("ok", false):
			var data: Dictionary = result.get("data", {})
			_online_room_id = String(data.get("roomId", ""))
			add_log("[Игра] Поиск пропущен: игроков %d, ботов %d." % [int(data.get("humanPlayers", 1)), int(data.get("bots", 3))])
		else:
			add_log("[Игра] Поиск пропущен, свободные места займут боты.")
	_start_auction_after_matchmaking()


func _start_auction_after_matchmaking() -> void:
	if not _matchmaking_active:
		return
	_matchmaking_active = false
	_matchmaking_timer.stop()
	if not _online_room_id.is_empty() and _server_connected:
		_start_online_auction()
		return
	var info: Dictionary = GameData.FIELD_TIERS[_matchmaking_tier]
	_show_central_view("auction")
	_round_timer.stop()
	auction_field_name = String(info["title"])
	add_log("[Игра] Вы вошли на «%s» (вход от %d монет)." % [auction_field_name, int(info["min_gold"])])
	_place_tier_items(int(info["lot_count"]))
	_auction_settled = false
	_auction_finished = false
	_revealed_round_bids = {}
	_round_bids_visible = false
	set_field_round(1)
	add_log("[Игра] Раунд 1: местоположение предметов скрыто...")
	add_log("[Игра] Стартовое золото: %d" % players[0].gold)
	_update_player_labels()


func _start_online_auction() -> void:
	var response: Dictionary = await _server_client.get_auction_room(_online_room_id)
	if not response.get("ok", false):
		_online_room_id = ""
		add_log("[Игра] Общая комната недоступна — запускается локальный режим.")
		_start_auction_after_matchmaking()
		return
	var snapshot: Dictionary = response.get("data", {})
	var info: Dictionary = GameData.FIELD_TIERS[_matchmaking_tier]
	_show_central_view("auction")
	round_info_panel.visible = true
	field_hbox.visible = true
	game_field.visible = true
	game_field_panel.visible = true
	auction_field_name = String(info["title"])
	_place_tier_items(int(info["lot_count"]), int(snapshot.get("fieldSeed", 0)))
	_auction_settled = false
	_auction_finished = false
	_online_last_round = -1
	_apply_online_room_snapshot(snapshot)
	if not _online_room_id.is_empty():
		_round_timer.start()
		_online_sync_timer.start()
	add_log("[Игра] Вы подключены к общей онлайн-комнате.")


func _poll_online_room() -> void:
	if _online_room_id.is_empty() or not _server_connected:
		return
	var response: Dictionary = await _server_client.get_auction_room(_online_room_id)
	if response.get("ok", false):
		_apply_online_room_snapshot(response.get("data", {}))


func _apply_online_room_snapshot(snapshot: Dictionary) -> void:
	var remote_players: Array = snapshot.get("players", [])
	if remote_players.is_empty():
		return
	var previous_local := players[0] if not players.is_empty() else null
	var rebuilt: Array[PlayerDataS] = []
	var ordered: Array = remote_players.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("id", 0)) == _server_player_id
	)
	for entry: Dictionary in ordered:
		var p := PlayerDataS.new()
		p.id = int(entry.get("id", 0))
		p.player_name = "Вы" if p.id == _server_player_id else String(entry.get("displayName", "Игрок"))
		p.is_bot = bool(entry.get("isBot", false))
		p.gold = int(entry.get("coins", 0))
		p.avatar_path = "res://icons/player_1.svg" if p.id == _server_player_id else "res://icons/player_%d.svg" % (mini(rebuilt.size() + 2, 4))
		p.has_acted = bool(entry.get("hasActed", false))
		p.last_bid = int(entry.get("bid", 0))
		rebuilt.append(p)
	players = rebuilt
	_field_round = clampi(int(snapshot.get("round", 1)), 1, 5)
	var previous_bids: Dictionary = snapshot.get("previousBids", {})
	_revealed_round_bids = {}
	for key: Variant in previous_bids:
		_revealed_round_bids[int(key)] = int(previous_bids[key])
	_round_bids_visible = String(snapshot.get("status", "active")) == "finished" or not previous_bids.is_empty()
	if _online_last_round != _field_round:
		var previous_local_bid := int(previous_bids.get(str(_server_player_id), 0))
		_prefill_calc(previous_local_bid)
		_online_last_round = _field_round
	update_round_info_from_state(auction_field_name, _field_round)
	if game_field.current_round != _field_round:
		game_field.reveal_for_round(_field_round, int(snapshot.get("fieldSeed", -1)) if not _online_room_id.is_empty() else -1)
	var remaining := maxi(int((int(snapshot.get("roundEndsAt", 0)) - int(snapshot.get("serverNow", Time.get_unix_time_from_system() * 1000))) / 1000), 0)
	round_time_left = remaining
	_update_round_timer_label()
	_update_player_labels()
	if String(snapshot.get("status", "active")) == "finished":
		_online_sync_timer.stop()
		_auction_finished = true
		if not _auction_settled:
			_settle_auction()
		_show_field_selection_in_game_area()
		_online_room_id = ""


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


## Набирает случайные предметы из каталога продажи и редкое снаряжение
## по шансам текущего поля и раскладывает
## их по верхним рядам поля «полками» — без наложений,
## цвет клетки = цвет качества.
## Шанс предмета = chance_starter / chance_mid / chance_elite
## (колонки CSV res://data/magic_auction_items.csv).
func _place_tier_items(count: int, field_seed: int = -1) -> void:
	field_items.clear()
	if field_seed >= 0:
		_item_rng.seed = field_seed
	else:
		_item_rng.randomize()
	# Колонка шансов выбранного поля (по умолчанию — начальное).
	var chance_key: String = "chance_starter"
	if current_tier >= 0:
		chance_key = String(GameData.FIELD_TIERS[current_tier]["chance_key"])
	# Взвешенный выбор без повторений: снаряжение имеет отдельный
	# очень низкий вес, а легендарные экземпляры дополнительно
	# зависят от числа игроков и уже выпавших копий.
	var pool: Array[Dictionary] = []
	for item_id: String in GameData.SELLABLE_ITEMS:
		var item: Dictionary = GameData.SELLABLE_ITEMS[item_id].duplicate(true)
		pool.append({"id": item_id, "item": item, "weight": float(item.get(chance_key, 0.0))})
	for gear_id: String in GameData.GEAR_CLASSES:
		for quality: int in range(1, 6):
			var gear_item := _make_field_gear_item(gear_id, quality)
			pool.append({
				"id": "%s_q%d" % [gear_id, quality],
				"item": gear_item,
				"weight": _gear_field_weight(gear_id, quality),
			})
	for ingredient_id: String in GameData.ALCHEMY_INGREDIENTS:
		var ingredient: Dictionary = GameData.ALCHEMY_INGREDIENTS[ingredient_id].duplicate(true)
		pool.append({"id": ingredient_id, "item": _make_field_ingredient_item(ingredient), "weight": float(ingredient.get(chance_key, 0.0))})
	var picked: Array[Dictionary] = []
	for i: int in mini(count, pool.size()):
		var total_weight := 0.0
		for candidate: Dictionary in pool:
			total_weight += float(candidate["weight"])
		var roll := _item_rng.randf() * total_weight
		var chosen: Dictionary = pool[pool.size() - 1]
		for candidate: Dictionary in pool:
			roll -= float(candidate["weight"])
			if roll <= 0.0:
				chosen = candidate
				break
		picked.append(chosen["item"])
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
			"quality": int(info.get("quality", 1)),
			"type": String(info.get("type", "sellable")),
			"gear_class_id": String(info.get("gear_class_id", "")),
			"size": item_size,
			"description": String(info.get("description", "")),
			"color": GameData.QUALITY_COLORS[info["quality"]],
		})
		col += item_size.x + 1
		shelf_h = maxi(shelf_h, item_size.y)
	rebuild_field()
	var titles: Array[String] = []
	for placed: Dictionary in field_items:
		titles.append(String(placed["title"]))
	add_log("[Игра] Лоты на поле: %s" % ", ".join(titles))


func _make_field_gear_item(gear_id: String, quality: int) -> Dictionary:
	var equip: EquipmentData = EquipmentData.make(gear_id, quality)
	var info: Dictionary = GameData.GEAR_CLASSES[gear_id]
	return {
		"title": equip.item_name,
		"cost": equip.cost,
		"quality": quality,
		"type": "equipment",
		"gear_class_id": gear_id,
		"size": Vector2i(info["size"]),
		"description": equip.ability_description(),
	}


func _make_field_ingredient_item(info: Dictionary) -> Dictionary:
	return {
		"title": String(info.get("title", "Ингредиент")),
		"cost": int(info.get("cost", 0)),
		"quality": int(info.get("quality", 1)),
		"type": "ingredient",
		"size": Vector2i(1, 1),
		"description": "Ингредиент для Башни алхимии.",
	}


func _gear_field_weight(gear_id: String, quality: int) -> float:
	var quality_weight: Array[float] = [0.18, 0.07, 0.02, 0.005, 0.001]
	var weight := quality_weight[clampi(quality, 1, 5) - 1] * 0.2
	if quality != GameData.Quality.LEGENDARY:
		return weight
	var registered := maxi(int(_field_rules.get("registeredPlayers", 1)), 1)
	var target := maxi(1, int(ceil(float(registered) / 1000.0)))
	var counts: Dictionary = _field_rules.get("legendaryCounts", {})
	var already_dropped := int(counts.get(gear_id, 0))
	if already_dropped >= target:
		return weight * 0.03
	return weight * minf(5.0, 1.0 + float(target - already_dropped))


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
		if not _online_room_id.is_empty():
			_poll_online_room()
			return
		_on_round_time_expired()


## Время вышло — запускается следующий раунд (после 5-го аукцион завершён).
func _on_round_time_expired() -> void:
	round_time_expired.emit(_field_round)
	add_log("[Игра] Время раунда %d вышло!" % _field_round)
	_advance_round()


## Завершает текущий раунд: досрочно (все сделали ставки) или по таймеру.
## После 5-го раунда аукцион завершается.
func _advance_round() -> void:
	if not _online_room_id.is_empty():
		return
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
	var total_lot_value := 0
	for item: Dictionary in field_items:
		total_lot_value += int(item.get("cost", 0))
	for p: PlayerDataS in players:
		if p.last_bid > winning_bid:
			winner = p.id
			winning_bid = p.last_bid
	var difference := total_lot_value - winning_bid
	var result_word := "ПЛЮС" if difference >= 0 else "МИНУС"
	_last_auction_summary = "Итоги аукциона\nСтоимость всех лотов: %d монет\nСтавка победителя: %d монет\nРазница: %s%d монет — %s\nПобедитель: %s" % [
		total_lot_value, winning_bid, "+" if difference >= 0 else "", difference, result_word, _player_name(winner)]
	if _auction_result_label != null:
		_auction_result_label.text = _last_auction_summary
		_auction_result_label.visible = true
	var local_player_id := _server_player_id if not _online_room_id.is_empty() else 1
	if _sell_simple_after_win_button != null:
		_sell_simple_after_win_button.visible = winner == local_player_id and winning_bid > 0
		_sell_simple_after_win_button.disabled = false
	if winner != local_player_id or winning_bid <= 0:
		add_log("[Игра] Лот выиграл %s. Ваши предметы не изменились." % _player_name(winner))
		return
	if _online_room_id.is_empty():
		players[0].gold = maxi(players[0].gold - winning_bid, 0)
	for item: Dictionary in field_items:
		var won_item := {
			"title": String(item.get("title", "Предмет")),
			"cost": int(item.get("cost", 0)),
			"size": "%dx%d" % [int(item.get("w", 1)), int(item.get("h", 1))],
			"quality": int(item.get("quality", 1)),
			"type": String(item.get("type", "sellable")),
			"gear_class_id": String(item.get("gear_class_id", "")),
			"description": String(item.get("description", "")),
		}
		inventory.append(won_item)
		if _server_connected:
			_claim_field_item_on_server(item)
	SaveDataS.save_game(players[0].gold, inventory)
	add_log("[Победа] Вы выиграли %d предмет(ов)." % field_items.size())
	_update_player_labels()
	_refresh_inventory()


func _claim_field_item_on_server(item: Dictionary) -> void:
	var size_value: Variant = item.get("size", Vector2i(1, 1))
	var size_x := int(item.get("w", 1))
	var size_y := int(item.get("h", 1))
	if size_value is Vector2i:
		size_x = size_value.x
		size_y = size_value.y
	var result: Dictionary = await _server_client.claim_field_item({
		"title": String(item.get("title", "Предмет")),
		"cost": int(item.get("cost", 0)),
		"quality": int(item.get("quality", 1)),
		"type": String(item.get("type", "sellable")),
		"gearClassId": String(item.get("gear_class_id", "")),
		"sizeX": size_x,
		"sizeY": size_y,
		"description": String(item.get("description", "")),
	})
	if result.get("ok", false):
		_apply_server_profile(result.get("data", {}).get("player", {}))


func _show_field_selection_in_game_area() -> void:
	_round_timer.stop()
	_set_role_locked(false)
	main_hbox.visible = true
	round_info_panel.visible = true
	field_hbox.visible = true
	game_field_panel.visible = true
	game_field.visible = true
	_tier_overlay.visible = true
	if _auction_result_label != null:
		_auction_result_label.text = _last_auction_summary
		_auction_result_label.visible = not _last_auction_summary.is_empty()
	_refresh_tier_buttons()


func _sell_all_simple_after_win() -> void:
	if _server_connected:
		var result: Dictionary = await _server_client.sell_all_simple_items()
		if not result.get("ok", false):
			add_log("[Инвентарь] Не удалось продать простые предметы.")
			return
		_apply_server_profile(result.get("data", {}).get("player", {}))
		add_log("[Инвентарь] Продано простых предметов: %d, получено: %d монет." % [int(result.get("data", {}).get("soldCount", 0)), int(result.get("data", {}).get("total", 0))])
	else:
		var total := 0
		var sold_count := 0
		for index in range(inventory.size() - 1, -1, -1):
			var item: Dictionary = inventory[index]
			if _is_equipment_item(item) or String(item.get("type", "")) in ["potion", "ingredient", "weapon"]:
				continue
			total += maxi(1, int(floor(float(item.get("cost", item.get("baseCost", 0))) * 0.7)))
			inventory.remove_at(index)
			sold_count += 1
		players[0].gold += total
		SaveDataS.save_game(players[0].gold, inventory)
		_refresh_inventory()
		_refresh_tier_buttons()
		add_log("[Инвентарь] Продано простых предметов: %d, получено: %d монет." % [sold_count, total])
	if _sell_simple_after_win_button != null:
		_sell_simple_after_win_button.disabled = true


func _player_name(player_id: int) -> String:
	for p: PlayerDataS in players:
		if p.id == player_id:
			return p.player_name
	return "никто"


## Все игроки поставили — новый раунд начинается, не дожидаясь таймера.
func _check_all_bid() -> void:
	if not _online_room_id.is_empty():
		return
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
			bid_label.text = "Ставка: %d" % previous_bid
		else:
			if p.has_acted:
				bid_label.text = "Готов"
			else:
				bid_label.text = "Ожидание"
		_set_bid_frame(avatar, p.has_acted)
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
	if not _online_room_id.is_empty():
		return
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
		add_log("[%s] сделал ставку: 0." % bot.player_name)
	_update_player_labels()
	if _check_early_victory(bot.id):
		return
	_check_all_bid()


func _check_early_victory(player_id: int) -> bool:
	if not _online_room_id.is_empty():
		return false
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
	calc_display.gui_input.connect(_on_calc_display_gui_input)
	calc_display.text_changed.connect(_on_calc_display_text_changed)


func _on_calc_display_gui_input(event: InputEvent) -> void:
	if not _calc_prefilled or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var printable := key_event.unicode > 0 or key_event.keycode in [KEY_BACKSPACE, KEY_DELETE, KEY_KP_0, KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5, KEY_KP_6, KEY_KP_7, KEY_KP_8, KEY_KP_9]
	var paste := key_event.keycode == KEY_V and key_event.ctrl_pressed
	if printable or paste:
		_calc_prefilled = false
		calc_expression = ""
		calc_display.text = ""


func _on_calc_display_text_changed(new_text: String) -> void:
	if not _calc_prefilled:
		calc_expression = new_text


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
	if player.has_acted:
		add_log("[Игра] Вы уже сделали ставку в этом раунде")
		return
	var value := _calc_result()
	if value < 0:
		add_log("[Игра] Введите ставку от 0 до доступного количества монет")
		return
	if value == 0:
		if not _online_room_id.is_empty():
			_submit_online_bid(0)
			return
		player.last_bid = 0
		player.has_acted = true
		add_log("[Вы] сделали ставку: 0.")
		_update_player_labels()
		_check_all_bid()
		return
	var amount: int = clampi(value, 1, player.gold)
	if amount < value:
		add_log("[Игра] Ставка ограничена доступным балансом.")
	if not _online_room_id.is_empty():
		_submit_online_bid(amount)
		return
	player.last_bid = amount
	player.has_acted = true
	add_log("[Вы] сделал ставку.")
	_update_player_labels()
	if _check_early_victory(player.id):
		return
	_check_all_bid()


func _submit_online_bid(amount: int) -> void:
	var result: Dictionary = await _server_client.submit_auction_bid(_online_room_id, amount)
	if not result.get("ok", false):
		var error_data: Dictionary = result.get("data", {})
		add_log("[Игра] Ставка не принята: %s" % String(error_data.get("error", "сервер отклонил запрос")))
		return
	_apply_online_room_snapshot(result.get("data", {}))
	add_log("[Вы] ставка принята сервером.")

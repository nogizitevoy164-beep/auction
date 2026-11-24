class_name GameData
extends RefCounted
## Ядро игровых данных «Магического аукциона».
## Содержит перечисления, цвета качеств/редкостей, справочник классов
## снаряжения и общие константы. Используется как GameData.Rarity.COMMON и т.п.

# ============================================================
#  РЕДКОСТЬ / КАЧЕСТВО (шкала 1..5, одинаковая для тех и других)
# ============================================================
enum Rarity {
	COMMON     = 1, # Обычный      — белый
	UNCOMMON   = 2, # Необычный    — зелёный
	RARE       = 3, # Редкий       — синий
	EPIC       = 4, # Эпический    — фиолетовый
	LEGENDARY  = 5, # Легендарный  — оранжевый
}

## Качество снаряжения использует ту же шкалу 1..5.
enum Quality {
	COMMON     = 1, # Обычное
	UNCOMMON   = 2, # Необычное
	RARE       = 3, # Редкое
	EPIC       = 4, # Эпическое
	LEGENDARY  = 5, # Легендарное
}

const RARITY_NAMES: Dictionary = {
	Rarity.COMMON:    "Обычный",
	Rarity.UNCOMMON:  "Необычный",
	Rarity.RARE:      "Редкий",
	Rarity.EPIC:      "Эпический",
	Rarity.LEGENDARY: "Легендарный",
}

const QUALITY_NAMES: Dictionary = {
	Quality.COMMON:    "Обычное",
	Quality.UNCOMMON:  "Необычное",
	Quality.RARE:      "Редкое",
	Quality.EPIC:      "Эпическое",
	Quality.LEGENDARY: "Легендарное",
}

## Цвет рамки по качеству/редкости (1..5).
const QUALITY_COLORS: Dictionary = {
	Rarity.COMMON:    Color(1.00, 1.00, 1.00), # белый
	Rarity.UNCOMMON:  Color(0.20, 0.85, 0.30), # зелёный
	Rarity.RARE:      Color(0.20, 0.45, 1.00), # синий
	Rarity.EPIC:      Color(0.60, 0.30, 0.90), # фиолетовый
	Rarity.LEGENDARY: Color(1.00, 0.55, 0.10), # оранжевый
}

# ============================================================
#  ТИПЫ ПРЕДМЕТОВ ИГРОВОГО ПОЛЯ
# ============================================================
enum ItemType {
	SELLABLE,               # Предмет для продажи
	INGREDIENT_ASSASSIN,    # Ингредиент для крафта брони ассасина
	INGREDIENT_WARRIOR,     # Ингредиент для крафта брони воина
	INGREDIENT_MAGE,        # Ингредиент для крафта брони мага
	WEAPON,                 # Оружие (клинок, меч, посох)
	INGREDIENT_CONSUMABLE,  # Ингредиент для крафта расходных материалов
}

const ITEM_TYPE_NAMES: Dictionary = {
	ItemType.SELLABLE:              "Предмет для продажи",
	ItemType.INGREDIENT_ASSASSIN:   "Ингредиент для крафта брони ассасина",
	ItemType.INGREDIENT_WARRIOR:    "Ингредиент для крафта брони воина",
	ItemType.INGREDIENT_MAGE:       "Ингредиент для крафта брони мага",
	ItemType.WEAPON:                "Оружие",
	ItemType.INGREDIENT_CONSUMABLE: "Ингредиент для крафта расходных материалов",
}

# ============================================================
#  СЛОТЫ СНАРЯЖЕНИЯ (основное + украшения)
# ============================================================
enum EquipSlot {
	HEAD,       # Головной убор
	ARMOR,      # Броня
	GLOVES,     # Перчатки
	BOOTS,      # Обувь
	WEAPON,     # Оружие
	RING1,      # Кольцо 1
	RING2,      # Кольцо 2
	NECKLACE,   # Ожерелье
}

const SLOT_NAMES: Dictionary = {
	EquipSlot.HEAD:     "Головной убор",
	EquipSlot.ARMOR:    "Броня",
	EquipSlot.GLOVES:   "Перчатки",
	EquipSlot.BOOTS:    "Обувь",
	EquipSlot.WEAPON:   "Оружие",
	EquipSlot.RING1:    "Кольцо 1",
	EquipSlot.RING2:    "Кольцо 2",
	EquipSlot.NECKLACE: "Ожерелье",
}

## Основное снаряжение: головной убор, броня, перчатки, обувь, оружие.
const MAIN_SLOTS: Array = [
	EquipSlot.HEAD, EquipSlot.ARMOR, EquipSlot.GLOVES, EquipSlot.BOOTS, EquipSlot.WEAPON,
]

## Украшения: кольцо 1, кольцо 2, ожерелье.
const JEWELRY_SLOTS: Array = [
	EquipSlot.RING1, EquipSlot.RING2, EquipSlot.NECKLACE,
]

# ============================================================
#  СПОСОБНОСТИ СНАРЯЖЕНИЯ
# ============================================================
enum Ability {
	UNLOCK_WEAPON,     # Открывает на поле оружие (клинок/меч/посох)
	UNLOCK_INGREDIENTS,# Открывает на поле ингредиенты (ветка задана в "unlock_branch")
	STEALTH,           # Скрыть свою ставку в одном из раундов
	DEFENSE,           # Защита от проигрыша: ставка ×2 в одном раунде
	CANCEL,            # Роба волшебства: отменить способности, применённые соперниками
	                   # (срабатывает только на носителе роби), в одном раунде
}

# ============================================================
#  СПРАВОЧНИК КЛАССОВ СНАРЯЖЕНИЯ
## Размер фиксирован классом (клетки = X × Y).
## base_cost — стартовая стоимость для фабрики EquipmentData.make().
## icon_path — иконка класса (res://icons/*.svg).
## has_capacity — предмет вмещает расходные материалы (кол-во по качеству).
## unlock_branch — какой тип ингредиентов/оружия открывает на поле.
# ============================================================
const GEAR_CLASSES: Dictionary = {
	# ---------- ГОЛОВНЫЕ УБОРЫ (2x2 = 4 клетки) ----------
	"hood_assassin": {
		"title": "Капюшон ассасина",
		"slot": EquipSlot.HEAD,
		"size": Vector2i(2, 2),
		"abilities": [Ability.UNLOCK_WEAPON],
		"unlock_branch": ItemType.WEAPON,
		"unlock_target": "Клинок",
		"base_cost": 3000,
		"icon_path": "res://icons/hood_assassin.svg",
	},
	"helm_warrior": {
		"title": "Шлем воина",
		"slot": EquipSlot.HEAD,
		"size": Vector2i(2, 2),
		"abilities": [Ability.UNLOCK_WEAPON],
		"unlock_branch": ItemType.WEAPON,
		"unlock_target": "Меч",
		"base_cost": 3000,
		"icon_path": "res://icons/helm_warrior.svg",
	},
	"hat_mage": {
		"title": "Шляпа мага",
		"slot": EquipSlot.HEAD,
		"size": Vector2i(2, 2),
		"abilities": [Ability.UNLOCK_WEAPON],
		"unlock_branch": ItemType.WEAPON,
		"unlock_target": "Посох",
		"base_cost": 3000,
		"icon_path": "res://icons/hat_mage.svg",
	},

	# ---------- БРОНЯ ----------
	"cloak_stealth": {
		"title": "Плащ скрытности",
		"slot": EquipSlot.ARMOR,
		"size": Vector2i(2, 3), # 6 клеток
		"abilities": [Ability.STEALTH],
		"has_capacity": true,
		"base_cost": 5000,
		"icon_path": "res://icons/cloak_stealth.svg",
	},
	"chest_defense": {
		"title": "Нагрудник защиты",
		"slot": EquipSlot.ARMOR,
		"size": Vector2i(3, 3), # 9 клеток
		"abilities": [Ability.DEFENSE],
		"has_capacity": true,
		"base_cost": 8000,
		"icon_path": "res://icons/chest_defense.svg",
	},
	"robe_magic": {
		"title": "Роба волшебства",
		"slot": EquipSlot.ARMOR,
		"size": Vector2i(2, 4), # 8 клеток
		"abilities": [Ability.CANCEL],
		"has_capacity": true,
		"base_cost": 6000,
		"icon_path": "res://icons/robe_magic.svg",
	},

	# ---------- ПЕРЧАТКИ ----------
	"gloves_assassin": {
		"title": "Перчатки ассасина",
		"slot": EquipSlot.GLOVES,
		"size": Vector2i(2, 1), # 2 клетки
		"abilities": [Ability.UNLOCK_INGREDIENTS],
		"unlock_branch": ItemType.INGREDIENT_ASSASSIN,
		"unlock_target": "Ингредиенты ассасина",
		"base_cost": 2000,
		"icon_path": "res://icons/gloves_assassin.svg",
	},
	"mittens_warrior": {
		"title": "Руковицы воина",
		"slot": EquipSlot.GLOVES,
		"size": Vector2i(2, 2), # 4 клетки (уточнено: 2х2 = 4)
		"abilities": [Ability.UNLOCK_INGREDIENTS],
		"unlock_branch": ItemType.INGREDIENT_WARRIOR,
		"unlock_target": "Ингредиенты воина",
		"base_cost": 2000,
		"icon_path": "res://icons/mittens_warrior.svg",
	},
	"gloves_mage": {
		"title": "Перчатки мага",
		"slot": EquipSlot.GLOVES,
		"size": Vector2i(2, 1), # 2 клетки
		"abilities": [Ability.UNLOCK_INGREDIENTS],
		"unlock_branch": ItemType.INGREDIENT_MAGE,
		"unlock_target": "Ингредиенты мага",
		"base_cost": 2000,
		"icon_path": "res://icons/gloves_mage.svg",
	},

	# ---------- ОБУВЬ (2x2 = 4 клетки, все три класса) ----------
	"boots_assassin": {
		"title": "Сапоги ассасина",
		"slot": EquipSlot.BOOTS,
		"size": Vector2i(2, 2),
		"abilities": [Ability.UNLOCK_INGREDIENTS],
		"unlock_branch": ItemType.INGREDIENT_CONSUMABLE,
		"unlock_target": "Ингредиенты расходных материалов",
		"base_cost": 2000,
		"icon_path": "res://icons/boots_assassin.svg",
	},
	"boots_plate": {
		"title": "Латные сапоги",
		"slot": EquipSlot.BOOTS,
		"size": Vector2i(2, 2),
		"abilities": [Ability.UNLOCK_INGREDIENTS],
		"unlock_branch": ItemType.INGREDIENT_CONSUMABLE,
		"unlock_target": "Ингредиенты расходных материалов",
		"base_cost": 2000,
		"icon_path": "res://icons/boots_plate.svg",
	},
	"boots_wizard": {
		"title": "Сапоги волшебника",
		"slot": EquipSlot.BOOTS,
		"size": Vector2i(2, 2),
		"abilities": [Ability.UNLOCK_INGREDIENTS],
		"unlock_branch": ItemType.INGREDIENT_CONSUMABLE,
		"unlock_target": "Ингредиенты расходных материалов",
		"base_cost": 2000,
		"icon_path": "res://icons/boots_wizard.svg",
	},
	# ---------- ОРУЖИЕ ----------
	"weapon_dagger_assassin": {
		"title": "Кинжал ассасина",
		"slot": EquipSlot.WEAPON,
		"size": Vector2i(1, 2),
		"abilities": [],
		"base_cost": 2500,
	},
	"weapon_sword_warrior": {
		"title": "Меч воина",
		"slot": EquipSlot.WEAPON,
		"size": Vector2i(1, 4),
		"abilities": [],
		"base_cost": 3000,
	},
	"weapon_staff_mage": {
		"title": "Посох мага",
		"slot": EquipSlot.WEAPON,
		"size": Vector2i(1, 4),
		"abilities": [],
		"base_cost": 3200,
	},
}

# ============================================================
#  ИГРОВЫЕ ПОЛЯ (три аукциона с разным входом и шансами лотов)
## Для входа на поле игрок должен иметь не менее min_gold монет.
## chance_* — колонки шансов выпадения предметов из CSV
## (res://data/magic_auction_items.csv), в процентах за появление лота.
# ============================================================
enum FieldTier {
	STARTER = 0,  # Начальный аукцион   — вход от 1000 монет
	MID     = 1,  # Средний аукцион     — вход от 10 000 монет
	ELITE   = 2,  # Элитный аукцион     — вход от 100 000 монет
}

const FIELD_TIERS: Dictionary = {
	FieldTier.STARTER: {
		"title": "Начальный аукцион",
		"min_gold": 1000,
		"chance_key": "chance_starter",
		"lot_count": 6,
	},
	FieldTier.MID: {
		"title": "Средний аукцион",
		"min_gold": 10000,
		"chance_key": "chance_mid",
		"lot_count": 8,
	},
	FieldTier.ELITE: {
		"title": "Элитный аукцион",
		"min_gold": 100000,
		"chance_key": "chance_elite",
		"lot_count": 10,
	},
}

# ============================================================
#  КАТАЛОГ ПРЕДМЕТОВ ДЛЯ ПРОДАЖИ (пул игрового поля)
## Тип: ItemType.SELLABLE. size — клетки X×Y, quality — шкала 1..5,
## cost — монеты. id используется фабрикой ItemData.create_sellable().
## chance_starter / chance_mid / chance_elite — шансы появления
## предмета на начальном / среднем / элитном поле (%, из CSV).
# ============================================================
const SELLABLE_ITEMS: Dictionary = {
	# ---------- Обычное (белый) ----------
	"copper_coin":            {"title": "Медная монета с гербом",         "size": Vector2i(1, 1), "quality": Rarity.COMMON,    "cost": 20,    "chance_starter": 23.83, "chance_mid": 15.57, "chance_elite": 9.0},
	"clay_mug":               {"title": "Глиняная кружка для эля",        "size": Vector2i(1, 1), "quality": Rarity.COMMON,    "cost": 30,    "chance_starter": 15.57, "chance_mid": 11.61, "chance_elite": 7.62},
	"leather_pouch":          {"title": "Кожаный кисет с травами",        "size": Vector2i(1, 1), "quality": Rarity.COMMON,    "cost": 40,    "chance_starter": 11.51, "chance_mid": 9.44,  "chance_elite": 6.75},
	"iron_candlestick":       {"title": "Железный подсвечник",            "size": Vector2i(1, 2), "quality": Rarity.COMMON,    "cost": 55,    "chance_starter": 8.24,  "chance_mid": 7.51,  "chance_elite": 5.91},
	"bone_hunting_horn":      {"title": "Охотничий рог из кости",         "size": Vector2i(1, 2), "quality": Rarity.COMMON,    "cost": 65,    "chance_starter": 6.91,  "chance_mid": 6.65,  "chance_elite": 5.51},
	"travel_kettle":          {"title": "Походный котелок на цепи",       "size": Vector2i(2, 2), "quality": Rarity.COMMON,    "cost": 80,    "chance_starter": 5.56,  "chance_mid": 5.73,  "chance_elite": 5.05},
	"militia_wooden_shield":  {"title": "Деревянный щит ополченца",       "size": Vector2i(2, 2), "quality": Rarity.COMMON,    "cost": 100,   "chance_starter": 4.4,   "chance_mid": 4.88,  "chance_elite": 4.59},
	# ---------- Необычное (зелёный) ----------
	"amber_silver_brooch":    {"title": "Серебряная брошь с янтарем",     "size": Vector2i(1, 1), "quality": Rarity.UNCOMMON,  "cost": 120,   "chance_starter": 3.63,  "chance_mid": 4.28,  "chance_elite": 4.26},
	"forest_elixir_vial":     {"title": "Склянка с лесным эликсиром",     "size": Vector2i(1, 1), "quality": Rarity.UNCOMMON,  "cost": 140,   "chance_starter": 3.09,  "chance_mid": 3.83,  "chance_elite": 3.99},
	"guild_scroll":           {"title": "Свиток с печатью гильдии",       "size": Vector2i(1, 2), "quality": Rarity.UNCOMMON,  "cost": 170,   "chance_starter": 2.52,  "chance_mid": 3.33,  "chance_elite": 3.68},
	"ranger_dagger":          {"title": "Кинжал лесного следопыта",       "size": Vector2i(1, 2), "quality": Rarity.UNCOMMON,  "cost": 190,   "chance_starter": 2.24,  "chance_mid": 3.07,  "chance_elite": 3.51},
	"sailor_spyglass":        {"title": "Подзорная труба мореплавателя",  "size": Vector2i(1, 3), "quality": Rarity.UNCOMMON,  "cost": 230,   "chance_starter": 1.83,  "chance_mid": 2.68,  "chance_elite": 3.24},
	"merchant_casket":        {"title": "Кованый ларец торговца",         "size": Vector2i(2, 2), "quality": Rarity.UNCOMMON,  "cost": 260,   "chance_starter": 1.61,  "chance_mid": 2.45,  "chance_elite": 3.08},
	"city_watch_crossbow":    {"title": "Арбалет городской стражи",       "size": Vector2i(2, 3), "quality": Rarity.UNCOMMON,  "cost": 300,   "chance_starter": 1.39,  "chance_mid": 2.21,  "chance_elite": 2.9},
	# ---------- Редкое (синий) ----------
	"royal_counselor_ring":   {"title": "Перстень королевского советника","size": Vector2i(1, 1), "quality": Rarity.RARE,      "cost": 350,   "chance_starter": 1.18,  "chance_mid": 1.98,  "chance_elite": 2.71},
	"star_astrolabe":         {"title": "Астролябия звездного звездочета","size": Vector2i(1, 1), "quality": Rarity.RARE,      "cost": 400,   "chance_starter": 1.03,  "chance_mid": 1.8,   "chance_elite": 2.57},
	"rune_north_axe":         {"title": "Рунический топор северян",       "size": Vector2i(1, 3), "quality": Rarity.RARE,      "cost": 500,   "chance_starter": 0.81,  "chance_mid": 1.53,  "chance_elite": 2.34},
	"crystal_chalice":        {"title": "Чаша из горного хрусталя",       "size": Vector2i(2, 2), "quality": Rarity.RARE,      "cost": 580,   "chance_starter": 0.69,  "chance_mid": 1.38,  "chance_elite": 2.2},
	"ancient_chronicle":      {"title": "Фолиант древних летописей",      "size": Vector2i(2, 2), "quality": Rarity.RARE,      "cost": 650,   "chance_starter": 0.62,  "chance_mid": 1.27,  "chance_elite": 2.09},
	"knight_visor_helm":      {"title": "Рыцарский шлем с забралом",      "size": Vector2i(2, 2), "quality": Rarity.RARE,      "cost": 720,   "chance_starter": 0.55,  "chance_mid": 1.18,  "chance_elite": 2.01},
	"baron_war_banner":       {"title": "Боевой штандарт барона",         "size": Vector2i(1, 4), "quality": Rarity.RARE,      "cost": 800,   "chance_starter": 0.5,   "chance_mid": 1.09,  "chance_elite": 1.92},
	# ---------- Эпическое (фиолетовый) ----------
	"fire_salamander_amulet": {"title": "Амулет Огненного Саламандра",    "size": Vector2i(1, 1), "quality": Rarity.EPIC,      "cost": 950,   "chance_starter": 0.41,  "chance_mid": 0.96,  "chance_elite": 1.78},
	"eternity_hourglass":     {"title": "Песочные часы вечности",         "size": Vector2i(1, 2), "quality": Rarity.EPIC,      "cost": 1150,  "chance_starter": 0.34,  "chance_mid": 0.84,  "chance_elite": 1.65},
	"archdruid_staff":        {"title": "Посох верховного друида",        "size": Vector2i(1, 4), "quality": Rarity.EPIC,      "cost": 1400,  "chance_starter": 0.28,  "chance_mid": 0.73,  "chance_elite": 1.52},
	"true_form_mirror":       {"title": "Зеркало Истинного Облика",       "size": Vector2i(2, 2), "quality": Rarity.EPIC,      "cost": 1550,  "chance_starter": 0.25,  "chance_mid": 0.68,  "chance_elite": 1.45},
	"alchemical_cube":        {"title": "Алхимический перегонный куб",    "size": Vector2i(2, 3), "quality": Rarity.EPIC,      "cost": 1800,  "chance_starter": 0.21,  "chance_mid": 0.61,  "chance_elite": 1.36},
	"mithril_plate_cuirass":  {"title": "Латная кираса из мифрила",       "size": Vector2i(2, 3), "quality": Rarity.EPIC,      "cost": 2000,  "chance_starter": 0.19,  "chance_mid": 0.56,  "chance_elite": 1.31},
	# ---------- Легендарное (оранжевый) ----------
	"first_dragon_teardrop":  {"title": "Слеза Первого Дракона",          "size": Vector2i(1, 1), "quality": Rarity.LEGENDARY, "cost": 2500,  "chance_starter": 0.15,  "chance_mid": 0.48,  "chance_elite": 1.19},
	"sun_dynasty_scepter":    {"title": "Скипетр Солнечной Династии",     "size": Vector2i(1, 3), "quality": Rarity.LEGENDARY, "cost": 3100,  "chance_starter": 0.12,  "chance_mid": 0.41,  "chance_elite": 1.09},
	"forgotten_king_crown":   {"title": "Корона Забытого Короля",         "size": Vector2i(2, 2), "quality": Rarity.LEGENDARY, "cost": 3700,  "chance_starter": 0.1,   "chance_mid": 0.36,  "chance_elite": 1.01},
	"paladin_light_greatsword": {"title": "Двуручный меч Паладина Света", "size": Vector2i(1, 4), "quality": Rarity.LEGENDARY, "cost": 4200,  "chance_starter": 0.09,  "chance_mid": 0.33,  "chance_elite": 0.96},
	"secret_magic_grimoire":  {"title": "Гримуар Тайной Магии",           "size": Vector2i(2, 3), "quality": Rarity.LEGENDARY, "cost": 4800,  "chance_starter": 0.08,  "chance_mid": 0.3,   "chance_elite": 0.9},
	"ancient_empire_ark":     {"title": "Золотой ковчег древней империи", "size": Vector2i(3, 3), "quality": Rarity.LEGENDARY, "cost": 5500,  "chance_starter": 0.07,  "chance_mid": 0.27,  "chance_elite": 0.85},
}

# ============================================================
#  ОБЩИЕ КОНСТАНТЫ
# ============================================================
## Границы стоимости предмета. Нижняя граница снижена до 1,
## чтобы вместить дешёвые предметы каталога (например монету за 20).
const COST_MIN: int = 1
const COST_MAX: int = 10000000
## Максимальный размер предмета в клетках (1..16).
const MAX_CELL_COUNT: int = 16

## Вместимость расходных материалов у брони по качеству 1..5:
## 2 / 3 / 4 / 5 / 7.
const CONSUMABLE_CAPACITY: Array[int] = [2, 3, 4, 5, 7]


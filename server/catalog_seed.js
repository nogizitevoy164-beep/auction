const icon = (file) => `/admin-assets/${file}`;

const sellables = [
  ['copper_coin', 'Медная монета с гербом', 1, 20, '1x1', 23.83, 15.57, 9.0],
  ['clay_mug', 'Глиняная кружка для эля', 1, 30, '1x1', 15.57, 11.61, 7.62],
  ['leather_pouch', 'Кожаный кисет с травами', 1, 40, '1x1', 11.51, 9.44, 6.75],
  ['iron_candlestick', 'Железный подсвечник', 1, 55, '1x2', 8.24, 7.51, 5.91],
  ['bone_hunting_horn', 'Охотничий рог из кости', 1, 65, '1x2', 6.91, 6.65, 5.51],
  ['travel_kettle', 'Походный котелок на цепи', 1, 80, '2x2', 5.56, 5.73, 5.05],
  ['militia_wooden_shield', 'Деревянный щит ополченца', 1, 100, '2x2', 4.4, 4.88, 4.59],
  ['amber_silver_brooch', 'Серебряная брошь с янтарем', 2, 120, '1x1', 3.63, 4.28, 4.26],
  ['forest_elixir_vial', 'Склянка с лесным эликсиром', 2, 140, '1x1', 3.09, 3.83, 3.99],
  ['guild_scroll', 'Свиток с печатью гильдии', 2, 170, '1x2', 2.52, 3.33, 3.68],
  ['ranger_dagger', 'Кинжал лесного следопыта', 2, 190, '1x2', 2.24, 3.07, 3.51],
  ['sailor_spyglass', 'Подзорная труба мореплавателя', 2, 230, '1x3', 1.83, 2.68, 3.24],
  ['merchant_casket', 'Кованый ларец торговца', 2, 260, '2x2', 1.61, 2.45, 3.08],
  ['city_watch_crossbow', 'Арбалет городской стражи', 2, 300, '2x3', 1.39, 2.21, 2.9],
  ['royal_counselor_ring', 'Перстень королевского советника', 3, 350, '1x1', 1.18, 1.98, 2.71],
  ['star_astrolabe', 'Астролябия звездного звездочета', 3, 400, '1x1', 1.03, 1.8, 2.57],
  ['rune_north_axe', 'Рунический топор северян', 3, 500, '1x3', .81, 1.53, 2.34],
  ['crystal_chalice', 'Чаша из горного хрусталя', 3, 580, '2x2', .69, 1.38, 2.2],
  ['ancient_chronicle', 'Фолиант древних летописей', 3, 650, '2x2', .62, 1.27, 2.09],
  ['knight_visor_helm', 'Рыцарский шлем с забралом', 3, 720, '2x2', .55, 1.18, 2.01],
  ['baron_war_banner', 'Боевой штандарт барона', 3, 800, '1x4', .5, 1.09, 1.92],
  ['fire_salamander_amulet', 'Амулет Огненного Саламандра', 4, 950, '1x1', .41, .96, 1.78],
  ['eternity_hourglass', 'Песочные часы вечности', 4, 1150, '1x2', .34, .84, 1.65],
  ['archdruid_staff', 'Посох верховного друида', 4, 1400, '1x4', .28, .73, 1.52],
  ['true_form_mirror', 'Зеркало Истинного Облика', 4, 1550, '2x2', .25, .68, 1.45],
  ['alchemical_cube', 'Алхимический перегонный куб', 4, 1800, '2x3', .21, .61, 1.36],
  ['mithril_plate_cuirass', 'Латная кираса из мифрила', 4, 2000, '2x3', .19, .56, 1.31],
  ['first_dragon_teardrop', 'Слеза Первого Дракона', 5, 2500, '1x1', .15, .48, 1.19],
  ['sun_dynasty_scepter', 'Скипетр Солнечной Династии', 5, 3100, '1x3', .12, .41, 1.09],
  ['forgotten_king_crown', 'Корона Забытого Короля', 5, 3700, '2x2', .1, .36, 1.01],
  ['paladin_light_greatsword', 'Двуручный меч Паладина Света', 5, 4200, '1x4', .09, .33, .96],
  ['secret_magic_grimoire', 'Гримуар Тайной Магии', 5, 4800, '2x3', .08, .3, .9],
  ['ancient_empire_ark', 'Золотой ковчег древней империи', 5, 5500, '3x3', .07, .27, .85]
];

const ingredients = [
  ['alchemy_ingredient_common', 'Обычная алхимическая трава', 1, 80, 4, 3, 2],
  ['alchemy_ingredient_uncommon', 'Необычный алхимический корень', 2, 180, 2, 2.5, 2.8],
  ['alchemy_ingredient_rare', 'Редкий кристалл эссенции', 3, 400, .8, 1.4, 2.1],
  ['alchemy_ingredient_epic', 'Эпическое сердце мандрагоры', 4, 900, .2, .6, 1.1],
  ['alchemy_ingredient_legendary', 'Легендарная звезда алхимика', 5, 2200, .03, .12, .35]
];

const weapons = [
  ['weapon_dagger_assassin', 'Кинжал ассасина', 'dagger', '1x2', 1, 2500, 'Открывает 2 выбранные клетки.', 'weapon_dagger_assassin.png'],
  ['weapon_sword_warrior', 'Меч воина', 'sword', '1x4', 1, 3000, 'Открывает 4 последовательные клетки по горизонтали.', 'weapon_sword_warrior.png'],
  ['weapon_staff_mage', 'Посох мага', 'staff', '1x4', 1, 3200, 'Открывает 4 последовательные клетки по вертикали.', 'weapon_staff_mage.png']
];

const gear = [
  ['hood_assassin', 'Капюшон ассасина', '2x2', 3000, 'hood_assassin.svg'], ['helm_warrior', 'Шлем воина', '2x2', 3000, 'helm_warrior.svg'], ['hat_mage', 'Шляпа мага', '2x2', 3000, 'hat_mage.svg'],
  ['cloak_stealth', 'Плащ скрытности', '2x3', 5000, 'cloak_stealth.svg'], ['chest_defense', 'Нагрудник защиты', '3x3', 8000, 'chest_defense.svg'], ['robe_magic', 'Роба волшебства', '2x4', 6000, 'robe_magic.svg'],
  ['gloves_assassin', 'Перчатки ассасина', '2x1', 2000, 'gloves_assassin.svg'], ['mittens_warrior', 'Руковицы воина', '2x2', 2000, 'mittens_warrior.svg'], ['gloves_mage', 'Перчатки мага', '2x1', 2000, 'gloves_mage.svg'],
  ['boots_assassin', 'Сапоги ассасина', '2x2', 2000, 'boots_assassin.svg'], ['boots_plate', 'Латные сапоги', '2x2', 2000, 'boots_plate.svg'], ['boots_wizard', 'Сапоги волшебника', '2x2', 2000, 'boots_wizard.svg']
];

function sizeOf(value) { const [x, y] = value.split('x').map(Number); return { sizeX: x, sizeY: y }; }
function chances(starter, mid, elite) { return { starter, mid, elite }; }
const ingredientIcons = {
  alchemy_ingredient_common: 'alchemy_ingredient_common_herb.png',
  alchemy_ingredient_uncommon: 'alchemy_ingredient_uncommon_root.png',
  alchemy_ingredient_rare: 'alchemy_ingredient_rare_crystal.png',
  alchemy_ingredient_epic: 'alchemy_ingredient_epic_mandrake.png',
  alchemy_ingredient_legendary: 'alchemy_ingredient_legendary.png'
};
function buildCatalog() {
  const result = sellables.map(([id, name, rarity, baseCost, size, starter, mid, elite]) => ({ id, name, description: 'Предмет для продажи.', type: 'sellable', rarity, baseCost, ...sizeOf(size), chances: chances(starter, mid, elite), iconPath: icon(`${id}.png`) }));
  result.push(...ingredients.map(([id, name, rarity, baseCost, starter, mid, elite]) => ({ id, name, description: 'Ингредиент для создания зелий. Можно складывать в пачки.', type: 'ingredient', rarity, baseCost, sizeX: 1, sizeY: 1, chances: chances(starter, mid, elite), iconPath: icon(ingredientIcons[id]) })));
  result.push(...weapons.map(([id, name, weaponKind, size, rarity, baseCost, description, image]) => ({ id, name, description, type: 'weapon', weaponKind, rarity, baseCost, ...sizeOf(size), chances: chances(.1, .3, .8), iconPath: icon(image) })));
  result.push(...gear.flatMap(([id, name, size, baseCost, image]) => Array.from({ length: 5 }, (_, index) => ({ id: `${id}_q${index + 1}`, baseId: id, name: `${name} — качество ${index + 1}`, description: 'Предмет экипировки с активными или пассивными свойствами.', type: 'equipment', gearClassId: id, rarity: index + 1, baseCost: baseCost * (index + 1), ...sizeOf(size), chances: chances(.1, .3, .8), iconPath: icon(image) }))));
  return result;
}

module.exports = { buildCatalog };

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const PORT = Number(process.env.PORT || 8080);
const ADMIN_KEY = process.env.ADMIN_KEY || 'dev-admin-key';
const DATA_DIR = path.join(__dirname, 'data');
const DATA_FILE = process.env.DATA_FILE || path.join(DATA_DIR, 'runtime.json');

const seed = {
  nextPlayerId: 1,
  nextListingId: 1,
  players: [],
  tokens: {},
  itemDefinitions: [
    { id: 'copper_coin', name: 'Медная монета', description: 'Обычный предмет.', type: 'sellable', rarity: 1, baseCost: 20, chances: { starter: 1, mid: 0.5, elite: 0.2 } },
    { id: 'weapon_dagger_assassin', name: 'Кинжал ассасина', description: 'Открывает 2 выбранные клетки.', type: 'weapon', weaponKind: 'dagger', rarity: 1, baseCost: 2500, chances: { starter: 0.1, mid: 0.3, elite: 0.8 } },
    { id: 'weapon_sword_warrior', name: 'Меч воина', description: 'Открывает 4 клетки по горизонтали.', type: 'weapon', weaponKind: 'sword', rarity: 1, baseCost: 3000, chances: { starter: 0.1, mid: 0.3, elite: 0.8 } },
    { id: 'weapon_staff_mage', name: 'Посох мага', description: 'Открывает 4 клетки по вертикали.', type: 'weapon', weaponKind: 'staff', rarity: 1, baseCost: 3200, chances: { starter: 0.1, mid: 0.3, elite: 0.8 } }
  ],
  news: [{ id: 1, title: 'Сервер запущен', message: 'Добро пожаловать на игровой сервер.', type: 'system', createdAt: new Date().toISOString() }]
};

function loadState() {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  if (!fs.existsSync(DATA_FILE)) {
    fs.writeFileSync(DATA_FILE, JSON.stringify(seed, null, 2));
    return structuredClone(seed);
  }
  return JSON.parse(fs.readFileSync(DATA_FILE, 'utf8'));
}

let state = loadState();
function saveState() {
  fs.writeFileSync(DATA_FILE, JSON.stringify(state, null, 2));
}

function json(res, status, body) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(body));
}

function error(res, status, message) { json(res, status, { error: message }); }
function id() { return crypto.randomUUID(); }

async function body(req) {
  let text = '';
  for await (const chunk of req) text += chunk;
  if (!text) return {};
  try { return JSON.parse(text); } catch { throw new Error('Некорректный JSON'); }
}

function auth(req) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  const playerId = state.tokens[token];
  return state.players.find((player) => player.id === playerId) || null;
}

function publicPlayer(player) {
  return { id: player.id, login: player.login, coins: player.coins, inventory: player.inventory, equipment: player.equipment, serverId: 1 };
}

function requirePlayer(req, res) {
  const player = auth(req);
  if (!player) { error(res, 401, 'Требуется авторизация'); return null; }
  return player;
}

function addNews(title, message, type = 'market') {
  state.news.unshift({ id: Date.now(), title, message, type, createdAt: new Date().toISOString() });
  state.news = state.news.slice(0, 100);
}

function ensureCastle(player) {
  if (!player.castle) player.castle = { level: 1, buildings: { coin_tower: { level: 1, storedCoins: 0, lastIncomeAt: Date.now() }, potion_tower: { level: 1 } } };
  if (!player.potions) player.potions = [];
  const tower = player.castle.buildings.coin_tower;
  const elapsedHours = Math.max(0, (Date.now() - Number(tower.lastIncomeAt || Date.now())) / 3600000);
  const incomePerHour = 100 * Number(tower.level || 1);
  tower.storedCoins = Math.min(incomePerHour * 24, Number(tower.storedCoins || 0) + Math.floor(elapsedHours * incomePerHour));
  tower.lastIncomeAt = Date.now();
  return player.castle;
}

function expireListings() {
  const now = Date.now(); let changed = false;
  for (const seller of state.players) {
    for (const listing of seller.listings || []) {
      if (listing.status !== 'active' || Date.parse(listing.expiresAt) > now) continue;
      listing.status = 'expired';
      const item = seller.inventory.find((x) => x.id === listing.instanceId);
      if (item) item.state = 'inventory';
      changed = true;
    }
  }
  if (changed) saveState();
}

async function handle(req, res) {
  expireListings();
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const parts = url.pathname.split('/').filter(Boolean);
  try {
    if (req.method === 'GET' && url.pathname === '/health') return json(res, 200, { ok: true, serverId: 1, playersOnline: state.players.length });
    if (req.method === 'POST' && url.pathname === '/api/v1/auth/register') {
      const data = await body(req);
      const login = String(data.login || '').trim();
      if (login.length < 3) return error(res, 400, 'Логин должен содержать минимум 3 символа');
      if (state.players.some((p) => p.login.toLowerCase() === login.toLowerCase())) return error(res, 409, 'Игрок уже существует');
      const player = { id: state.nextPlayerId++, login, coins: 1000, inventory: [], equipment: {}, listings: [], castle: null, potions: [] };
      const token = id(); state.players.push(player); state.tokens[token] = player.id; saveState();
      return json(res, 201, { token, player: publicPlayer(player) });
    }
    if (req.method === 'POST' && url.pathname === '/api/v1/auth/login') {
      const data = await body(req); const player = state.players.find((p) => p.login === data.login);
      if (!player) return error(res, 401, 'Неверные данные входа');
      const token = id(); state.tokens[token] = player.id; saveState(); return json(res, 200, { token, player: publicPlayer(player) });
    }
    if (req.method === 'GET' && url.pathname === '/api/v1/catalog/items') return json(res, 200, { items: state.itemDefinitions });
    if (req.method === 'GET' && url.pathname === '/api/v1/news') return json(res, 200, { news: state.news });
    if (req.method === 'GET' && url.pathname === '/api/v1/market/listings') return json(res, 200, { listings: state.players.flatMap((p) => p.listings || []).filter((l) => l.status === 'active') });

    const player = requirePlayer(req, res); if (!player) return;
    if (req.method === 'GET' && url.pathname === '/api/v1/me') return json(res, 200, publicPlayer(player));
    if (req.method === 'GET' && url.pathname === '/api/v1/castle') { const castle = ensureCastle(player); saveState(); return json(res, 200, castle); }
    if (req.method === 'POST' && url.pathname === '/api/v1/castle/collect') {
      const castle = ensureCastle(player); const tower = castle.buildings.coin_tower; const collected = Number(tower.storedCoins || 0);
      player.coins += collected; tower.storedCoins = 0; saveState(); return json(res, 200, { collected, player: publicPlayer(player), castle });
    }
    if (req.method === 'POST' && url.pathname === '/api/v1/castle/upgrade') {
      const castle = ensureCastle(player); const tower = castle.buildings.coin_tower; const cost = Number(tower.level || 1) * 1000;
      if (player.coins < cost) return error(res, 400, 'Недостаточно монет для улучшения');
      player.coins -= cost; tower.level += 1; saveState(); return json(res, 200, { cost, player: publicPlayer(player), castle });
    }
    if (req.method === 'GET' && url.pathname === '/api/v1/potions') { ensureCastle(player); return json(res, 200, { potions: player.potions }); }
    if (req.method === 'POST' && url.pathname === '/api/v1/potions/craft') {
      const castle = ensureCastle(player); const level = Number(castle.buildings.potion_tower.level || 1);
      const potion = { id: id(), recipeId: 'healing_potion', name: 'Зелье восстановления', quality: Math.min(level, 5), state: 'inventory', createdAt: new Date().toISOString() };
      player.potions.push(potion); saveState(); return json(res, 201, { potion, player: publicPlayer(player) });
    }
    if (req.method === 'POST' && url.pathname === '/api/v1/inventory/sell') {
      const data = await body(req); const index = player.inventory.findIndex((x) => x.id === data.instanceId && x.state === 'inventory');
      if (index < 0) return error(res, 404, 'Предмет не найден в инвентаре');
      const item = player.inventory[index]; const price = Math.max(1, Math.floor(Number(item.baseCost || 0) * 0.7));
      player.inventory.splice(index, 1); player.coins += price; saveState();
      return json(res, 200, { price, player: publicPlayer(player) });
    }
    if (req.method === 'POST' && url.pathname === '/api/v1/equipment/equip') {
      const data = await body(req); const item = player.inventory.find((x) => x.id === data.instanceId && x.state === 'inventory');
      const slot = String(data.slot || ''); if (!item || !slot) return error(res, 400, 'Предмет или слот некорректны');
      const previousId = player.equipment[slot];
      if (previousId) { const previous = player.inventory.find((x) => x.id === previousId); if (previous) previous.state = 'inventory'; }
      item.state = 'equipped'; player.equipment[slot] = item.id; saveState();
      return json(res, 200, publicPlayer(player));
    }
    if (req.method === 'POST' && url.pathname === '/api/v1/inventory/grant-demo-item') {
      const data = await body(req); const definition = state.itemDefinitions.find((x) => x.id === data.definitionId);
      if (!definition) return error(res, 404, 'Описание предмета не найдено');
      const instance = { id: id(), definitionId: definition.id, name: definition.name, baseCost: definition.baseCost, quality: Number(data.quality || definition.rarity), state: 'inventory' };
      player.inventory.push(instance); saveState(); return json(res, 201, instance);
    }
    if (req.method === 'POST' && url.pathname === '/api/v1/market/listings') {
      const data = await body(req); const item = player.inventory.find((x) => x.id === data.instanceId && x.state === 'inventory');
      const price = Number(data.price);
      if (!item || !Number.isInteger(price) || price <= 0) return error(res, 400, 'Предмет или цена некорректны');
      item.state = 'market_listing'; const listing = { id: state.nextListingId++, sellerId: player.id, instanceId: item.id, name: item.name, price, status: 'active', expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString() };
      player.listings.push(listing); saveState(); return json(res, 201, listing);
    }
    if (req.method === 'POST' && parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'market' && parts[3] === 'listings' && parts[5] === 'buy') {
      const listingId = Number(parts[4]); const listing = state.players.flatMap((p) => p.listings || []).find((x) => x.id === listingId && x.status === 'active');
      if (!listing) return error(res, 404, 'Лот не найден');
      if (listing.sellerId === player.id || player.coins < listing.price) return error(res, 400, 'Покупка недоступна');
      const seller = state.players.find((p) => p.id === listing.sellerId); const item = seller.inventory.find((x) => x.id === listing.instanceId);
      player.coins -= listing.price; seller.coins += listing.price; item.state = 'inventory'; seller.listings = seller.listings.filter((x) => x.id !== listing.id); player.inventory.push(item); listing.status = 'sold'; addNews('Предмет продан', `${item.name} был продан на рынке.`, 'market'); saveState(); return json(res, 200, { listing, player: publicPlayer(player) });
    }
    if (req.method === 'POST' && url.pathname.startsWith('/api/v1/admin/items')) {
      if (req.headers['x-admin-key'] !== ADMIN_KEY) return error(res, 403, 'Нужны права администратора');
      const data = await body(req); if (!data.id || !data.name) return error(res, 400, 'Нужны id и name');
      const existing = state.itemDefinitions.find((x) => x.id === data.id); if (existing) Object.assign(existing, data); else state.itemDefinitions.push({ ...data, chances: data.chances || { starter: 0, mid: 0, elite: 0 } });
      saveState(); return json(res, 200, { items: state.itemDefinitions });
    }
    return error(res, 404, 'Маршрут не найден');
  } catch (e) { return error(res, 400, e.message); }
}

const server = http.createServer(handle);
server.listen(PORT, () => console.log(`Auction server listening on http://127.0.0.1:${PORT}`));
process.on('SIGTERM', () => server.close(() => process.exit(0)));

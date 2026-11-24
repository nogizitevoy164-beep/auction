const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { WebSocketServer } = require('ws');
const { hashPassword, verifyPassword } = require('./auth');
const { createPool, checkConnection, ensureRuntimeTable, loadRuntimeState, saveRuntimeState } = require('./db');

const PORT = Number(process.env.PORT || 8080);
const ADMIN_KEY = process.env.ADMIN_KEY || 'dev-admin-key';
const DATA_DIR = path.join(__dirname, 'data');
const DATA_FILE = process.env.DATA_FILE || path.join(DATA_DIR, 'runtime.json');
const postgres = createPool();
const POLICY_VERSIONS = { terms: '1.0', privacy: '1.0', rules: '1.0', age: '1.0' };
const POLICY_SUMMARIES = {
  terms: 'Пользовательское соглашение: правила доступа, виртуальные предметы и ответственность игрока.',
  privacy: 'Политика конфиденциальности: какие данные хранятся, зачем они нужны и как запросить удаление.',
  rules: 'Правила игры: запрет читов, мультиаккаунтов, мошенничества и эксплуатации ошибок.',
  age: 'Возрастное ограничение: игрок подтверждает, что соответствует минимальному возрасту, установленному для игры.'
};

const seed = {
  nextPlayerId: 1,
  nextListingId: 1,
  players: [],
  tokens: {},
  legendaryAuctions: [],
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
let sockets = new Set();
const MATCHMAKING_CAPACITY = 4;
const matchmakingQueues = new Map();
const matchmakingStarted = new Map();
let ready = Promise.resolve();
function saveState() {
  fs.writeFileSync(DATA_FILE, JSON.stringify(state, null, 2));
  if (postgres) saveRuntimeState(postgres, state).catch((error) => console.error(`PostgreSQL save failed: ${error.message}`));
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

function fieldRules() {
  const legendaryCounts = {};
  for (const player of state.players) {
    for (const item of player.inventory || []) {
      const quality = Number(item.quality || item.rarity || 1);
      if (quality < 5) continue;
      const gearId = String(item.gearClassId || item.gear_class_id || (item.type === 'weapon' ? item.id : ''));
      if (gearId) legendaryCounts[gearId] = Number(legendaryCounts[gearId] || 0) + 1;
    }
  }
  return { registeredPlayers: state.players.length, legendaryCounts };
}

function publicPlayer(player) {
  return { id: player.id, login: player.login, displayName: player.displayName || player.login, emailVerified: Boolean(player.emailVerified), policyAcceptances: player.policyAcceptances || {}, coins: player.coins, inventory: player.inventory, equipment: player.equipment, serverId: 1, fieldRules: fieldRules() };
}

function requirePlayer(req, res) {
  const player = auth(req);
  if (!player) { error(res, 401, 'Требуется авторизация'); return null; }
  return player;
}

function matchmakingStatus(tier, playerId = 0) {
  const queue = matchmakingQueues.get(String(tier)) || [];
  const started = matchmakingStarted.get(String(tier));
  const isStarted = Boolean(started && started.players.includes(playerId) && Date.now() - started.startedAt < 60000);
  return { tier: Number(tier), waitingPlayers: queue.length, capacity: MATCHMAKING_CAPACITY, ready: queue.length >= MATCHMAKING_CAPACITY || isStarted, status: isStarted ? 'started' : 'waiting' };
}

function addNews(title, message, type = 'market') {
  state.news.unshift({ id: Date.now(), title, message, type, createdAt: new Date().toISOString() });
  state.news = state.news.slice(0, 100);
  broadcast('news_created', state.news[0]);
}

function broadcast(type, payload) {
  const message = JSON.stringify({ type, payload });
  for (const socket of sockets) if (socket.readyState === 1) socket.send(message);
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

function availableCoins(player) { return Number(player.coins || 0) - Number(player.reservedCoins || 0); }

function settleLegendaryAuction(auction) {
  if (auction.status !== 'active') return;
  auction.status = 'finished';
  const seller = state.players.find((p) => p.id === auction.sellerId);
  const item = seller?.inventory.find((x) => x.id === auction.instanceId);
  if (auction.currentBidderId) {
    const winner = state.players.find((p) => p.id === auction.currentBidderId);
    const bid = Number(auction.currentPrice);
    if (winner && seller && item) {
      winner.reservedCoins = Math.max(0, Number(winner.reservedCoins || 0) - bid);
      winner.coins -= bid; seller.coins += bid;
      item.state = 'inventory'; seller.inventory = seller.inventory.filter((x) => x.id !== item.id); winner.inventory.push(item);
      addNews('Легендарный предмет продан', `${item.name} продан на легендарном аукционе.`, 'legendary_item');
    }
  } else if (item) item.state = 'inventory';
  saveState();
}

function processLegendaryAuctions() {
  const now = Date.now();
  for (const auction of state.legendaryAuctions) if (auction.status === 'active' && Date.parse(auction.endsAt) <= now) settleLegendaryAuction(auction);
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
  await ready;
  expireListings();
  processLegendaryAuctions();
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const parts = url.pathname.split('/').filter(Boolean);
  try {
    if (req.method === 'GET' && url.pathname === '/health') return json(res, 200, { ok: true, serverId: 1, playersOnline: state.players.length, storage: postgres ? 'postgresql-configured' : 'json' });
    if (req.method === 'GET' && url.pathname === '/admin') {
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      return res.end(fs.readFileSync(path.join(__dirname, 'admin.html')));
    }
    if (req.method === 'GET' && url.pathname === '/api/v1/policies') return json(res, 200, { versions: POLICY_VERSIONS, summaries: POLICY_SUMMARIES, minimumAge: 13 });
    if (req.method === 'POST' && url.pathname === '/api/v1/auth/register') {
      const data = await body(req);
      const login = String(data.login || '').trim();
      if (login.length < 3) return error(res, 400, 'Логин должен содержать минимум 3 символа');
      const isGuestRegistration = !data.email && !data.password && !data.policyAcceptances;
      if (isGuestRegistration) {
        const existingGuest = state.players.find((p) => p.login.toLowerCase() === login.toLowerCase());
        if (existingGuest) {
          const guestToken = id(); state.tokens[guestToken] = existingGuest.id;
          return json(res, 200, { token: guestToken, player: publicPlayer(existingGuest) });
        }
        const guestCredentials = hashPassword(`guest:${login}`);
        const guest = { id: state.nextPlayerId++, login, displayName: login, emailVerified: false, passwordSalt: guestCredentials.salt, passwordHash: guestCredentials.hash, coins: 1000, reservedCoins: 0, inventory: [], equipment: {}, listings: [], castle: null, potions: [] };
        const guestToken = id(); state.players.push(guest); state.tokens[guestToken] = guest.id; saveState();
        return json(res, 201, { token: guestToken, player: publicPlayer(guest) });
      }
      const email = String(data.email || '').trim().toLowerCase();
      const password = String(data.password || '');
      const displayName = String(data.displayName || login).trim();
      if (!/^\S+@\S+\.\S+$/.test(email)) return error(res, 400, 'Укажите корректный email');
      if (password.length < 8) return error(res, 400, 'Пароль должен содержать минимум 8 символов');
      if (displayName.length < 2) return error(res, 400, 'Имя игрока должно содержать минимум 2 символа');
      if (!data.ageConfirmed) return error(res, 400, 'Нужно подтвердить возраст');
      const acceptances = data.policyAcceptances || {};
      for (const key of Object.keys(POLICY_VERSIONS)) if (acceptances[key] !== POLICY_VERSIONS[key]) return error(res, 400, `Нужно принять политику: ${key}`);
      const currentPlayer = auth(req);
      const guestLogin = String(data.guestLogin || '').trim();
      const migratingGuest = currentPlayer && !currentPlayer.email && currentPlayer.login === guestLogin && currentPlayer.login.toLowerCase() === login.toLowerCase();
      if (state.players.some((p) => p !== currentPlayer && (p.login.toLowerCase() === login.toLowerCase() || String(p.email || '').toLowerCase() === email))) return error(res, 409, 'Логин или email уже зарегистрирован');
      const credentials = hashPassword(password);
      const player = migratingGuest ? currentPlayer : { id: state.nextPlayerId++, login, coins: 1000, reservedCoins: 0, inventory: [], equipment: {}, listings: [], castle: null, potions: [] };
      Object.assign(player, { login, email, displayName, emailVerified: false, passwordSalt: credentials.salt, passwordHash: credentials.hash, ageConfirmedAt: new Date().toISOString(), policyAcceptances: { ...acceptances } });
      const token = id(); state.players.push(player); state.tokens[token] = player.id; saveState();
      return json(res, 201, { token, player: publicPlayer(player) });
    }
    if (req.method === 'POST' && url.pathname === '/api/v1/auth/login') {
      const data = await body(req); const identifier = String(data.login || data.email || '').trim().toLowerCase();
      const player = state.players.find((p) => p.login.toLowerCase() === identifier || String(p.email || '').toLowerCase() === identifier);
      const password = data.password || (player && !player.email ? `guest:${player.login}` : '');
      if (!player || !verifyPassword(String(password), { salt: player.passwordSalt, hash: player.passwordHash })) return error(res, 401, 'Неверный логин, email или пароль');
      const token = id(); state.tokens[token] = player.id; saveState(); return json(res, 200, { token, player: publicPlayer(player) });
    }
    if (req.method === 'GET' && url.pathname === '/api/v1/catalog/items') return json(res, 200, { items: state.itemDefinitions });
    if (req.method === 'GET' && url.pathname === '/api/v1/news') return json(res, 200, { news: state.news });
    if (req.method === 'GET' && url.pathname === '/api/v1/market/listings') return json(res, 200, { listings: state.players.flatMap((p) => p.listings || []).filter((l) => l.status === 'active') });
    if (req.method === 'GET' && url.pathname === '/api/v1/legendary-auctions') return json(res, 200, { auctions: state.legendaryAuctions.filter((a) => a.status === 'active') });

    if (req.method === 'POST' && url.pathname === '/api/v1/admin/items') {
      if (req.headers['x-admin-key'] !== ADMIN_KEY) return error(res, 403, 'Нужны права администратора');
      const data = await body(req); if (!data.id || !data.name) return error(res, 400, 'Нужны id и name');
      const existing = state.itemDefinitions.find((x) => x.id === data.id);
      if (existing) Object.assign(existing, data);
      else state.itemDefinitions.push({ ...data, chances: data.chances || { starter: 0, mid: 0, elite: 0 } });
      saveState(); broadcast('catalog_updated', { id: data.id }); return json(res, 200, { items: state.itemDefinitions });
    }
    const player = requirePlayer(req, res); if (!player) return;
    if (req.method === 'GET' && url.pathname === '/api/v1/me') return json(res, 200, publicPlayer(player));
    if (url.pathname === '/api/v1/matchmaking/status' && req.method === 'GET') {
      const tier = String(url.searchParams.get('tier') || '0');
      return json(res, 200, matchmakingStatus(tier, player.id));
    }
    if (url.pathname === '/api/v1/matchmaking/join' && req.method === 'POST') {
      const data = await body(req); const tier = String(Number(data.tier));
      if (!['0', '1', '2'].includes(tier)) return error(res, 400, 'Поле аукциона указано неверно');
      const queue = matchmakingQueues.get(tier) || [];
      if (!queue.includes(player.id)) queue.push(player.id);
      matchmakingQueues.set(tier, queue);
      const snapshot = matchmakingStatus(tier);
      if (queue.length >= MATCHMAKING_CAPACITY) {
        matchmakingStarted.set(tier, { players: [...queue], startedAt: Date.now() });
        matchmakingQueues.delete(tier);
        return json(res, 200, { ...snapshot, waitingPlayers: queue.length, ready: true, status: 'started' });
      }
      return json(res, 200, snapshot);
    }
    if (url.pathname === '/api/v1/matchmaking/skip' && req.method === 'POST') {
      const data = await body(req); const tier = String(Number(data.tier));
      if (!['0', '1', '2'].includes(tier)) return error(res, 400, 'Поле аукциона указано неверно');
      const queue = matchmakingQueues.get(tier) || [];
      if (!queue.includes(player.id)) queue.push(player.id);
      matchmakingStarted.set(tier, { players: [...queue], startedAt: Date.now() });
      matchmakingQueues.delete(tier);
      return json(res, 200, { ...matchmakingStatus(tier, player.id), waitingPlayers: queue.length, ready: true, status: 'started', humanPlayers: queue.length, bots: Math.max(0, MATCHMAKING_CAPACITY - queue.length) });
    }
    if (url.pathname === '/api/v1/matchmaking/leave' && req.method === 'POST') {
      const data = await body(req); const tier = String(Number(data.tier));
      const queue = (matchmakingQueues.get(tier) || []).filter((id) => id !== player.id);
      if (queue.length) matchmakingQueues.set(tier, queue); else matchmakingQueues.delete(tier);
      return json(res, 200, matchmakingStatus(tier, player.id));
    }
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
    if (req.method === 'POST' && url.pathname === '/api/v1/inventory/claim-field-item') {
      const data = await body(req);
      if (!data.title) return error(res, 400, 'Нужно название предмета');
      const quality = Math.max(1, Math.min(5, Number(data.quality || 1)));
      const instance = {
        id: id(),
        definitionId: String(data.gearClassId || data.gear_class_id || data.definitionId || data.title),
        name: String(data.title),
        baseCost: Math.max(0, Number(data.cost || data.baseCost || 0)),
        quality,
        rarity: quality,
        type: String(data.type || 'sellable'),
        gearClassId: String(data.gearClassId || data.gear_class_id || ''),
        sizeX: Math.max(1, Number(data.sizeX || 1)),
        sizeY: Math.max(1, Number(data.sizeY || 1)),
        description: String(data.description || ''),
        state: 'inventory'
      };
      player.inventory.push(instance); saveState();
      return json(res, 201, { instance, player: publicPlayer(player) });
    }
    if (req.method === 'POST' && url.pathname === '/api/v1/market/listings') {
      const data = await body(req); const item = player.inventory.find((x) => x.id === data.instanceId && x.state === 'inventory');
      const price = Number(data.price);
      if (!item || !Number.isInteger(price) || price <= 0) return error(res, 400, 'Предмет или цена некорректны');
      const itemType = String(item.type || '').toLowerCase();
      const marketable = itemType === 'equipment' || itemType === 'weapon' || itemType === 'potion' || Boolean(item.gearClassId || item.gear_class_id);
      if (!marketable) return error(res, 400, 'Этот предмет предназначен только для продажи и не выставляется на рынок');
      item.state = 'market_listing'; const listing = { id: state.nextListingId++, sellerId: player.id, instanceId: item.id, name: item.name, price, status: 'active', expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString() };
      player.listings.push(listing); saveState(); return json(res, 201, listing);
    }
    if (req.method === 'POST' && url.pathname === '/api/v1/legendary-auctions') {
      const data = await body(req); const item = player.inventory.find((x) => x.id === data.instanceId && x.state === 'inventory' && Number(x.quality) >= 5);
      const hours = Number(data.durationHours); const startPrice = Number(data.startPrice);
      if (!item || !Number.isInteger(startPrice) || startPrice <= 0 || hours < 3 || hours > 24) return error(res, 400, 'Нужен легендарный предмет, цена и срок от 3 до 24 часов');
      item.state = 'legendary_auction'; const auction = { id: id(), sellerId: player.id, instanceId: item.id, name: item.name, startPrice, currentPrice: startPrice, currentBidderId: null, endsAt: new Date(Date.now() + hours * 3600000).toISOString(), status: 'active' };
      state.legendaryAuctions.push(auction); addNews('Легендарный предмет выставлен', `${item.name} выставлен на легендарный аукцион.`, 'legendary_item'); saveState(); return json(res, 201, auction);
    }
    if (req.method === 'POST' && parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'market' && parts[3] === 'listings' && parts[5] === 'buy') {
      const listingId = Number(parts[4]); const listing = state.players.flatMap((p) => p.listings || []).find((x) => x.id === listingId && x.status === 'active');
      if (!listing) return error(res, 404, 'Лот не найден');
      if (listing.sellerId === player.id || player.coins < listing.price) return error(res, 400, 'Покупка недоступна');
      const seller = state.players.find((p) => p.id === listing.sellerId); const item = seller.inventory.find((x) => x.id === listing.instanceId);
      player.coins -= listing.price; seller.coins += listing.price; item.state = 'inventory'; seller.listings = seller.listings.filter((x) => x.id !== listing.id); player.inventory.push(item); listing.status = 'sold'; addNews('Предмет продан', `${item.name} был продан на рынке.`, 'market'); saveState(); return json(res, 200, { listing, player: publicPlayer(player) });
    }
    if (req.method === 'POST' && parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'market' && parts[3] === 'listings' && parts[5] === 'cancel') {
      const listingId = Number(parts[4]);
      const listing = player.listings.find((x) => x.id === listingId && x.status === 'active');
      if (!listing) return error(res, 404, 'Лот не найден или принадлежит другому игроку');
      const item = player.inventory.find((x) => x.id === listing.instanceId);
      if (item) item.state = 'inventory';
      listing.status = 'cancelled';
      player.listings = player.listings.filter((x) => x.id !== listing.id);
      saveState();
      return json(res, 200, { listing, player: publicPlayer(player) });
    }
    if (req.method === 'POST' && parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'legendary-auctions' && parts[4] === 'bid') {
      const auction = state.legendaryAuctions.find((x) => x.id === parts[3] && x.status === 'active');
      const data = await body(req); const amount = Number(data.amount);
      if (!auction || auction.sellerId === player.id) return error(res, 404, 'Аукцион недоступен');
      const minimum = auction.currentBidderId ? Number(auction.currentPrice) + 1000 : Number(auction.startPrice);
      if (!Number.isInteger(amount) || amount < minimum || availableCoins(player) < amount) return error(res, 400, 'Ставка должна быть выше на 1000 монет и доступна по балансу');
      if (auction.currentBidderId) { const previous = state.players.find((p) => p.id === auction.currentBidderId); if (previous) previous.reservedCoins = Math.max(0, Number(previous.reservedCoins || 0) - auction.currentPrice); }
      player.reservedCoins = Number(player.reservedCoins || 0) + amount; auction.currentPrice = amount; auction.currentBidderId = player.id; saveState(); return json(res, 200, auction);
    }
    if (req.method === 'POST' && parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'legendary-auctions' && parts[4] === 'finish') {
      const auction = state.legendaryAuctions.find((x) => x.id === parts[3] && x.status === 'active');
      if (!auction || auction.sellerId !== player.id) return error(res, 403, 'Завершить аукцион может только продавец');
      settleLegendaryAuction(auction); return json(res, 200, auction);
    }
    return error(res, 404, 'Маршрут не найден');
  } catch (e) { return error(res, 400, e.message); }
}

const server = http.createServer(handle);
const websocket = new WebSocketServer({ server, path: '/ws' });
websocket.on('connection', (socket) => {
  sockets.add(socket);
  socket.send(JSON.stringify({ type: 'connected', payload: { serverId: 1 } }));
  socket.send(JSON.stringify({ type: 'news_snapshot', payload: state.news }));
  socket.on('close', () => sockets.delete(socket));
});
if (postgres) {
  ready = (async () => {
    await ensureRuntimeTable(postgres);
    const stored = await loadRuntimeState(postgres);
    if (stored) state = stored;
    else await saveRuntimeState(postgres, state);
  })().catch((error) => { console.error(`PostgreSQL bootstrap failed: ${error.message}`); throw error; });
}

server.listen(PORT, async () => {
  console.log(`Auction server listening on http://127.0.0.1:${PORT}`);
  if (postgres) console.log(`PostgreSQL connection: ${await checkConnection(postgres).catch(() => false) ? 'ok' : 'failed'}`);
});
process.on('SIGTERM', () => server.close(() => process.exit(0)));

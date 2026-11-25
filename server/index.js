const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { WebSocketServer } = require('ws');
const { hashPassword, verifyPassword } = require('./auth');
const { createPool, checkConnection, ensureRuntimeTable, loadRuntimeState, saveRuntimeState } = require('./db');
const { buildCatalog } = require('./catalog_seed');

const PORT = Number(process.env.PORT || 8080);
const ADMIN_KEY = process.env.ADMIN_KEY || 'dev-admin-key';
const DATA_DIR = path.join(__dirname, 'data');
const DATA_FILE = process.env.DATA_FILE || path.join(DATA_DIR, 'runtime.json');
const UPDATES_DIR = path.join(__dirname, 'updates');
const postgres = createPool();
const POLICY_VERSIONS = { terms: '1.0', privacy: '1.0', rules: '1.0', age: '1.0' };
const POLICY_SUMMARIES = {
  terms: 'Пользовательское соглашение: правила доступа, виртуальные предметы и ответственность игрока.',
  privacy: 'Политика конфиденциальности: какие данные хранятся, зачем они нужны и как запросить удаление.',
  rules: 'Правила игры: запрет читов, мультиаккаунтов, мошенничества и эксплуатации ошибок.',
  age: 'Возрастное ограничение: игрок подтверждает, что соответствует минимальному возрасту, установленному для игры.'
};
const DEFAULT_TOWER_DEFINITIONS = {
  coin_tower: { title: 'Башня монет', description: 'Приносит пассивный доход, который можно забрать раз в сутки.', maxLevel: 5, upgradeCosts: [1000, 2000, 4000, 8000], incomePerHour: [100, 200, 350, 550, 800] },
  alchemy_tower: { title: 'Башня алхимии', description: 'Позволяет создавать зелья качества от обычного до легендарного.', maxLevel: 5, upgradeCosts: [1500, 3500, 7000, 14000], potionQualityByLevel: [1, 2, 3, 4, 5] }
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
if (!state.castleTowerDefinitions) state.castleTowerDefinitions = structuredClone(DEFAULT_TOWER_DEFINITIONS);
// Keep the server catalogue complete even when runtime.json was created by an older build.
const seededCatalog = buildCatalog();
if (!Array.isArray(state.itemDefinitions)) state.itemDefinitions = [];
for (const item of seededCatalog) {
  const existing = state.itemDefinitions.find((candidate) => candidate.id === item.id);
  if (existing) {
    if (item.type === 'equipment' || !existing.iconPath) existing.iconPath = item.iconPath;
    if (!existing.sizeX) existing.sizeX = item.sizeX;
    if (!existing.sizeY) existing.sizeY = item.sizeY;
    if (!existing.chances) existing.chances = item.chances;
  } else state.itemDefinitions.push(item);
}
saveState();
let sockets = new Set();
const MATCHMAKING_CAPACITY = 4;
const matchmakingQueues = new Map();
const matchmakingStarted = new Map();
const auctionRooms = new Map();
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

function isStackableItem(item) {
  const type = String(item?.type || '').toLowerCase();
  return !['equipment', 'weapon', 'potion'].includes(type) && !item?.gearClassId && !item?.gear_class_id;
}

function stackKey(item) {
  return [String(item.definitionId || item.name || item.title || ''), String(item.name || item.title || ''), String(item.type || ''), Number(item.quality || item.rarity || 1), Number(item.baseCost ?? item.cost ?? 0), String(item.description || '')].join('|');
}

function itemQuantity(item) { return Math.max(1, Number(item?.quantity) || 1); }

function addInventoryItem(player, item, quantity = 1) {
  const amount = Math.max(1, Number(quantity) || 1);
  if (isStackableItem(item)) {
    const existing = (player.inventory || []).find((candidate) => isStackableItem(candidate) && stackKey(candidate) === stackKey(item));
    if (existing) { existing.quantity = itemQuantity(existing) + amount; return existing; }
  }
  item.quantity = isStackableItem(item) ? amount : 1;
  player.inventory.push(item);
  return item;
}

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

function castleTowerDefinitions() {
  if (!state.castleTowerDefinitions) state.castleTowerDefinitions = structuredClone(DEFAULT_TOWER_DEFINITIONS);
  return state.castleTowerDefinitions;
}

function createAuctionRoom(tier, playerIds, botCount = 0) {
  const room = {
    id: id(), tier: Number(tier), fieldSeed: crypto.randomInt(1, 2147483647),
    status: 'active', round: 1, roundEndsAt: Date.now() + 40000,
    bids: {}, previousBids: {}, winnerId: null, winningBid: 0, lotValue: null, deficit: 0, redistribution: {}, settled: false,
    players: playerIds.map((playerId) => ({ id: playerId, isBot: false })), botReadyAt: {}
  };
  for (let index = 0; index < botCount; index += 1) {
    const botId = -(index + 1);
    room.players.push({ id: botId, isBot: true, name: `Бот ${index + 1}` });
    room.botReadyAt[String(botId)] = Date.now() + 500 + ((room.fieldSeed + index * 137) % 4500);
  }
  auctionRooms.set(room.id, room);
  return room;
}

function roomForPlayer(roomId, playerId) {
  const room = auctionRooms.get(String(roomId));
  return room && room.players.some((entry) => entry.id === playerId) ? room : null;
}

function processAuctionRoom(room) {
  if (!room || room.status !== 'active') return;
  const now = Date.now();
  for (const entry of room.players) {
    if (!entry.isBot || Object.prototype.hasOwnProperty.call(room.bids, String(entry.id))) continue;
    const readyAt = Number(room.botReadyAt[String(entry.id)] || 0);
    if (now >= readyAt || now >= room.roundEndsAt) {
      const variation = Math.abs((room.fieldSeed + room.round * 977 + Math.abs(entry.id) * 313) % 700);
      room.bids[String(entry.id)] = Math.min(300 + variation, 1000);
    }
  }
  const allActed = room.players.every((entry) => Object.prototype.hasOwnProperty.call(room.bids, String(entry.id)));
  if (now < room.roundEndsAt && !allActed) return;
  room.previousBids = { ...room.bids };
  const ranked = Object.entries(room.bids).sort((a, b) => Number(b[1]) - Number(a[1]));
  if (ranked.length) {
    const [winnerId, bid] = ranked[0];
    room.winnerId = Number(winnerId); room.winningBid = Number(bid);
  }
  if (room.round >= 5) {
    room.status = 'finished';
    settleAuctionRoom(room);
    return;
  }
  room.round += 1; room.bids = {}; room.roundEndsAt = Date.now() + 40000;
  for (const entry of room.players) if (entry.isBot) room.botReadyAt[String(entry.id)] = Date.now() + 500 + ((room.fieldSeed + room.round * 701 + Math.abs(entry.id) * 137) % 4500);
}

function settleAuctionRoom(room) {
  if (!room || room.settled) return;
  const lotValue = Math.max(0, Number(room.lotValue || 0));
  const deficit = Math.max(0, Number(room.winningBid || 0) - lotValue);
  room.deficit = deficit;
  room.redistribution = {};
  const winnerId = Number(room.winnerId || 0);
  const recipients = room.players.filter((entry) => Number(entry.id) !== winnerId);
  if (winnerId > 0) {
    const winner = state.players.find((player) => player.id === winnerId);
    if (winner) winner.coins = Math.max(0, Number(winner.coins || 0) - Number(room.winningBid || 0));
  }
  if (deficit > 0 && recipients.length > 0) {
    const share = Math.floor(deficit / recipients.length);
    const remainder = deficit % recipients.length;
    recipients.forEach((entry, index) => {
      const amount = share + (index < remainder ? 1 : 0);
      room.redistribution[String(entry.id)] = amount;
      if (entry.id > 0 && amount > 0) {
        const player = state.players.find((candidate) => candidate.id === entry.id);
        if (player) player.coins = Number(player.coins || 0) + amount;
      }
    });
  }
  room.settled = true;
  saveState();
}

function publicAuctionRoom(room) {
  processAuctionRoom(room);
  const players = room.players.map((entry) => {
    const profile = state.players.find((player) => player.id === entry.id);
    return { id: entry.id, displayName: entry.isBot ? entry.name : (profile?.displayName || profile?.login || 'Игрок'), isBot: entry.isBot, coins: profile?.coins || 0, bid: room.bids[String(entry.id)], hasActed: Object.prototype.hasOwnProperty.call(room.bids, String(entry.id)) };
  });
  return { roomId: room.id, tier: room.tier, fieldSeed: room.fieldSeed, clueSeed: room.fieldSeed, status: room.status, round: room.round, roundEndsAt: room.roundEndsAt, serverNow: Date.now(), bids: room.bids, previousBids: room.previousBids, winnerId: room.winnerId, winningBid: room.winningBid, lotValue: room.lotValue, deficit: room.deficit, redistribution: room.redistribution, players };
}

function matchmakingStatus(tier, playerId = 0) {
  const queue = matchmakingQueues.get(String(tier)) || [];
  const started = matchmakingStarted.get(String(tier));
  const room = started ? auctionRooms.get(started.roomId) : null;
  const isStarted = Boolean(room && room.players.some((entry) => entry.id === playerId));
  return { tier: Number(tier), waitingPlayers: queue.length, capacity: MATCHMAKING_CAPACITY, ready: queue.length >= MATCHMAKING_CAPACITY || isStarted, status: isStarted ? 'started' : 'waiting', roomId: isStarted ? room.id : '' };
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
  if (!player.castle) player.castle = { level: 1, buildings: { coin_tower: { level: 1, storedCoins: 0, lastIncomeAt: Date.now() }, alchemy_tower: { level: 1 } } };
  if (!player.castle.buildings.alchemy_tower) player.castle.buildings.alchemy_tower = { level: 1 };
  if (player.castle.buildings.potion_tower && !player.castle.buildings.alchemy_tower.level) player.castle.buildings.alchemy_tower = player.castle.buildings.potion_tower;
  player.castle.towerDefinitions = castleTowerDefinitions();
  if (!player.potions) player.potions = [];
  const tower = player.castle.buildings.coin_tower;
  const elapsedHours = Math.max(0, (Date.now() - Number(tower.lastIncomeAt || Date.now())) / 3600000);
  const incomeTable = castleTowerDefinitions().coin_tower.incomePerHour;
  const incomePerHour = Number(incomeTable[Math.max(0, Math.min(incomeTable.length - 1, Number(tower.level || 1) - 1))] || 100);
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
    if (req.method === 'GET' && url.pathname === '/updates/latest.json') {
      const manifestPath = path.join(UPDATES_DIR, 'latest.json');
      if (!fs.existsSync(manifestPath)) return error(res, 404, 'Манифест обновлений ещё не опубликован');
      res.writeHead(200, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-cache' });
      return res.end(fs.readFileSync(manifestPath));
    }
    if (req.method === 'GET' && parts[0] === 'updates' && parts[1] && parts[1] !== 'latest.json') {
      const filename = path.basename(parts[1]);
      if (filename !== parts[1] || !filename.endsWith('.zip')) return error(res, 400, 'Некорректный файл обновления');
      const updatePath = path.join(UPDATES_DIR, filename);
      if (!fs.existsSync(updatePath)) return error(res, 404, 'Файл обновления не найден');
      res.writeHead(200, { 'content-type': 'application/zip', 'content-length': fs.statSync(updatePath).size, 'cache-control': 'public, max-age=3600' });
      return fs.createReadStream(updatePath).pipe(res);
    }
    if (req.method === 'GET' && url.pathname === '/health') return json(res, 200, { ok: true, serverId: 1, playersOnline: state.players.length, storage: postgres ? 'postgresql-configured' : 'json' });
    if (req.method === 'GET' && url.pathname === '/admin') {
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      return res.end(fs.readFileSync(path.join(__dirname, 'admin.html')));
    }
    if (req.method === 'GET' && parts[0] === 'admin-assets' && parts[1]) {
      const filename = path.basename(parts[1]);
      if (filename !== parts[1]) return error(res, 400, 'Некорректный файл изображения');
      const assetPath = path.join(__dirname, 'admin-assets', filename);
      if (!fs.existsSync(assetPath)) return error(res, 404, 'Изображение не найдено');
      const extension = path.extname(filename).toLowerCase();
      const contentType = extension === '.svg' ? 'image/svg+xml' : extension === '.webp' ? 'image/webp' : 'image/png';
      res.writeHead(200, { 'content-type': contentType, 'cache-control': 'public, max-age=86400' });
      return fs.createReadStream(assetPath).pipe(res);
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
    if (req.method === 'GET' && url.pathname === '/api/v1/admin/castle-towers') {
      if (req.headers['x-admin-key'] !== ADMIN_KEY) return error(res, 403, 'Нужны права администратора');
      return json(res, 200, { towers: castleTowerDefinitions() });
    }
    if (req.method === 'POST' && url.pathname === '/api/v1/admin/castle-towers') {
      if (req.headers['x-admin-key'] !== ADMIN_KEY) return error(res, 403, 'Нужны права администратора');
      const data = await body(req); const towerId = String(data.id || '');
      if (!castleTowerDefinitions()[towerId]) return error(res, 404, 'Башня не найдена');
      const current = castleTowerDefinitions()[towerId];
      if (data.title !== undefined) current.title = String(data.title);
      if (data.description !== undefined) current.description = String(data.description);
      if (Array.isArray(data.upgradeCosts)) current.upgradeCosts = data.upgradeCosts.map((value) => Math.max(0, Number(value) || 0));
      if (Array.isArray(data.incomePerHour)) current.incomePerHour = data.incomePerHour.map((value) => Math.max(0, Number(value) || 0));
      if (Array.isArray(data.potionQualityByLevel)) current.potionQualityByLevel = data.potionQualityByLevel.map((value) => Math.max(1, Math.min(5, Number(value) || 1)));
      saveState(); return json(res, 200, { towers: castleTowerDefinitions() });
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
        const room = createAuctionRoom(tier, [...queue], 0);
        matchmakingStarted.set(tier, { roomId: room.id });
        matchmakingQueues.delete(tier);
        return json(res, 200, { ...snapshot, waitingPlayers: queue.length, ready: true, status: 'started', roomId: room.id });
      }
      return json(res, 200, snapshot);
    }
    if (url.pathname === '/api/v1/matchmaking/skip' && req.method === 'POST') {
      const data = await body(req); const tier = String(Number(data.tier));
      if (!['0', '1', '2'].includes(tier)) return error(res, 400, 'Поле аукциона указано неверно');
      const queue = matchmakingQueues.get(tier) || [];
      if (!queue.includes(player.id)) queue.push(player.id);
      const room = createAuctionRoom(tier, [...queue], Math.max(0, MATCHMAKING_CAPACITY - queue.length));
      matchmakingStarted.set(tier, { roomId: room.id });
      matchmakingQueues.delete(tier);
      return json(res, 200, { ...matchmakingStatus(tier, player.id), waitingPlayers: queue.length, ready: true, status: 'started', roomId: room.id, humanPlayers: queue.length, bots: Math.max(0, MATCHMAKING_CAPACITY - queue.length) });
    }
    if (url.pathname === '/api/v1/matchmaking/leave' && req.method === 'POST') {
      const data = await body(req); const tier = String(Number(data.tier));
      const queue = (matchmakingQueues.get(tier) || []).filter((id) => id !== player.id);
      if (queue.length) matchmakingQueues.set(tier, queue); else matchmakingQueues.delete(tier);
      return json(res, 200, matchmakingStatus(tier, player.id));
    }
    if (parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'auction' && parts[3] === 'rooms' && req.method === 'GET') {
      const room = roomForPlayer(parts[4], player.id);
      if (!room) return error(res, 404, 'Игровая комната не найдена');
      return json(res, 200, publicAuctionRoom(room));
    }
    if (parts[0] === 'api' && parts[1] === 'v1' && parts[2] === 'auction' && parts[3] === 'rooms' && parts[5] === 'bid' && req.method === 'POST') {
      const room = roomForPlayer(parts[4], player.id);
      if (!room || room.status !== 'active') return error(res, 404, 'Аукцион недоступен');
      processAuctionRoom(room);
      if (room.status !== 'active') return json(res, 200, publicAuctionRoom(room));
      if (Object.prototype.hasOwnProperty.call(room.bids, String(player.id))) return error(res, 400, 'Вы уже сделали ставку в этом раунде');
      const data = await body(req); const amount = Number(data.amount);
      if (!Number.isInteger(amount) || amount < 0 || amount > Number(player.coins || 0)) return error(res, 400, 'Ставка должна быть целым числом от 0 до доступного баланса');
      const lotValue = Number(data.lotValue);
      if (!Number.isInteger(lotValue) || lotValue < 0) return error(res, 400, 'Некорректная стоимость лотов');
      if (room.lotValue === null) room.lotValue = lotValue;
      if (room.lotValue !== lotValue) return error(res, 409, 'Стоимость лотов не совпадает с данными комнаты');
      room.bids[String(player.id)] = amount;
      const otherBids = Object.entries(room.bids).filter(([id]) => Number(id) !== player.id).map(([, bid]) => Number(bid));
      const highestOther = otherBids.length ? Math.max(...otherBids) : 0;
      const protection = [2.0, 1.5, 1.3, 1.1, 1.0][Math.max(0, Math.min(4, room.round - 1))];
      if (amount > 0 && highestOther > 0 && amount > Math.ceil(highestOther * protection)) {
        room.previousBids = { ...room.bids }; room.winnerId = player.id; room.winningBid = amount; room.status = 'finished';
        settleAuctionRoom(room);
      }
      saveState();
      return json(res, 200, publicAuctionRoom(room));
    }
    if (req.method === 'GET' && url.pathname === '/api/v1/castle') { const castle = ensureCastle(player); saveState(); return json(res, 200, castle); }
    if (req.method === 'POST' && url.pathname === '/api/v1/castle/collect') {
      const castle = ensureCastle(player); const tower = castle.buildings.coin_tower; const collected = Number(tower.storedCoins || 0);
      player.coins += collected; tower.storedCoins = 0; saveState(); return json(res, 200, { collected, player: publicPlayer(player), castle });
    }
    if (req.method === 'POST' && url.pathname === '/api/v1/castle/upgrade') {
      const castle = ensureCastle(player); const tower = castle.buildings.coin_tower; const definition = castleTowerDefinitions().coin_tower; const cost = Number(definition.upgradeCosts[Math.max(0, Number(tower.level || 1) - 1)] || 0);
      if (Number(tower.level || 1) >= Number(definition.maxLevel || 5)) return error(res, 400, 'Башня уже максимального уровня');
      if (player.coins < cost) return error(res, 400, 'Недостаточно монет для улучшения');
      player.coins -= cost; tower.level += 1; saveState(); return json(res, 200, { cost, player: publicPlayer(player), castle });
    }
    if (req.method === 'POST' && url.pathname === '/api/v1/castle/upgrade-alchemy') {
      const castle = ensureCastle(player); const tower = castle.buildings.alchemy_tower; const definition = castleTowerDefinitions().alchemy_tower; const cost = Number(definition.upgradeCosts[Math.max(0, Number(tower.level || 1) - 1)] || 0);
      if (Number(tower.level || 1) >= Number(definition.maxLevel || 5)) return error(res, 400, 'Башня уже максимального уровня');
      if (player.coins < cost) return error(res, 400, 'Недостаточно монет для улучшения');
      player.coins -= cost; tower.level += 1; saveState(); return json(res, 200, { cost, player: publicPlayer(player), castle });
    }
    if (req.method === 'GET' && url.pathname === '/api/v1/potions') { ensureCastle(player); return json(res, 200, { potions: player.potions }); }
    if (req.method === 'POST' && url.pathname === '/api/v1/potions/craft') {
      const castle = ensureCastle(player); const level = Number(castle.buildings.alchemy_tower.level || 1); const definition = castleTowerDefinitions().alchemy_tower;
      const maxQuality = Number(definition.potionQualityByLevel[Math.max(0, Math.min(4, level - 1))] || level);
      const ingredientIndex = (player.inventory || []).findIndex((item) => item.state === 'inventory' && item.type === 'ingredient' && Number(item.quality || 1) <= maxQuality);
      if (ingredientIndex < 0) return error(res, 400, `Нужен ингредиент качества не выше ${maxQuality}`);
      const ingredient = player.inventory[ingredientIndex];
      if (itemQuantity(ingredient) > 1) ingredient.quantity = itemQuantity(ingredient) - 1;
      else player.inventory.splice(ingredientIndex, 1);
      const potion = { id: id(), recipeId: 'reveal_item', name: 'Зелье откровения', quality: Math.min(Number(ingredient.quality || 1), maxQuality), baseCost: 250 * Math.min(Number(ingredient.quality || 1), maxQuality), type: 'potion', effect: 'Открывает информацию об одном предмете на поле', state: 'inventory', createdAt: new Date().toISOString() };
      player.potions.push(potion); addInventoryItem(player, potion); saveState(); return json(res, 201, { potion, player: publicPlayer(player) });
    }
    if (req.method === 'POST' && url.pathname === '/api/v1/potions/use') {
      const data = await body(req); const index = (player.inventory || []).findIndex((item) => item.id === data.instanceId && item.type === 'potion' && item.state === 'inventory');
      if (index < 0) return error(res, 404, 'Зелье не найдено');
      const potion = player.inventory.splice(index, 1)[0]; player.potions = (player.potions || []).filter((item) => item.id !== potion.id); saveState();
      return json(res, 200, { potion, player: publicPlayer(player) });
    }
    if (req.method === 'POST' && url.pathname === '/api/v1/inventory/sell') {
      const data = await body(req); const index = player.inventory.findIndex((x) => x.id === data.instanceId && x.state === 'inventory');
      if (index < 0) return error(res, 404, 'Предмет не найден в инвентаре');
      const item = player.inventory[index]; const price = Math.max(0, Math.round(Number(item.baseCost ?? item.cost ?? 0))) * itemQuantity(item);
      player.inventory.splice(index, 1); player.coins += price; saveState();
      return json(res, 200, { price, player: publicPlayer(player) });
    }
    if (req.method === 'POST' && url.pathname === '/api/v1/inventory/sell-all-simple') {
      let soldCount = 0; let total = 0;
      player.inventory = (player.inventory || []).filter((item) => {
        const itemType = String(item.type || '').toLowerCase();
        const isSimple = item.state === 'inventory' && !['equipment', 'weapon', 'potion', 'ingredient'].includes(itemType) && !item.gearClassId && !item.gear_class_id;
        if (!isSimple) return true;
        const quantity = itemQuantity(item); soldCount += quantity; total += Math.max(0, Math.round(Number(item.baseCost ?? item.cost ?? 0))) * quantity; return false;
      });
      player.coins += total; saveState(); return json(res, 200, { soldCount, total, player: publicPlayer(player) });
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
      addInventoryItem(player, instance); saveState(); return json(res, 201, instance);
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
      addInventoryItem(player, instance); saveState();
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

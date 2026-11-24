const { spawn } = require('node:child_process');
const assert = require('node:assert/strict');
const WebSocket = require('ws');

const port = 18080;
const dataFile = require('node:path').join(__dirname, `test-runtime-${process.pid}.json`);
const child = spawn(process.execPath, ['index.js'], { cwd: __dirname, env: { ...process.env, PORT: String(port), DATA_FILE: dataFile }, stdio: ['ignore', 'pipe', 'pipe'] });
const base = `http://127.0.0.1:${port}`;

async function request(path, options = {}) {
  for (let i = 0; i < 30; i++) {
    try { return await fetch(base + path, options); } catch { await new Promise((r) => setTimeout(r, 50)); }
  }
  throw new Error('server did not start');
}

(async () => {
  try {
    const health = await request('/health'); assert.equal(health.status, 200);
    const admin = await request('/admin'); assert.equal(admin.status, 200);
    const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
    await new Promise((resolve, reject) => { ws.once('message', (message) => { assert.equal(JSON.parse(message).type, 'connected'); resolve(); }); ws.once('error', reject); });
    ws.close();
    const created = await request('/api/v1/auth/register', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ login: `test_${Date.now()}` }) });
    assert.equal(created.status, 201); const account = await created.json();
    const headers = { authorization: `Bearer ${account.token}`, 'content-type': 'application/json' };
    const grant = await request('/api/v1/inventory/grant-demo-item', { method: 'POST', headers, body: JSON.stringify({ definitionId: 'copper_coin' }) });
    assert.equal(grant.status, 201); const item = await grant.json();
    const listing = await request('/api/v1/market/listings', { method: 'POST', headers, body: JSON.stringify({ instanceId: item.id, price: 99 }) });
    assert.equal(listing.status, 201); const data = await listing.json(); assert.equal(data.price, 99);
    const weaponResponse = await request('/api/v1/inventory/grant-demo-item', { method: 'POST', headers, body: JSON.stringify({ definitionId: 'weapon_staff_mage', quality: 5 }) });
    assert.equal(weaponResponse.status, 201); const weapon = await weaponResponse.json();
    const legendary = await request('/api/v1/legendary-auctions', { method: 'POST', headers, body: JSON.stringify({ instanceId: weapon.id, startPrice: 500, durationHours: 3 }) });
    assert.equal(legendary.status, 201); const auction = await legendary.json();
    const buyerResponse = await request('/api/v1/auth/register', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ login: `buyer_${Date.now()}` }) });
    const buyer = await buyerResponse.json();
    const bid = await request(`/api/v1/legendary-auctions/${auction.id}/bid`, { method: 'POST', headers: { authorization: `Bearer ${buyer.token}`, 'content-type': 'application/json' }, body: JSON.stringify({ amount: 500 }) });
    assert.equal(bid.status, 200);
    const finished = await request(`/api/v1/legendary-auctions/${auction.id}/finish`, { method: 'POST', headers });
    assert.equal(finished.status, 200);
    console.log('SERVER TESTS PASSED');
  } finally { child.kill('SIGTERM'); try { require('node:fs').unlinkSync(dataFile); } catch {} }
})().catch((error) => { console.error(error); child.kill('SIGTERM'); process.exitCode = 1; });

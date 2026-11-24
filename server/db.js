// PostgreSQL adapter подготовлен для следующего режима запуска.
// При отсутствии DATABASE_URL сервер продолжает использовать JSON-прототип.
let Pool;
try { ({ Pool } = require('pg')); } catch { Pool = null; }

function createPool() {
  if (!process.env.DATABASE_URL || !Pool) return null;
  return new Pool({ connectionString: process.env.DATABASE_URL, max: 10, ssl: process.env.DATABASE_SSL === 'true' ? { rejectUnauthorized: false } : undefined });
}

async function checkConnection(pool) {
  if (!pool) return false;
  const client = await pool.connect();
  try { await client.query('SELECT 1'); return true; } finally { client.release(); }
}

async function withTransaction(pool, callback) {
  if (!pool) throw new Error('PostgreSQL не настроен');
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await callback(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally { client.release(); }
}

module.exports = { createPool, checkConnection, withTransaction };

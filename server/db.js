// PostgreSQL adapter подготовлен для следующего режима запуска.
// При отсутствии DATABASE_URL сервер продолжает использовать JSON-прототип.
let Pool;
try { ({ Pool } = require('pg')); } catch { Pool = null; }

function createPool() {
  if (!process.env.DATABASE_URL || !Pool) return null;
  return new Pool({ connectionString: process.env.DATABASE_URL, max: 10, ssl: process.env.DATABASE_SSL === 'true' ? { rejectUnauthorized: false } : undefined });
}

module.exports = { createPool };

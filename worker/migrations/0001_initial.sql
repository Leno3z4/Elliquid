PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS strategies (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL,
  risk TEXT NOT NULL,
  target_apy REAL,
  management_fee_bps INTEGER NOT NULL DEFAULT 0,
  performance_fee_bps INTEGER NOT NULL DEFAULT 0,
  active INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS projects (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  wallet TEXT NOT NULL,
  base_token TEXT NOT NULL,
  quote_token TEXT NOT NULL,
  verified INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS liquidity_requests (
  id TEXT PRIMARY KEY NOT NULL,
  project_id TEXT NOT NULL REFERENCES projects(id),
  strategy_id TEXT NOT NULL REFERENCES strategies(id),
  target_quote TEXT NOT NULL,
  duration_seconds INTEGER NOT NULL,
  max_inventory_bps INTEGER NOT NULL,
  liquidity_fee_bps INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'open',
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS vaults (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  strategy_id TEXT NOT NULL REFERENCES strategies(id),
  asset_symbol TEXT NOT NULL,
  chain_id INTEGER NOT NULL,
  contract_address TEXT,
  tvl TEXT NOT NULL DEFAULT '0',
  active INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS execution_events (
  id TEXT PRIMARY KEY NOT NULL,
  vault_id TEXT REFERENCES vaults(id),
  event_type TEXT NOT NULL,
  tx_hash TEXT,
  payload TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_liquidity_requests_status ON liquidity_requests(status);
CREATE INDEX IF NOT EXISTS idx_execution_events_vault ON execution_events(vault_id);

CREATE TABLE IF NOT EXISTS execution_intents (
  action_key TEXT PRIMARY KEY NOT NULL,
  vault_id TEXT REFERENCES vaults(id),
  action TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'prepared',
  tx_hash TEXT,
  error TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_execution_intents_status ON execution_intents(status);
CREATE INDEX IF NOT EXISTS idx_execution_intents_vault ON execution_intents(vault_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_execution_intents_tx_hash ON execution_intents(tx_hash) WHERE tx_hash IS NOT NULL;

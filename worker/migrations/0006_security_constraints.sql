-- Idempotency writes must have a single owner per wallet/key pair.
CREATE UNIQUE INDEX IF NOT EXISTS idx_idempotency_wallet_key
  ON idempotency_keys(wallet, key);

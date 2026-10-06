ALTER TABLE liquidity_requests ADD COLUMN onchain_request_id INTEGER;
ALTER TABLE liquidity_requests ADD COLUMN last_tx_hash TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_liquidity_requests_onchain_id
  ON liquidity_requests(onchain_request_id)
  WHERE onchain_request_id IS NOT NULL;

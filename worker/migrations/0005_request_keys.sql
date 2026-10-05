ALTER TABLE liquidity_requests ADD COLUMN request_key TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_liquidity_requests_request_key
  ON liquidity_requests(request_key);

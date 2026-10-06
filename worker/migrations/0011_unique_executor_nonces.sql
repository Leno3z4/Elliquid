-- One pending transaction per executor nonce.
-- This prevents concurrent workers from reserving the same nonce for different actions.
CREATE UNIQUE INDEX IF NOT EXISTS idx_execution_intents_executor_nonce
  ON execution_intents(from_address, nonce)
  WHERE from_address IS NOT NULL AND nonce IS NOT NULL;

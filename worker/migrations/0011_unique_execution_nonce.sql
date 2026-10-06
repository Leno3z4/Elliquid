-- Prevent two different execution intents from claiming the same signer nonce.
-- This is a safety rail for concurrent Worker invocations; the loser must retry
-- after the first transaction advances the pending nonce.
CREATE UNIQUE INDEX IF NOT EXISTS idx_execution_intents_from_nonce_unique
  ON execution_intents(from_address, nonce)
  WHERE from_address IS NOT NULL AND nonce IS NOT NULL;

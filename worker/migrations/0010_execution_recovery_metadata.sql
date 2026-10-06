ALTER TABLE execution_intents ADD COLUMN from_address TEXT;
ALTER TABLE execution_intents ADD COLUMN nonce INTEGER;

CREATE INDEX IF NOT EXISTS idx_execution_intents_from_nonce
  ON execution_intents(from_address, nonce)
  WHERE from_address IS NOT NULL AND nonce IS NOT NULL;

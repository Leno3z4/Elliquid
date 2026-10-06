ALTER TABLE execution_intents ADD COLUMN reference_id TEXT;
CREATE INDEX IF NOT EXISTS idx_execution_intents_reference
  ON execution_intents(reference_id)
  WHERE reference_id IS NOT NULL;

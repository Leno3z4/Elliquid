-- Backfill request keys introduced by 0005 before relying on the unique index.
-- Existing request IDs are already unique, so they are safe deterministic keys.
UPDATE liquidity_requests SET request_key = id WHERE request_key IS NULL;

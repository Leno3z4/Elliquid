export interface Env {
  DB: D1Database;
  API_ORIGIN?: string;
  ENVIRONMENT?: string;
  ELYSIUM_RPC_URL?: string;
  MARKETPLACE_ADDRESS?: string;
  EXECUTOR_PRIVATE_KEY?: string;
  EXECUTOR_ADDRESS?: string;
  RECONCILE_BATCH_SIZE?: string;
  MIN_REQUEST_DURATION_SECONDS?: string;
  MAX_REQUEST_DURATION_SECONDS?: string;
  MAX_INVENTORY_BPS?: string;
  MAX_LIQUIDITY_FEE_BPS?: string;
  PUBLIC_RATE_LIMITER: RateLimit;
  WRITE_RATE_LIMITER: RateLimit;
}

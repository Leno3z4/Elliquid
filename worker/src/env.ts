export interface Env {
  DB: D1Database;
  API_ORIGIN?: string;
  ENVIRONMENT?: string;
  ELYSIUM_RPC_URL?: string;
  PUBLIC_RATE_LIMITER: RateLimit;
  WRITE_RATE_LIMITER: RateLimit;
}

# Elliquid API

Cloudflare Worker + Hono + D1 API for Elliquid.

## Local setup

1. Create a D1 database:

    npx wrangler d1 create elliquid-db

2. Copy the returned database ID into `worker/wrangler.jsonc` as `database_id`.

3. Apply migrations:

    npx wrangler d1 migrations apply elliquid-db --remote

4. Start the Worker:

    npm run dev:api

The API exposes:

- `GET /api/health`
- `GET /api/strategies`
- `GET /api/projects`
- `GET /api/liquidity-requests`
- `GET /api/vaults`
- `POST /api/liquidity-requests`

## Database

D1 stores application state and indexed execution history. On-chain contracts remain the authority for user funds, permissions and settlement.

Do not put private keys in D1. The execution worker will use Cloudflare secrets for signing configuration when that layer is introduced.

## Production TODO

- Replace placeholder D1 ID.
- Seed strategy registry.
- Add authentication/signature verification for write endpoints.
- Add contract event indexer.
- Add strategy keeper / execution queue.
- Add durable idempotency keys around transactions.

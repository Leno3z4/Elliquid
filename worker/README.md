# Elliquid API

Cloudflare Worker + Hono + D1 API for Elliquid.

## Local setup

The repository is already configured with the Elliquid D1 database ID.

1. Install dependencies from the repository root:

    npm install

2. Apply all pending D1 migrations:

    npx wrangler d1 migrations apply elliquid-db --remote

3. Start the Worker locally:

    npm run dev:api

For local Worker development, copy `worker/.dev.vars.example` to `worker/.dev.vars` when local variables are needed.

## API

- `GET /api/health`
- `GET /api/chain/status`
- `GET /api/strategies`
- `GET /api/projects`
- `GET /api/liquidity-requests`
- `GET /api/vaults`
- `POST /api/liquidity-requests`
- `POST /api/strategy/evaluate`

## Database

D1 stores application state and indexed execution history. On-chain contracts remain the authority for user funds, permissions and settlement.

Do not put private keys in D1. Execution signing configuration belongs in Cloudflare Secrets when the keeper layer is enabled.

## Strategy engine

`/api/strategy/evaluate` exposes the deterministic risk loop used by the future keeper. It returns a decision without executing capital movement.

The current decisions are:

- `DEPLOY`
- `HOLD`
- `REDUCE`
- `EXIT`

Execution adapters are kept behind explicit contract permissions.

## Chain integration

`/api/chain/status` reads the configured Elysium testnet RPC through viem and returns the observed chain ID and latest block number.

The V2 liquidity adapter does not hard-code a router address. The deployed adapter receives a fixed router address at construction time so the production deployment can be pointed at the actual Elysium AMM selected for Elliquid.

## Production TODO

- Authenticate and signature-verify write endpoints.
- Add contract event indexer.
- Add strategy allocation records and idempotency keys.
- Add keeper / execution queue.
- Deploy and verify Solidity contracts on Elysium testnet.
- Configure the Elysium AMM router and deploy the V2 adapter.

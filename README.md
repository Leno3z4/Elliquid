# Elliquid

**Programmable liquidity marketplace for Elysium.**

Elliquid connects three sides of the liquidity problem:

1. Capital suppliers deposit into managed strategy vaults.
2. Elysium projects request liquidity with explicit size, duration, fee and inventory limits.
3. Strategy execution deploys, monitors and rebalances liquidity according to risk constraints.

The product is designed around one core loop:

`capital -> vault -> strategy -> liquidity -> fees / PnL -> risk decision -> rebalance`

## Stack

- **Web:** Next.js + React + TypeScript
- **Wallet / EVM:** wagmi + viem (being wired into the UI)
- **API:** Hono + TypeScript on Cloudflare Workers
- **Database:** Cloudflare D1 (SQLite) + Drizzle ORM
- **Contracts:** Solidity + Foundry
- **Research later:** Python for strategy research/backtesting
- **Performance later:** Rust only if execution becomes a measured bottleneck

## Repository layout

    app/                    Next.js App Router
    components/             React UI
    lib/                    frontend utilities
    packages/shared/        shared domain types
    worker/                 Hono API + D1 database
    contracts/              Solidity protocol layer

## Local development

Frontend:

    npm install
    npm run dev

API:

    npm run dev:api

The API uses Cloudflare D1. Create the database first and place the returned ID in `worker/wrangler.jsonc`, then apply migrations.

## Runtime architecture

    Browser
      |
      v
    Next.js
      |
      | HTTPS
      v
    Hono / Cloudflare Worker
      |                \
      v                 v
    D1 / Drizzle     Elysium RPC
      |                 |
      v                 v
    indexed state    contracts / AMMs
                        |
                        v
                  strategy execution

The execution engine will be introduced inside the Worker runtime as a separate service boundary, not mixed directly into HTTP handlers.

## Current status

- [x] application shell and dashboard
- [x] strategy vault UX
- [x] project liquidity marketplace UX
- [x] wallet connection / Elysium testnet targeting
- [x] Solidity vault accounting foundation
- [x] liquidity mandate contract
- [x] Cloudflare Worker API foundation
- [x] D1 schema + initial migration
- [ ] seed strategy / project registry
- [ ] authenticated write endpoints
- [x] Elysium chain client + role-checked execution boundary
- [ ] Elysium-compatible AMM adapter (venue-specific; bridge router is not an AMM)
- [x] real wallet transaction execution/reconciliation service (testnet-ready; deployment still required)
- [ ] chain event indexer
- [ ] strategy / allocation engine
- [ ] rebalance keeper
- [ ] testnet deployment (awaiting verified venue + end-to-end test)
- [ ] contract test suite
- [ ] audit hardening

## Safety rule

Elliquid is a capital coordination and execution layer — not a promise of yield.

Mainnet deposits require audited contracts, isolated strategy permissions, explicit loss handling, withdrawal controls, transaction idempotency and operational monitoring.


## Deployment configuration

Core contracts intentionally do not embed Elysium token, router, or owner addresses. Use constructor parameters / deployment environment variables instead. The V2 liquidity adapter takes a venue-specific V2-compatible AMM router that can be rotated through a two-step owner-controlled update; the Elysium bridge router is not an acceptable value because it is a bridge gateway, not an AMM interface.

For Worker execution, configure `MARKETPLACE_ADDRESS`, `EXECUTOR_ADDRESS`, and the `EXECUTOR_PRIVATE_KEY` secret in Cloudflare. Keep the executor wallet dedicated to Elliquid so nonce reservation and transaction recovery cannot collide with unrelated transactions.

The current Elysium testnet defaults are chain ID 99801, RPC `https://testnet-rpc.elysium.kinetiq.xyz`, and native gas HYPE. Mainnet contract addresses are not embedded because the official docs currently mark them as coming at launch.

Execution lifecycle:
`authenticated request -> D1 execution intent -> nonce/hash reservation -> RPC preflight -> sign -> broadcast -> receipt reconciliation -> state transition`.

An uncertain broadcast is left recoverable under the same action key/nonce; the service does not automatically submit a second transaction while the original status is unknown.


## Deployment configuration

See `contracts/REMIX_DEPLOYMENT.md` for the Remix deployment order, configurable parameters, safety boundaries and Elysium-specific integration rules.

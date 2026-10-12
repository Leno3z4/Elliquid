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
- [x] Elliquid-native constant-product AMM core (factory, independent pair pools, bounded multi-hop router; testnet only until audited)
- [x] real wallet transaction execution/reconciliation service (testnet-ready; deployment still required)
- [ ] chain event indexer
- [ ] strategy / allocation engine
- [ ] rebalance keeper
- [ ] Native AMM deployment + end-to-end testnet demo (frontend and contract integration are in the feature branch; deployment is still required)
- [x] Foundry unit and fuzz tests for existing contracts and native AMM core (security review still required)
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


## Native Elliquid AMM (hackathon scope)

Elliquid now has a first-party constant-product pool design rather than requiring Market Lab or another venue to create its pools. The core pieces are:

- `ElliquidPoolFactory`: owner-controlled token allowlist, deterministic token ordering, one pool per pair, per-new-pool fee configuration, bounded on-chain pool pagination and protocol pause.
- `ElliquidPool`: one pair of ERC-20 tokens, LP shares, liquidity add/remove, exact-input swaps, per-pool immutable fees, deadlines and minimum-output checks. The emergency pause stops swaps and new liquidity but keeps LP withdrawals available.
- `ElliquidRouter`: ratio-aware liquidity add with excess-token refunds, LP removal, direct swaps and bounded multi-hop routes (up to four hops). It exposes a V2-compatible liquidity method so the existing vault adapter can be configured against Elliquid's own router rather than an external AMM.
- `components/elliquid-pools.tsx`: reads the factory/pool state from Elysium Testnet and supports allowlisting (factory owner only), pool creation, swap, add liquidity and remove liquidity from a connected wallet.

### Testnet configuration

Deploy the factory and router using the Remix guide in `contracts/REMIX_DEPLOYMENT.md`, then set these public frontend environment values and redeploy the web app:

- `NEXT_PUBLIC_ELLIQUID_POOL_FACTORY_ADDRESS`
- `NEXT_PUBLIC_ELLIQUID_ROUTER_ADDRESS`

Pool listing and quotes are read from contracts, not from placeholder pool metrics. The UI is intentionally disabled until both addresses are configured.

### Security and operational boundary

This is a hackathon/testnet implementation, **not an audited production AMM**. Only allowlist known standard ERC-20s; rebasing, fee-on-transfer and non-standard tokens are unsupported. An AMM pool's spot price must not be used as a lending collateral oracle or the vault's sole source of NAV. Before accepting real deposits, complete external review, stateful invariant/fuzz testing, static analysis, gas/DoS assessment, end-to-end deployment testing and an operational pause/incident plan.

The current native AMM lives in the draft pull request [#4](https://github.com/Leno3z4/Elliquid/pull/4). It is not yet merged or deployed. The separate Market Lab experiment [#2](https://github.com/Leno3z4/Elliquid/pull/2) is not required by this architecture and remains separate.

# Elliquid

**Programmable liquidity marketplace for Elysium.**

Elliquid connects three sides of the liquidity problem:

1. Capital suppliers deposit into managed strategy vaults.
2. Elysium projects request liquidity with explicit size, duration, fee and inventory limits.
3. Strategy execution deploys, monitors and rebalances liquidity according to risk constraints.

The MVP is intentionally adapter-agnostic so Elysium-native AMM integrations can be added without rewriting the capital layer. A future HyperCore adapter can provide hedging and rebalancing once the relevant Elysium/HyperCore write path is available.

## Local development

    npm install
    npm run dev

Open http://localhost:3000.

## Current status

- [x] polished app shell and dashboard
- [x] strategy vault UX
- [x] project liquidity marketplace UX
- [x] wallet connection / Elysium testnet targeting
- [x] vault accounting contract skeleton
- [x] liquidity mandate contract
- [ ] AMM adapter
- [ ] real wallet transactions
- [ ] testnet deployment
- [ ] strategy keeper / rebalance engine
- [ ] audited production contracts

## Product rule

Elliquid is a capital coordination and execution layer — not a promise of yield. All displayed yield figures in the MVP are demo/model values until backed by reproducible testnet performance data.

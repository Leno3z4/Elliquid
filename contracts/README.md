# Elliquid contracts

Hackathon-stage Solidity protocol layer for the Elliquid liquidity marketplace.

## Core contracts

- `ElliquidVault.sol` — single-asset vault with share accounting, isolated strategy execution, adapter allowlisting, loss protection and emergency strategy pause.
- `ElliquidVaultFactory.sol` — governance-controlled vault provisioning.
- `LiquidityMarketplace.sol` — project liquidity mandates with bounded economics and request-key idempotency.
- `StrategyRegistry.sol` — governance registry of approved strategy adapters and risk envelopes.
- `ProjectRegistry.sol` — governance allowlist and metadata registry for liquidity-requesting projects.
- `FeeController.sol` — bounded fee policy and treasury collection boundary.
- `IElliquidAdapter.sol` — adapter execution boundary.
- `V2SingleSidedLiquidityAdapter.sol` — generic V2-compatible adapter; only use with a separately verified AMM router.

## Elysium integration rule

Elysium supports spot AMMs and PropAMMs, but the published testnet router address is the canonical bridge router. It must **not** be passed to `V2SingleSidedLiquidityAdapter`. A venue-specific adapter should only be enabled after the target AMM/PropAMM contract interface and deployment address are independently verified.

## Security status

These contracts are not externally audited. The repository includes Foundry unit tests and CI, but that is not a substitute for an independent security review or adversarial testnet deployment. Keep deposits intentionally small until those steps are complete.

See `REMIX_DEPLOYMENT.md` for deployment order, role separation, configuration boundaries and preflight checks.

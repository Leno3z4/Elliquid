# Elliquid contracts

Hackathon-stage EVM contracts for the Elliquid liquidity marketplace.

## Scope

- ElliquidVault.sol — minimal share-accounting vault with a manager-controlled strategy sync hook.
- LiquidityMarketplace.sol — project-side liquidity mandate registry.
- IElliquidAdapter.sol — adapter surface for AMM execution and later HyperCore-connected execution.

These contracts are **not audited** and are not intended for mainnet deposits. Before mainnet use we need audited ERC-4626-compatible accounting, withdrawal queues, explicit adapter allowlists, role separation, loss handling, pause guardians and strategy-specific permissioning.

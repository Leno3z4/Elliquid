# Elliquid Remix / Testnet Deployment

This is a hackathon-stage deployment guide. Do not use real capital. The contracts are not audited.

## Elysium network values

Use the Kinetiq Elysium testnet:

- Chain ID: 99801 (0x185d9)
- RPC: https://testnet-rpc.elysium.kinetiq.xyz
- Native gas: HYPE
- Explorer: https://elysium.kinetiq.xyz/testnet-explorer

HYPE is native gas on Elysium. It is not the ERC-20 asset constructor argument for ElliquidVault. Vault assets must be an ERC-20 contract.

## Deployment order in Remix

Remix should deploy the production contracts in `contracts/src` directly. The Foundry scripts under `contracts/script` are optional automation helpers and are not required for Remix deployment.

### 1. Deploy control-plane contracts

Deploy these with the same governance owner:

1. `ElliquidVaultFactory`
2. `LiquidityMarketplace`
3. `StrategyRegistry`
4. `ProjectRegistry`
5. `FeeController`

Use a dedicated treasury for `FeeController`. Do not use a user deposit address as treasury.

### 2. Create the vault

Constructor:

| Parameter | Value |
|---|---|
| _asset | The verified ERC-20 you will manage on Elysium testnet |
| _name | Your chosen vault name |
| _symbol | Your chosen vault share symbol |
| _owner | Governance/owner wallet |
| _strategyExecutor | Initial dedicated keeper/executor wallet |

The vault constructor sets the initial executor explicitly.
Immediately after deployment, record the vault address.

### 3. Configure the marketplace and vault

On the marketplace:

- call `startOperatorUpdate(executorWallet)`
- call `acceptOperatorUpdate()`

On the vault:

- call `startStrategyExecutorUpdate(executorWallet)`, then `acceptStrategyExecutorUpdate()`
- call `startPauseGuardianUpdate(guardianWallet)`, then `acceptPauseGuardianUpdate()`
- keep `setMaxAdapterFundingBps` conservative
- only approve verified adapters

The pause guardian can stop strategy execution but cannot unpause it or change economic configuration. Keep this key operationally separate from the owner where possible.

### 4. Deploy an AMM adapter only after the venue is verified

For DeployElliquidAdapter.s.sol, AMM_ROUTER means a verified V2-compatible AMM router.

Do not use the Elysium canonical bridge router as AMM_ROUTER. Kinetiq documents that router for token bridging (outboundTransfer, gateway resolution and L2 token calculation), not V2 liquidity operations.

If the target Elysium venue does not expose the V2 router interface used by V2SingleSidedLiquidityAdapter, do not deploy/use that adapter. Add a venue-specific adapter instead.

After deploying a compatible adapter:

1. On the adapter, call setVaultAllowed(vaultAddress, true).
2. On the vault, call setAdapterAllowed(adapterAddress, true).
3. Set the executor with setStrategyExecutor(executorWallet) when using a dedicated keeper.
4. Keep the funding cap conservative with setMaxAdapterFundingBps(...).

The two allowlists are intentional: the adapter must trust the vault and the vault must trust the adapter.

## Configuration philosophy

The following are product/deployment configuration and can change:

- vault name/symbol
- ERC-20 asset address
- owner
- strategy executor
- marketplace operator
- approved adapter
- venue/router address
- request duration limits
- inventory limits
- liquidity fee limits
- RPC endpoint used by the Worker
- Worker rate limits

The following remain safety boundaries:

- adapter allowlisting
- single-use vault action keys
- two-step ownership transfer
- strategy-loss ceiling
- adapter funding ceiling
- execution-journal state transitions
- executor nonce uniqueness
- transaction-hash reconciliation
- signed API writes and replay protection

Changing configuration must never be treated as equivalent to changing the security model.

## Mutable vs permanent configuration

The design intentionally separates values that may legitimately change from accounting/security invariants.

| Value | Policy |
|---|---|
| Vault ERC-20 asset | **Permanent per vault** — changing it would invalidate share accounting and existing positions. Create another vault for another asset. |
| Vault name / symbol | Identity metadata; changing is unnecessary for the MVP. |
| Vault owner | Mutable via two-step ownership transfer. |
| Strategy executor | Mutable by the vault owner. |
| Pause guardian | Mutable by the vault owner. |
| Deposits / strategy pause | Mutable emergency controls. |
| Approved adapters | Mutable allowlist. |
| Strategy loss limit | Mutable, hard-capped. |
| Adapter funding cap | Mutable, hard-capped. |
| Marketplace operator | Mutable by marketplace owner. |
| Marketplace economic limits | Mutable, hard-capped. |
| Strategy adapter + risk envelope | Mutable by registry owner, within hard ceilings. |
| Registered project status/metadata | Mutable by registry owner. |
| Fee treasury | Mutable by fee-controller owner. |
| Fee rates | Mutable, hard-capped. |
| Fee callers | Mutable allowlist. |
| V2 adapter AMM router | **Mutable through two-step router rotation**; router must be a deployed contract. |
| Safety ceilings / protocol constants | Permanent in code unless a future audited contract version intentionally changes them. |

The goal is that a changed venue, keeper, guardian, treasury, strategy policy or marketplace configuration does not require redeploying the whole protocol. The exceptions are deliberate safety invariants, especially the vault asset.

## Foundry deployment scripts

The deployment flow is intentionally kept to three scripts so it is practical to use while avoiding a monolithic script that exceeds the EIP-170 contract-size limit in Remix.

1. `DeployElliquid.s.sol` — deploys the four non-vault control-plane contracts:
   - `LiquidityMarketplace`
   - `StrategyRegistry`
   - `ProjectRegistry`
   - `FeeController`
   Requires `OWNER` and `TREASURY`.

2. `DeployElliquidFactoryVault.s.sol` — deploys `ElliquidVaultFactory`, creates the vault, installs the pause guardian, and sets the marketplace operator.
   Requires `OWNER`, `MARKETPLACE`, `ASSET`, `EXECUTOR`, `PAUSE_GUARDIAN`, `VAULT_NAME`, `VAULT_SYMBOL`, and `VAULT_KEY`.

3. `DeployElliquidAdapter.s.sol` — deploys the generic V2-compatible adapter.
   Requires `OWNER` and `AMM_ROUTER`.

Run the core control-plane script first, then the factory/vault script using the resulting marketplace address, then the adapter only after a verified V2-compatible AMM router is available.

For Remix, the production contracts under `contracts/src` can still be deployed directly using the deployment order above. The Foundry scripts are optional automation helpers.
   
## Worker secrets

Do not place the executor private key in D1, GitHub, .dev.vars.example, or source code.

For Cloudflare, configure:

- EXECUTOR_PRIVATE_KEY as a Worker secret
- EXECUTOR_ADDRESS as a normal configuration value
- MARKETPLACE_ADDRESS as a normal configuration value

The private key is only used to construct/sign transactions in the authorized deployment or Worker runtime.

## Preflight checklist

Before the first testnet transaction verify:

- wallet is on Elysium chain ID 99801
- executor wallet has HYPE for gas
- marketplace operator() equals the executor
- vault strategyExecutor() equals the executor
- vault asset() equals the intended ERC-20
- vault approvedAdapters(adapter) is true
- adapter allowedVaults(vault) is true
- adapter router is a verified AMM router, not a bridge router
- request limits onchain match or exceed the Worker configuration
- D1 migrations 0001 through 0012 have applied successfully
- the first transaction uses an intentionally tiny test amount

## Security/audit status

This is still hackathon-stage code, not an external audit. The current hardening pass includes:

- two-step ownership transfers
- separate owner/executor/pause-guardian roles
- strategy emergency pause
- adapter allowlists on both vault and adapter
- single-use action keys
- per-call adapter funding cap
- loss circuit breaker
- zero-NAV protection
- request-key idempotency
- bounded marketplace economics
- explicit project allowlisting
- bounded fee policy
- execution journaling and nonce/hash reconciliation in the Worker

Before mainnet, perform an independent Solidity audit and adversarial integration testing against every real AMM/PropAMM adapter.

## What is deliberately not claimed

Elliquid does not currently claim a production Elysium AMM address, HyperCore hedge, or mainnet deployment address. Kinetiq's public technical documentation describes the Elysium AMM/PropAMM lifecycle and HyperCore integration, but exact production venue addresses/interfaces must be verified before an adapter is enabled.

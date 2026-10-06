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

### 1. Deploy ElliquidVault

Constructor:

| Parameter | Value |
|---|---|
| _asset | The verified ERC-20 you will manage on Elysium testnet |
| _name | Your chosen vault name |
| _symbol | Your chosen vault share symbol |
| _owner | Governance/owner wallet |

The constructor initially sets strategyExecutor = owner.

Immediately after deployment, record the vault address.

### 2. Deploy LiquidityMarketplace

Constructor:

| Parameter | Value |
|---|---|
| _owner | The governance/owner wallet |

Then call setOperator(executorWallet).

Use the dedicated keeper/executor address, not a browser wallet that holds user funds.

### 3. Deploy an AMM adapter only after the venue is verified

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

## Worker secrets

Do not place the executor private key in D1, GitHub, .dev.vars.example, or source code.

For Cloudflare, configure:

- EXECUTOR_PRIVATE_KEY as a Worker secret
- EXECUTOR_ADDRESS as a normal configuration value
- MARKETPLACE_ADDRESS as a normal configuration value

The private key is only used to construct/sign the transaction in the Worker runtime.

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
- D1 migrations 0001 through 0011 have applied successfully
- the first transaction uses an intentionally tiny test amount

## What is deliberately not claimed

Elliquid does not currently claim a production Elysium AMM address, HyperCore hedge, or mainnet deployment address. Kinetiq's public technical documentation describes the Elysium AMM/PropAMM lifecycle and HyperCore integration, but exact production venue addresses/interfaces must be verified before an adapter is enabled.

# Elliquid Native AMM — Testnet Deployment

This guide covers Elliquid's own pool system. It does not use Market Lab or another protocol's router.

## Scope

- **ElliquidPoolFactory**: token allowlist, unique pool registry, bounded pool pagination, fee configuration and emergency pause.
- **ElliquidPool**: constant-product swaps, LP share tokens, liquidity add/remove, slippage bounds and reserve accounting.
- **ElliquidRouter**: token approvals and refunds, single/multi-hop swaps (up to four hops), quotes, and LP management.

The pricing curve is x * y = k. The pool fee is deducted from input for the swap calculation and stays in the pool for liquidity providers. A fee set on a pool never changes; the factory's default only applies to new pools.

## Elysium testnet

- Chain ID: 99801
- RPC used in the repo: https://testnet-rpc.elysium.kinetiq.xyz
- Native gas asset: HYPE
- Explorer: [Elysium testnet explorer](https://elysium.kinetiq.xyz/testnet-explorer)

Example test assets to verify on-chain before use:

| Token | Address | Decimals | Notes |
|---|---|---:|---|
| Bridged test USDC | 0x7D29d8047B905000459c0E80c34a26CeedcB47b2 | 6 | Testnet representation, not real US dollars |
| WHYPE candidate | 0xCD57F65c2B0e5881CFC2E609F7CD53b746E1F234 | Query on-chain | An independent Elysium testnet tracker currently indexes this address as WHYPE; it is not an official allowlist |

These are testnet assets, not dollar-backed guarantees or mainnet assets. An independent tracker lists the USDC and WHYPE addresses above, but its labels are not proof of authenticity: https://elysium-testnet.vercel.app/. Before allowlisting either token, inspect its explorer contract and on-chain bytecode, call symbol() and decimals(), and test balanceOf / transfer / transferFrom with a minimal amount. Confirm mint/admin controls and that it is the expected asset. Do not allowlist based on symbol alone.

## Deploy with Foundry (repeatable)

The repository includes `script/DeployElliquidAMM.s.sol`. Set these values in a local, untracked Foundry environment file or shell environment:

- `AMM_OWNER`: dedicated Elysium testnet admin address.
- `AMM_DEFAULT_FEE_BPS`: `30` for a 0.30% default fee (100 = 1.00%, the immutable safety ceiling).

Run from the `contracts` directory:

```sh
forge script script/DeployElliquidAMM.s.sol:DeployElliquidAMM --rpc-url elysium_testnet --broadcast --private-key "$ELYSIUM_TESTNET_PRIVATE_KEY"
```

Use a testnet-only deployer, set `AMM_OWNER` to the wallet or multisig that should own the factory, and keep `ELYSIUM_TESTNET_PRIVATE_KEY` in your shell/secret manager—not in GitHub source, `.env.example`, frontend variables or chat. If explorer verification is properly configured, add `--verify` and its API key as a local environment secret; otherwise verify each contract through the explorer workflow. Record both deployed addresses from the broadcast output. The deployer and AMM_OWNER should normally be the same test wallet for the demo.

## Recommended first demo: deploy a complete testnet stack

The repository includes `ElliquidTestnetToken.sol` and `script/DeployElliquidAMMDemo.s.sol`. The demo script deploys the factory, router, two clearly labelled fake tokens, creates their pool, and seeds it with starter liquidity. This avoids depending on an unverified token address just to exercise the user journey.

Run from the `contracts` directory with a **testnet-only** wallet:

```sh
export AMM_OWNER=0xYOUR_TESTNET_WALLET_ADDRESS
export AMM_DEFAULT_FEE_BPS=30
forge script script/DeployElliquidAMMDemo.s.sol:DeployElliquidAMMDemo --rpc-url elysium_testnet --broadcast --private-key "$ELYSIUM_TESTNET_PRIVATE_KEY"
```

`AMM_OWNER` must be the address derived from the same private key supplied to Foundry. Keep `ELYSIUM_TESTNET_PRIVATE_KEY` out of source control and chat. Do not store it in any `NEXT_PUBLIC_*` variable. The script mints 1,000,000 `eUSD-TEST` (6 decimals) and 1,000,000 `eAST` (18 decimals) to the owner, then seeds the pool with 10,000 of each. These are valueless demo assets with owner-controlled minting; **they are not USDC, not backed by dollars, and not suitable for real funds**.

Foundry prints the deployment transactions and receipt logs. Record the factory, router, pool, and both token addresses. In the frontend/Vercel preview environment, set only these public addresses:

- `NEXT_PUBLIC_ELLIQUID_POOL_FACTORY_ADDRESS`: factory deployment address.
- `NEXT_PUBLIC_ELLIQUID_ROUTER_ADDRESS`: router deployment address.

Redeploy the preview after setting those variables. In the Pools tab, enter the token addresses from the broadcast log to select the pre-seeded pool. Verify the factory `getPool(eUSD-TEST, eAST)`, read the pool reserves, do a small swap, and remove a small portion of LP shares. Test a complete add → swap → remove journey before recording the demo.

This is a demo deployment recipe, not a mainnet recipe. The mintable demo token contract should never be used as a production asset.

### Windows PowerShell option

If you are using Windows and Foundry is installed, import a dedicated testnet key into Foundry's encrypted keystore instead of putting the raw key in a command:

```powershell
cast wallet import elliquid-demo --interactive
$env:AMM_OWNER = "0xYOUR_TESTNET_WALLET_ADDRESS"
$env:AMM_DEFAULT_FEE_BPS = "30"
forge script script/DeployElliquidAMMDemo.s.sol:DeployElliquidAMMDemo --rpc-url elysium_testnet --account elliquid-demo --sender $env:AMM_OWNER --broadcast
```

The imported account must match AMM_OWNER. Use only a dedicated testnet wallet; never share the private key or keystore password. If Foundry is not installed, use Remix and deploy the factory/router first, but the demo tokens still require compiling and deploying the demo token contracts.

## Remix deployment order

Compile with Solidity 0.8.24 and the optimizer enabled.

1. Deploy ElliquidPoolFactory with:
   - initialOwner: your dedicated Elysium testnet admin wallet.
   - initialFeeBps: 30 (0.30%, below the hard 1% ceiling).
2. Deploy ElliquidRouter with _factory equal to the new factory address.
3. Using the factory owner wallet, call setTokenAllowed(token, true) for each verified test token.
4. Call createPool(tokenA, tokenB) on the factory. Pool creation is permissionless, but both tokens must already be allowlisted.
5. Read getPool(tokenA, tokenB) in the factory. The returned address must be nonzero; confirm token0, token1 and feeBps on the pool.
6. Approve the router to spend small amounts of both tokens from the liquidity provider wallet. Call router addLiquidity with desired amounts in each token's raw units, conservative minimum amounts, minShares greater than zero, the provider as recipient, and a deadline around five minutes ahead.
7. Confirm the pool's getReserves, totalSupply and the provider's LP-share balanceOf.
8. Approve the router for a small input amount. Call getAmountsOut to obtain a quote, then swapExactTokensForTokens using an output minimum below the quote to allow for small price movement. Do not set the minimum to zero in a user-facing app.
9. Test removal by approving the router to spend LP shares and calling removeLiquidity. Confirm both underlying token balances return to the wallet.
10. Test the emergency pause. It must block swaps and new liquidity, while LP withdrawal should still work. Unpause after the test.

Do not paste private keys into the repository, deployment scripts, frontend variables or chat. The factory owner has token-onboarding, fee-for-new-pools and pause authority. Use a multisig/timelock for a real launch, not a developer's hot wallet.

## Frontend environment

Set these public contract addresses only after deployment and verification:

- NEXT_PUBLIC_ELLIQUID_POOL_FACTORY_ADDRESS
- NEXT_PUBLIC_ELLIQUID_ROUTER_ADDRESS

These addresses are public; signing keys are not. Empty values should leave pool actions disabled.

## Security limitations (not production approval)

- This implementation supports standard, non-rebasing ERC-20 assets only. Fee-on-transfer, rebasing, callback-dependent, and otherwise non-standard tokens are unsupported.
- Pool creation is limited to tokens explicitly allowlisted by the factory owner. Existing pools continue to work if a token is later removed from the allowlist.
- There is no oracle or TWAP, no flash-swap interface, no permit flow, and no automated liquidity-management strategy.
- Exact-input swap quotes can move before inclusion. The router enforces the user's minimum output and deadline, but does not protect against a manipulated external price.
- The reserve registry is paginated and router paths are capped at four hops; clients must not iterate an unbounded pool list in a single RPC response.
- CI and unit tests are not an independent audit. Keep this testnet-only until invariant/fuzz testing, malicious-token tests, manual review and an independent security audit are completed.

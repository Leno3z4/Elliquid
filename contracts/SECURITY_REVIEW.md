# Elliquid Security Review — Hackathon Pass

Date: 2026-10-06

## Scope

Reviewed the Solidity control plane currently in `contracts/src` and the Worker execution model at a design level. This is an internal hardening review, **not an independent security audit**.

## Current contract inventory

- ElliquidVault
- ElliquidVaultFactory
- LiquidityMarketplace
- StrategyRegistry
- ProjectRegistry
- FeeController
- V2SingleSidedLiquidityAdapter
- IElliquidAdapter

## High-priority controls now present

- two-step ownership transfer on governance-controlled contracts
- separated vault owner and strategy executor
- independent pause guardian for strategy execution
- guardian can pause but cannot unpause or change economics
- adapter allowlisting on the vault
- vault allowlisting on the V2 adapter
- single-use adapter action keys
- per-call adapter funding ceiling
- loss circuit breaker
- zero-NAV protection
- safe low-level ERC-20 transfer/approve handling in the vault
- request-key idempotency
- bounded marketplace duration/inventory/fee settings
- project registration allowlist
- bounded fee policy
- Worker transaction journal, nonce uniqueness and uncertain-broadcast reconciliation

## Findings / remaining risks

### 1. AMM integration is not yet production-ready — HIGH

Elysium documentation confirms that spot AMMs and PropAMMs are part of the ecosystem, but the published Elysium testnet router is the canonical bridge router. It is not a V2 AMM router.

**Action:** do not configure `V2SingleSidedLiquidityAdapter` with the bridge router. A venue-specific adapter must be written only after the AMM/PropAMM interface and deployed address are verified.

### 2. NAV reporting is a trusted-adapter boundary — HIGH

An approved adapter can report managed NAV. A compromised or incorrectly configured adapter could overstate NAV and affect share pricing.

**Current mitigation:** only explicitly approved adapters can report NAV, loss is capped, zero NAV is blocked while shares exist, and adapters are separately allowlisted.

**Before mainnet:** bind NAV reporting to strategy position accounting or an independently verifiable valuation path.

### 3. Adapter execution is trusted strategy code — HIGH

The vault intentionally delegates assets to an approved adapter. A malicious adapter can lose or misroute funds within the configured funding cap.

**Mitigation:** two-sided allowlisting, per-call cap, single-use action key, executor separation and emergency strategy pause.

**Before mainnet:** adversarial-test every adapter with malicious router/token behavior.

### 4. Withdrawal liquidity can be temporarily unavailable — MEDIUM

Withdrawals are immediate only when the vault has enough idle ERC-20 liquidity. Managed positions can make withdrawals revert.

**MVP policy:** clearly expose this limitation in the UI.

**Before mainnet:** implement a tested withdrawal queue / strategy unwind path if strategies can remain invested for meaningful periods.

### 5. FeeController is policy infrastructure, not automatic performance accounting — MEDIUM

The fee controller caps and collects explicitly approved fee amounts. It does not independently calculate performance fees or management fees.

**Action:** keep fee calculation off until strategy accounting is proven; never represent configured rates as fees already earned.

### 6. Mainnet venue and asset addresses are intentionally unresolved — HIGH

No production Elysium AMM, PropAMM, or managed ERC-20 address is hard-coded.

**Action:** deployment must fail closed until those addresses are verified from official venue documentation or deployment artifacts.

## Test status

Foundry build and tests are run by GitHub Actions on every main-branch push. The suite covers vault accounting, adapter idempotency/funding limits, strategy pause, marketplace idempotency/limits, project registry and fee controls.

## Mainnet gate

Do not accept production deposits until:

1. the real venue adapter is verified and tested;
2. an independent Solidity review is completed;
3. malicious ERC-20/router tests pass;
4. Worker execution reconciliation is tested against dropped/unknown transactions;
5. withdrawal behavior is tested with deployed positions;
6. ownership, executor, guardian and treasury addresses are independently reviewed;
7. all testnet configuration is recorded and reproducible.

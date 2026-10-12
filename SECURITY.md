# Elliquid security invariants

This is a hackathon-stage system. The invariants below are treated as requirements, not optional hardening.

## API

- Write endpoints must authenticate a wallet-controlled signature.
- Signed writes expire after a five-minute timestamp window; the database idempotency record is retained for 24 hours.
- Every signed write carries an Idempotency-Key, and the signature commits to the request payload hash.
- A wallet cannot reuse an idempotency key for a different payload or endpoint.
- Replaying a completed request returns the original response instead of creating a second resource.
- Project-side writes must match the signed wallet to the stored project owner.

## Execution

- Every keeper action gets a unique action key.
- The action key is persisted before a transaction is prepared.
- A broadcast transaction must record its transaction hash.
- Retries use the existing execution journal rather than creating a second action.
- A post-broadcast failure is never treated as permission to blindly rebroadcast; it must be reconciled against chain state.

## Contracts

- Vault strategy execution is separated from ownership.
- Only explicitly approved adapters can execute against a vault.
- Vault action keys are single-use on-chain.
- Adapter allowances are reset before and after execution.
- Loss reporting is restricted to approved adapters and bounded by a configured circuit breaker.
- Liquidity requests use creator-scoped idempotency keys.
- Liquidity request expiry can only occur after the recorded expiry timestamp.
- Filled requests can only be filled by the configured operator.
- Ownership transfer uses a two-step acceptance flow.

## Never do

- Never store private signing keys in D1.
- Never trust a wallet address supplied in a request body as authentication.
- Never retry a transaction blindly after a timeout or unknown receipt.
- Never allow the frontend to choose an arbitrary adapter or router address.
- Never present modeled yield as realized performance.

Before mainnet deposits, the contracts and execution system need formal threat modeling, complete unit/integration/fuzz testing, operational key separation, withdrawal controls, adapter audits and independent security review.


## Native AMM scope and limitations

The native AMM implementation is hackathon/testnet software and has not received an independent security audit. Passing CI or local fuzz tests is necessary but insufficient evidence of safety.

- **Token support is allowlisted.** Only allowlist known Elysium Testnet ERC-20s after checking the contract, metadata, ownership/upgrade properties and transfer behavior. The factory checks for deployed code, but cannot prove a token is honest.
- **Supported tokens:** standard ERC-20s with exact, non-rebasing transfers only. Fee-on-transfer and rebasing assets are unsupported. Balance-delta checks are intended to fail closed when transfer amounts are non-standard.
- **Pricing:** each pool is a constant-product AMM. The initial default fee is 30 bps (0.30%); governance can set a fee for future pools up to a hard cap of 100 bps (1.00%). Existing pools retain immutable fees.
- **Initial price:** the first liquidity provider determines the initial token ratio. The ratio is not independently price-discovered or oracle-verified. Seed with an intentionally chosen ratio and test amounts.
- **Swap protection:** swaps require a deadline and minimum output. The router limits routes to four hops and rejects repeated path tokens. UI quotes are indicative, so users must review the transaction and minimum output before signing.
- **Emergency pause:** the factory owner can stop pool creation, swaps and additional liquidity. LP withdrawals remain enabled during pause. The owner is a privileged role that should be a multisig for a serious deployment.
- **Liquidity provider risk:** LPs are exposed to price movement, impermanent loss, low liquidity, token contract risk and loss of a token's market value.
- **No oracle guarantees:** pool spot prices must not be used as a trusted oracle, collateral valuation source or sole source of vault NAV.
- **Vault integration is incomplete:** the existing deployed vault does not value native LP shares or automatically unwind them before user withdrawals. Do not send vault capital into AMM pools through the existing adapter until a separate end-to-end integration proves share accounting, NAV, loss handling and withdrawals.

## Required before production funds

- Independent review of pool, router, factory, vault and strategy code.
- Static analysis (for example, Slither) and triage of every finding.
- Extended fuzz/stateful invariant testing for LP share math, reserve accounting, paths, rounding, donations, pauses, approvals, malformed tokens and reverting recipients.
- End-to-end testnet runs using verified tokens: factory/router deploy; allowlist; pair create; seed; swap both directions; add/remove liquidity; pause/unpause; retry failing transactions.
- Review compiler and static-analysis warnings, deployed bytecode size, dependency audit findings, RPC rate behavior and operational logs.
- Multisig-controlled owner, written pause/unpause procedure and key-compromise response.
- Verify deployed bytecode and constructor parameters; keep addresses and transaction hashes in a versioned release record.
- Separate design/security review of pool-aware vault accounting before enabling any strategy adapter.

## Native AMM test coverage in CI

The Foundry suite covers pair creation, allowlists, pair ordering/duplicate rejection, liquidity add/remove, direct and multi-hop swaps, slippage/deadline behavior, pause behavior, fee constraints, donation reconciliation, plus fuzzed constant-product and atomic-slippage properties. These tests cover selected scenarios only and do not prove absence of exploitable bugs.

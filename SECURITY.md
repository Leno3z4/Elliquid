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

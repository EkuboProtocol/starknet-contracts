# Ekubo STRK20 swap anonymizer

This package contains the stateless helper used by a STRK20 privacy pool to execute exact-input
Ekubo swaps. A single invocation may split its input across several routes, and every route may
contain several hops.

## Security model and assumptions

- The privacy pool withdraws the exact public input amount to this contract and calls
  `privacy_invoke` atomically. It consumes the returned `OpenNoteDeposit` in the same transaction.
- The helper is permissionless, has no storage and has no administrator. The caller and router are
  intentionally supplied at invocation time.
- Tokens must implement the standard Starknet ERC-20 behavior. The helper checks the amount it
  actually receives against `minimum_received`, but rebasing tokens, callback tokens and other
  non-standard balance semantics are outside the supported token model.
- No user or protocol balances are meant to remain in this contract between transactions. Tokens
  transferred directly to this address are not attributed to an owner and may be consumed by a
  later permissionless invocation.
- The deployed Router and Core revisions used in production are part of the audit and release
  compatibility matrix.

## Enforced invariants

- Input and output tokens are non-zero and distinct, and the input amount is non-zero.
- Every split and route is non-empty, every split amount is non-zero, and split amounts sum exactly
  to the withdrawn input.
- Every route is token-contiguous and terminates in the declared output token.
- Every Router node uses `sqrt_ratio_limit = 0`, and any input left on the Router causes a revert.
- The Router's aggregate output and the amount actually received by this contract must both satisfy
  `minimum_received`.
- The returned open-note deposit contains only the output balance increase from this invocation.

## Build and test

From this directory:

```sh
scarb --profile release build
snforge test
```

The release process must record the source commit, privacy dependency revision, Cairo/Scarb
versions, Sierra class hash and compiled class hash. The deployed class hash must be reproduced from
the audited commit before either the Sepolia or mainnet address is added to the interface.

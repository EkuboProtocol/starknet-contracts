# Swap anonymizer source audit — 2026-09-09

## Scope and conclusion

Reviewed the entire `src/ekubo_swap_anonymizer.cairo` helper at baseline
`d5431b133179a1c1074d7b4d9be50225f6f858db`, then reviewed and tested the input-accounting
fix in this revision. This is a source review with executable adversarial tests, not a
formal verification or an independent third-party audit.

One low-severity availability issue was reproduced and fixed. No fund-loss issue was
identified within the supported model: standard ERC-20 tokens, the reviewed Ekubo
Router/Core behavior, and an authenticated privacy-pool transaction that atomically
withdraws input, invokes the helper and consumes its returned deposit. These conditions
are essential; the permissionless helper does not authenticate arbitrary routers,
tokens, extensions or callers.

The review includes calldata validation, token accounting, checked arithmetic, external
call boundaries, approvals, Router/Core settlement, the pinned privacy server's note
consumption, and deployment compatibility. AMM mathematics, the privacy proof system,
wallet signing and compiler correctness were not independently audited.

## A-01: Router input donations can deny service (low, fixed)

**Baseline:** After swapping, the helper called `Router.clear(input)` and required the
returned value to be zero. The shared Router is permissionless and may already hold
input-token donations. One donated unit therefore caused a fully filled, otherwise
valid swap to revert with `IN_TOKEN_NOT_CLEARED`. A reverted transaction leaves the
pre-existing donation in place, so retries also fail until someone clears the Router.
An attacker can repeat the donation. No victim funds are lost; anyone can remove the
donation through the public clear function.

**Reproduction:** Deploy the actual Core, Router and Positions contracts, fund three
pools, prefund the helper with 100 input units, and mint one input unit to the Router.
A 60/40 split across multihop/direct routes reverts at the baseline assertion. The
same setup succeeds without the donation. The baseline reproduction passed before
changing production source.

**Fix:** Read the Router input balance before funding it, then require the same balance
after settlement. For standard tokens, `before + input - consumed == before` requires
consumption of exactly this invocation's input. Existing donations remain on the Router;
partial fills still revert. The external ABI, statelessness and output accounting are
unchanged.

**Evidence:** `router_input_donation_does_not_block_valid_swap`, reverse-direction
split/multihop settlement, `real_privacy_pool_rolls_back_partial_fill`, and 64 fuzz
runs of `split_accounting_preserves_router_donations` pass. The deployed class must be
replaced because this is a production-code change; see `DEPLOYMENT.md` for the release
record.

## Invariants and review results

| Area | Result and evidence |
| --- | --- |
| Route authorization | Nonzero router/tokens/input; distinct endpoints; nonempty routes/splits; positive splits; continuity and terminal output checked before transfers. Existing invalid-route/zero-value tests cover these branches. Pool-key validity, extension behavior and skip-ahead semantics are delegated to Core. |
| Exact input | Checked `u128` split sum equals declared input. Explicit overflow rejection test passes. Every Router node uses the extreme-price default (`sqrt_ratio_limit = 0`); balance conservation rejects incomplete input consumption. |
| Output accounting | Credit is `min(actual balance increase, Router clear result)`, positive, representable as `u128`, and at least the caller's `u256` minimum. Helper donations are excluded. Router output donations are unowned and may be credited by the public clear operation. Overflow, zero-output and shortfall tests pass. |
| Settlement | The real Router pays first-hop input and withdraws terminal output through Core. Core's lock requires all token deltas to settle; intermediate-hop debt cannot survive a successful lock. Tests exercise both swap directions and split/multihop routing. |
| Approvals | Only actual credited output is approved to the immediate caller; transfer/approve false returns revert. A real Privacy server pulls the output and consumes its allowance. False-return and allowance tests pass. |
| Atomicity | Real Privacy + Router + Core tests verify input restoration, unchanged Core token balances, zero residual Router/helper swap funds, zero allowance and absent note after slippage, partial-fill and wrong-note-token failures. |
| Open note | Real Privacy validates note existence, open salt, zero prior amount and token equality before `transfer_from`. Success test checks that the stored note amount exactly equals pool output received, excluding a seven-unit helper donation. |
| Arithmetic/serialization | ABI types constrain input/splits to `u128`, minimum to `u256`; sum, balance subtraction and output conversion are checked. Exact return type is `Span<OpenNoteDeposit>`, consumed by production Privacy with trailing-data validation. Both `u128` overflow boundaries have explicit tests. |
| Authority/lifecycle | No storage, admin, upgrade, withdraw or recovery entrypoints. No balances should be deliberately left across transactions. Direct calls and donated input are permissionless by design. |

## External calls and supported-token limits

The helper calls input `balanceOf` and `transfer`, Router `multi_multihop_swap`, input
`balanceOf` again, output `balanceOf`, Router `clear_minimum` (which calls output
`balanceOf`/`transfer`), output `balanceOf` again, and output `approve`. Privacy then
calls the token to pull the returned deposit. All are relevant trust boundaries.

The existing nested-output-transfer regression verifies that nested proceeds cannot
inflate the outer note through the balance-delta window. It does **not** establish
safety for arbitrary hooks during input transfer, balance reads, extensions or approval.
The helper has no reentrancy guard. A malicious token/router can lie about balances,
move funds or callback; callback and rebasing tokens remain unsupported. Privacy's own
reentrancy guard protects its server execution, not every external helper path.

Transfer-tax checks in helper tests cover only the Router-to-helper leg. The pinned
Privacy `checked_transfer_from` checks the available balance, allowance and boolean
return, not the recipient's balance increase. A token taxing that final leg could
undercollateralize a note. Therefore fee-on-transfer tokens are also unsupported end
to end, even when helper-level shortfall tests pass. Test tokens implement both Cairo
ERC-20 naming conventions because Router and Privacy use different dispatcher names.

Leaving a helper output allowance unconsumed across transactions breaks the intended
atomic lifecycle. Authentication of the caller's note, router, routes, amount and
minimum belongs to the privacy proof/wallet flow. The helper itself does not enforce
identity, replay protection, quote expiry, route count limits or privacy of public swap
amounts. Large routes may exhaust transaction resources and revert at the caller's cost.
Slippage protection is aggregate; a zero minimum deliberately permits any positive output.

## Verification and limits

With Scarb/Cairo 2.20.0 and Foundry 0.62.1:

- Release build and package formatting pass.
- 23 tests pass, none ignored; the accounting fuzz test runs 64 cases.
- Tests use actual locally deployed Router, Core, Positions and the production Privacy
  server pinned to `3dfe66fe2b59d7b95709ec719547fa88b8ef63f9`.
- Privacy integration injects action-bound proof facts using Foundry's cheatcode and
  mints pre-existing pool balances. It tests server execution and rollback, not proof
  generation, client note ownership or a signed wallet transaction. Event ciphertext is
  dummy test data.
- The test runner warns that `snforge_std` 0.59.0 is older than its recommended version;
  all exercised cheatcodes and tests pass. Dependency workspace-profile warnings remain.

Live read-only verification at mainnet block **14589163** found:

| Contract | Class hash |
| --- | --- |
| Baseline helper | `0x753c2562f67422bfdfb8c57e079bb1cdcfcbb8067693f53161964e1281ae504` |
| Router | `0x5fdb47de4edfd5983f6a82a1beeb1aab2b69d3674b90730aa1693d94d73f0d3` |
| Core | `0x423df19e032f2d9bf9bb5bc1ea96db2b06d4c752c8c130cba7d577eed1de20a` |

The Router's `core` storage matches the Core address in `DEPLOYMENT.md`. These are
on-chain identity checks; the local integration suite is not a mainnet fork and does
not independently reproduce the historical Router/Core class hashes. Compatibility
with those deployed implementations and a real STRK20 wallet/prover remain integration
limits. No signed end-to-end private swap was performed in this audit.

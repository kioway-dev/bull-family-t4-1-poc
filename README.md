# Bull Family T4-1 — Proof of Concept

## Finding

The `Agreements` contract (`0x84C6D5dAf99BC65ed3A1D26Ca88ffa834D143999`,
Robinhood Chain, chain id 4663) lets **anyone** call `poke()`, and the
documented 10-minute hold is **not continuous**: a `call_gte` / `call_lte`
condition only needs to be true for one instant when poked, can be false for
the whole 10 minutes, and true again for one instant at release time — and
`release()` then pays in full.

The documentation promises a `call_gte` / `call_lte` condition "must stay true
for 10 minutes, Bull's keeper records it". On-chain, `poke(id, idx)` records
`heldSince = block.timestamp` when the condition is currently true (and records
nothing when false), a second poke does not reset the clock, and `release()`
only checks that `heldSince` was set at least 600 seconds ago and that the
condition is currently true. The keeper cannot close this gap, because the poke
is permissionless: anyone — including the payee themself — can poke before the
keeper ever looks.

## What this proves

`testPokeIsPermissionlessAndHoldIsNotContinuous` in
`test/Agreements.t.sol` (fork of Robinhood mainnet at pinned block 116262502):

1. Create a `call_gte` agreement against a controllable mock value (starts 0,
   condition false). `poke` by a random address succeeds and records nothing
   (`heldSince` stays 0).
2. Set the mock to 100 (condition true for an instant). The **payee themself**
   pokes — succeeds, `heldSince` is set.
3. Set the mock to 0 (condition false for the whole 10 minutes). Warp +600 s.
   `release` while currently false reverts.
4. Set the mock to 100 again (true for a single instant at release time).
   `release` **succeeds and pays the payee the full 0.001 ETH**.

Complementary tests in the same file: `testCallGteHold` (release at 599 s hold
reverts, at 601 s succeeds), `testCallGteHoldResets` (a second poke does not
reset the clock), `testReleaseRequiresCurrentTruth`.

## How to run

```sh
forge test --fork-url https://rpc.mainnet.chain.robinhood.com -vv
```

Requires Foundry (tested with 1.9.0) and network access to the public
Robinhood Chain RPC. The fork is pinned to block 116262502 inside the test.
Expected result: **33/33 tests pass**.

To run only the headline test:

```sh
forge test --fork-url https://rpc.mainnet.chain.robinhood.com --match-test testPokeIsPermissionlessAndHoldIsNotContinuous -vv
```

## Notes

- This is a fork test only. No real funds move anywhere: all actors are
  throwaway addresses funded with `vm.deal` on the fork.
- `test/ApiTxs.sol` contains signed `createAgreement` calldata and fee-quote
  signatures captured from live Bull API responses (read-only tx-builder
  outputs). They are single-use, expired test fixtures — not secrets.
- Impact today is $0: there are no open agreements and the Agreements
  contract holds 0 ETH, so nothing can be released against the rules right now.
  The bug is real and proven; the funds at risk are what the program judges.

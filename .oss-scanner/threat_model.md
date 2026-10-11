# Threat model — Deeptrade Core

## What this project does and where untrusted input enters

Deeptrade Core is a Sui Move package that wraps DeepBook spot trading: it charges and settles protocol fees, runs a treasury of protocol-owned DEEP that can cover DeepBook fees for users, and prices exposure to that treasury against Pyth oracles and on-chain DeepBook pool data.

Untrusted input enters through every `public` / `entry` function in `packages/deeptrade-core/sources/`. Callers choose arguments and object arguments inside a programmable transaction block (PTB). Shared objects (treasury, fee config, multisig config, tickets) are reachable by anyone. Pyth price feeds and DeepBook pool state are adversarial inputs for coverage-fee pricing; see `docs/oracle-pricing-security.md`.

## Components that matter most / least

**Highest priority (funds, admin, pricing):**

- `treasury.move` — protocol-owned DEEP reserves and withdrawals
- `fee.move` / `fee_manager.move` — fee schedules, unsettled fees, settlement to protocol
- `oracle.move` — dual-price (Pyth + pool) validation for coverage fees
- `order.move` / `swap.move` — user trading entry points that charge fees
- `ticket.move` — timelock tickets for sensitive admin actions
- `multisig_config.move` — on-chain multisig guarantee for admin
- Version / admin paths that can enable or disable protocol versions

**Still in scope (rounding / loyalty accounting):**

- `loyalty.move`, `math.move`, `helper.move`, `pool.move`, `admin.move`

**Out of scope for this scanner:**

- `examples/` and `scripts/` (TypeScript multisig / admin transaction builders)
- DeepBook and Pyth package internals (integration assumptions with them remain in scope)
- Frontend, indexer, and off-chain services

## How to exercise it

The Docker image ends with the test-fork dependency pins already applied (same swap as `.github/workflows/move_test.yml`). From `/src` with no network:

```bash
sui move test --lint --path packages/deeptrade-core
```

Add new reproducers as `test_scenario` tests under `packages/deeptrade-core/tests/` (grouped by area: `admin/`, `core/`, `fee/`, `helpers/`, `loyalty/`). Prefer a minimal failing unit test over a full end-to-end PTB when demonstrating a bug.

## How you rate severity

- **Critical** — theft or permanent lock of treasury or user funds; bypass of the on-chain multisig or timelock that lets a non-authorized party perform a privileged action.
- **High** — fee evasion or systematic overcharging at material scale; oracle / pool price manipulation that causes the protocol to undercharge for DEEP coverage (reserve drain) or overcharge users.
- **Medium** — bounded rounding leaks; griefing or DoS of shared objects that blocks honest users without direct fund theft.
- **Low** — incorrect gas estimates, misleading events, or documentation-only issues with no fund impact.

## Anything to leave alone

- A compromised multisig signer (trusted role by design); focus on whether the on-chain checks can be bypassed without that compromise.
- DeepBook or Pyth bugs that do not involve how this package consumes their outputs.
- Findings already identified and marked resolved in the MoveBit audit (October 2025) under `audits/`, unless you can show a remaining exploitable instance.
- The commented-out dual dependency blocks in `Move.toml` (dev-only; production pins are the active ones until the Dockerfile swaps them for tests).

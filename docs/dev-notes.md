# Dev Notes

Short operational notes for developers: deployment, upgrade, and development tools for `deeptrade-core` package.

## Deployment

1. Go to `packages/deeptrade-core` directory (`cd packages/deeptrade-core/`)
2. Set `address` to `0x0` in `Move.toml`
3. Publish:
   ```bash
   sui client publish --gas-budget 220000000 --skip-dependency-verification
   ```
4. Copy the new package `address` into `packages/deeptrade-core/Move.toml`
5. Update `examples/constants.ts` with new:
   - `DEEPTRADE_CORE_PACKAGE_ID`
   - `ADMIN_CAP_OBJECT_ID`
   - `TREASURY_OBJECT_ID`
6. Add DEEP coins to reserves if needed:
   ```bash
   ts-node examples/treasury/deposit-into-reserves.ts
   ```

## Upgrade

1. Go to `packages/deeptrade-core` directory (`cd packages/deeptrade-core/`)
2. Set `address` to `0x0` in `Move.toml`
3. Verify compatibility:
   ```bash
   sui client upgrade --dry-run --verify-compatibility --upgrade-capability <UPGRADE_CAP_ID> --gas-budget 1000000000
   ```
4. Dry run upgrade (without `--verify-compatibility`):
   ```bash
   sui client upgrade --dry-run --upgrade-capability <UPGRADE_CAP_ID> --gas-budget 1000000000
   ```
5. Upgrade:
   ```bash
   sui client upgrade --upgrade-capability <UPGRADE_CAP_ID> --gas-budget 1000000000
   ```
6. Set `address` in `Move.toml` to the new package address (from contract upgrade tx effects)
7. Build:
   ```bash
   sui move build
   ```
8. (Optional) Update `examples/constants.ts` IDs if they changed

## Treasury Operations (Admin Only)

1. Run `examples/treasury/get-charged-fee-info.ts` to get the list of coins with charged fees (coverage fees and protocol fees).
2. Run `examples/treasury/admin-withdraw-all-coins-coverage-fee.ts` to withdraw all coins coverage fees (coverage fees charged in output coin of each swap and for limit/market orders in SUI).
3. Run `examples/treasury/admin-withdraw-protocol-fee.ts` to withdraw all protocol fees (protocol fees charged in SUI, pool creation fees charged in DEEP).
4. Run `examples/treasury/withdraw-all-deep-reserves.ts` to withdraw all DEEP coins from reserves.

## Development Tools

### Lines of Code Analysis

Analyze and count lines of code across all Deeptrade Core package modules:

```bash
node scripts/count-loc.js [--help for options]
```

The script provides a detailed breakdown by module and calculates effective lines of code. It analyzes both source files and test files separately.

Example: `🎯 Effective LoC (sources only): 1,234 lines`

## Development notes

Use `sui move build --lint` for linting - enables additional linting checks beyond the default linters

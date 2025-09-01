# Dev Notes

Short operational notes for developers: deployment, upgrade, and development tools for `deeptrade-core` package.

## Deployment

1. Go to `packages/deeptrade-core` directory (`cd packages/deeptrade-core/`)
2. Set `address` to `0x0` in `Move.toml`
3. Publish:
   ```bash
   sui client publish --gas-budget 420000000
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
3. (optionally) In case it's update, that requires force update all clients and disable previous version, bump `CURRENT_VERSION` in `packages/deeptrade-core/helper.move`.
4. Make sure that `env` is set in `Move.lock` (or legacy `published_at` present in `Move.toml`).
5. Verify compatibility:
   ```bash
   sui client upgrade --dry-run --verify-compatibility --upgrade-capability <UPGRADE_CAP_ID> --gas-budget 1000000000
   ```
6. Dry run upgrade (without `--verify-compatibility`):
   ```bash
   sui client upgrade --dry-run --upgrade-capability <UPGRADE_CAP_ID> --gas-budget 1000000000
   ```
7. Upgrade:
   ```bash
   sui client upgrade --upgrade-capability <UPGRADE_CAP_ID> --gas-budget 1000000000
   ```
8. Set `address` in `Move.toml` to the new package address (from contract upgrade tx effects)
9. Build:
   ```bash
   sui move build
   ```
10. (Optional) Update `examples/constants.ts` IDs if they changed

## Running Tests

This section describes how to run the test suite for the `deeptrade-core` package. For information on generating coverage reports, see the "Test Coverage Reports" section below.

We prefer using remote dependencies in `[dependencies]` section of `Move.toml`, to ensure that we
maintain clarity for external observers and avoid potential integrity issues that could arise from
using modified local versions of dependencies in long-term.

The core issue affecting testing is a Sui compiler bug ([Sui issue #23173](https://github.com/MystenLabs/sui/issues/23173)) that prevents the project from building when development dependencies are active (uncommented).

Therefore, running tests always requires temporarily uncommenting these dependencies.

### Manual Testing Steps

1.  **Uncomment Dependencies**: In `packages/deeptrade-core/Move.toml`, find the `[dev-dependencies]` section and uncomment the lines for `deepbook` and `Pyth`.

2.  **Run Tests**: From the root of the project, run the test command.
    - To run all tests:
      ```bash
      (cd packages/deeptrade-core && sui move test)
      ```
    - To run specific tests, you can add a filter string that matches the test function name:
      ```bash
      (cd packages/deeptrade-core && sui move test <FILTER_STRING>)
      ```

3.  **Re-comment Dependencies**: After testing is complete, remember to comment the `[dev-dependencies]` in `Move.toml` back out to avoid build issues.

## Test Coverage Reports

There are three ways to generate and view test coverage reports. The automated scripts are recommended for convenience and reliability.

### Method 1: Automated Terminal Summary (Recommended)

This script runs all tests, generates coverage data, and prints a summary directly in your terminal. It handles dependency management for you.

1.  **Run the script:**
    ```bash
    sh scripts/run-coverage.sh
    ```
2.  **Review the summary:** The script will print a summary table of test coverage.
3.  **(Optional) Explore manually:** The script also generates the necessary coverage data. You can then manually inspect the coverage for any specific module. For example:
    ```bash
    (cd packages/deeptrade-core && sui move coverage source --module pool)
    ```

### Method 2: Automated HTML Report Generation

This method is ideal for detailed reviews or for providing reports to auditors. It generates a full, browsable HTML coverage report.

1.  **Prerequisite: Install `aha`**: This tool converts terminal output to HTML. You only need to do this once.
    - On macOS: `brew install aha`
    - On Debian/Ubuntu: `sudo apt-get install aha`
2.  **Run the script:**
    ```bash
    sh scripts/generate-coverage-report.sh
    ```
3.  **View the Report:** The script will generate a `coverage-reports` directory and provide a command to start a local web server to view the files. Open the `index.html` file in your browser to see the report.

### Method 3: Manual Coverage Analysis

If you prefer to run everything manually, follow these steps:

1.  **Uncomment Dependencies**: In `packages/deeptrade-core/Move.toml`, find the `[dev-dependencies]` section and uncomment the lines for `deepbook` and `Pyth`.

2.  **Run Tests with Coverage**: From the root of the project, run the test command with the `--coverage` flag.

    ```bash
    (cd packages/deeptrade-core && sui move test --coverage)
    ```

3.  **Re-comment Dependencies**: After testing is complete, remember to comment the `[dev-dependencies]` in `Move.toml` back out.

4.  **View Coverage Results**:
    - For a summary:
      ```bash
      (cd packages/deeptrade-core && sui move coverage summary)
      ```
    - For a specific module:
      ```bash
      (cd packages/deeptrade-core && sui move coverage source --module pool)
      ```

## Treasury Operations (Admin Only)

1. Run `examples/treasury/get-charged-fee-info.ts` to get the list of coins with charged fees (coverage fees and protocol fees).
2. Run `examples/ticket/admin-withdraw-all-coins-coverage-fee.ts` to withdraw all coins coverage fees (coverage fees charged in output coin of each swap and for limit/market orders in SUI).
3. Run `examples/ticket/admin-withdraw-protocol-fee.ts` to withdraw all protocol fees (protocol fees charged in SUI, pool creation fees charged in DEEP).
4. Run `examples/ticket/admin-withdraw-all-deep-reserves.ts` to withdraw all DEEP coins from reserves.

## Development Tools

### Multisig Testing Tool

For testing contract endpoints that require multisig authorization, use the multisig testing tool:

```bash
npm run test:multisig <transaction-bytes>
```

This tool automates the multisig transaction flow by:

1. Signing the transaction with all configured signers
2. Combining the signatures
3. Executing the final transaction

The tool uses the multisig configuration from `examples/multisig/multisig.ts`. Useful for rapid testing of multisig-protected endpoints during development.

### Lines of Code Analysis

Analyze and count lines of code across all Deeptrade Core package modules:

```bash
node scripts/count-loc.js [--help for options]
```

The script provides a detailed breakdown by module and calculates effective lines of code. It analyzes both source files and test files separately.

Example: `🎯 Effective LoC (sources only): 1,234 lines`

## Development notes

Use `sui move build --lint` for linting - enables additional linting checks beyond the default linters

### Package Address Workaround

The `deeptrade_core` address in `packages/deeptrade-core/Move.toml` is set to `0x1` as a workaround for a Sui compiler bug that creates namespace conflicts when a package and its dependencies share module names ([Sui issue #22194](https://github.com/MystenLabs/sui/issues/22194)). Our package and its `deepbook` dependency both contain `math`, `pool`, and `order` modules.

While developers typically set a package's address to `0x0` for local development, we use `0x1` to prevent build failures.

**Important**: This address must be changed to `0x0` before deploying or upgrading the package.

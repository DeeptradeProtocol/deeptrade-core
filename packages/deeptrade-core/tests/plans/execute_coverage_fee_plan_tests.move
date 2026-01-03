#[test_only]
module deeptrade_core::execute_coverage_fee_plan_tests;

use deepbook::balance_manager::BalanceManager;
use deepbook::balance_manager_tests::create_acct_and_share_with_funds;
use deeptrade_core::dt_order::{
    execute_coverage_fee_plan,
    get_coverage_fee_plan,
    assert_coverage_fee_plan_eq
};
use deeptrade_core::fee::calculate_deep_reserves_coverage_order_fee;
use deeptrade_core::treasury::{Self, Treasury};
use std::unit_test::assert_eq;
use sui::coin::mint_for_testing;
use sui::sui::SUI;
use sui::test_scenario::{begin, end, return_shared};
use sui::test_utils::destroy;

// === Constants ===
const ALICE: address = @0xAAAA;
const SUI_MULTIPLIER: u64 = 1_000_000_000; // SUI has 9 decimals
const DEEP_MULTIPLIER: u64 = 1_000_000; // DEEP has 6 decimals
const SUI_PER_DEEP: u64 = 37_815_000_000;

#[test]
fun coverage_fee_from_both_wallet_and_balance_manager() {
    // Test-specific constants
    let deep_from_reserves = 40_000 * DEEP_MULTIPLIER; // 40,000 DEEP taken from treasury
    let balance_manager_sui = 500 * SUI_MULTIPLIER; // 500 SUI in BM
    let wallet_sui_amount = 2000 * SUI_MULTIPLIER; // 2000 SUI in wallet

    // Calculate expected values based on get_coverage_fee_plan logic
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        SUI_PER_DEEP,
        deep_from_reserves,
    ); // Coverage fee in SUI
    let expected_from_wallet = coverage_fee - balance_manager_sui; // Remaining from wallet
    let expected_from_bm = balance_manager_sui; // 500 SUI from balance manager

    let mut scenario = begin(ALICE);

    // Step 1: Setup treasury
    scenario.next_tx(ALICE);
    {
        treasury::init_for_testing(scenario.ctx());
    };

    // Step 2: Setup balance manager with initial SUI
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        balance_manager_sui,
        &mut scenario,
    );

    // Step 3: Create wallet SUI coin
    scenario.next_tx(ALICE);
    let wallet_sui_coin = mint_for_testing<SUI>(wallet_sui_amount, scenario.ctx());

    // Step 4: Create CoverageFeePlan using get_coverage_fee_plan
    let fee_plan = get_coverage_fee_plan(
        deep_from_reserves, // deep_from_reserves (amount of DEEP taken from treasury)
        false, // is_pool_whitelisted
        SUI_PER_DEEP, // sui_per_deep (from get_coverage_fee_plan tests)
        wallet_sui_amount, // SUI in wallet
        balance_manager_sui, // SUI in balance manager
    );

    // Verify the CoverageFeePlan is correct before execution
    assert_coverage_fee_plan_eq(
        fee_plan,
        expected_from_wallet,
        expected_from_bm,
        true, // user_covers_fee
    );

    // Step 5: Execute the test
    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(
            balance_manager_id,
        );
        let mut sui_coin = wallet_sui_coin;

        // Record initial balances
        let initial_bm_sui_balance = balance_manager.balance<SUI>();
        let initial_wallet_sui_balance = sui_coin.value();

        // Verify there is no SUI coverage fee in the treasury
        assert_eq!(treasury.has_deep_reserves_coverage_fee<SUI>(), false);

        // Execute coverage fee plan
        execute_coverage_fee_plan(
            &mut treasury,
            &mut balance_manager,
            &mut sui_coin,
            &fee_plan,
            scenario.ctx(),
        );

        // Step 6: Verify results

        // Verify treasury coverage fee increased by total fee amount
        let final_treasury_coverage_fee = treasury.get_deep_reserves_coverage_fee_balance<SUI>();
        assert_eq!(
            final_treasury_coverage_fee,
            fee_plan.from_wallet_cfp() + fee_plan.from_balance_manager_cfp(),
        );

        // Verify balance manager SUI balance decreased by expected amount
        let final_bm_sui_balance = balance_manager.balance<SUI>();
        assert_eq!(
            final_bm_sui_balance,
            initial_bm_sui_balance - fee_plan.from_balance_manager_cfp(),
        );

        // Verify wallet SUI coin decreased by expected amount
        let final_wallet_sui_balance = sui_coin.value();
        assert_eq!(
            final_wallet_sui_balance,
            initial_wallet_sui_balance - fee_plan.from_wallet_cfp(),
        );

        // Cleanup
        destroy(sui_coin);
        return_shared(treasury);
        return_shared(balance_manager);
    };

    scenario.end();
}

#[test]
fun coverage_fee_from_wallet_only() {
    // Test-specific constants
    let deep_from_reserves = 25_000 * DEEP_MULTIPLIER; // 25,000 DEEP taken from treasury
    let balance_manager_sui = 0; // No SUI in balance manager
    let wallet_sui_amount = 2000 * SUI_MULTIPLIER; // 2000 SUI in wallet

    // Calculate expected values based on get_coverage_fee_plan logic
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        SUI_PER_DEEP,
        deep_from_reserves,
    ); // Coverage fee in SUI
    let expected_from_wallet = coverage_fee; // All from wallet since BM is empty
    let expected_from_bm = 0; // Nothing from balance manager

    let mut scenario = begin(ALICE);

    // Step 1: Setup treasury
    scenario.next_tx(ALICE);
    {
        treasury::init_for_testing(scenario.ctx());
    };

    // Step 2: Setup balance manager with no SUI
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        balance_manager_sui,
        &mut scenario,
    );

    // Step 3: Create wallet SUI coin
    scenario.next_tx(ALICE);
    let wallet_sui_coin = mint_for_testing<SUI>(wallet_sui_amount, scenario.ctx());

    // Step 4: Create CoverageFeePlan using get_coverage_fee_plan
    let fee_plan = get_coverage_fee_plan(
        deep_from_reserves, // deep_from_reserves (amount of DEEP taken from treasury)
        false, // is_pool_whitelisted
        SUI_PER_DEEP, // sui_per_deep
        wallet_sui_amount, // SUI in wallet
        balance_manager_sui, // SUI in balance manager
    );

    // Verify the CoverageFeePlan is correct before execution
    assert_coverage_fee_plan_eq(
        fee_plan,
        expected_from_wallet,
        expected_from_bm,
        true, // user_covers_fee
    );

    // Step 5: Execute the test
    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(
            balance_manager_id,
        );
        let mut sui_coin = wallet_sui_coin;

        // Record initial balances
        let initial_bm_sui_balance = balance_manager.balance<SUI>();
        let initial_wallet_sui_balance = sui_coin.value();

        // Verify there is no SUI coverage fee in the treasury
        assert_eq!(treasury.has_deep_reserves_coverage_fee<SUI>(), false);

        // Execute coverage fee plan
        execute_coverage_fee_plan(
            &mut treasury,
            &mut balance_manager,
            &mut sui_coin,
            &fee_plan,
            scenario.ctx(),
        );

        // Step 6: Verify results

        // Verify treasury coverage fee increased by total fee amount
        let final_treasury_coverage_fee = treasury.get_deep_reserves_coverage_fee_balance<SUI>();
        assert_eq!(final_treasury_coverage_fee, fee_plan.from_wallet_cfp());

        // Verify balance manager SUI balance remains unchanged (no SUI was taken)
        let final_bm_sui_balance = balance_manager.balance<SUI>();
        assert_eq!(final_bm_sui_balance, initial_bm_sui_balance);

        // Verify wallet SUI coin decreased by expected amount
        let final_wallet_sui_balance = sui_coin.value();
        assert_eq!(
            final_wallet_sui_balance,
            initial_wallet_sui_balance - fee_plan.from_wallet_cfp(),
        );

        // Cleanup
        destroy(sui_coin);
        return_shared(treasury);
        return_shared(balance_manager);
    };

    scenario.end();
}

#[test]
fun coverage_fee_from_balance_manager_only() {
    // Test-specific constants
    let deep_from_reserves = 15_000 * DEEP_MULTIPLIER; // 15,000 DEEP taken from treasury
    let balance_manager_sui = 2000 * SUI_MULTIPLIER; // 2000 SUI in balance manager
    let wallet_sui_amount = 0; // No SUI in wallet

    // Calculate expected values based on get_coverage_fee_plan logic
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        SUI_PER_DEEP,
        deep_from_reserves,
    ); // Coverage fee in SUI
    let expected_from_wallet = 0; // Nothing from wallet since wallet is empty
    let expected_from_bm = coverage_fee; // All from balance manager

    let mut scenario = begin(ALICE);

    // Step 1: Setup treasury
    scenario.next_tx(ALICE);
    {
        treasury::init_for_testing(scenario.ctx());
    };

    // Step 2: Setup balance manager with SUI
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        balance_manager_sui,
        &mut scenario,
    );

    // Step 3: Create wallet SUI coin (empty)
    scenario.next_tx(ALICE);
    let wallet_sui_coin = mint_for_testing<SUI>(wallet_sui_amount, scenario.ctx());

    // Step 4: Create CoverageFeePlan using get_coverage_fee_plan
    let fee_plan = get_coverage_fee_plan(
        deep_from_reserves, // deep_from_reserves (amount of DEEP taken from treasury)
        false, // is_pool_whitelisted
        SUI_PER_DEEP, // sui_per_deep
        wallet_sui_amount, // SUI in wallet
        balance_manager_sui, // SUI in balance manager
    );

    // Verify the CoverageFeePlan is correct before execution
    assert_coverage_fee_plan_eq(
        fee_plan,
        expected_from_wallet,
        expected_from_bm,
        true, // user_covers_fee
    );

    // Step 5: Execute the test
    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(
            balance_manager_id,
        );
        let mut sui_coin = wallet_sui_coin;

        // Record initial balances
        let initial_bm_sui_balance = balance_manager.balance<SUI>();
        let initial_wallet_sui_balance = sui_coin.value();

        // Verify there is no SUI coverage fee in the treasury
        assert_eq!(treasury.has_deep_reserves_coverage_fee<SUI>(), false);

        // Execute coverage fee plan
        execute_coverage_fee_plan(
            &mut treasury,
            &mut balance_manager,
            &mut sui_coin,
            &fee_plan,
            scenario.ctx(),
        );

        // Step 6: Verify results

        // Verify treasury coverage fee increased by total fee amount
        let final_treasury_coverage_fee = treasury.get_deep_reserves_coverage_fee_balance<SUI>();
        assert_eq!(final_treasury_coverage_fee, fee_plan.from_balance_manager_cfp());

        // Verify balance manager SUI balance decreased by expected amount
        let final_bm_sui_balance = balance_manager.balance<SUI>();
        assert_eq!(
            final_bm_sui_balance,
            initial_bm_sui_balance - fee_plan.from_balance_manager_cfp(),
        );

        // Verify wallet SUI coin remains unchanged (no SUI was taken)
        let final_wallet_sui_balance = sui_coin.value();
        assert_eq!(final_wallet_sui_balance, initial_wallet_sui_balance);

        // Cleanup
        destroy(sui_coin);
        return_shared(treasury);
        return_shared(balance_manager);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = deeptrade_core::dt_order::EInsufficientFee)]
fun insufficient_fee_aborts() {
    // Test-specific constants
    let deep_from_reserves = 60_000 * DEEP_MULTIPLIER; // 60,000 DEEP taken from treasury
    let balance_manager_sui = 100 * SUI_MULTIPLIER; // 100 SUI in balance manager
    let wallet_sui_amount = 100 * SUI_MULTIPLIER; // 100 SUI in wallet

    // Calculate expected values based on get_coverage_fee_plan logic
    let coverage_fee = calculate_deep_reserves_coverage_order_fee(
        SUI_PER_DEEP,
        deep_from_reserves,
    ); // Coverage fee in SUI
    let total_available = balance_manager_sui + wallet_sui_amount; // 200 SUI total

    // Verify that total available is less than required coverage fee
    assert!(total_available < coverage_fee);

    let mut scenario = begin(ALICE);

    // Step 1: Setup treasury
    scenario.next_tx(ALICE);
    {
        treasury::init_for_testing(scenario.ctx());
    };

    // Step 2: Setup balance manager with insufficient SUI
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        balance_manager_sui,
        &mut scenario,
    );

    // Step 3: Create wallet SUI coin with insufficient amount
    scenario.next_tx(ALICE);
    let wallet_sui_coin = mint_for_testing<SUI>(wallet_sui_amount, scenario.ctx());

    // Step 4: Create CoverageFeePlan using get_coverage_fee_plan
    let fee_plan = get_coverage_fee_plan(
        deep_from_reserves, // deep_from_reserves (amount of DEEP taken from treasury)
        false, // is_pool_whitelisted
        SUI_PER_DEEP, // sui_per_deep
        wallet_sui_amount, // SUI in wallet
        balance_manager_sui, // SUI in balance manager
    );

    // Verify the CoverageFeePlan indicates insufficient funds
    assert_coverage_fee_plan_eq(
        fee_plan,
        0, // from_wallet (should be 0 when insufficient)
        0, // from_balance_manager (should be 0 when insufficient)
        false, // user_covers_fee (should be false when insufficient)
    );

    // Step 5: Execute the test - this should abort with EInsufficientFee
    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(
            balance_manager_id,
        );
        let mut sui_coin = wallet_sui_coin;

        // Execute coverage fee plan - this should abort
        execute_coverage_fee_plan(
            &mut treasury,
            &mut balance_manager,
            &mut sui_coin,
            &fee_plan,
            scenario.ctx(),
        );

        // Cleanup
        destroy(sui_coin);
        return_shared(treasury);
        return_shared(balance_manager);
    };

    scenario.end();
}

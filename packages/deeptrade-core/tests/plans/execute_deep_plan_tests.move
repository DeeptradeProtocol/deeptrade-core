#[test_only]
module deeptrade_core::execute_deep_plan_tests;

use deepbook::balance_manager::BalanceManager;
use deepbook::balance_manager_tests::create_acct_and_share_with_funds;
use deeptrade_core::dt_order::{execute_deep_plan, get_deep_plan, assert_deep_plan_eq};
use deeptrade_core::treasury::{Self, Treasury};
use std::unit_test::assert_eq;
use sui::coin::mint_for_testing;
use sui::test_scenario::{begin, end, return_shared};
use sui::test_utils::destroy;
use token::deep::DEEP;

// === Constants ===
const ALICE: address = @0xAAAA;
const DEEP_MULTIPLIER: u64 = 1_000_000;

#[test]
fun deep_from_both_wallet_and_treasury_reserves() {
    // Test-specific constants
    let deep_required = 5_000 * DEEP_MULTIPLIER; // 5,000 DEEP total needed
    let balance_manager_deep = 1_000 * DEEP_MULTIPLIER; // 1,000 DEEP in BM
    let wallet_deep_amount = 2_000 * DEEP_MULTIPLIER; // 2,000 DEEP in wallet
    let treasury_deep_amount = 10_000 * DEEP_MULTIPLIER; // 10,000 DEEP in treasury

    // Calculate expected values based on get_deep_plan logic
    let user_deep_total = balance_manager_deep + wallet_deep_amount;
    let expected_from_wallet = wallet_deep_amount; // Take all from wallet
    let expected_from_treasury = deep_required - user_deep_total; // Remaining needed from treasury

    let mut scenario = begin(ALICE);

    // Step 1: Setup treasury with DEEP reserves
    scenario.next_tx(ALICE);
    {
        treasury::init_for_testing(scenario.ctx());
    };

    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let treasury_deep_coin = mint_for_testing<DEEP>(treasury_deep_amount, scenario.ctx());
        treasury.deposit_into_reserves(treasury_deep_coin);
        return_shared(treasury);
    };

    // Step 2: Setup balance manager with initial DEEP
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        balance_manager_deep,
        &mut scenario,
    );

    // Step 3: Create wallet DEEP coin
    scenario.next_tx(ALICE);
    let wallet_deep_coin = mint_for_testing<DEEP>(wallet_deep_amount, scenario.ctx());

    // Step 4: Create DeepPlan using get_deep_plan
    let deep_plan = get_deep_plan(
        false, // not whitelisted
        deep_required, // total DEEP needed
        balance_manager_deep, // DEEP in balance manager
        wallet_deep_amount, // DEEP in wallet
        treasury_deep_amount, // DEEP in treasury reserves
    );

    // Verify the DeepPlan is correct before execution
    assert_deep_plan_eq(
        deep_plan,
        expected_from_wallet,
        balance_manager_deep,
        expected_from_treasury,
        true, // deep_reserves_cover_order
    );

    // Step 5: Execute the test
    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(
            balance_manager_id,
        );
        let mut deep_coin = wallet_deep_coin;

        // Record initial balances
        let initial_treasury_balance = treasury.deep_reserves();
        let initial_bm_balance = balance_manager.balance<DEEP>();
        let initial_wallet_balance = deep_coin.value();

        // Execute deep plan
        execute_deep_plan(
            &mut treasury,
            &mut balance_manager,
            &mut deep_coin,
            &deep_plan,
            scenario.ctx(),
        );

        // Step 6: Verify results

        // Verify treasury reserves decreased by expected amount
        let final_treasury_balance = treasury.deep_reserves();
        assert_eq!(
            final_treasury_balance,
            initial_treasury_balance - deep_plan.from_deep_reserves(),
        );

        // Verify wallet coin decreased by expected amount
        let final_wallet_balance = deep_coin.value();
        assert_eq!(final_wallet_balance, initial_wallet_balance - deep_plan.from_user_wallet());

        // Verify balance manager balance increased by total amount
        let final_bm_balance = balance_manager.balance<DEEP>();
        assert_eq!(
            final_bm_balance,
            initial_bm_balance + deep_plan.from_user_wallet() + deep_plan.from_deep_reserves(),
        );

        // Cleanup
        destroy(deep_coin);
        return_shared(treasury);
        return_shared(balance_manager);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = deeptrade_core::dt_order::EInsufficientDeepReserves)]
fun insufficient_deep_reserves_aborts() {
    // Test-specific constants
    let deep_required = 5_000 * DEEP_MULTIPLIER; // 5,000 DEEP total needed
    let balance_manager_deep = 1_000 * DEEP_MULTIPLIER; // 1,000 DEEP in BM
    let wallet_deep_amount = 2_000 * DEEP_MULTIPLIER; // 2,000 DEEP in wallet
    let treasury_deep_amount = 1_000 * DEEP_MULTIPLIER; // Only 1,000 DEEP in treasury (insufficient)

    let mut scenario = begin(ALICE);

    // Step 1: Setup treasury with insufficient DEEP reserves
    scenario.next_tx(ALICE);
    {
        treasury::init_for_testing(scenario.ctx());
    };

    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let treasury_deep_coin = mint_for_testing<DEEP>(treasury_deep_amount, scenario.ctx());
        treasury.deposit_into_reserves(treasury_deep_coin);
        return_shared(treasury);
    };

    // Step 2: Setup balance manager with initial DEEP
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        balance_manager_deep,
        &mut scenario,
    );

    // Step 3: Create wallet DEEP coin
    scenario.next_tx(ALICE);
    let wallet_deep_coin = mint_for_testing<DEEP>(wallet_deep_amount, scenario.ctx());

    // Step 4: Create DeepPlan using get_deep_plan
    let deep_plan = get_deep_plan(
        false, // not whitelisted
        deep_required, // total DEEP needed
        balance_manager_deep, // DEEP in balance manager
        wallet_deep_amount, // DEEP in wallet
        treasury_deep_amount, // DEEP in treasury reserves (insufficient)
    );

    // Verify the DeepPlan indicates insufficient reserves
    assert_deep_plan_eq(
        deep_plan,
        0, // from_user_wallet should be 0 when insufficient
        0, // from_balance_manager should be 0 when insufficient
        0, // from_deep_reserves should be 0 when insufficient
        false, // deep_reserves_cover_order should be false
    );

    // Step 5: Execute the test - should abort with EInsufficientDeepReserves
    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(
            balance_manager_id,
        );
        let mut deep_coin = wallet_deep_coin;

        // This should abort because deep_reserves_cover_order = false
        execute_deep_plan(
            &mut treasury,
            &mut balance_manager,
            &mut deep_coin,
            &deep_plan,
            scenario.ctx(),
        );

        // This line should never be reached
        destroy(deep_coin);
        return_shared(treasury);
        return_shared(balance_manager);
    };

    scenario.end();
}

#[test]
fun deep_only_from_treasury_reserves() {
    // Test-specific constants
    let deep_required = 5_000 * DEEP_MULTIPLIER; // 5,000 DEEP total needed
    let balance_manager_deep = 1_000 * DEEP_MULTIPLIER; // 1,000 DEEP in BM
    let wallet_deep_amount = 0; // No DEEP in wallet
    let treasury_deep_amount = 10_000 * DEEP_MULTIPLIER; // 10,000 DEEP in treasury

    // Calculate expected values based on get_deep_plan logic
    let user_deep_total = balance_manager_deep + wallet_deep_amount;
    let expected_from_wallet = 0; // Nothing in wallet
    let expected_from_treasury = deep_required - user_deep_total; // All remaining needed from treasury

    let mut scenario = begin(ALICE);

    // Step 1: Setup treasury with DEEP reserves
    scenario.next_tx(ALICE);
    {
        treasury::init_for_testing(scenario.ctx());
    };

    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let treasury_deep_coin = mint_for_testing<DEEP>(treasury_deep_amount, scenario.ctx());
        treasury.deposit_into_reserves(treasury_deep_coin);
        return_shared(treasury);
    };

    // Step 2: Setup balance manager with initial DEEP
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        balance_manager_deep,
        &mut scenario,
    );

    // Step 3: Create empty wallet DEEP coin
    scenario.next_tx(ALICE);
    let wallet_deep_coin = mint_for_testing<DEEP>(wallet_deep_amount, scenario.ctx());

    // Step 4: Create DeepPlan using get_deep_plan
    let deep_plan = get_deep_plan(
        false, // not whitelisted
        deep_required, // total DEEP needed
        balance_manager_deep, // DEEP in balance manager
        wallet_deep_amount, // DEEP in wallet (0)
        treasury_deep_amount, // DEEP in treasury reserves
    );

    // Verify the DeepPlan is correct before execution
    assert_deep_plan_eq(
        deep_plan,
        expected_from_wallet,
        balance_manager_deep,
        expected_from_treasury,
        true, // deep_reserves_cover_order
    );

    // Step 5: Execute the test
    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(
            balance_manager_id,
        );
        let mut deep_coin = wallet_deep_coin;

        // Record initial balances
        let initial_treasury_balance = treasury.deep_reserves();
        let initial_bm_balance = balance_manager.balance<DEEP>();
        let initial_wallet_balance = deep_coin.value();

        // Execute deep plan
        execute_deep_plan(
            &mut treasury,
            &mut balance_manager,
            &mut deep_coin,
            &deep_plan,
            scenario.ctx(),
        );

        // Step 6: Verify results

        // Verify treasury reserves decreased by expected amount
        let final_treasury_balance = treasury.deep_reserves();
        assert_eq!(
            final_treasury_balance,
            initial_treasury_balance - deep_plan.from_deep_reserves(),
        );

        // Verify wallet coin remains unchanged (no DEEP taken from wallet)
        let final_wallet_balance = deep_coin.value();
        assert_eq!(final_wallet_balance, initial_wallet_balance);

        // Verify balance manager balance increased by treasury amount only
        let final_bm_balance = balance_manager.balance<DEEP>();
        assert_eq!(final_bm_balance, initial_bm_balance + deep_plan.from_deep_reserves());

        // Cleanup
        destroy(deep_coin);
        return_shared(treasury);
        return_shared(balance_manager);
    };

    scenario.end();
}

#[test]
fun deep_only_from_wallet() {
    // Test-specific constants
    let deep_required = 5_000 * DEEP_MULTIPLIER; // 5,000 DEEP total needed
    let balance_manager_deep = 1_000 * DEEP_MULTIPLIER; // 1,000 DEEP in BM
    let wallet_deep_amount = 5_000 * DEEP_MULTIPLIER; // 5,000 DEEP in wallet (more than needed)
    let treasury_deep_amount = 10_000 * DEEP_MULTIPLIER; // 10,000 DEEP in treasury (unused)

    // Calculate expected values based on get_deep_plan logic
    let expected_from_wallet = deep_required - balance_manager_deep; // Only what's needed from wallet
    let expected_from_treasury = 0; // No treasury needed

    let mut scenario = begin(ALICE);

    // Step 1: Setup treasury with DEEP reserves (unused in this test)
    scenario.next_tx(ALICE);
    {
        treasury::init_for_testing(scenario.ctx());
    };

    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let treasury_deep_coin = mint_for_testing<DEEP>(treasury_deep_amount, scenario.ctx());
        treasury.deposit_into_reserves(treasury_deep_coin);
        return_shared(treasury);
    };

    // Step 2: Setup balance manager with initial DEEP
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        balance_manager_deep,
        &mut scenario,
    );

    // Step 3: Create wallet DEEP coin
    scenario.next_tx(ALICE);
    let wallet_deep_coin = mint_for_testing<DEEP>(wallet_deep_amount, scenario.ctx());

    // Step 4: Create DeepPlan using get_deep_plan
    let deep_plan = get_deep_plan(
        false, // not whitelisted
        deep_required, // total DEEP needed
        balance_manager_deep, // DEEP in balance manager
        wallet_deep_amount, // DEEP in wallet
        treasury_deep_amount, // DEEP in treasury reserves (unused)
    );

    // Verify the DeepPlan is correct before execution
    assert_deep_plan_eq(
        deep_plan,
        expected_from_wallet,
        balance_manager_deep,
        expected_from_treasury,
        true, // deep_reserves_cover_order
    );

    // Step 5: Execute the test
    scenario.next_tx(ALICE);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(
            balance_manager_id,
        );
        let mut deep_coin = wallet_deep_coin;

        // Record initial balances
        let initial_treasury_balance = treasury.deep_reserves();
        let initial_bm_balance = balance_manager.balance<DEEP>();
        let initial_wallet_balance = deep_coin.value();

        // Execute deep plan
        execute_deep_plan(
            &mut treasury,
            &mut balance_manager,
            &mut deep_coin,
            &deep_plan,
            scenario.ctx(),
        );

        // Step 6: Verify results

        // Verify treasury reserves remain unchanged (no DEEP taken from treasury)
        let final_treasury_balance = treasury.deep_reserves();
        assert_eq!(final_treasury_balance, initial_treasury_balance);

        // Verify wallet coin decreased by expected amount
        let final_wallet_balance = deep_coin.value();
        assert_eq!(final_wallet_balance, initial_wallet_balance - deep_plan.from_user_wallet());

        // Verify balance manager balance increased by wallet amount only
        let final_bm_balance = balance_manager.balance<DEEP>();
        assert_eq!(final_bm_balance, initial_bm_balance + deep_plan.from_user_wallet());

        // Cleanup
        destroy(deep_coin);
        return_shared(treasury);
        return_shared(balance_manager);
    };

    scenario.end();
}

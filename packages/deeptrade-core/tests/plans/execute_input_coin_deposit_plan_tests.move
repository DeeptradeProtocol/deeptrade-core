#[test_only]
module deeptrade_core::execute_input_coin_deposit_plan_tests;

use deepbook::balance_manager::BalanceManager;
use deepbook::balance_manager_tests::{create_acct_and_share_with_funds, USDC, SPAM};
use deeptrade_core::dt_order::{
    execute_input_coin_deposit_plan,
    get_input_coin_deposit_plan,
    assert_input_coin_deposit_plan_eq
};
use std::unit_test::assert_eq;
use sui::coin::mint_for_testing;
use sui::test_scenario::{begin, end, return_shared};
use sui::test_utils::destroy;

// === Constants ===
const ALICE: address = @0xAAAA;
const TOKEN_MULTIPLIER: u64 = 1_000_000;

#[test]
fun input_coin_deposit_bid_from_wallet() {
    // Test-specific constants
    let required_amount = 5_000 * TOKEN_MULTIPLIER; // 5,000 tokens needed
    let balance_manager_quote = 1_000 * TOKEN_MULTIPLIER; // 1,000 quote tokens in BM
    let wallet_quote_amount = 5_000 * TOKEN_MULTIPLIER; // 5,000 quote tokens in wallet
    let wallet_base_amount = 10_000 * TOKEN_MULTIPLIER; // 10,000 base tokens in wallet (unused for bid)

    // Calculate expected values based on get_input_coin_deposit_plan logic
    let expected_from_wallet = required_amount - balance_manager_quote; // 4,000 tokens needed from wallet

    let mut scenario = begin(ALICE);

    // Step 1: Setup balance manager with initial quote tokens
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        balance_manager_quote,
        &mut scenario,
    );

    // Step 2: Create wallet coins
    scenario.next_tx(ALICE);
    let base_coin = mint_for_testing<SPAM>(wallet_base_amount, scenario.ctx());
    let quote_coin = mint_for_testing<USDC>(wallet_quote_amount, scenario.ctx());

    // Step 3: Create InputCoinDepositPlan using get_input_coin_deposit_plan
    let deposit_plan = get_input_coin_deposit_plan(
        required_amount, // total amount needed
        wallet_quote_amount, // quote tokens in wallet (input coin for bid)
        balance_manager_quote, // quote tokens in balance manager
    );

    // Verify the InputCoinDepositPlan is correct before execution
    assert_input_coin_deposit_plan_eq(
        deposit_plan,
        expected_from_wallet,
        true, // user_has_enough_input_coin
    );

    // Step 4: Execute the test
    scenario.next_tx(ALICE);
    {
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(
            balance_manager_id,
        );
        let mut base_coin_mut = base_coin;
        let mut quote_coin_mut = quote_coin;

        // Record initial balances
        let initial_bm_quote_balance = balance_manager.balance<USDC>();
        let initial_bm_base_balance = balance_manager.balance<SPAM>();
        let initial_wallet_quote_balance = quote_coin_mut.value();
        let initial_wallet_base_balance = base_coin_mut.value();

        // Execute input coin deposit plan
        execute_input_coin_deposit_plan(
            &mut balance_manager,
            &mut base_coin_mut,
            &mut quote_coin_mut,
            &deposit_plan,
            true, // is_bid
            scenario.ctx(),
        );

        // Step 5: Verify results

        // Verify quote tokens in balance manager increased by expected amount
        let final_bm_quote_balance = balance_manager.balance<USDC>();
        assert_eq!(
            final_bm_quote_balance,
            initial_bm_quote_balance + deposit_plan.from_user_wallet_icdp(),
        );

        // Verify base tokens in balance manager remain unchanged (not used for bid)
        let final_bm_base_balance = balance_manager.balance<SPAM>();
        assert_eq!(final_bm_base_balance, initial_bm_base_balance);

        // Verify quote coin in wallet decreased by expected amount
        let final_wallet_quote_balance = quote_coin_mut.value();
        assert_eq!(
            final_wallet_quote_balance,
            initial_wallet_quote_balance - deposit_plan.from_user_wallet_icdp(),
        );

        // Verify base coin in wallet remains unchanged (not used for bid)
        let final_wallet_base_balance = base_coin_mut.value();
        assert_eq!(final_wallet_base_balance, initial_wallet_base_balance);

        // Cleanup
        destroy(base_coin_mut);
        destroy(quote_coin_mut);
        return_shared(balance_manager);
    };

    scenario.end();
}

#[test]
fun input_coin_deposit_ask_from_wallet() {
    // Test-specific constants
    let required_amount = 8_000 * TOKEN_MULTIPLIER; // 8,000 tokens needed
    let balance_manager_base = 2_500 * TOKEN_MULTIPLIER; // 2,500 base tokens in BM
    let wallet_base_amount = 7_000 * TOKEN_MULTIPLIER; // 7,000 base tokens in wallet
    let wallet_quote_amount = 15_000 * TOKEN_MULTIPLIER; // 15,000 quote tokens in wallet (unused for ask)

    // Calculate expected values based on get_input_coin_deposit_plan logic
    let expected_from_wallet = required_amount - balance_manager_base; // 5,500 tokens needed from wallet

    let mut scenario = begin(ALICE);

    // Step 1: Setup balance manager with initial base tokens
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        balance_manager_base,
        &mut scenario,
    );

    // Step 2: Create wallet coins
    scenario.next_tx(ALICE);
    let base_coin = mint_for_testing<SPAM>(wallet_base_amount, scenario.ctx());
    let quote_coin = mint_for_testing<USDC>(wallet_quote_amount, scenario.ctx());

    // Step 3: Create InputCoinDepositPlan using get_input_coin_deposit_plan
    let deposit_plan = get_input_coin_deposit_plan(
        required_amount, // total amount needed
        wallet_base_amount, // base tokens in wallet (input coin for ask)
        balance_manager_base, // base tokens in balance manager
    );

    // Verify the InputCoinDepositPlan is correct before execution
    assert_input_coin_deposit_plan_eq(
        deposit_plan,
        expected_from_wallet,
        true, // user_has_enough_input_coin
    );

    // Step 4: Execute the test
    scenario.next_tx(ALICE);
    {
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(
            balance_manager_id,
        );
        let mut base_coin_mut = base_coin;
        let mut quote_coin_mut = quote_coin;

        // Record initial balances
        let initial_bm_base_balance = balance_manager.balance<SPAM>();
        let initial_bm_quote_balance = balance_manager.balance<USDC>();
        let initial_wallet_base_balance = base_coin_mut.value();
        let initial_wallet_quote_balance = quote_coin_mut.value();

        // Execute input coin deposit plan
        execute_input_coin_deposit_plan(
            &mut balance_manager,
            &mut base_coin_mut,
            &mut quote_coin_mut,
            &deposit_plan,
            false, // is_ask
            scenario.ctx(),
        );

        // Step 5: Verify results

        // Verify base tokens in balance manager increased by expected amount
        let final_bm_base_balance = balance_manager.balance<SPAM>();
        assert_eq!(
            final_bm_base_balance,
            initial_bm_base_balance + deposit_plan.from_user_wallet_icdp(),
        );

        // Verify quote tokens in balance manager remain unchanged (not used for ask)
        let final_bm_quote_balance = balance_manager.balance<USDC>();
        assert_eq!(final_bm_quote_balance, initial_bm_quote_balance);

        // Verify base coin in wallet decreased by expected amount
        let final_wallet_base_balance = base_coin_mut.value();
        assert_eq!(
            final_wallet_base_balance,
            initial_wallet_base_balance - deposit_plan.from_user_wallet_icdp(),
        );

        // Verify quote coin in wallet remains unchanged (not used for ask)
        let final_wallet_quote_balance = quote_coin_mut.value();
        assert_eq!(final_wallet_quote_balance, initial_wallet_quote_balance);

        // Cleanup
        destroy(base_coin_mut);
        destroy(quote_coin_mut);
        return_shared(balance_manager);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = deeptrade_core::dt_order::EInsufficientInput)]
fun insufficient_input_coin_aborts() {
    // Test-specific constants
    let required_amount = 10_000 * TOKEN_MULTIPLIER; // 10,000 tokens needed
    let balance_manager_quote = 2_000 * TOKEN_MULTIPLIER; // 2,000 quote tokens in BM
    let wallet_quote_amount = 3_000 * TOKEN_MULTIPLIER; // 3,000 quote tokens in wallet (insufficient)
    let wallet_base_amount = 20_000 * TOKEN_MULTIPLIER; // 20,000 base tokens in wallet (unused for bid)

    let mut scenario = begin(ALICE);

    // Step 1: Setup balance manager with initial quote tokens
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        balance_manager_quote,
        &mut scenario,
    );

    // Step 2: Create wallet coins
    scenario.next_tx(ALICE);
    let base_coin = mint_for_testing<SPAM>(wallet_base_amount, scenario.ctx());
    let quote_coin = mint_for_testing<USDC>(wallet_quote_amount, scenario.ctx());

    // Step 3: Create InputCoinDepositPlan using get_input_coin_deposit_plan
    let deposit_plan = get_input_coin_deposit_plan(
        required_amount, // total amount needed
        wallet_quote_amount, // quote tokens in wallet (insufficient)
        balance_manager_quote, // quote tokens in balance manager
    );

    // Verify the InputCoinDepositPlan indicates insufficient input
    assert_input_coin_deposit_plan_eq(
        deposit_plan,
        0, // from_user_wallet should be 0 when insufficient
        false, // user_has_enough_input_coin should be false
    );

    // Step 4: Execute the test - should abort with EInsufficientInput
    scenario.next_tx(ALICE);
    {
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(
            balance_manager_id,
        );
        let mut base_coin_mut = base_coin;
        let mut quote_coin_mut = quote_coin;

        // This should abort because user_has_enough_input_coin = false
        execute_input_coin_deposit_plan(
            &mut balance_manager,
            &mut base_coin_mut,
            &mut quote_coin_mut,
            &deposit_plan,
            true, // is_bid
            scenario.ctx(),
        );

        // This line should never be reached
        destroy(base_coin_mut);
        destroy(quote_coin_mut);
        return_shared(balance_manager);
    };

    scenario.end();
}

#[test]
fun no_wallet_deposit_needed() {
    // Test-specific constants
    let required_amount = 5_000 * TOKEN_MULTIPLIER; // 5,000 tokens needed
    let balance_manager_quote = 8_000 * TOKEN_MULTIPLIER; // 8,000 quote tokens in BM (more than needed)
    let wallet_quote_amount = 10_000 * TOKEN_MULTIPLIER; // 10,000 quote tokens in wallet (unused)
    let wallet_base_amount = 12_000 * TOKEN_MULTIPLIER; // 12,000 base tokens in wallet (unused for bid)

    // Calculate expected values based on get_input_coin_deposit_plan logic
    let expected_from_wallet = 0; // No wallet deposit needed

    let mut scenario = begin(ALICE);

    // Step 1: Setup balance manager with sufficient quote tokens
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        balance_manager_quote,
        &mut scenario,
    );

    // Step 2: Create wallet coins
    scenario.next_tx(ALICE);
    let base_coin = mint_for_testing<SPAM>(wallet_base_amount, scenario.ctx());
    let quote_coin = mint_for_testing<USDC>(wallet_quote_amount, scenario.ctx());

    // Step 3: Create InputCoinDepositPlan using get_input_coin_deposit_plan
    let deposit_plan = get_input_coin_deposit_plan(
        required_amount, // total amount needed
        wallet_quote_amount, // quote tokens in wallet (unused)
        balance_manager_quote, // quote tokens in balance manager (sufficient)
    );

    // Verify the InputCoinDepositPlan is correct before execution
    assert_input_coin_deposit_plan_eq(
        deposit_plan,
        expected_from_wallet,
        true, // user_has_enough_input_coin
    );

    // Step 4: Execute the test
    scenario.next_tx(ALICE);
    {
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(
            balance_manager_id,
        );
        let mut base_coin_mut = base_coin;
        let mut quote_coin_mut = quote_coin;

        // Record initial balances
        let initial_bm_quote_balance = balance_manager.balance<USDC>();
        let initial_bm_base_balance = balance_manager.balance<SPAM>();
        let initial_wallet_quote_balance = quote_coin_mut.value();
        let initial_wallet_base_balance = base_coin_mut.value();

        // Execute input coin deposit plan
        execute_input_coin_deposit_plan(
            &mut balance_manager,
            &mut base_coin_mut,
            &mut quote_coin_mut,
            &deposit_plan,
            true, // is_bid
            scenario.ctx(),
        );

        // Step 5: Verify results

        // Verify quote tokens in balance manager remain unchanged (no deposit needed)
        let final_bm_quote_balance = balance_manager.balance<USDC>();
        assert_eq!(final_bm_quote_balance, initial_bm_quote_balance);

        // Verify base tokens in balance manager remain unchanged (not used for bid)
        let final_bm_base_balance = balance_manager.balance<SPAM>();
        assert_eq!(final_bm_base_balance, initial_bm_base_balance);

        // Verify quote coin in wallet remains unchanged (no deposit needed)
        let final_wallet_quote_balance = quote_coin_mut.value();
        assert_eq!(final_wallet_quote_balance, initial_wallet_quote_balance);

        // Verify base coin in wallet remains unchanged (not used for bid)
        let final_wallet_base_balance = base_coin_mut.value();
        assert_eq!(final_wallet_base_balance, initial_wallet_base_balance);

        // Cleanup
        destroy(base_coin_mut);
        destroy(quote_coin_mut);
        return_shared(balance_manager);
    };

    scenario.end();
}

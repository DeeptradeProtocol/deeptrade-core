#[test_only]
module deeptrade_core::execute_protocol_fee_plan_tests;

use deepbook::balance_manager::BalanceManager;
use deepbook::balance_manager_tests::create_acct_and_share_with_funds;
use deepbook::constants;
use deepbook::order_info::{Self, OrderInfo};
use deeptrade_core::add_to_user_unsettled_fees_tests::setup_fee_manager_test;
use deeptrade_core::dt_order::{execute_protocol_fee_plan, get_protocol_fee_plan};
use deeptrade_core::fee::calculate_protocol_fees;
use deeptrade_core::fee_manager::FeeManager;
use deeptrade_core::helper::calculate_order_taker_maker_ratio;
use std::unit_test::assert_eq;
use sui::coin::mint_for_testing;
use sui::object::id_from_address;
use sui::sui::SUI;
use sui::test_scenario::{end, return_shared};
use sui::test_utils::destroy;

// === Constants ===
const ALICE: address = @0xAAAA;

// Fee rates for testing (in billionths)
const TAKER_FEE_RATE: u64 = 2_500_000; // 0.25%
const MAKER_FEE_RATE: u64 = 1_000_000; // 0.1%
const ORDER_AMOUNT: u64 = 1_000_000; // 1M units
const DISCOUNT_RATE: u64 = 0; // No discount by default

// Test addresses
const POOL_ID: address = @0x1;
const BALANCE_MANAGER_ID: address = @0x2;

#[test]
fun both_taker_and_maker_fees_from_both_sources() {
    let mut scenario = setup_fee_manager_test(ALICE);

    // Step 1: Setup balance manager with funds
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        ORDER_AMOUNT * constants::float_scaling(),
        &mut scenario,
    );

    // Step 2: Create partially executed order (both taker and maker fees apply)
    let order_info = create_partially_executed_order(ORDER_AMOUNT, 600_000); // 60% executed (40% maker)

    // Step 3: Calculate expected fees
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        order_info.original_quantity(),
        order_info.executed_quantity(),
        order_info.status(),
    );

    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        taker_ratio,
        maker_ratio,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    // Step 4: Create fee plan with fees split between wallet and balance manager
    // Put 2/3 in BM, 1/3 in wallet
    let coin_in_balance_manager = (total_fee * 2) / 3;
    let coin_in_wallet = total_fee - coin_in_balance_manager;

    let fee_plan = get_protocol_fee_plan(
        &order_info,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        coin_in_wallet,
        coin_in_balance_manager,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    // Step 5: Execute the test
    scenario.next_tx(ALICE);
    {
        let mut fee_manager = scenario.take_shared<FeeManager>();
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let mut wallet_coin = mint_for_testing<SUI>(coin_in_wallet, scenario.ctx());

        // Record initial balances
        let initial_balance_manager_balance = balance_manager.balance<SUI>();
        let initial_wallet_coin_balance = wallet_coin.value();

        // Verify no protocol unsettled fee exists initially
        assert_eq!(fee_manager.has_protocol_unsettled_fee<SUI>(), false);

        // Verify no user unsettled fee exists initially
        assert_eq!(
            fee_manager.has_user_unsettled_fee(
                order_info.pool_id(),
                order_info.balance_manager_id(),
                order_info.order_id(),
            ),
            false,
        );

        // Execute protocol fee plan
        execute_protocol_fee_plan(
            &mut fee_manager,
            &mut balance_manager,
            &mut wallet_coin,
            &order_info,
            &fee_plan,
            scenario.ctx(),
        );

        // Step 6: Verify results

        // Verify taker fees are added to protocol unsettled fees
        let final_fee_manager_balance = fee_manager.get_protocol_unsettled_fee_balance<SUI>();
        assert_eq!(final_fee_manager_balance, taker_fee);

        // Verify maker fees are added to user unsettled fees
        assert_eq!(
            fee_manager.has_user_unsettled_fee(
                order_info.pool_id(),
                order_info.balance_manager_id(),
                order_info.order_id(),
            ),
            true,
        );
        assert_eq!(
            fee_manager.get_user_unsettled_fee_balance<SUI>(
                order_info.pool_id(),
                order_info.balance_manager_id(),
                order_info.order_id(),
            ),
            maker_fee,
        );

        // Verify balance manager balance decreased by BM portion
        let final_balance_manager_balance = balance_manager.balance<SUI>();
        let expected_bm_decrease =
            fee_plan.taker_fee_from_balance_manager() + fee_plan.maker_fee_from_balance_manager();
        assert_eq!(
            final_balance_manager_balance,
            initial_balance_manager_balance - expected_bm_decrease,
        );

        // Verify wallet coin decreased by wallet portion
        let final_wallet_coin_balance = wallet_coin.value();
        let expected_wallet_decrease =
            fee_plan.taker_fee_from_wallet() + fee_plan.maker_fee_from_wallet();
        assert_eq!(
            final_wallet_coin_balance,
            initial_wallet_coin_balance - expected_wallet_decrease,
        );

        // Verify fee plan values are correct
        assert_eq!(
            fee_plan.taker_fee_from_wallet() + fee_plan.taker_fee_from_balance_manager(),
            taker_fee,
        );
        assert_eq!(
            fee_plan.maker_fee_from_wallet() + fee_plan.maker_fee_from_balance_manager(),
            maker_fee,
        );
        assert_eq!(fee_plan.user_covers_fee(), true);

        destroy(wallet_coin);
        return_shared(fee_manager);
        return_shared(balance_manager);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = deeptrade_core::dt_order::EInsufficientFee)]
fun insufficient_fee_aborts() {
    let mut scenario = setup_fee_manager_test(ALICE);

    // Step 1: Setup balance manager with minimal funds
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        1000, // Very small amount
        &mut scenario,
    );

    // Step 2: Create partially executed order (both taker and maker fees apply)
    let order_info = create_partially_executed_order(ORDER_AMOUNT, 500_000); // 50% executed (50% maker)

    // Step 3: Calculate expected fees
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        order_info.original_quantity(),
        order_info.executed_quantity(),
        order_info.status(),
    );

    let (_, _, _) = calculate_protocol_fees(
        taker_ratio,
        maker_ratio,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    // Step 4: Create fee plan with insufficient funds
    // Put very little in both wallet and balance manager
    let coin_in_balance_manager = 100; // Much less than required
    let coin_in_wallet = 100; // Much less than required

    let fee_plan = get_protocol_fee_plan(
        &order_info,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        coin_in_wallet,
        coin_in_balance_manager,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    // Step 5: Execute the test - should abort with EInsufficientFee
    scenario.next_tx(ALICE);
    {
        let mut fee_manager = scenario.take_shared<FeeManager>();
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let mut wallet_coin = mint_for_testing<SUI>(coin_in_wallet, scenario.ctx());

        // This should abort because user_covers_fee = false
        execute_protocol_fee_plan(
            &mut fee_manager,
            &mut balance_manager,
            &mut wallet_coin,
            &order_info,
            &fee_plan,
            scenario.ctx(),
        );

        // This line should never be reached
        destroy(wallet_coin);
        return_shared(fee_manager);
        return_shared(balance_manager);
    };

    scenario.end();
}

#[test]
fun pure_maker_order_no_taker_fee() {
    let mut scenario = setup_fee_manager_test(ALICE);

    // Step 1: Setup balance manager with funds
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        ORDER_AMOUNT * constants::float_scaling(),
        &mut scenario,
    );

    // Step 2: Create live order (no execution, pure maker)
    let order_info = create_live_order(ORDER_AMOUNT);

    // Step 3: Calculate expected fees
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        order_info.original_quantity(),
        order_info.executed_quantity(),
        order_info.status(),
    );

    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        taker_ratio,
        maker_ratio,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    // Step 4: Create fee plan with all fees in wallet
    let coin_in_balance_manager = total_fee / 2; // 1/2 in balance manager
    let coin_in_wallet = total_fee - coin_in_balance_manager; // 1/2 in wallet

    let fee_plan = get_protocol_fee_plan(
        &order_info,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        coin_in_wallet,
        coin_in_balance_manager,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    // Step 5: Execute the test
    scenario.next_tx(ALICE);
    {
        let mut fee_manager = scenario.take_shared<FeeManager>();
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let mut wallet_coin = mint_for_testing<SUI>(coin_in_wallet, scenario.ctx());

        // Record initial balances
        let initial_balance_manager_balance = balance_manager.balance<SUI>();
        let initial_wallet_coin_balance = wallet_coin.value();

        // Verify no protocol unsettled fee exists initially
        assert_eq!(fee_manager.has_protocol_unsettled_fee<SUI>(), false);

        // Verify no user unsettled fee exists initially
        assert_eq!(
            fee_manager.has_user_unsettled_fee(
                order_info.pool_id(),
                order_info.balance_manager_id(),
                order_info.order_id(),
            ),
            false,
        );

        // Execute protocol fee plan
        execute_protocol_fee_plan(
            &mut fee_manager,
            &mut balance_manager,
            &mut wallet_coin,
            &order_info,
            &fee_plan,
            scenario.ctx(),
        );

        // Step 6: Verify results

        // Verify no taker fees are added to protocol unsettled fees
        assert_eq!(fee_manager.has_protocol_unsettled_fee<SUI>(), false);

        // Verify maker fees are added to user unsettled fees
        assert_eq!(
            fee_manager.has_user_unsettled_fee(
                order_info.pool_id(),
                order_info.balance_manager_id(),
                order_info.order_id(),
            ),
            true,
        );
        assert_eq!(
            fee_manager.get_user_unsettled_fee_balance<SUI>(
                order_info.pool_id(),
                order_info.balance_manager_id(),
                order_info.order_id(),
            ),
            maker_fee,
        );

        // Verify balance manager balance decreased by maker fee from balance manager
        let final_balance_manager_balance = balance_manager.balance<SUI>();
        assert_eq!(
            final_balance_manager_balance,
            initial_balance_manager_balance - fee_plan.maker_fee_from_balance_manager(),
        );

        // Verify wallet coin decreased by maker fee from wallet
        let final_wallet_coin_balance = wallet_coin.value();
        assert_eq!(
            final_wallet_coin_balance,
            initial_wallet_coin_balance - fee_plan.maker_fee_from_wallet(),
        );

        // Verify fee plan values are correct
        assert_eq!(fee_plan.taker_fee_from_wallet(), 0);
        assert_eq!(fee_plan.taker_fee_from_balance_manager(), 0);
        assert!(fee_plan.maker_fee_from_wallet() > 0);
        assert!(fee_plan.maker_fee_from_balance_manager() > 0);
        assert_eq!(fee_plan.user_covers_fee(), true);

        // Verify calculated fees
        assert_eq!(taker_fee, 0);
        assert_eq!(total_fee, maker_fee);

        destroy(wallet_coin);
        return_shared(fee_manager);
        return_shared(balance_manager);
    };

    scenario.end();
}

#[test]
fun pure_taker_order_no_maker_fee() {
    let mut scenario = setup_fee_manager_test(ALICE);

    // Step 1: Setup balance manager with funds
    let balance_manager_id = create_acct_and_share_with_funds(
        ALICE,
        ORDER_AMOUNT * constants::float_scaling(),
        &mut scenario,
    );

    // Step 2: Create fully executed order (pure taker, no maker)
    let order_info = create_fully_executed_order(ORDER_AMOUNT);

    // Step 3: Calculate expected fees
    let (taker_ratio, maker_ratio) = calculate_order_taker_maker_ratio(
        order_info.original_quantity(),
        order_info.executed_quantity(),
        order_info.status(),
    );

    let (total_fee, taker_fee, maker_fee) = calculate_protocol_fees(
        taker_ratio,
        maker_ratio,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    // Step 4: Create fee plan with fees split between wallet and balance manager
    let coin_in_balance_manager = total_fee / 2; // 1/2 in balance manager
    let coin_in_wallet = total_fee - coin_in_balance_manager; // 1/2 in wallet

    let fee_plan = get_protocol_fee_plan(
        &order_info,
        TAKER_FEE_RATE,
        MAKER_FEE_RATE,
        coin_in_wallet,
        coin_in_balance_manager,
        ORDER_AMOUNT,
        DISCOUNT_RATE,
    );

    // Step 5: Execute the test
    scenario.next_tx(ALICE);
    {
        let mut fee_manager = scenario.take_shared<FeeManager>();
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let mut wallet_coin = mint_for_testing<SUI>(coin_in_wallet, scenario.ctx());

        // Record initial balances
        let initial_balance_manager_balance = balance_manager.balance<SUI>();
        let initial_wallet_coin_balance = wallet_coin.value();

        // Verify no protocol unsettled fee exists initially
        assert_eq!(fee_manager.has_protocol_unsettled_fee<SUI>(), false);

        // Verify no user unsettled fee exists initially
        assert_eq!(
            fee_manager.has_user_unsettled_fee(
                order_info.pool_id(),
                order_info.balance_manager_id(),
                order_info.order_id(),
            ),
            false,
        );

        // Execute protocol fee plan
        execute_protocol_fee_plan(
            &mut fee_manager,
            &mut balance_manager,
            &mut wallet_coin,
            &order_info,
            &fee_plan,
            scenario.ctx(),
        );

        // Step 6: Verify results

        // Verify taker fees are added to protocol unsettled fees
        let final_fee_manager_balance = fee_manager.get_protocol_unsettled_fee_balance<SUI>();
        assert_eq!(final_fee_manager_balance, taker_fee);

        // Verify no maker fees are added to user unsettled fees
        assert_eq!(
            fee_manager.has_user_unsettled_fee(
                order_info.pool_id(),
                order_info.balance_manager_id(),
                order_info.order_id(),
            ),
            false,
        );

        // Verify balance manager balance decreased by taker fee from balance manager
        let final_balance_manager_balance = balance_manager.balance<SUI>();
        assert_eq!(
            final_balance_manager_balance,
            initial_balance_manager_balance - fee_plan.taker_fee_from_balance_manager(),
        );

        // Verify wallet coin decreased by taker fee from wallet
        let final_wallet_coin_balance = wallet_coin.value();
        assert_eq!(
            final_wallet_coin_balance,
            initial_wallet_coin_balance - fee_plan.taker_fee_from_wallet(),
        );

        // Verify fee plan values are correct
        assert!(fee_plan.taker_fee_from_wallet() > 0);
        assert!(fee_plan.taker_fee_from_balance_manager() > 0);
        assert_eq!(fee_plan.maker_fee_from_wallet(), 0);
        assert_eq!(fee_plan.maker_fee_from_balance_manager(), 0);
        assert_eq!(fee_plan.user_covers_fee(), true);

        // Verify calculated fees
        assert_eq!(maker_fee, 0);
        assert_eq!(total_fee, taker_fee);

        destroy(wallet_coin);
        return_shared(fee_manager);
        return_shared(balance_manager);
    };

    scenario.end();
}

// === Helper Functions ===

/// Creates a partially executed order for testing (both taker and maker fees apply)
#[test_only]
fun create_partially_executed_order(original_quantity: u64, executed_quantity: u64): OrderInfo {
    let status = constants::partially_filled();

    order_info::create_order_info_for_tests(
        id_from_address(POOL_ID),
        id_from_address(BALANCE_MANAGER_ID),
        1, // order_id
        ALICE,
        1_000_000, // price
        original_quantity,
        executed_quantity,
        status,
        true, // is_bid
        true, // fee_is_deep
    )
}

/// Creates a live order for testing (no execution, pure maker fees)
#[test_only]
fun create_live_order(original_quantity: u64): OrderInfo {
    let status = constants::live();

    order_info::create_order_info_for_tests(
        id_from_address(POOL_ID),
        id_from_address(BALANCE_MANAGER_ID),
        1, // order_id
        ALICE,
        1_000_000, // price
        original_quantity,
        0, // executed_quantity = 0 (no execution)
        status,
        true, // is_bid
        true, // fee_is_deep
    )
}

/// Creates a fully executed order for testing (pure taker fees, no maker fees)
#[test_only]
fun create_fully_executed_order(original_quantity: u64): OrderInfo {
    let status = constants::filled();

    order_info::create_order_info_for_tests(
        id_from_address(POOL_ID),
        id_from_address(BALANCE_MANAGER_ID),
        1, // order_id
        ALICE,
        1_000_000, // price
        original_quantity,
        original_quantity, // executed_quantity = original_quantity (fully executed)
        status,
        true, // is_bid
        true, // fee_is_deep
    )
}

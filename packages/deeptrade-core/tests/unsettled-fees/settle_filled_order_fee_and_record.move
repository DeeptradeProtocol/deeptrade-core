#[test_only]
module deeptrade_core::settle_filled_order_fee_and_record_tests;

use deepbook::balance_manager::BalanceManager;
use deepbook::balance_manager_tests::{USDC, create_acct_and_share_with_funds};
use deepbook::constants;
use deepbook::pool::Pool;
use deepbook::pool_tests::place_limit_order;
use deeptrade_core::fee_manager::{
    FeeManager,
    settle_filled_order_fee_and_record,
    start_protocol_fee_settlement
};
use deeptrade_core::settle_user_fees_tests::setup_test_environment;
use deeptrade_core::treasury::Treasury;
use std::unit_test::assert_eq;
use sui::balance;
use sui::clock::Clock;
use sui::sui::SUI;
use sui::test_scenario::{end, return_shared};

// === Constants ===
const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;
const BOB: address = @0xBBBB;

#[test]
/// Test that the protocol can settle fees from a fully filled order.
fun protocol_settles_fee_on_fully_filled_order() {
    let (mut scenario, pool_id, balance_manager_id, fee_manager_id) = setup_test_environment();

    // Step 1: Alice places a buy order and adds an unsettled fee.
    scenario.next_tx(ALICE);
    let order_id = {
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1,
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(),
            100 * constants::float_scaling(),
            true,
            true,
            constants::max_u64(),
            &mut scenario,
        );

        let fee_balance = balance::create_for_testing<SUI>(1000);
        fee_manager.add_to_user_unsettled_fees(fee_balance, &order_info, scenario.ctx());

        let order_id = order_info.order_id();
        return_shared(fee_manager);
        order_id
    };

    // Step 2: Bob places a matching sell order that completely fills Alice's order.
    scenario.next_tx(BOB);
    {
        // Bob needs his own balance manager with funds to place a sell order
        let balance_manager_id_bob = create_acct_and_share_with_funds(
            BOB,
            1_000_000 * constants::float_scaling(),
            &mut scenario,
        );

        place_limit_order<SUI, USDC>(
            BOB,
            pool_id,
            balance_manager_id_bob,
            2,
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(),
            100 * constants::float_scaling(),
            false,
            true,
            constants::max_u64(),
            &mut scenario,
        );
    };

    // Step 3: Verify the order is no longer live and the unsettled fee still exists.
    scenario.next_tx(ALICE);
    {
        let fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);

        assert_eq!(pool.account_open_orders(&balance_manager).contains(&order_id), false);
        assert_eq!(fee_manager.has_user_unsettled_fee(pool_id, balance_manager_id, order_id), true);

        return_shared(fee_manager);
        return_shared(pool);
        return_shared(balance_manager);
    };

    // Step 4: Settle the protocol fee.
    scenario.next_tx(OWNER); // Protocol action
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let mut receipt = start_protocol_fee_settlement<SUI>();

        settle_filled_order_fee_and_record(
            &mut treasury,
            &mut fee_manager,
            &mut receipt,
            &pool,
            &balance_manager,
            order_id,
        );

        let (orders_count, total_settled) = receipt.finish_protocol_fee_settlement_for_testing();
        assert_eq!(orders_count, 1);
        assert_eq!(total_settled, 1000);

        // Verify the unsettled fee is now empty but still exists for future storage rebate claim
        assert_eq!(fee_manager.has_user_unsettled_fee(pool_id, balance_manager_id, order_id), true);
        assert_eq!(
            fee_manager.get_user_unsettled_fee_balance<SUI>(pool_id, balance_manager_id, order_id),
            0,
        );

        // Verify protocol fees have been collected
        assert_eq!(treasury.get_protocol_fee_balance<SUI>(), 1000);

        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test]
/// Test that the protocol can settle a fee from a user-cancelled order.
fun protocol_settles_fee_on_user_cancelled_order() {
    let (mut scenario, pool_id, balance_manager_id, fee_manager_id) = setup_test_environment();

    // Step 1: Alice places an order and adds an unsettled fee.
    scenario.next_tx(ALICE);
    let order_id = {
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1,
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(),
            100 * constants::float_scaling(),
            true,
            true,
            constants::max_u64(),
            &mut scenario,
        );
        let fee_balance = balance::create_for_testing<SUI>(1000);
        fee_manager.add_to_user_unsettled_fees(fee_balance, &order_info, scenario.ctx());
        let order_id = order_info.order_id();
        return_shared(fee_manager);
        order_id
    };

    // Step 2: Alice cancels the order directly through DeepBook, orphaning the fee.
    scenario.next_tx(ALICE);
    {
        let mut pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let clock = scenario.take_shared<Clock>();
        let trade_proof = balance_manager.generate_proof_as_owner(scenario.ctx());

        pool.cancel_order(&mut balance_manager, &trade_proof, order_id, &clock, scenario.ctx());

        return_shared(pool);
        return_shared(balance_manager);
        return_shared(clock);
    };

    // Step 3: Settle the protocol fee for the orphaned fee.
    scenario.next_tx(OWNER);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let mut receipt = start_protocol_fee_settlement<SUI>();

        settle_filled_order_fee_and_record(
            &mut treasury,
            &mut fee_manager,
            &mut receipt,
            &pool,
            &balance_manager,
            order_id,
        );

        let (_, total_settled) = receipt.finish_protocol_fee_settlement_for_testing();
        assert_eq!(total_settled, 1000);
        assert_eq!(treasury.get_protocol_fee_balance<SUI>(), 1000);

        // Verify the unsettled fee is now empty but still exists for future storage rebate claim
        assert_eq!(fee_manager.has_user_unsettled_fee(pool_id, balance_manager_id, order_id), true);
        assert_eq!(
            fee_manager.get_user_unsettled_fee_balance<SUI>(pool_id, balance_manager_id, order_id),
            0,
        );

        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test]
/// Test that the protocol ignores live, unfilled orders.
fun protocol_ignores_live_unfilled_order() {
    let (mut scenario, pool_id, balance_manager_id, fee_manager_id) = setup_test_environment();

    // Step 1: Alice places an order and adds an unsettled fee.
    scenario.next_tx(ALICE);
    let order_id = {
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1,
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(),
            100 * constants::float_scaling(),
            true,
            true,
            constants::max_u64(),
            &mut scenario,
        );
        let fee_balance = balance::create_for_testing<SUI>(1000);
        fee_manager.add_to_user_unsettled_fees(fee_balance, &order_info, scenario.ctx());
        let order_id = order_info.order_id();
        return_shared(fee_manager);
        order_id
    };

    // Step 2: Attempt to settle fees while the order is still live.
    scenario.next_tx(OWNER);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let mut receipt = start_protocol_fee_settlement<SUI>();

        // This should do nothing because the order is live.
        settle_filled_order_fee_and_record(
            &mut treasury,
            &mut fee_manager,
            &mut receipt,
            &pool,
            &balance_manager,
            order_id,
        );

        let (orders_count, total_settled) = receipt.finish_protocol_fee_settlement_for_testing();
        assert_eq!(orders_count, 0);
        assert_eq!(total_settled, 0);

        // Verify the unsettled fee is still there and has previous balance
        assert_eq!(fee_manager.has_user_unsettled_fee(pool_id, balance_manager_id, order_id), true);
        assert_eq!(
            fee_manager.get_user_unsettled_fee_balance<SUI>(pool_id, balance_manager_id, order_id),
            1000,
        );

        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test]
/// Test that the protocol ignores live, partially filled orders.
fun protocol_ignores_live_partially_filled_order() {
    let (mut scenario, pool_id, balance_manager_id, fee_manager_id) = setup_test_environment();

    // Step 1: Alice places an order and adds an unsettled fee.
    scenario.next_tx(ALICE);
    let order_id = {
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1,
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(),
            100 * constants::float_scaling(),
            true,
            true,
            constants::max_u64(),
            &mut scenario,
        );
        let fee_balance = balance::create_for_testing<SUI>(1000);
        fee_manager.add_to_user_unsettled_fees(fee_balance, &order_info, scenario.ctx());
        let order_id = order_info.order_id();
        return_shared(fee_manager);
        order_id
    };

    // Step 2: Bob partially fills Alice's order.
    scenario.next_tx(BOB);
    {
        let balance_manager_id_bob = create_acct_and_share_with_funds(
            BOB,
            1_000_000 * constants::float_scaling(),
            &mut scenario,
        );
        place_limit_order<SUI, USDC>(
            BOB,
            pool_id,
            balance_manager_id_bob,
            2,
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(),
            30 * constants::float_scaling(),
            false,
            true,
            constants::max_u64(),
            &mut scenario,
        );
    };

    // Step 3: Attempt to settle fees while the order is still live.
    scenario.next_tx(OWNER);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let mut receipt = start_protocol_fee_settlement<SUI>();

        settle_filled_order_fee_and_record(
            &mut treasury,
            &mut fee_manager,
            &mut receipt,
            &pool,
            &balance_manager,
            order_id,
        );

        let (orders_count, total_settled) = receipt.finish_protocol_fee_settlement_for_testing();
        assert_eq!(orders_count, 0);
        assert_eq!(total_settled, 0);

        // Verify the unsettled fee is still there and has previous balance
        assert_eq!(fee_manager.has_user_unsettled_fee(pool_id, balance_manager_id, order_id), true);
        assert_eq!(
            fee_manager.get_user_unsettled_fee_balance<SUI>(pool_id, balance_manager_id, order_id),
            1000,
        );

        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test]
/// Test the batch settlement of multiple fees.
fun protocol_settles_batch_of_fees_correctly() {
    let (mut scenario, pool_id, balance_manager_id, fee_manager_id) = setup_test_environment();

    // === Order A: To be fully filled ===
    scenario.next_tx(ALICE);
    let order_a_id = {
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1,
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(),
            100 * constants::float_scaling(),
            true,
            true,
            constants::max_u64(),
            &mut scenario,
        );
        let fee_balance = balance::create_for_testing<SUI>(1000);
        fee_manager.add_to_user_unsettled_fees(fee_balance, &order_info, scenario.ctx());
        let order_id = order_info.order_id();
        return_shared(fee_manager);
        order_id
    };

    // === Order B: To be cancelled ===
    scenario.next_tx(ALICE);
    let order_b_id = {
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            2,
            constants::no_restriction(),
            constants::self_matching_allowed(),
            constants::float_scaling(), // Price < 2.0
            100 * constants::float_scaling(),
            true,
            true,
            constants::max_u64(),
            &mut scenario,
        );
        let fee_balance = balance::create_for_testing<SUI>(500);
        fee_manager.add_to_user_unsettled_fees(fee_balance, &order_info, scenario.ctx());
        let order_id = order_info.order_id();
        return_shared(fee_manager);
        order_id
    };

    // === Order C: To remain live ===
    scenario.next_tx(ALICE);
    let order_c_id = {
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            3,
            constants::no_restriction(),
            constants::self_matching_allowed(),
            3 * constants::float_scaling() / 2,
            100 * constants::float_scaling(),
            true,
            true,
            constants::max_u64(),
            &mut scenario,
        );
        let fee_balance = balance::create_for_testing<SUI>(2000);
        fee_manager.add_to_user_unsettled_fees(fee_balance, &order_info, scenario.ctx());
        let order_id = order_info.order_id();
        return_shared(fee_manager);
        order_id
    };

    // --- Trigger state changes for orders A and B ---

    // Fill order A
    scenario.next_tx(BOB);
    {
        let balance_manager_id_bob = create_acct_and_share_with_funds(
            BOB,
            100 * constants::float_scaling(),
            &mut scenario,
        );
        place_limit_order<SUI, USDC>(
            BOB,
            pool_id,
            balance_manager_id_bob,
            4,
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(),
            100 * constants::float_scaling(),
            false,
            true,
            constants::max_u64(),
            &mut scenario,
        );
    };

    // Cancel order B
    scenario.next_tx(ALICE);
    {
        let mut pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let clock = scenario.take_shared<Clock>();
        let trade_proof = balance_manager.generate_proof_as_owner(scenario.ctx());
        pool.cancel_order(&mut balance_manager, &trade_proof, order_b_id, &clock, scenario.ctx());
        return_shared(pool);
        return_shared(balance_manager);
        return_shared(clock);
    };

    // --- Perform batch settlement ---
    scenario.next_tx(OWNER);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);

        let mut receipt = start_protocol_fee_settlement<SUI>();

        // Settle all three orders
        settle_filled_order_fee_and_record(
            &mut treasury,
            &mut fee_manager,
            &mut receipt,
            &pool,
            &balance_manager,
            order_a_id,
        ); // Filled
        settle_filled_order_fee_and_record(
            &mut treasury,
            &mut fee_manager,
            &mut receipt,
            &pool,
            &balance_manager,
            order_b_id,
        ); // Cancelled
        settle_filled_order_fee_and_record(
            &mut treasury,
            &mut fee_manager,
            &mut receipt,
            &pool,
            &balance_manager,
            order_c_id,
        ); // Live

        let (orders_count, total_settled) = receipt.finish_protocol_fee_settlement_for_testing();

        // Should have settled fees for filled (A) and cancelled (B) orders.
        assert_eq!(orders_count, 2);
        assert_eq!(total_settled, 1500); // 1000 from A + 500 from B

        // Verify unsettled fee for filled order A is now empty but still exists for future storage rebate claim
        assert_eq!(
            fee_manager.has_user_unsettled_fee(pool_id, balance_manager_id, order_a_id),
            true,
        );
        assert_eq!(
            fee_manager.get_user_unsettled_fee_balance<SUI>(
                pool_id,
                balance_manager_id,
                order_a_id,
            ),
            0,
        );

        // Verify unsettled fee for live order C is untouched.
        assert_eq!(
            fee_manager.has_user_unsettled_fee(pool_id, balance_manager_id, order_c_id),
            true,
        );
        assert_eq!(
            fee_manager.get_user_unsettled_fee_balance<SUI>(
                pool_id,
                balance_manager_id,
                order_c_id,
            ),
            2000,
        );

        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test]
/// Test that the protocol ignores orders with no unsettled fees.
fun protocol_ignores_order_with_no_unsettled_fees() {
    let (mut scenario, pool_id, balance_manager_id, fee_manager_id) = setup_test_environment();

    // Step 1: Alice places an order but NO unsettled fee is added.
    scenario.next_tx(ALICE);
    let order_id = {
        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1,
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(),
            100 * constants::float_scaling(),
            true,
            true,
            constants::max_u64(),
            &mut scenario,
        );
        // Note: No unsettled fee is added here
        order_info.order_id()
    };

    // Step 2: Cancel the order to make it non-live.
    scenario.next_tx(ALICE);
    {
        let mut pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let clock = scenario.take_shared<Clock>();
        let trade_proof = balance_manager.generate_proof_as_owner(scenario.ctx());

        pool.cancel_order(&mut balance_manager, &trade_proof, order_id, &clock, scenario.ctx());

        return_shared(pool);
        return_shared(balance_manager);
        return_shared(clock);
    };

    // Step 3: Try to settle protocol fees for the order with no unsettled fees.
    scenario.next_tx(OWNER);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let mut receipt = start_protocol_fee_settlement<SUI>();

        // This should do nothing because there are no unsettled fees for this order.
        settle_filled_order_fee_and_record(
            &mut treasury,
            &mut fee_manager,
            &mut receipt,
            &pool,
            &balance_manager,
            order_id,
        );

        let (orders_count, total_settled) = receipt.finish_protocol_fee_settlement_for_testing();
        assert_eq!(orders_count, 0);
        assert_eq!(total_settled, 0);

        // Verify no unsettled fee exists for this order.
        assert_eq!(
            fee_manager.has_user_unsettled_fee(pool_id, balance_manager_id, order_id),
            false,
        );

        // Verify no protocol fees were collected.
        assert_eq!(treasury.get_protocol_fee_balance<SUI>(), 0);

        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test]
/// Test that calling settle_filled_order_fee_and_record twice on the same order
/// doesn't update the receipt the second time.
fun protocol_ignores_already_settled_fee_on_second_call() {
    let (mut scenario, pool_id, balance_manager_id, fee_manager_id) = setup_test_environment();

    // Step 1: Alice places an order and adds an unsettled fee.
    scenario.next_tx(ALICE);
    let order_id = {
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let order_info = place_limit_order<SUI, USDC>(
            ALICE,
            pool_id,
            balance_manager_id,
            1,
            constants::no_restriction(),
            constants::self_matching_allowed(),
            2 * constants::float_scaling(),
            100 * constants::float_scaling(),
            true,
            true,
            constants::max_u64(),
            &mut scenario,
        );
        let fee_balance = balance::create_for_testing<SUI>(1000);
        fee_manager.add_to_user_unsettled_fees(fee_balance, &order_info, scenario.ctx());
        let order_id = order_info.order_id();
        return_shared(fee_manager);
        order_id
    };

    // Step 2: Cancel the order to make it non-live.
    scenario.next_tx(ALICE);
    {
        let mut pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let mut balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let clock = scenario.take_shared<Clock>();
        let trade_proof = balance_manager.generate_proof_as_owner(scenario.ctx());

        pool.cancel_order(&mut balance_manager, &trade_proof, order_id, &clock, scenario.ctx());

        return_shared(pool);
        return_shared(balance_manager);
        return_shared(clock);
    };

    // Step 3: First settlement - should succeed and update receipt.
    scenario.next_tx(OWNER);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let mut receipt = start_protocol_fee_settlement<SUI>();

        // First call should settle the fee
        settle_filled_order_fee_and_record(
            &mut treasury,
            &mut fee_manager,
            &mut receipt,
            &pool,
            &balance_manager,
            order_id,
        );

        let (orders_count, total_settled) = receipt.finish_protocol_fee_settlement_for_testing();
        assert_eq!(orders_count, 1);
        assert_eq!(total_settled, 1000);

        // Verify the unsettled fee is now empty but still exists for future storage rebate claim
        assert_eq!(fee_manager.has_user_unsettled_fee(pool_id, balance_manager_id, order_id), true);
        assert_eq!(
            fee_manager.get_user_unsettled_fee_balance<SUI>(pool_id, balance_manager_id, order_id),
            0,
        );

        // Verify protocol fees have been collected
        assert_eq!(treasury.get_protocol_fee_balance<SUI>(), 1000);

        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(pool);
        return_shared(balance_manager);
    };

    // Step 4: Second settlement - should do nothing and not update receipt.
    scenario.next_tx(OWNER);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let balance_manager = scenario.take_shared_by_id<BalanceManager>(balance_manager_id);
        let mut receipt = start_protocol_fee_settlement<SUI>();

        // Second call should do nothing since fee is already settled
        settle_filled_order_fee_and_record(
            &mut treasury,
            &mut fee_manager,
            &mut receipt,
            &pool,
            &balance_manager,
            order_id,
        );

        let (orders_count, total_settled) = receipt.finish_protocol_fee_settlement_for_testing();
        // Receipt should show no additional settlements
        assert_eq!(orders_count, 0);
        assert_eq!(total_settled, 0);

        // Verify the unsettled fee still exists but remains empty
        assert_eq!(fee_manager.has_user_unsettled_fee(pool_id, balance_manager_id, order_id), true);
        assert_eq!(
            fee_manager.get_user_unsettled_fee_balance<SUI>(pool_id, balance_manager_id, order_id),
            0,
        );

        // Verify protocol fees remain the same (no additional collection)
        assert_eq!(treasury.get_protocol_fee_balance<SUI>(), 1000);

        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

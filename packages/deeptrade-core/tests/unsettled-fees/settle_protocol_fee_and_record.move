#[test_only]
module deeptrade_core::settle_protocol_fee_and_record_tests;

use deepbook::balance_manager_tests::{create_acct_and_share_with_funds, USDC};
use deepbook::constants;
use deepbook::pool::Pool;
use deepbook::pool_tests::place_limit_order;
use deeptrade_core::fee_manager::{
    Self,
    FeeManager,
    settle_protocol_fee_and_record,
    start_protocol_fee_settlement
};
use deeptrade_core::settle_user_fees_tests::setup_test_environment;
use deeptrade_core::treasury::Treasury;
use std::unit_test::assert_eq;
use sui::balance;
use sui::sui::SUI;
use sui::test_scenario::{end, return_shared};

// === Constants ===
const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;
const BOB: address = @0xBBBB;

#[test]
/// Test settling a single existing protocol fee.
fun settle_single_fee() {
    let (mut scenario, _, _, fee_manager_id) = setup_test_environment();

    // Step 1: Add a protocol unsettled fee to the FeeManager.
    scenario.next_tx(ALICE);
    {
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let fee_balance = balance::create_for_testing<SUI>(1000);
        fee_manager.add_to_protocol_unsettled_fees(fee_balance, scenario.ctx());

        assert_eq!(fee_manager.get_protocol_unsettled_fee_balance<SUI>(), 1000);
        return_shared(fee_manager);
    };

    // Step 2: Settle the protocol fee.
    scenario.next_tx(OWNER); // Can be any address
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let mut receipt = start_protocol_fee_settlement<SUI>();

        settle_protocol_fee_and_record(&mut treasury, &mut fee_manager, &mut receipt);

        let (orders_count, total_settled) = fee_manager::finish_protocol_fee_settlement_for_testing(
            receipt,
        );

        // settle_protocol_fee_and_record does not increment orders_count
        assert_eq!(orders_count, 0);
        assert_eq!(total_settled, 1000);

        // Verify that the fee was transferred to the treasury
        assert_eq!(treasury.get_protocol_fee_balance<SUI>(), 1000);

        // Verify the unsettled fee is now empty but still exists for storage rebate claim
        assert_eq!(fee_manager.has_protocol_unsettled_fee<SUI>(), true);
        assert_eq!(fee_manager.get_protocol_unsettled_fee_balance<SUI>(), 0);

        return_shared(treasury);
        return_shared(fee_manager);
    };

    end(scenario);
}

#[test]
/// Test attempting to settle a fee when none exists.
fun settle_non_existent_fee() {
    let (mut scenario, _, _, fee_manager_id) = setup_test_environment();

    scenario.next_tx(OWNER);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let mut receipt = start_protocol_fee_settlement<SUI>();

        // Verify no fee exists initially
        assert_eq!(fee_manager.has_protocol_unsettled_fee<SUI>(), false);

        settle_protocol_fee_and_record(&mut treasury, &mut fee_manager, &mut receipt);

        let (orders_count, total_settled) = fee_manager::finish_protocol_fee_settlement_for_testing(
            receipt,
        );
        assert_eq!(orders_count, 0);
        assert_eq!(total_settled, 0);
        assert_eq!(treasury.get_protocol_fee_balance<SUI>(), 0);

        // Verify no fee was created
        assert_eq!(fee_manager.has_protocol_unsettled_fee<SUI>(), false);

        return_shared(treasury);
        return_shared(fee_manager);
    };

    end(scenario);
}

#[test]
/// Test settling a fee that is already zero.
fun settle_zero_fee() {
    let (mut scenario, _, _, fee_manager_id) = setup_test_environment();

    // Step 1: Add and then settle a protocol fee, leaving an empty balance object.
    scenario.next_tx(ALICE);
    {
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let fee_balance = balance::create_for_testing<SUI>(1000);
        fee_manager.add_to_protocol_unsettled_fees(fee_balance, scenario.ctx());
        return_shared(fee_manager);
    };

    scenario.next_tx(OWNER);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let mut receipt = start_protocol_fee_settlement<SUI>();
        settle_protocol_fee_and_record(&mut treasury, &mut fee_manager, &mut receipt);
        let (_, total_settled) = fee_manager::finish_protocol_fee_settlement_for_testing(receipt);
        assert_eq!(total_settled, 1000);
        assert_eq!(treasury.get_protocol_fee_balance<SUI>(), 1000);
        return_shared(treasury);
        return_shared(fee_manager);
    };

    // Step 2: Attempt to settle the same fee again, which is now zero.
    scenario.next_tx(OWNER);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let mut receipt = start_protocol_fee_settlement<SUI>();

        // Verify fee exists but is zero
        assert_eq!(fee_manager.has_protocol_unsettled_fee<SUI>(), true);
        assert_eq!(fee_manager.get_protocol_unsettled_fee_balance<SUI>(), 0);

        settle_protocol_fee_and_record(&mut treasury, &mut fee_manager, &mut receipt);

        let (orders_count, total_settled) = fee_manager::finish_protocol_fee_settlement_for_testing(
            receipt,
        );
        assert_eq!(orders_count, 0);
        assert_eq!(total_settled, 0);

        // Treasury balance should not have changed.
        assert_eq!(treasury.get_protocol_fee_balance<SUI>(), 1000);

        return_shared(treasury);
        return_shared(fee_manager);
    };

    end(scenario);
}

#[test]
/// Test settling fees for multiple coin types.
fun settle_multiple_coin_types() {
    let (mut scenario, _, _, fee_manager_id) = setup_test_environment();

    // Step 1: Add protocol unsettled fees for SUI and USDC.
    scenario.next_tx(ALICE);
    {
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);

        let sui_fee = balance::create_for_testing<SUI>(1000);
        fee_manager.add_to_protocol_unsettled_fees(sui_fee, scenario.ctx());

        let usdc_fee = balance::create_for_testing<USDC>(2500);
        fee_manager.add_to_protocol_unsettled_fees(usdc_fee, scenario.ctx());

        assert_eq!(fee_manager.get_protocol_unsettled_fee_balance<SUI>(), 1000);
        assert_eq!(fee_manager.get_protocol_unsettled_fee_balance<USDC>(), 2500);

        return_shared(fee_manager);
    };

    // Step 2: Settle both fees.
    scenario.next_tx(OWNER);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);

        // Settle SUI
        let mut sui_receipt = start_protocol_fee_settlement<SUI>();
        settle_protocol_fee_and_record(&mut treasury, &mut fee_manager, &mut sui_receipt);
        let (_, sui_total) = fee_manager::finish_protocol_fee_settlement_for_testing(sui_receipt);
        assert_eq!(sui_total, 1000);

        // Settle USDC
        let mut usdc_receipt = start_protocol_fee_settlement<USDC>();
        settle_protocol_fee_and_record(&mut treasury, &mut fee_manager, &mut usdc_receipt);
        let (_, usdc_total) = fee_manager::finish_protocol_fee_settlement_for_testing(
            usdc_receipt,
        );
        assert_eq!(usdc_total, 2500);

        // Verify treasury balances
        assert_eq!(treasury.get_protocol_fee_balance<SUI>(), 1000);
        assert_eq!(treasury.get_protocol_fee_balance<USDC>(), 2500);

        // Verify unsettled fees are empty but still exist for storage rebate claim
        assert_eq!(fee_manager.has_protocol_unsettled_fee<SUI>(), true);
        assert_eq!(fee_manager.get_protocol_unsettled_fee_balance<SUI>(), 0);
        assert_eq!(fee_manager.has_protocol_unsettled_fee<USDC>(), true);
        assert_eq!(fee_manager.get_protocol_unsettled_fee_balance<USDC>(), 0);

        return_shared(treasury);
        return_shared(fee_manager);
    };

    end(scenario);
}

#[test]
/// Test settlement from a real-world scenario: user cancels a partially filled order.
fun settle_fee_from_partially_filled_cancelled_order() {
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

        let fee_balance = balance::create_for_testing<SUI>(1000); // Fee for 100 quantity
        fee_manager.add_to_user_unsettled_fees(fee_balance, &order_info, scenario.ctx());

        let order_id = order_info.order_id();
        return_shared(fee_manager);
        order_id
    };

    // Step 2: Bob partially fills Alice's order (30 out of 100).
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

    // Step 3: Alice cancels her partially filled order. This will move the fee for the
    // filled portion (30%) to the protocol's unsettled fees.
    scenario.next_tx(ALICE);
    {
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let mut pool = scenario.take_shared_by_id<Pool<SUI, USDC>>(pool_id);
        let mut balance_manager = scenario.take_shared_by_id<
            deepbook::balance_manager::BalanceManager,
        >(
            balance_manager_id,
        );

        // This call splits the unsettled fee, returning the unfilled portion to the user
        // and adding the filled portion to the protocol's unsettled fees.
        let coin = fee_manager.settle_user_fees<SUI, USDC, SUI>(
            &pool,
            &balance_manager,
            order_id,
            scenario.ctx(),
        );
        // Filled portion fee is proportional to the filled amount.
        // The original maker order was for 100, filled 30, so 30% of the fee goes to protocol.
        // 1000 * (1 - 30/100) = 700 returned to user.
        // Actually, filled_quantity is 30, original_quantity is 100, maker_quantity is 100
        // fee is 1000. not_executed_quantity = 70.
        // return_to_user = 1000 * 70 / 100 = 700.
        assert_eq!(coin.value(), 700);
        coin.burn_for_testing();

        // The 300 should now be in the protocol unsettled fees bag.
        assert_eq!(fee_manager.get_protocol_unsettled_fee_balance<SUI>(), 300);

        // Cancel the order on DeepBook
        let clock = scenario.take_shared();
        let trade_proof = balance_manager.generate_proof_as_owner(scenario.ctx());
        pool.cancel_order(&mut balance_manager, &trade_proof, order_id, &clock, scenario.ctx());

        return_shared(fee_manager);
        return_shared(pool);
        return_shared(balance_manager);
        return_shared(clock);
    };

    // Step 4: Settle the protocol fee.
    scenario.next_tx(OWNER);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let mut receipt = start_protocol_fee_settlement<SUI>();

        settle_protocol_fee_and_record(&mut treasury, &mut fee_manager, &mut receipt);

        let (_, total_settled) = fee_manager::finish_protocol_fee_settlement_for_testing(receipt);
        assert_eq!(total_settled, 300);
        assert_eq!(treasury.get_protocol_fee_balance<SUI>(), 300);

        // Verify unsettled fees are empty but still exist for storage rebate claim
        assert_eq!(fee_manager.has_protocol_unsettled_fee<SUI>(), true);
        assert_eq!(fee_manager.get_protocol_unsettled_fee_balance<SUI>(), 0);

        return_shared(treasury);
        return_shared(fee_manager);
    };

    end(scenario);
}

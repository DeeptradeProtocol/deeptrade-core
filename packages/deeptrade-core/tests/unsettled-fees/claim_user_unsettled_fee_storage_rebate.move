#[test_only]
module deeptrade_core::claim_user_unsettled_fee_storage_rebate_tests;

use deepbook::balance_manager_tests::{USDC, create_acct_and_share_with_funds};
use deepbook::constants;
use deeptrade_core::fee_manager::{
    FeeManager,
    claim_user_unsettled_fee_storage_rebate,
    claim_user_unsettled_fee_storage_rebate_admin,
    settle_filled_order_fee_and_record,
    start_protocol_fee_settlement
};
use deeptrade_core::multisig_config::{MultisigConfig, ESenderIsNotValidMultisig};
use deeptrade_core::settle_user_fees_tests::setup_test_environment;
use deeptrade_core::treasury::Treasury;
use multisig::multisig_test_utils::get_test_multisig_address;
use std::unit_test::assert_eq;
use sui::balance;
use sui::sui::SUI;
use sui::test_scenario::{Scenario, end, return_shared, take_shared, take_shared_by_id};
use sui::test_utils::destroy;

// === Constants ===
const OWNER: address = @0x1;
const ALICE: address = @0xAAAA;
const BOB: address = @0xBBBB;
const UNRELATED_USER: address = @0xCCCC;

#[test]
/// Test that the owner can claim a storage rebate for a settled fee.
fun owner_claims_rebate_successfully() {
    let (
        mut scenario,
        pool_id,
        balance_manager_id,
        fee_manager_id,
        order_id,
    ) = setup_filled_order_for_rebate();

    // Claim the storage rebate as the fee manager owner
    scenario.next_tx(ALICE);
    {
        let treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let pool = scenario.take_shared_by_id(pool_id);
        let balance_manager = scenario.take_shared_by_id(balance_manager_id);

        claim_user_unsettled_fee_storage_rebate<SUI, USDC, SUI>(
            &treasury,
            &mut fee_manager,
            &pool,
            &balance_manager,
            order_id,
            scenario.ctx(),
        );

        // Verify the unsettled fee object has been destroyed
        assert_eq!(
            fee_manager.has_user_unsettled_fee(pool_id, balance_manager_id, order_id),
            false,
        );

        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = deeptrade_core::fee_manager::EInvalidOwner)]
/// Test that a non-owner cannot claim a storage rebate.
fun unauthorized_user_claim_fails() {
    let (
        mut scenario,
        pool_id,
        balance_manager_id,
        fee_manager_id,
        order_id,
    ) = setup_filled_order_for_rebate();

    // Attempt to claim as an unrelated user
    scenario.next_tx(UNRELATED_USER);
    {
        let treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let pool = scenario.take_shared_by_id(pool_id);
        let balance_manager = scenario.take_shared_by_id(balance_manager_id);

        claim_user_unsettled_fee_storage_rebate<SUI, USDC, SUI>(
            &treasury,
            &mut fee_manager,
            &pool,
            &balance_manager,
            order_id,
            scenario.ctx(),
        );

        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = deeptrade_core::fee_manager::EUserUnsettledFeeNotEmpty)]
/// Test that claiming a rebate for a non-empty (unsettled) fee fails.
fun claim_for_unsettled_fee_fails() {
    let (mut scenario, pool_id, balance_manager_id, fee_manager_id) = setup_test_environment();

    // Step 1: Alice places an order and adds an unsettled fee.
    scenario.next_tx(ALICE);
    let order_id = {
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let order_info = deepbook::pool_tests::place_limit_order<SUI, USDC>(
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

    // Step 2: Attempt to claim the rebate without settling the fee first.
    scenario.next_tx(ALICE);
    {
        let treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let pool = scenario.take_shared_by_id(pool_id);
        let balance_manager = scenario.take_shared_by_id(balance_manager_id);

        claim_user_unsettled_fee_storage_rebate<SUI, USDC, SUI>(
            &treasury,
            &mut fee_manager,
            &pool,
            &balance_manager,
            order_id,
            scenario.ctx(),
        );

        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test]
/// Test that claiming a rebate for an order with no unsettled fee does nothing.
fun claim_for_non_existent_fee_is_noop() {
    let (mut scenario, pool_id, balance_manager_id, fee_manager_id) = setup_test_environment();

    // Some arbitrary order ID that does not have an unsettled fee.
    let order_id = 12345;

    scenario.next_tx(ALICE);
    {
        let treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let pool = scenario.take_shared_by_id(pool_id);
        let balance_manager = scenario.take_shared_by_id(balance_manager_id);

        // This should be a no-op since the fee does not exist.
        claim_user_unsettled_fee_storage_rebate<SUI, USDC, SUI>(
            &treasury,
            &mut fee_manager,
            &pool,
            &balance_manager,
            order_id,
            scenario.ctx(),
        );

        // Verify that nothing has changed.
        assert_eq!(
            fee_manager.has_user_unsettled_fee(pool_id, balance_manager_id, order_id),
            false,
        );

        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(pool);
        return_shared(balance_manager);
    };

    end(scenario);
}

#[test]
/// Test that a protocol admin can claim a user's storage rebate.
fun admin_claims_rebate_successfully() {
    let (
        mut scenario,
        pool_id,
        balance_manager_id,
        fee_manager_id,
        order_id,
    ) = setup_filled_order_for_rebate();

    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let pool = scenario.take_shared_by_id(pool_id);
        let balance_manager = scenario.take_shared_by_id(balance_manager_id);
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        claim_user_unsettled_fee_storage_rebate_admin<SUI, USDC, SUI>(
            &treasury,
            &mut fee_manager,
            &pool,
            &balance_manager,
            &config,
            &admin_cap,
            order_id,
            scenario.ctx(),
        );

        // Verify the unsettled fee object has been destroyed
        assert_eq!(
            fee_manager.has_user_unsettled_fee(pool_id, balance_manager_id, order_id),
            false,
        );

        destroy(admin_cap);
        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(pool);
        return_shared(balance_manager);
        return_shared(config);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = ESenderIsNotValidMultisig)]
/// Test that a non-multisig sender cannot claim a rebate via the admin function.
fun non_multisig_admin_claim_fails() {
    let (
        mut scenario,
        pool_id,
        balance_manager_id,
        fee_manager_id,
        order_id,
    ) = setup_filled_order_for_rebate();

    // Attempt to claim as a regular user, not the multisig admin
    scenario.next_tx(UNRELATED_USER);
    {
        let treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let pool = scenario.take_shared_by_id(pool_id);
        let balance_manager = scenario.take_shared_by_id(balance_manager_id);
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        claim_user_unsettled_fee_storage_rebate_admin<SUI, USDC, SUI>(
            &treasury,
            &mut fee_manager,
            &pool,
            &balance_manager,
            &config,
            &admin_cap,
            order_id,
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(pool);
        return_shared(balance_manager);
        return_shared(config);
    };

    end(scenario);
}

#[test_only]
public(package) fun setup_filled_order_for_rebate(): (Scenario, ID, ID, ID, u128) {
    let (mut scenario, pool_id, balance_manager_id, fee_manager_id) = setup_test_environment();

    // Step 1: Alice places a buy order and adds an unsettled fee.
    scenario.next_tx(ALICE);
    let order_id = {
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let order_info = deepbook::pool_tests::place_limit_order<SUI, USDC>(
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
        let balance_manager_id_bob = create_acct_and_share_with_funds(
            BOB,
            1_000_000 * constants::float_scaling(),
            &mut scenario,
        );

        deepbook::pool_tests::place_limit_order<SUI, USDC>(
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

    // Step 3: Settle the protocol fee, leaving an empty fee object.
    scenario.next_tx(OWNER);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let pool = scenario.take_shared_by_id(pool_id);
        let balance_manager = scenario.take_shared_by_id(balance_manager_id);
        let mut receipt = start_protocol_fee_settlement<SUI>();

        settle_filled_order_fee_and_record<SUI, USDC, SUI>(
            &mut treasury,
            &mut fee_manager,
            &mut receipt,
            &pool,
            &balance_manager,
            order_id,
        );

        receipt.finish_protocol_fee_settlement_for_testing();

        // Verify the unsettled fee is now empty but still exists.
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

    (scenario, pool_id, balance_manager_id, fee_manager_id, order_id)
}

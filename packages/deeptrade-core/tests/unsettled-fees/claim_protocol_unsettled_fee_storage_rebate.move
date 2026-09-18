#[test_only]
module deeptrade_core::claim_protocol_unsettled_fee_storage_rebate_tests;

use deepbook::balance_manager_tests::USDC;
use deeptrade_core::create_rebates_claimer_cap_tests::create_rebates_claimer_cap_as_admin;
use deeptrade_core::fee_manager::{
    FeeManager,
    RebatesClaimerCap,
    claim_protocol_unsettled_fee_storage_rebate,
    claim_protocol_unsettled_fee_storage_rebate_admin,
    claim_protocol_unsettled_fee_storage_rebate_claimer,
    settle_protocol_fee_and_record,
    start_protocol_fee_settlement,
    EInvalidOwner,
    EProtocolUnsettledFeeNotEmpty,
    ESenderIsNotRebatesClaimer,
};
use deeptrade_core::multisig_config::{MultisigConfig, ESenderIsNotValidMultisig};
use deeptrade_core::settle_user_fees_tests::setup_test_environment;
use deeptrade_core::treasury::Treasury;
use deeptrade_core::update_rebates_claimer_cap_owner_tests::update_rebates_claimer_cap_owner_as_admin;
use multisig::multisig_test_utils::get_test_multisig_address;
use std::unit_test::assert_eq;
use sui::balance;
use sui::sui::SUI;
use sui::test_scenario::{Scenario, end, return_shared, take_shared, take_shared_by_id};
use sui::test_utils::destroy;

// === Constants ===
const ALICE: address = @0xAAAA;
const UNRELATED_USER: address = @0xCCCC;
const BOB: address = @0xBBBB;
const CLAIMER: address = @0xDDDD;

#[test]
/// Test that the owner can claim a storage rebate for a settled fee.
fun owner_claims_rebate_successfully() {
    let (mut scenario, fee_manager_id) = setup_protocol_fee_for_rebate();

    // Claim the storage rebate as the fee manager owner
    scenario.next_tx(ALICE);
    {
        let treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        claim_protocol_unsettled_fee_storage_rebate<SUI>(
            &treasury,
            &mut fee_manager,
            scenario.ctx(),
        );

        // Verify the unsettled fee object has been destroyed
        assert_eq!(fee_manager.has_protocol_unsettled_fee<SUI>(), false);

        return_shared(treasury);
        return_shared(fee_manager);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = EInvalidOwner)]
/// Test that a non-owner cannot claim a storage rebate.
fun unauthorized_user_claim_fails() {
    let (mut scenario, fee_manager_id) = setup_protocol_fee_for_rebate();

    // Attempt to claim as an unrelated user
    scenario.next_tx(UNRELATED_USER);
    {
        let treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        claim_protocol_unsettled_fee_storage_rebate<SUI>(
            &treasury,
            &mut fee_manager,
            scenario.ctx(),
        );
        return_shared(treasury);
        return_shared(fee_manager);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = EProtocolUnsettledFeeNotEmpty)]
/// Test that claiming a rebate for a non-empty (unsettled) fee fails.
fun claim_for_unsettled_fee_fails() {
    let (mut scenario, _pool_id, _balance_manager_id, fee_manager_id) = setup_test_environment();

    // Step 1: Add a protocol fee, but do not settle it.
    scenario.next_tx(ALICE);
    {
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let fee_balance = balance::create_for_testing<SUI>(1000);
        fee_manager.add_to_protocol_unsettled_fees(
            fee_balance,
            scenario.ctx(),
        );
        return_shared(fee_manager);
    };

    // Step 2: Attempt to claim the rebate without settling the fee first.
    scenario.next_tx(ALICE);
    {
        let treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        claim_protocol_unsettled_fee_storage_rebate<SUI>(
            &treasury,
            &mut fee_manager,
            scenario.ctx(),
        );
        return_shared(treasury);
        return_shared(fee_manager);
    };

    end(scenario);
}

#[test]
/// Test that claiming a rebate for an coin type with no unsettled fee does nothing.
fun claim_for_non_existent_fee_is_noop() {
    let (mut scenario, _pool_id, _balance_manager_id, fee_manager_id) = setup_test_environment();

    scenario.next_tx(ALICE);
    {
        let treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);

        // Verify that the fee does not exist for USDC.
        assert_eq!(fee_manager.has_protocol_unsettled_fee<USDC>(), false);

        // This should be a no-op since the fee does not exist for USDC.
        claim_protocol_unsettled_fee_storage_rebate<USDC>(
            &treasury,
            &mut fee_manager,
            scenario.ctx(),
        );

        // Verify that nothing has changed.
        assert_eq!(fee_manager.has_protocol_unsettled_fee<USDC>(), false);

        return_shared(treasury);
        return_shared(fee_manager);
    };

    end(scenario);
}

#[test]
/// Test that a protocol admin can claim a protocol's storage rebate.
fun admin_claims_rebate_successfully() {
    let (mut scenario, fee_manager_id) = setup_protocol_fee_for_rebate();

    let multisig_address = get_test_multisig_address();
    scenario.next_tx(multisig_address);
    {
        let treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        claim_protocol_unsettled_fee_storage_rebate_admin<SUI>(
            &treasury,
            &mut fee_manager,
            &config,
            &admin_cap,
            scenario.ctx(),
        );

        // Verify the unsettled fee object has been destroyed
        assert_eq!(fee_manager.has_protocol_unsettled_fee<SUI>(), false);

        destroy(admin_cap);
        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(config);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = ESenderIsNotValidMultisig)]
/// Test that a non-multisig sender cannot claim a rebate via the admin function.
fun non_multisig_admin_claim_fails() {
    let (mut scenario, fee_manager_id) = setup_protocol_fee_for_rebate();

    // Attempt to claim as a regular user, not the multisig admin
    scenario.next_tx(UNRELATED_USER);
    {
        let treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let config = scenario.take_shared<MultisigConfig>();
        let admin_cap = deeptrade_core::admin::get_admin_cap_for_testing(scenario.ctx());

        claim_protocol_unsettled_fee_storage_rebate_admin<SUI>(
            &treasury,
            &mut fee_manager,
            &config,
            &admin_cap,
            scenario.ctx(),
        );

        destroy(admin_cap);
        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(config);
    };

    end(scenario);
}

#[test]
/// Test that a rebates claimer can claim a protocol's storage rebate.
fun claimer_claims_rebate_successfully() {
    let (mut scenario, fee_manager_id) = setup_protocol_fee_for_rebate();

    create_rebates_claimer_cap_as_admin(&mut scenario, CLAIMER);

    scenario.next_tx(CLAIMER);
    {
        let treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let rebates_claimer_cap = scenario.take_shared<RebatesClaimerCap>();

        claim_protocol_unsettled_fee_storage_rebate_claimer<SUI>(
            &treasury,
            &mut fee_manager,
            &rebates_claimer_cap,
            scenario.ctx(),
        );

        assert_eq!(fee_manager.has_protocol_unsettled_fee<SUI>(), false);

        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(rebates_claimer_cap);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = ESenderIsNotRebatesClaimer)]
/// Test that a non-claimer cannot claim a rebate via the claimer function.
fun unauthorized_claimer_claim_fails() {
    let (mut scenario, fee_manager_id) = setup_protocol_fee_for_rebate();

    create_rebates_claimer_cap_as_admin(&mut scenario, CLAIMER);

    scenario.next_tx(UNRELATED_USER);
    {
        let treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let rebates_claimer_cap = scenario.take_shared<RebatesClaimerCap>();

        claim_protocol_unsettled_fee_storage_rebate_claimer<SUI>(
            &treasury,
            &mut fee_manager,
            &rebates_claimer_cap,
            scenario.ctx(),
        );

        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(rebates_claimer_cap);
    };

    end(scenario);
}

#[test]
/// Test that the new cap owner can claim after ownership is transferred.
fun new_claimer_can_claim_after_owner_update() {
    let (mut scenario, fee_manager_id) = setup_protocol_fee_for_rebate();

    create_rebates_claimer_cap_as_admin(&mut scenario, CLAIMER);
    update_rebates_claimer_cap_owner_as_admin(&mut scenario, BOB);

    scenario.next_tx(BOB);
    {
        let treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let rebates_claimer_cap = scenario.take_shared<RebatesClaimerCap>();

        claim_protocol_unsettled_fee_storage_rebate_claimer<SUI>(
            &treasury,
            &mut fee_manager,
            &rebates_claimer_cap,
            scenario.ctx(),
        );

        assert_eq!(fee_manager.has_protocol_unsettled_fee<SUI>(), false);

        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(rebates_claimer_cap);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = ESenderIsNotRebatesClaimer)]
/// Test that the previous cap owner cannot claim after ownership is transferred.
fun old_claimer_cannot_claim_after_owner_update() {
    let (mut scenario, fee_manager_id) = setup_protocol_fee_for_rebate();

    create_rebates_claimer_cap_as_admin(&mut scenario, CLAIMER);
    update_rebates_claimer_cap_owner_as_admin(&mut scenario, BOB);

    scenario.next_tx(CLAIMER);
    {
        let treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let rebates_claimer_cap = scenario.take_shared<RebatesClaimerCap>();

        claim_protocol_unsettled_fee_storage_rebate_claimer<SUI>(
            &treasury,
            &mut fee_manager,
            &rebates_claimer_cap,
            scenario.ctx(),
        );

        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(rebates_claimer_cap);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = ESenderIsNotRebatesClaimer)]
/// Test that the FeeManager owner cannot claim via the claimer function.
fun fee_manager_owner_cannot_claim_via_claimer() {
    let (mut scenario, fee_manager_id) = setup_protocol_fee_for_rebate();

    create_rebates_claimer_cap_as_admin(&mut scenario, CLAIMER);

    scenario.next_tx(ALICE);
    {
        let treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let rebates_claimer_cap = scenario.take_shared<RebatesClaimerCap>();

        claim_protocol_unsettled_fee_storage_rebate_claimer<SUI>(
            &treasury,
            &mut fee_manager,
            &rebates_claimer_cap,
            scenario.ctx(),
        );

        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(rebates_claimer_cap);
    };

    end(scenario);
}

#[test, expected_failure(abort_code = EProtocolUnsettledFeeNotEmpty)]
/// Test that a claimer cannot claim a rebate for a non-empty (unsettled) fee.
fun claimer_claim_for_unsettled_fee_fails() {
    let (mut scenario, _pool_id, _balance_manager_id, fee_manager_id) = setup_test_environment();

    create_rebates_claimer_cap_as_admin(&mut scenario, CLAIMER);

    scenario.next_tx(ALICE);
    {
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let fee_balance = balance::create_for_testing<SUI>(1000);
        fee_manager.add_to_protocol_unsettled_fees(
            fee_balance,
            scenario.ctx(),
        );
        return_shared(fee_manager);
    };

    scenario.next_tx(CLAIMER);
    {
        let treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let rebates_claimer_cap = scenario.take_shared<RebatesClaimerCap>();

        claim_protocol_unsettled_fee_storage_rebate_claimer<SUI>(
            &treasury,
            &mut fee_manager,
            &rebates_claimer_cap,
            scenario.ctx(),
        );

        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(rebates_claimer_cap);
    };

    end(scenario);
}

#[test]
/// Test that a claimer claiming a rebate for a coin type with no unsettled fee does nothing.
fun claimer_claim_for_non_existent_fee_is_noop() {
    let (mut scenario, _pool_id, _balance_manager_id, fee_manager_id) = setup_test_environment();

    create_rebates_claimer_cap_as_admin(&mut scenario, CLAIMER);

    scenario.next_tx(CLAIMER);
    {
        let treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let rebates_claimer_cap = scenario.take_shared<RebatesClaimerCap>();

        assert_eq!(fee_manager.has_protocol_unsettled_fee<USDC>(), false);

        claim_protocol_unsettled_fee_storage_rebate_claimer<USDC>(
            &treasury,
            &mut fee_manager,
            &rebates_claimer_cap,
            scenario.ctx(),
        );

        assert_eq!(fee_manager.has_protocol_unsettled_fee<USDC>(), false);

        return_shared(treasury);
        return_shared(fee_manager);
        return_shared(rebates_claimer_cap);
    };

    end(scenario);
}

/// Sets up a test scenario where a protocol fee has been settled, leaving an empty
/// `Balance` object ready for a storage rebate claim.
#[test_only]
public(package) fun setup_protocol_fee_for_rebate(): (Scenario, ID) {
    let (mut scenario, _pool_id, _balance_manager_id, fee_manager_id) = setup_test_environment();

    // Step 1: Add a fee to the protocol's unsettled fees.
    scenario.next_tx(ALICE);
    {
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let fee_balance = balance::create_for_testing<SUI>(1000);
        fee_manager.add_to_protocol_unsettled_fees(
            fee_balance,
            scenario.ctx(),
        );
        return_shared(fee_manager);
    };

    // Step 2: Settle the protocol fee, leaving an empty fee object.
    // Can be any user, using BOB here.
    scenario.next_tx(BOB);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let mut fee_manager = scenario.take_shared_by_id<FeeManager>(fee_manager_id);
        let mut receipt = start_protocol_fee_settlement<SUI>();

        settle_protocol_fee_and_record<SUI>(
            &mut treasury,
            &mut fee_manager,
            &mut receipt,
        );

        let (count, total) = receipt.finish_protocol_fee_settlement_for_testing();
        assert_eq!(count, 0); // orders_count is not incremented for protocol fees
        assert_eq!(total, 1000);

        // Verify the unsettled fee is now empty but still exists.
        assert_eq!(fee_manager.has_protocol_unsettled_fee<SUI>(), true);
        assert_eq!(fee_manager.get_protocol_unsettled_fee_balance<SUI>(), 0);

        return_shared(treasury);
        return_shared(fee_manager);
    };

    (scenario, fee_manager_id)
}

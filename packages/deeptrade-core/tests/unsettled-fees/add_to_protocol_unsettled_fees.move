#[test_only]
module deeptrade_core::add_to_protocol_unsettled_fees_tests;

use deeptrade_core::add_to_user_unsettled_fees_tests::setup_fee_manager_test;
use deeptrade_core::fee_manager::FeeManager;
use std::unit_test::assert_eq;
use sui::balance;
use sui::sui::SUI;
use sui::test_scenario;
use token::deep::DEEP;

// === Constants ===
const OWNER: address = @0x1;
const UNAUTHORIZED: address = @0xDEADBEEF;

#[test]
fun add_fee_for_new_coin_type_success() {
    let mut scenario = setup_fee_manager_test(OWNER);
    let fee_amount = 1000u64;

    scenario.next_tx(OWNER);
    {
        let mut fee_manager = scenario.take_shared<FeeManager>();
        let fee_balance = balance::create_for_testing<SUI>(fee_amount);

        // Verify fee doesn't exist before adding
        assert_eq!(fee_manager.has_protocol_unsettled_fee<SUI>(), false);

        // Add fee
        fee_manager.add_to_protocol_unsettled_fees(fee_balance, scenario.ctx());

        // Verify fee was stored correctly
        assert_eq!(fee_manager.has_protocol_unsettled_fee<SUI>(), true);
        assert_eq!(fee_manager.get_protocol_unsettled_fee_balance<SUI>(), fee_amount);

        test_scenario::return_shared(fee_manager);
    };

    scenario.end();
}

#[test]
fun aggregate_fees_for_existing_coin_type_success() {
    let mut scenario = setup_fee_manager_test(OWNER);
    let fee_amount_1 = 1000u64;
    let fee_amount_2 = 500u64;
    let expected_total_fee = fee_amount_1 + fee_amount_2;

    scenario.next_tx(OWNER);
    {
        let mut fee_manager = scenario.take_shared<FeeManager>();
        let ctx = scenario.ctx();
        let fee_balance_1 = balance::create_for_testing<SUI>(fee_amount_1);
        let fee_balance_2 = balance::create_for_testing<SUI>(fee_amount_2);

        // Add first fee
        fee_manager.add_to_protocol_unsettled_fees(fee_balance_1, ctx);
        assert_eq!(fee_manager.get_protocol_unsettled_fee_balance<SUI>(), fee_amount_1);

        // Add second fee
        fee_manager.add_to_protocol_unsettled_fees(fee_balance_2, ctx);

        // Verify total fee is aggregated
        assert_eq!(fee_manager.get_protocol_unsettled_fee_balance<SUI>(), expected_total_fee);

        test_scenario::return_shared(fee_manager);
    };

    scenario.end();
}

#[test]
fun handle_zero_value_fee_gracefully() {
    let mut scenario = setup_fee_manager_test(OWNER);

    scenario.next_tx(OWNER);
    {
        let mut fee_manager = scenario.take_shared<FeeManager>();
        let fee_balance = balance::create_for_testing<SUI>(0);

        // Verify fee doesn't exist
        assert_eq!(fee_manager.has_protocol_unsettled_fee<SUI>(), false);

        // Add zero fee
        fee_manager.add_to_protocol_unsettled_fees(fee_balance, scenario.ctx());

        // Verify fee still doesn't exist
        assert_eq!(fee_manager.has_protocol_unsettled_fee<SUI>(), false);

        test_scenario::return_shared(fee_manager);
    };

    scenario.end();
}

#[test]
fun handle_multiple_distinct_coin_types_correctly() {
    let mut scenario = setup_fee_manager_test(OWNER);
    let sui_fee_amount = 1000u64;
    let deep_fee_amount = 500u64;

    scenario.next_tx(OWNER);
    {
        let mut fee_manager = scenario.take_shared<FeeManager>();
        let ctx = scenario.ctx();
        let sui_fee = balance::create_for_testing<SUI>(sui_fee_amount);
        let deep_fee = balance::create_for_testing<DEEP>(deep_fee_amount);

        // Verify no fees exist
        assert_eq!(fee_manager.has_protocol_unsettled_fee<SUI>(), false);
        assert_eq!(fee_manager.has_protocol_unsettled_fee<DEEP>(), false);

        // Add SUI fee
        fee_manager.add_to_protocol_unsettled_fees(sui_fee, ctx);

        // Add DEEP fee
        fee_manager.add_to_protocol_unsettled_fees(deep_fee, ctx);

        // Verify both fees exist and are stored correctly
        assert_eq!(fee_manager.has_protocol_unsettled_fee<SUI>(), true);
        assert_eq!(fee_manager.has_protocol_unsettled_fee<DEEP>(), true);
        assert_eq!(fee_manager.get_protocol_unsettled_fee_balance<SUI>(), sui_fee_amount);
        assert_eq!(fee_manager.get_protocol_unsettled_fee_balance<DEEP>(), deep_fee_amount);

        test_scenario::return_shared(fee_manager);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = deeptrade_core::fee_manager::EInvalidOwner)]
fun add_with_unauthorized_user_fails() {
    let mut scenario = setup_fee_manager_test(OWNER);

    scenario.next_tx(UNAUTHORIZED);
    {
        let mut fee_manager = scenario.take_shared<FeeManager>();
        let fee_balance = balance::create_for_testing<SUI>(1000);

        fee_manager.add_to_protocol_unsettled_fees(fee_balance, scenario.ctx());

        test_scenario::return_shared(fee_manager);
    };

    scenario.end();
}

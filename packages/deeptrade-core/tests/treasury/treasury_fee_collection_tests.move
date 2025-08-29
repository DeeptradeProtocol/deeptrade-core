#[test_only]
module deeptrade_core::treasury_fee_collection_tests;

use deeptrade_core::treasury::{Self, Treasury};
use sui::balance;
use sui::test_scenario::{Self, Scenario};

// Dummy coin types to simulate fees from different assets
#[test_only]
public struct DUMMY_COIN_1 has drop {}

#[test_only]
public struct DUMMY_COIN_2 has drop {}

const USER: address = @0xCAFE;
const FEE_AMOUNT_1: u64 = 100_000_000;
const FEE_AMOUNT_2: u64 = 250_000_000;

#[test]
fun test_join_first_protocol_fee() {
    let mut scenario = setup();

    scenario.next_tx(USER);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let fee_balance = balance::create_for_testing<DUMMY_COIN_1>(FEE_AMOUNT_1);

        let balance_before = treasury.get_protocol_fee_balance<DUMMY_COIN_1>();
        assert!(balance_before == 0, 1);

        treasury.join_protocol_fee(fee_balance);

        let balance_after = treasury.get_protocol_fee_balance<DUMMY_COIN_1>();
        assert!(balance_after == FEE_AMOUNT_1, 2);

        // Verify another coin type is unaffected
        let other_balance = treasury.get_protocol_fee_balance<DUMMY_COIN_2>();
        assert!(other_balance == 0, 3);

        test_scenario::return_shared(treasury);
    };

    scenario.end();
}

#[test]
fun test_join_subsequent_protocol_fee() {
    let mut scenario = setup();

    scenario.next_tx(USER);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let fee_balance_1 = balance::create_for_testing<DUMMY_COIN_1>(FEE_AMOUNT_1);
        let fee_balance_2 = balance::create_for_testing<DUMMY_COIN_1>(FEE_AMOUNT_2);

        // Join first fee
        treasury.join_protocol_fee(fee_balance_1);
        let balance_after_1 = treasury.get_protocol_fee_balance<DUMMY_COIN_1>();
        assert!(balance_after_1 == FEE_AMOUNT_1, 1);

        // Join second fee
        treasury.join_protocol_fee(fee_balance_2);
        let balance_after_2 = treasury.get_protocol_fee_balance<DUMMY_COIN_1>();
        assert!(balance_after_2 == FEE_AMOUNT_1 + FEE_AMOUNT_2, 2);

        test_scenario::return_shared(treasury);
    };

    scenario.end();
}

#[test]
fun test_join_coverage_fee() {
    let mut scenario = setup();

    scenario.next_tx(USER);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let fee_balance_1 = balance::create_for_testing<DUMMY_COIN_1>(FEE_AMOUNT_1);
        let fee_balance_2 = balance::create_for_testing<DUMMY_COIN_1>(FEE_AMOUNT_2);

        // Join first fee
        treasury.join_coverage_fee(fee_balance_1);
        let balance_after_1 = treasury.get_deep_reserves_coverage_fee_balance<DUMMY_COIN_1>();
        assert!(balance_after_1 == FEE_AMOUNT_1, 1);

        // Join second fee
        treasury.join_coverage_fee(fee_balance_2);
        let balance_after_2 = treasury.get_deep_reserves_coverage_fee_balance<DUMMY_COIN_1>();
        assert!(balance_after_2 == FEE_AMOUNT_1 + FEE_AMOUNT_2, 2);

        // Verify protocol fee balance is unaffected
        let protocol_balance = treasury.get_protocol_fee_balance<DUMMY_COIN_1>();
        assert!(protocol_balance == 0, 3);

        test_scenario::return_shared(treasury);
    };

    scenario.end();
}

#[test]
fun test_join_zero_value_protocol_fee() {
    let mut scenario = setup();

    scenario.next_tx(USER);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let zero_fee_balance = balance::create_for_testing<DUMMY_COIN_1>(0);

        let balance_before = treasury.get_protocol_fee_balance<DUMMY_COIN_1>();
        assert!(balance_before == 0, 1);

        // This should not abort and should not change the balance
        treasury.join_protocol_fee(zero_fee_balance);

        let balance_after = treasury.get_protocol_fee_balance<DUMMY_COIN_1>();
        assert!(balance_after == 0, 2);

        test_scenario::return_shared(treasury);
    };

    scenario.end();
}

#[test]
fun test_join_zero_value_coverage_fee() {
    let mut scenario = setup();

    scenario.next_tx(USER);
    {
        let mut treasury = scenario.take_shared<Treasury>();
        let zero_fee_balance = balance::create_for_testing<DUMMY_COIN_1>(0);

        let balance_before = treasury.get_deep_reserves_coverage_fee_balance<DUMMY_COIN_1>();
        assert!(balance_before == 0, 1);

        // This should not abort and should not change the balance
        treasury.join_coverage_fee(zero_fee_balance);

        let balance_after = treasury.get_deep_reserves_coverage_fee_balance<DUMMY_COIN_1>();
        assert!(balance_after == 0, 2);

        test_scenario::return_shared(treasury);
    };

    scenario.end();
}

// === Helper Functions ===

#[test_only]
fun setup(): Scenario {
    let mut scenario = test_scenario::begin(USER);

    // Initialise treasury
    scenario.next_tx(USER);
    {
        treasury::init_for_testing(scenario.ctx());
    };

    scenario
}

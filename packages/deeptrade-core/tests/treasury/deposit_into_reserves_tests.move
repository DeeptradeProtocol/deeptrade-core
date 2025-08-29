#[test_only]
module deeptrade_core::deposit_into_reserves_tests;

use deeptrade_core::treasury::{
    Self,
    Treasury,
    DeepReservesDeposited,
    unwrap_deep_reserves_deposited_event
};
use sui::event;
use sui::test_scenario::{Self, Scenario};
use token::deep::DEEP;

const USER: address = @0xCAFE;
const DEPOSIT_AMOUNT: u64 = 1_000_000_000;

#[test]
fun test_deposit_success() {
    let mut scenario = setup();

    // Deposit DEEP into reserves
    scenario.next_tx(USER);
    {
        let deep_coin = sui::coin::mint_for_testing<DEEP>(DEPOSIT_AMOUNT, scenario.ctx());
        let mut treasury: Treasury = scenario.take_shared<Treasury>();
        let treasury_id = object::id(&treasury);

        let reserves_before = treasury.deep_reserves();
        treasury::deposit_into_reserves(&mut treasury, deep_coin);
        let reserves_after = treasury.deep_reserves();

        assert!(reserves_after == reserves_before + DEPOSIT_AMOUNT, 1);

        // Verify event
        let deposited_events = event::events_by_type<DeepReservesDeposited<DEEP>>();
        assert!(deposited_events.length() == 1, 2);
        let (event_treasury_id, event_amount) = unwrap_deep_reserves_deposited_event(
            &deposited_events[0],
        );
        assert!(event_treasury_id == treasury_id, 3);
        assert!(event_amount == DEPOSIT_AMOUNT, 4);

        test_scenario::return_shared(treasury);
    };

    scenario.end();
}

#[test]
fun test_deposit_zero_value() {
    let mut scenario = setup();

    // Attempt to deposit a zero-value coin
    scenario.next_tx(USER);
    {
        let zero_coin = sui::coin::mint_for_testing<DEEP>(0, scenario.ctx());
        let mut treasury: Treasury = scenario.take_shared<Treasury>();

        let reserves_before = treasury.deep_reserves();
        treasury::deposit_into_reserves(&mut treasury, zero_coin);
        let reserves_after = treasury.deep_reserves();

        assert!(reserves_after == reserves_before, 1);

        // Verify no event was emitted
        let deposited_events = event::events_by_type<DeepReservesDeposited<DEEP>>();
        assert!(deposited_events.length() == 0, 2);

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

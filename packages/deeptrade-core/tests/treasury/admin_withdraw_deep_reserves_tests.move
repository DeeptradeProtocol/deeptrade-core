#[test_only]
module deeptrade_core::admin_withdraw_deep_reserves_tests;

use deeptrade_core::admin_init_tests::setup_with_admin_cap;
use deeptrade_core::create_ticket_tests::create_ticket_with_multisig;
use deeptrade_core::ticket::{
    AdminTicket,
    ETicketTypeMismatch,
    TicketDestroyed,
    ticket_delay_duration,
    unwrap_ticket_destroyed_event,
    update_default_fees_ticket_type,
    withdraw_deep_reserves_ticket_type
};
use deeptrade_core::treasury::{
    Self,
    Treasury,
    init_for_testing,
    unwrap_deep_reserves_withdrawn_event,
    DeepReservesWithdrawn,
    EInsufficientDeepReserves
};
use multisig::multisig_test_utils::get_test_multisig_address;
use sui::clock;
use sui::coin;
use sui::event;
use sui::test_scenario::{Self, Scenario};
use token::deep::DEEP;

const DEPOSIT_AMOUNT: u64 = 1_000_000_000;

/// Test successful withdrawal of deep reserves using a valid ticket
#[test]
fun test_withdraw_deep_reserves_success() {
    let (mut scenario) = setup_with_deposit();
    let multisig_address = get_test_multisig_address();

    let ticket_type = withdraw_deep_reserves_ticket_type();
    create_ticket_with_multisig(&mut scenario, ticket_type);
    let ticket: AdminTicket = scenario.take_shared<AdminTicket>();
    let ticket_id = object::id(&ticket);

    // Advance time to make the ticket ready
    let delay = ticket_delay_duration();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(delay);

    // Perform the withdrawal
    scenario.next_tx(multisig_address);
    let mut treasury: Treasury = scenario.take_shared<Treasury>();
    let withdrawn_coin = treasury::withdraw_deep_reserves(
        &mut treasury,
        ticket,
        DEPOSIT_AMOUNT,
        &clock,
        scenario.ctx(),
    );
    let treasury_id = object::id(&treasury);

    // Verify coin amount and burn it
    assert!(coin::value(&withdrawn_coin) == DEPOSIT_AMOUNT, 0);
    coin::burn_for_testing(withdrawn_coin);

    // Verify TicketDestroyed event
    let consumed_ticket_events = event::events_by_type<TicketDestroyed>();
    assert!(consumed_ticket_events.length() == 1, 1);
    let (event_ticket_id, event_ticket_type, event_is_expired) = unwrap_ticket_destroyed_event(
        &consumed_ticket_events[0],
    );

    assert!(event_ticket_id == ticket_id, 2);
    assert!(event_ticket_type == ticket_type, 3);
    assert!(!event_is_expired, 4);

    // Verify DeepReservesWithdrawn event
    let deep_reserves_withdrawn_events = event::events_by_type<DeepReservesWithdrawn<DEEP>>();
    assert!(deep_reserves_withdrawn_events.length() == 1, 5);
    let (event_treasury_id, event_amount) = unwrap_deep_reserves_withdrawn_event(
        &deep_reserves_withdrawn_events[0],
    );
    assert!(event_treasury_id == treasury_id, 6);
    assert!(event_amount == DEPOSIT_AMOUNT, 7);

    clock::destroy_for_testing(clock);
    test_scenario::return_shared(treasury);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = ETicketTypeMismatch)]
/// Test withdrawal fails when using a ticket of the wrong type
fun test_withdraw_deep_reserves_fails_wrong_ticket_type() {
    let (mut scenario) = setup_with_deposit();
    let multisig_address = get_test_multisig_address();

    // Create a ticket of an incorrect type
    let wrong_ticket_type = update_default_fees_ticket_type();
    create_ticket_with_multisig(&mut scenario, wrong_ticket_type);

    // Advance time to make the ticket ready
    let delay = ticket_delay_duration();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(delay);

    let mut treasury: Treasury = scenario.take_shared<Treasury>();
    let ticket_to_use: AdminTicket = scenario.take_shared<AdminTicket>();

    // Attempt the withdrawal, which should fail
    scenario.next_tx(multisig_address);

    let withdrawn_coin = treasury::withdraw_deep_reserves(
        &mut treasury,
        ticket_to_use,
        DEPOSIT_AMOUNT,
        &clock,
        scenario.ctx(),
    );
    test_scenario::return_shared(treasury);
    coin::burn_for_testing(withdrawn_coin);

    clock::destroy_for_testing(clock);
    scenario.end();
}

#[test]
#[expected_failure(abort_code = EInsufficientDeepReserves)]
fun test_withdraw_deep_reserves_fails_insufficient_funds() {
    let (mut scenario) = setup_with_deposit();
    let multisig_address = get_test_multisig_address();

    let ticket_type = withdraw_deep_reserves_ticket_type();
    create_ticket_with_multisig(&mut scenario, ticket_type);
    let ticket: AdminTicket = scenario.take_shared<AdminTicket>();

    // Advance time to make the ticket ready
    let delay = ticket_delay_duration();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(delay);

    // Attempt the withdrawal, which should fail
    scenario.next_tx(multisig_address);
    let mut treasury: Treasury = scenario.take_shared<Treasury>();

    // Attempt to withdraw more than was deposited
    let withdrawn_coin = treasury::withdraw_deep_reserves(
        &mut treasury,
        ticket,
        DEPOSIT_AMOUNT + 1, // The crucial part
        &clock,
        scenario.ctx(),
    );

    // Cleanup - these lines should not be reached
    test_scenario::return_shared(treasury);
    coin::burn_for_testing(withdrawn_coin);
    clock::destroy_for_testing(clock);
    scenario.end();
}

// === Helper Functions ===
/// Setup a scenario with a treasury and a DEEP coin deposit
#[test_only]
fun setup_with_deposit(): Scenario {
    let multisig_address = get_test_multisig_address();
    let (mut scenario) = setup_with_admin_cap(multisig_address);

    // Init treasury and get its ID
    scenario.next_tx(multisig_address);
    {
        init_for_testing(scenario.ctx());
    };

    // Deposit DEEP into reserves
    scenario.next_tx(@0xDEADBEEF);
    {
        let deep_coin = coin::mint_for_testing<DEEP>(DEPOSIT_AMOUNT, scenario.ctx());
        let mut treasury: Treasury = scenario.take_shared<Treasury>();
        treasury::deposit_into_reserves(&mut treasury, deep_coin);
        test_scenario::return_shared(treasury);
    };

    scenario
}

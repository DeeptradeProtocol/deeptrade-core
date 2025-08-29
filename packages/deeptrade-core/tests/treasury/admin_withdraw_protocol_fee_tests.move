#[test_only]
module deeptrade_core::admin_withdraw_protocol_fee_tests;

use deeptrade_core::admin_init_tests::setup_with_admin_cap;
use deeptrade_core::create_ticket_tests::create_ticket_with_multisig;
use deeptrade_core::ticket::{
    AdminTicket,
    ETicketTypeMismatch,
    TicketDestroyed,
    ticket_delay_duration,
    unwrap_ticket_destroyed_event,
    withdraw_deep_reserves_ticket_type,
    withdraw_protocol_fee_ticket_type
};
use deeptrade_core::treasury::{
    Self,
    Treasury,
    ProtocolFeeWithdrawn,
    init_for_testing,
    join_protocol_fee,
    unwrap_protocol_fee_withdrawn_event
};
use multisig::multisig_test_utils::get_test_multisig_address;
use sui::balance;
use sui::clock;
use sui::coin;
use sui::event;
use sui::test_scenario::{Self, Scenario};

const DEPOSIT_AMOUNT: u64 = 1_000_000_000;

#[test_only]
public struct COIN has drop {}

#[test_only]
public struct UNUSED_COIN has drop {}

/// Test successful withdrawal of protocol fees using a valid ticket
#[test]
fun test_withdraw_protocol_fee_success() {
    let (mut scenario) = setup_with_deposit();
    let multisig_address = get_test_multisig_address();

    let ticket_type = withdraw_protocol_fee_ticket_type();
    create_ticket_with_multisig(&mut scenario, ticket_type);
    let ticket: AdminTicket = scenario.take_shared<AdminTicket>();
    let ticket_id = object::id(&ticket);

    let delay = ticket_delay_duration();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(delay);

    scenario.next_tx(multisig_address);
    let mut treasury: Treasury = scenario.take_shared<Treasury>();
    let treasury_id = object::id(&treasury);
    let withdrawn_coin = treasury::withdraw_protocol_fee<COIN>(
        &mut treasury,
        ticket,
        &clock,
        scenario.ctx(),
    );

    assert!(coin::value(&withdrawn_coin) == DEPOSIT_AMOUNT, 0);
    coin::burn_for_testing(withdrawn_coin);

    let consumed_ticket_events = event::events_by_type<TicketDestroyed>();
    assert!(vector::length(&consumed_ticket_events) == 1, 1);
    let (event_ticket_id, _, _) = unwrap_ticket_destroyed_event(
        vector::borrow(&consumed_ticket_events, 0),
    );
    assert!(event_ticket_id == ticket_id, 2);

    let withdrawn_events = event::events_by_type<ProtocolFeeWithdrawn<COIN>>();
    assert!(vector::length(&withdrawn_events) == 1, 3);
    let (event_treasury_id, event_amount) = unwrap_protocol_fee_withdrawn_event(
        vector::borrow(&withdrawn_events, 0),
    );
    assert!(event_treasury_id == treasury_id, 4);
    assert!(event_amount == DEPOSIT_AMOUNT, 5);

    clock::destroy_for_testing(clock);
    test_scenario::return_shared(treasury);
    scenario.end();
}

/// Test withdrawal fails when using a ticket of the wrong type
#[test]
#[expected_failure(abort_code = ETicketTypeMismatch)]
fun test_withdraw_protocol_fee_fails_wrong_ticket_type() {
    let (mut scenario) = setup_with_deposit();
    let multisig_address = get_test_multisig_address();

    let wrong_ticket_type = withdraw_deep_reserves_ticket_type();
    create_ticket_with_multisig(&mut scenario, wrong_ticket_type);
    let ticket: AdminTicket = scenario.take_shared<AdminTicket>();

    let delay = ticket_delay_duration();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(delay);

    scenario.next_tx(multisig_address);
    let mut treasury: Treasury = scenario.take_shared<Treasury>();
    let coin = treasury::withdraw_protocol_fee<COIN>(
        &mut treasury,
        ticket,
        &clock,
        scenario.ctx(),
    );
    coin::burn_for_testing(coin); // Burn the coin to satisfy the linter

    test_scenario::return_shared(treasury);
    clock::destroy_for_testing(clock);
    scenario.end();
}

#[test]
/// Test withdrawal returns a zero coin when no fees have been collected for the given coin type
fun test_withdraw_protocol_fee_no_fees_returns_zero() {
    let (mut scenario) = setup_with_deposit(); // Re-using setup, but will withdraw a different coin type
    let multisig_address = get_test_multisig_address();

    let ticket_type = withdraw_protocol_fee_ticket_type();
    create_ticket_with_multisig(&mut scenario, ticket_type);
    let ticket: AdminTicket = scenario.take_shared<AdminTicket>();

    let delay = ticket_delay_duration();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.increment_for_testing(delay);

    scenario.next_tx(multisig_address);
    let mut treasury: Treasury = scenario.take_shared<Treasury>();
    let withdrawn_coin = treasury::withdraw_protocol_fee<UNUSED_COIN>(
        &mut treasury,
        ticket,
        &clock,
        scenario.ctx(),
    );

    // Verify the returned coin has a value of 0
    assert!(coin::value(&withdrawn_coin) == 0, 0);
    coin::burn_for_testing(withdrawn_coin);

    // Verify no withdrawal event was emitted
    let withdrawn_events = event::events_by_type<ProtocolFeeWithdrawn<UNUSED_COIN>>();
    assert!(vector::length(&withdrawn_events) == 0, 1);

    clock::destroy_for_testing(clock);
    test_scenario::return_shared(treasury);
    scenario.end();
}

// === Helper Functions ===
/// Setup a scenario with a treasury and a protocol fee deposit
#[test_only]
fun setup_with_deposit(): Scenario {
    let multisig_address = get_test_multisig_address();
    let (mut scenario) = setup_with_admin_cap(multisig_address);

    scenario.next_tx(multisig_address);
    {
        init_for_testing(scenario.ctx());
    };

    scenario.next_tx(@0xDEADBEEF);
    {
        let mut treasury: Treasury = scenario.take_shared<Treasury>();
        let balance = balance::create_for_testing<COIN>(DEPOSIT_AMOUNT);
        join_protocol_fee(&mut treasury, balance);
        test_scenario::return_shared(treasury);
    };

    scenario
}
